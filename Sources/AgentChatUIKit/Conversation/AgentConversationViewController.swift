import AgentChatCore
import UIKit

/// A block-based, runtime-neutral conversation timeline for iPhone and iPad.
@MainActor
public final class AgentConversationViewController: UIViewController {
    /// Receives host-owned interactions such as attachment picking.
    public weak var delegate: (any AgentConversationViewControllerDelegate)?
    /// Routes runtime commands and host navigation without exposing either to cells.
    public var actionHandler: AgentActionHandler?

    private let store: AgentConversationStore
    private var configuration: AgentConversationConfiguration
    private var theme: AgentChatTheme
    private let rendererRegistry: AgentBlockRendererRegistry
    private let collectionView: UICollectionView
    private let composer: AgentComposerView
    private let connectionBanner = UILabel()
    private let jumpToLatestButton = UIButton(type: .system)
    private let historyLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private var displayedTurns: [AgentTurn] = []
    private var updateScheduler: AgentUpdateScheduler!
    private var scrollCoordinator: AgentScrollCoordinator!
    private var patchTask: Task<Void, Never>?
    private var composerTask: Task<Void, Never>?
    private var expandedBlockIDs: Set<AgentBlockID> = []
    private var initializedExpansionBlockIDs: Set<AgentBlockID> = []
    private var resolvingApprovalIDs: Set<AgentApprovalID> = []
    private var isLoadingHistory = false
    private var isHistoryRequestArmed = false
    private var isPerformingCollectionUpdate = false
    private var pendingCollectionUpdate: AgentScheduledUpdate?
    private var pendingCellReconfigurationBlockIDs: Set<AgentBlockID> = []
    private var pendingHeightChangeBlockIDs: Set<AgentBlockID> = []
    private var needsInitialScrollToLatest = true
    private var pendingViewportResizeAnchor: AgentLayoutAnchor?
    private var pendingViewportResizeRestorationAnchor: AgentLayoutAnchor?
    private var pendingViewportResizeWasFollowingLatest = false
    private var bannerHeightConstraint: NSLayoutConstraint?

    /// Creates a scene-scoped conversation controller.
    public init(
        store: AgentConversationStore,
        configuration: AgentConversationConfiguration = .init(),
        theme: AgentChatTheme = .system,
        rendererRegistry: AgentBlockRendererRegistry = .default
    ) {
        self.store = store
        self.configuration = configuration
        self.theme = theme
        self.rendererRegistry = rendererRegistry
        let layoutConfiguration = AgentTimelineLayoutConfiguration(
            compactSideInset: theme.metrics.pageInset,
            maximumContentWidth: theme.metrics.maximumContentWidth,
            blockSpacing: theme.metrics.blockSpacing,
            sectionTopInset: 4,
            sectionBottomInset: 8,
            estimatedItemHeight: 44
        )
        self.collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: AgentConversationLayoutFactory.makeLayout(
                configuration: layoutConfiguration
            )
        )
        self.composer = AgentComposerView(maximumHeight: configuration.maximumComposerHeight)
        super.init(nibName: nil, bundle: nil)
        self.composer.importHandler = { [weak self] providers, sourceView in
            guard let self else { return }
            self.delegate?.conversationViewController(
                self,
                didPaste: providers,
                sourceView: sourceView
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        patchTask?.cancel()
        composerTask?.cancel()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureDataSource()
        configureCoordinators()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
        displayedTurns = presentationTurns
        collectionView.reloadData()
        observeStore()
        observeComposer()
        updateConnectionBanner()
        updateComposerState()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard needsInitialScrollToLatest else { return }
        needsInitialScrollToLatest = false
        scrollCoordinator.scrollToLatest()
    }

    public override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        let anchor = beginViewportResize()
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(
            alongsideTransition: { [weak self] _ in
                self?.collectionView.collectionViewLayout.invalidateLayout()
            },
            completion: { [weak self] _ in
                self?.endViewportResize(restoring: anchor)
            }
        )
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        rendererRegistry.removeCachedData()
    }

    func beginViewportResize() -> AgentLayoutAnchor? {
        let wasFollowingLatest = scrollCoordinator.isFollowingLatest
        let anchor = scrollCoordinator.captureAnchor(edge: wasFollowingLatest ? .bottom : .top)
        pendingViewportResizeAnchor = anchor
        pendingViewportResizeRestorationAnchor = nil
        pendingViewportResizeWasFollowingLatest = wasFollowingLatest
        collectionView.collectionViewLayout.invalidateLayout()
        return anchor
    }

    func endViewportResize(restoring anchor: AgentLayoutAnchor?) {
        guard let anchor, pendingViewportResizeAnchor == anchor else { return }
        guard !isPerformingCollectionUpdate else {
            pendingViewportResizeRestorationAnchor = anchor
            return
        }
        performViewportResizeRestoration(anchor)
    }

    private func performViewportResizeRestoration(_ anchor: AgentLayoutAnchor) {
        guard pendingViewportResizeAnchor == anchor else { return }
        // Rich Markdown children capture the available content width when they are built.
        // Recreate only visible items after the new bounds have landed; off-screen items
        // are configured with the new width when they are next dequeued.
        let visibleItems = collectionView.indexPathsForVisibleItems
        isPerformingCollectionUpdate = true
        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates {
                if !visibleItems.isEmpty {
                    collectionView.reconfigureItems(at: visibleItems)
                }
            } completion: { [weak self] _ in
                guard let self else { return }
                guard self.pendingViewportResizeAnchor == anchor else {
                    self.completeCollectionUpdate()
                    return
                }
                self.collectionView.layoutIfNeeded()
                self.restoreViewportAfterResize(anchor)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.pendingViewportResizeAnchor == anchor else {
                        self.completeCollectionUpdate()
                        return
                    }
                    self.collectionView.layoutIfNeeded()
                    self.restoreViewportAfterResize(anchor)
                    self.pendingViewportResizeAnchor = nil
                    self.pendingViewportResizeWasFollowingLatest = false
                    self.completeCollectionUpdate()
                }
            }
        }
    }

    private func restoreViewportAfterResize(_ anchor: AgentLayoutAnchor) {
        if pendingViewportResizeWasFollowingLatest {
            scrollCoordinator.scrollToLatest()
        } else {
            scrollCoordinator.restore(anchor)
        }
    }

    /// Replaces the current visual theme and invalidates appearance-sensitive caches.
    public func apply(theme: AgentChatTheme) {
        self.theme = theme
        view.backgroundColor = theme.colors.background
        collectionView.backgroundColor = theme.colors.background
        let layoutConfiguration = AgentTimelineLayoutConfiguration(
            compactSideInset: theme.metrics.pageInset,
            maximumContentWidth: theme.metrics.maximumContentWidth,
            blockSpacing: theme.metrics.blockSpacing,
            sectionTopInset: 4,
            sectionBottomInset: 8,
            estimatedItemHeight: 44
        )
        collectionView.setCollectionViewLayout(
            AgentConversationLayoutFactory.makeLayout(configuration: layoutConfiguration),
            animated: false
        )
        collectionView.reloadData()
    }

    /// Replaces attachment metadata displayed by the default composer.
    public func setComposerAttachments(_ attachments: [AgentAttachment]) {
        var state = currentComposerState()
        state.attachments = attachments
        state.attachmentStatuses = state.attachmentStatuses.filter { id, _ in
            attachments.contains { $0.id == id }
        }
        composer.apply(state)
    }

    /// Replaces upload or validation state for one pending attachment.
    public func setComposerAttachmentStatus(
        _ status: AgentComposerAttachmentStatus,
        for attachmentID: AgentAttachmentID
    ) {
        var state = currentComposerState()
        guard state.attachments.contains(where: { $0.id == attachmentID }) else { return }
        state.attachmentStatuses[attachmentID] = status
        composer.apply(state)
    }

    /// Replaces host-defined default composer controls.
    public func setComposerAccessories(_ accessories: [AgentComposerAccessory]) {
        configuration.composerAccessories = accessories
        var state = currentComposerState()
        state.accessories = accessories
        composer.apply(state)
    }

    public override var keyCommands: [UIKeyCommand]? {
        guard configuration.enablesKeyboardCommands else { return nil }
        var commands = [
            UIKeyCommand(
                title: AgentStrings.send,
                image: UIImage(systemName: "arrow.up"),
                action: #selector(sendFromKeyboard),
                input: "\r",
                modifierFlags: .command,
                propertyList: nil,
                alternates: [],
                discoverabilityTitle: AgentStrings.send,
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: AgentStrings.messagePlaceholder,
                image: nil,
                action: #selector(focusComposer),
                input: "k",
                modifierFlags: [.command, .shift],
                propertyList: nil,
                alternates: [],
                discoverabilityTitle: AgentStrings.messagePlaceholder,
                attributes: [],
                state: .off
            ),
        ]
        if configuration.runtimeCapabilities.contains(.interrupt) {
            commands.append(
                UIKeyCommand(
                    title: AgentStrings.stop,
                    image: UIImage(systemName: "stop.fill"),
                    action: #selector(stopFromKeyboard),
                    input: UIKeyCommand.inputEscape,
                    modifierFlags: [],
                    propertyList: nil,
                    alternates: [],
                    discoverabilityTitle: AgentStrings.stop,
                    attributes: [],
                    state: .off
                )
            )
        }
        return commands
    }

    private func configureHierarchy() {
        view.backgroundColor = theme.colors.background
        collectionView.backgroundColor = theme.colors.background
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.selfSizingInvalidation = .disabled
        collectionView.delegate = self
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.accessibilityIdentifier = "AgentConversationTimeline"

        connectionBanner.translatesAutoresizingMaskIntoConstraints = false
        connectionBanner.font = .preferredFont(forTextStyle: .subheadline)
        connectionBanner.adjustsFontForContentSizeCategory = true
        connectionBanner.textAlignment = .center
        connectionBanner.numberOfLines = 0
        connectionBanner.backgroundColor = .systemYellow.withAlphaComponent(0.22)
        connectionBanner.textColor = .label
        connectionBanner.isHidden = true
        connectionBanner.accessibilityIdentifier = "AgentConversationConnectionBanner"
        bannerHeightConstraint = connectionBanner.heightAnchor.constraint(equalToConstant: 0)
        bannerHeightConstraint?.isActive = true

        composer.translatesAutoresizingMaskIntoConstraints = false

        var jumpConfiguration = UIButton.Configuration.filled()
        jumpConfiguration.title = AgentStrings.jumpToLatest
        jumpConfiguration.image = UIImage(systemName: "arrow.down")
        jumpConfiguration.imagePadding = 5
        jumpConfiguration.cornerStyle = .capsule
        jumpToLatestButton.configuration = jumpConfiguration
        jumpToLatestButton.isPointerInteractionEnabled = true
        jumpToLatestButton.translatesAutoresizingMaskIntoConstraints = false
        jumpToLatestButton.isHidden = true
        jumpToLatestButton.accessibilityIdentifier = "AgentConversationJumpToLatestButton"
        jumpToLatestButton.addAction(
            UIAction { [weak self] _ in
                self?.scrollCoordinator.scrollToLatest()
            },
            for: .touchUpInside
        )

        historyLoadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        historyLoadingIndicator.hidesWhenStopped = true
        historyLoadingIndicator.accessibilityIdentifier = "AgentHistoryLoadingIndicator"

        view.addSubview(connectionBanner)
        view.addSubview(collectionView)
        view.addSubview(composer)
        view.addSubview(historyLoadingIndicator)
        view.addSubview(jumpToLatestButton)
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        NSLayoutConstraint.activate([
            connectionBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            connectionBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            connectionBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: connectionBanner.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
            composer.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 12
            ),
            composer.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -12
            ),
            composer.bottomAnchor.constraint(
                equalTo: view.keyboardLayoutGuide.topAnchor,
                constant: -8
            ),
            jumpToLatestButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
            jumpToLatestButton.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -10),
            historyLoadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            historyLoadingIndicator.topAnchor.constraint(
                equalTo: collectionView.topAnchor,
                constant: 10
            ),
        ])
    }

    private func configureDataSource() {
        rendererRegistry.registerAll(in: collectionView)
        collectionView.register(
            AgentTurnHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: AgentTurnHeaderView.reuseIdentifier
        )

        collectionView.dataSource = self
    }

    private func configureCoordinators() {
        scrollCoordinator = AgentScrollCoordinator(
            collectionView: collectionView,
            followingThreshold: configuration.followingThreshold,
            itemIdentifier: { [weak self] in self?.blockID(at: $0) },
            indexPath: { [weak self] in self?.indexPath(for: $0) },
            orderedBlockIDs: { [weak self] in
                self?.displayedTurns.flatMap { $0.blocks.map(\.id) } ?? []
            }
        )
        scrollCoordinator.didChangeUnreadCount = { [weak self] count in
            self?.updateJumpButton(unreadCount: count)
        }

        updateScheduler = AgentUpdateScheduler { [weak self] update in
            self?.apply(update)
        }
    }

    private func observeStore() {
        let stream = store.makePatchStream()
        patchTask = Task { [weak self] in
            for await patch in stream {
                guard !Task.isCancelled, let self else { return }
                self.updateScheduler.enqueue(patch)
            }
        }
    }

    private func observeComposer() {
        composerTask = Task { [weak self] in
            guard let self else { return }
            for await action in self.composer.actionStream {
                guard !Task.isCancelled else { return }
                self.handleComposer(action)
            }
        }
    }

    private func apply(_ update: AgentScheduledUpdate) {
        guard !isPerformingCollectionUpdate else {
            mergePendingCollectionUpdate(update)
            return
        }

        updateConnectionBanner()
        updateComposerState()
        cleanupResolvedApprovalState()
        if update.patches.contains(where: { patch in
            if case .historyStateChanged = patch { return true }
            return false
        }) {
            setHistoryLoading(false)
        }

        if update.requiresStructuralReconciliation {
            let updatedTurns = presentationTurns
            let isPrepend = update.patches.contains { patch in
                if case .prependTurns = patch { return true }
                return false
            }
            let anchor =
                isPrepend
                ? scrollCoordinator.beginHistoryPrepend()
                : nil
            let shouldFollow = scrollCoordinator.shouldAutomaticallyFollowLatest
            let insertedCount = update.patches.reduce(into: 0) { count, patch in
                switch patch {
                case .insertBlock, .insertTurn: count += 1
                default: break
                }
            }
            applyStructuralChanges(
                to: updatedTurns,
                anchor: anchor,
                followLatest: shouldFollow,
                forceReload: update.patches.contains { patch in
                    if case .replaceAll = patch { return true }
                    return false
                }
            )
            if !shouldFollow, insertedCount > 0 {
                scrollCoordinator.receivedNewContent(count: insertedCount)
            }
            return
        }

        displayedTurns = presentationTurns
        let existing = Set(displayedTurns.flatMap { $0.blocks.map(\.id) })
        let updatedIndexPaths = update.reconfiguredBlockIDs
            .filter(existing.contains)
            .compactMap(indexPath(for:))
        let turnIDs = update.patches.compactMap { patch -> AgentTurnID? in
            if case .reconfigureTurn(let turnID) = patch { return turnID }
            return nil
        }
        reconfigureVisibleTurnHeaders(ids: Set(turnIDs))

        guard !updatedIndexPaths.isEmpty else { return }

        isPerformingCollectionUpdate = true
        let shouldFollow = scrollCoordinator.shouldAutomaticallyFollowLatest
        UIView.performWithoutAnimation {
            collectionView.reconfigureItems(at: updatedIndexPaths)
            collectionView.performBatchUpdates(nil) { [weak self] _ in
                self?.finishCollectionUpdate(shouldFollow ? .followLatest : .none)
            }
        }
    }

    private func applyStructuralChanges(
        to updatedTurns: [AgentTurn],
        anchor: AgentLayoutAnchor?,
        followLatest: Bool,
        forceReload: Bool
    ) {
        isPerformingCollectionUpdate = true
        synchronizeDefaultExpansionState()
        let previousTurns = displayedTurns
        guard !forceReload,
            let changes = AgentTimelineBatchChanges(from: previousTurns, to: updatedTurns)
        else {
            displayedTurns = updatedTurns
            UIView.performWithoutAnimation {
                collectionView.reloadData()
                collectionView.layoutIfNeeded()
            }
            finishCollectionUpdate(completionIntent(anchor: anchor, followLatest: followLatest))
            return
        }

        guard changes.hasChanges else {
            displayedTurns = updatedTurns
            reconfigureVisibleItems()
            finishCollectionUpdate(completionIntent(anchor: anchor, followLatest: followLatest))
            return
        }

        displayedTurns = updatedTurns
        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates {
                collectionView.deleteItems(at: changes.deletedItems)
                collectionView.deleteSections(changes.deletedSections)
                collectionView.insertSections(changes.insertedSections)
                collectionView.insertItems(at: changes.insertedItems)
            } completion: { [weak self] _ in
                guard let self else { return }
                self.reconfigureVisibleItems()
                self.finishCollectionUpdate(
                    self.completionIntent(anchor: anchor, followLatest: followLatest)
                )
            }
        }
    }

    private func mergePendingCollectionUpdate(_ update: AgentScheduledUpdate) {
        var pending = pendingCollectionUpdate ?? AgentScheduledUpdate()
        pending.requiresStructuralReconciliation =
            pending.requiresStructuralReconciliation || update.requiresStructuralReconciliation
        pending.reconfiguredBlockIDs.formUnion(update.reconfiguredBlockIDs)
        pending.patches.append(contentsOf: update.patches)
        pendingCollectionUpdate = pending
    }

    private func completionIntent(
        anchor: AgentLayoutAnchor?,
        followLatest: Bool
    ) -> AgentCollectionCompletionIntent {
        if let anchor {
            return .restoreHistory(anchor)
        }
        return followLatest ? .followLatest : .none
    }

    private func finishCollectionUpdate(_ intent: AgentCollectionCompletionIntent) {
        switch intent {
        case .none:
            collectionView.layoutIfNeeded()
            completeCollectionUpdate()

        case .restoreHistory(let anchor):
            collectionView.layoutIfNeeded()
            scrollCoordinator.restore(anchor)
            completeCollectionUpdate()

        case .followLatest:
            collectionView.layoutIfNeeded()
            if scrollCoordinator.shouldAutomaticallyFollowLatest {
                scrollCoordinator.scrollToLatest()
            }
            // Keep the transaction closed until UICollectionView has materialized the target
            // cell. Parsed content can then enqueue its own height transaction without overlap.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.collectionView.layoutIfNeeded()
                if self.scrollCoordinator.shouldAutomaticallyFollowLatest {
                    self.scrollCoordinator.scrollToLatest()
                }
                self.completeCollectionUpdate()
            }

        case .preserveBlock(let blockID, let viewportOffset):
            // Compositional-layout self-sizing settles on the following layout turn. Keep the
            // transaction closed until the single viewport adjustment has been applied.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.collectionView.layoutIfNeeded()
                self.restoreViewportPosition(of: blockID, offset: viewportOffset)
                self.completeCollectionUpdate()
            }
        }
    }

    private func completeCollectionUpdate() {
        isPerformingCollectionUpdate = false

        while !isPerformingCollectionUpdate {
            if let pending = pendingCollectionUpdate {
                pendingCollectionUpdate = nil
                apply(pending)
                return
            }
            if let anchor = pendingViewportResizeRestorationAnchor {
                pendingViewportResizeRestorationAnchor = nil
                performViewportResizeRestoration(anchor)
                return
            }
            if let blockID = pendingCellReconfigurationBlockIDs.first {
                pendingCellReconfigurationBlockIDs.remove(blockID)
                reconfigure(blockID)
                continue
            }
            if let blockID = pendingHeightChangeBlockIDs.first {
                pendingHeightChangeBlockIDs.remove(blockID)
                handleCellHeightChange(blockID)
                continue
            }
            return
        }
    }

    private func synchronizeDefaultExpansionState() {
        let blocks = presentationTurns.flatMap(\.blocks)
        let liveBlockIDs = Set(blocks.map(\.id))
        initializedExpansionBlockIDs.formIntersection(liveBlockIDs)
        expandedBlockIDs.formIntersection(liveBlockIDs)

        for block in blocks where initializedExpansionBlockIDs.insert(block.id).inserted {
            switch block.content {
            case .tool(let value) where value.displayMode == .expanded:
                expandedBlockIDs.insert(block.id)
            case .fileSearch:
                expandedBlockIDs.insert(block.id)
            default:
                break
            }
        }
    }

    private func reconfigureVisibleItems() {
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        guard !visibleIndexPaths.isEmpty else { return }
        UIView.performWithoutAnimation {
            collectionView.reconfigureItems(at: visibleIndexPaths)
        }
        reconfigureVisibleTurnHeaders(ids: Set(displayedTurns.map(\.id)))
    }

    private func route(_ action: AgentBlockUIAction) {
        switch action {
        case .toggleExpanded(let blockID):
            if !expandedBlockIDs.insert(blockID).inserted {
                expandedBlockIDs.remove(blockID)
            }
            reconfigure(blockID)

        case .copy(let blockID):
            if let block = turnAndBlock(for: blockID)?.block {
                UIPasteboard.general.string = AgentBlockCopyText.text(for: block)
            }

        case .openArtifact(let id):
            perform(.host(.openArtifact(id)))

        case .openFile(let reference):
            perform(.host(.openResource(reference)))

        case .previewImage(let reference, let alternativeText):
            perform(
                .host(
                    .previewImage(
                        reference: reference,
                        alternativeText: alternativeText
                    )
                )
            )

        case .openLink(let url):
            guard let scheme = url.scheme?.lowercased(),
                ["http", "https", "mailto"].contains(scheme)
            else { return }
            perform(.host(.openURL(url)))

        case .retry(let blockID):
            perform(
                .runtime(
                    .retry(
                        .init(conversationID: store.snapshot.id, blockID: blockID)
                    )
                )
            )

        case .approve(let response):
            guard actionHandler != nil else { return }
            resolvingApprovalIDs.insert(response.approvalID)
            reconfigureApproval(response.approvalID)
            perform(.runtime(.approve(response)), approvalID: response.approvalID)

        case .reject(let response):
            guard actionHandler != nil else { return }
            resolvingApprovalIDs.insert(response.approvalID)
            reconfigureApproval(response.approvalID)
            perform(.runtime(.reject(response)), approvalID: response.approvalID)

        case .custom(let kind, let payload):
            perform(.host(.custom(kind: kind, payload: payload)))
        }
    }

    private func handleComposer(_ action: AgentComposerAction) {
        switch action {
        case .send(let text, let attachments):
            let pendingState = currentComposerState()
            let request = AgentSubmitRequest(
                conversationID: store.snapshot.id,
                text: text,
                attachments: attachments
            )
            var submittedState = pendingState
            submittedState.text = ""
            submittedState.attachments = []
            submittedState.attachmentStatuses = [:]
            submittedState.isRunning = configuration.runtimeCapabilities.contains(.interrupt)
            submittedState.canSend = false
            submittedState.statusMessage = AgentStrings.running
            composer.apply(submittedState)
            delegate?.conversationViewController(self, didUpdateDraftAttachments: [])
            perform(
                .runtime(.submit(request)),
                failure: { [weak self] in
                    guard let self else { return }
                    self.composer.apply(pendingState)
                    self.delegate?.conversationViewController(
                        self,
                        didUpdateDraftAttachments: pendingState.attachments
                    )
                }
            )
        case .stop:
            guard configuration.runtimeCapabilities.contains(.interrupt) else { return }
            perform(
                .runtime(.interrupt(.init(conversationID: store.snapshot.id)))
            )
        case .pickAttachments:
            guard configuration.runtimeCapabilities.contains(.attachments) else { return }
            delegate?.conversationViewControllerDidRequestAttachments(self, sourceView: composer)
        case .removeAttachment(let attachmentID):
            var state = currentComposerState()
            state.attachments.removeAll { $0.id == attachmentID }
            state.attachmentStatuses[attachmentID] = nil
            composer.apply(state)
            delegate?.conversationViewController(
                self,
                didUpdateDraftAttachments: state.attachments
            )
        case .retryAttachment(let attachmentID):
            delegate?.conversationViewController(
                self,
                didRequestRetryFor: attachmentID
            )
        case .selectAccessory(let id):
            perform(
                .host(
                    .custom(
                        kind: "agentchat.composer.accessory",
                        payload: .object(["id": .string(id)])
                    )
                )
            )
        }
    }

    private func perform(
        _ action: AgentConversationAction,
        approvalID: AgentApprovalID? = nil,
        success: (@MainActor () -> Void)? = nil,
        failure: (@MainActor () -> Void)? = nil
    ) {
        guard let actionHandler else {
            failure?()
            return
        }
        Task { [weak self] in
            do {
                try await actionHandler(action)
                success?()
            } catch {
                guard let self else { return }
                failure?()
                if let approvalID {
                    self.resolvingApprovalIDs.remove(approvalID)
                    self.reconfigureApproval(approvalID)
                }
                self.connectionBanner.text = error.localizedDescription
                self.showConnectionBanner()
            }
        }
    }

    private func updateConnectionBanner() {
        switch store.snapshot.state {
        case .offline(let message):
            connectionBanner.text = message ?? AgentStrings.offline
            showConnectionBanner()
        case .failed(let failure):
            connectionBanner.text = failure.message
            showConnectionBanner()
        case .connecting:
            connectionBanner.text = AgentStrings.connecting
            showConnectionBanner()
        case .idle, .connected:
            connectionBanner.isHidden = true
            bannerHeightConstraint?.isActive = true
        }
    }

    private func updateComposerState() {
        var state = currentComposerState()
        let canInterrupt = configuration.runtimeCapabilities.contains(.interrupt)
        state.isRunning = isConversationRunning && canInterrupt
        scrollCoordinator.setStreaming(isConversationRunning)
        state.canPickAttachments = configuration.runtimeCapabilities.contains(.attachments)
        state.accessories = configuration.composerAccessories
        state.contextDescription = configuration.composerContextDescription
        switch store.snapshot.state {
        case .connected, .idle:
            state.statusMessage = isConversationRunning ? AgentStrings.running : nil
            state.canSend = !isConversationRunning
        case .connecting:
            state.statusMessage = AgentStrings.connecting
            state.canSend = false
        case .offline(let message):
            state.statusMessage = message ?? AgentStrings.offline
            state.canSend = configuration.allowsSendingWhileOffline && !isConversationRunning
        case .failed(let failure):
            state.statusMessage = failure.message
            state.canSend = false
        }
        composer.apply(state)
    }

    private func currentComposerState() -> AgentComposerState {
        var state = composer.currentState
        state.isRunning =
            isConversationRunning
            && configuration.runtimeCapabilities.contains(.interrupt)
        return state
    }

    private var isConversationRunning: Bool {
        guard let state = store.snapshot.turns.last?.state else { return false }
        switch state {
        case .streaming, .running, .waitingForApproval: return true
        default: return false
        }
    }

    private var availableContentWidth: CGFloat {
        let inset = max(
            theme.metrics.pageInset,
            (collectionView.bounds.width - theme.metrics.maximumContentWidth) / 2
        )
        return max(1, collectionView.bounds.width - inset * 2)
    }

    private func updateJumpButton(unreadCount: Int) {
        jumpToLatestButton.isHidden = unreadCount == 0
        jumpToLatestButton.accessibilityLabel =
            unreadCount > 0
            ? "\(AgentStrings.jumpToLatest), \(unreadCount)"
            : AgentStrings.jumpToLatest
    }

    private func setHistoryLoading(_ isLoading: Bool) {
        isLoadingHistory = isLoading
        if isLoading {
            historyLoadingIndicator.startAnimating()
        } else {
            historyLoadingIndicator.stopAnimating()
        }
    }

    private func finishScrollInteraction() {
        isHistoryRequestArmed = false
        scrollCoordinator.userDidEndInteraction()
        DispatchQueue.main.asyncAfter(
            deadline: .now() + AgentScrollPolicy.userInteractionCooldown + 0.01
        ) { [weak self] in
            guard let self, self.scrollCoordinator.shouldAutomaticallyFollowLatest else { return }
            // A final height update may have landed during the cooldown. Reconcile once
            // after direct manipulation without overriding a newer history-reading intent.
            self.scrollCoordinator.scrollToLatest()
        }
    }

    private func showConnectionBanner() {
        bannerHeightConstraint?.isActive = false
        connectionBanner.isHidden = false
    }

    private func turnAndBlock(for blockID: AgentBlockID) -> (turn: AgentTurn, block: AgentBlock)? {
        for turn in presentationTurns {
            if let block = turn.blocks.first(where: { $0.id == blockID }) { return (turn, block) }
        }
        return nil
    }

    private func displayedTurnAndBlock(
        at indexPath: IndexPath
    ) -> (turn: AgentTurn, block: AgentBlock)? {
        guard displayedTurns.indices.contains(indexPath.section),
            displayedTurns[indexPath.section].blocks.indices.contains(indexPath.item)
        else { return nil }
        let turn = displayedTurns[indexPath.section]
        return (turn, turn.blocks[indexPath.item])
    }

    private func blockID(at indexPath: IndexPath) -> AgentBlockID? {
        displayedTurnAndBlock(at: indexPath)?.block.id
    }

    private func indexPath(for blockID: AgentBlockID) -> IndexPath? {
        for (section, turn) in displayedTurns.enumerated() {
            if let item = turn.blocks.firstIndex(where: { $0.id == blockID }) {
                return IndexPath(item: item, section: section)
            }
        }
        return nil
    }

    private func makeRenderContext(
        turn: AgentTurn,
        block: AgentBlock
    ) -> AgentBlockRenderContext {
        AgentBlockRenderContext(
            conversationID: store.snapshot.id,
            turn: turn,
            block: block,
            availableWidth: availableContentWidth,
            theme: theme,
            environment: AgentRenderEnvironment(
                contentSizeCategory: traitCollection.preferredContentSizeCategory.rawValue,
                reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled,
                resolvingApprovalIDs: resolvingApprovalIDs,
                expandedBlockIDs: expandedBlockIDs,
                canRetry: configuration.runtimeCapabilities.contains(.retry),
                toolPresentationStyle: configuration.toolPresentationStyle
            ),
            imageProvider: configuration.imageProvider,
            actionSink: AgentBlockActionSink { [weak self] action in
                self?.route(action)
            }
        )
    }

    private func reconfigureVisibleTurnHeaders(ids: Set<AgentTurnID>) {
        guard !ids.isEmpty else { return }
        for section in displayedTurns.indices where ids.contains(displayedTurns[section].id) {
            let indexPath = IndexPath(item: 0, section: section)
            guard
                let header = collectionView.supplementaryView(
                    forElementKind: UICollectionView.elementKindSectionHeader,
                    at: indexPath
                ) as? AgentTurnHeaderView
            else { continue }
            header.configure(turn: displayedTurns[section])
        }
    }

    private func handleCellHeightChange(_ blockID: AgentBlockID) {
        guard !isPerformingCollectionUpdate else {
            pendingHeightChangeBlockIDs.insert(blockID)
            return
        }
        guard let indexPath = indexPath(for: blockID),
            collectionView.indexPathsForVisibleItems.contains(indexPath)
        else { return }

        isPerformingCollectionUpdate = true
        let shouldFollow = scrollCoordinator.shouldAutomaticallyFollowLatest
        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates(nil) { [weak self] _ in
                self?.finishCollectionUpdate(shouldFollow ? .followLatest : .none)
            }
        }
    }

    /// Defensively mirrors the reducer's first-identifier-wins policy for host-supplied stores.
    private var presentationTurns: [AgentTurn] {
        var seenTurnIDs: Set<AgentTurnID> = []
        var seenBlockIDs: Set<AgentBlockID> = []
        return store.snapshot.turns.compactMap { candidate in
            guard seenTurnIDs.insert(candidate.id).inserted else { return nil }
            var turn = candidate
            turn.blocks = candidate.blocks.filter { seenBlockIDs.insert($0.id).inserted }
            return turn
        }
    }

    private func reconfigure(_ blockID: AgentBlockID) {
        guard !isPerformingCollectionUpdate else {
            pendingCellReconfigurationBlockIDs.insert(blockID)
            return
        }
        guard let indexPath = indexPath(for: blockID),
            let attributes = collectionView.layoutAttributesForItem(at: indexPath)
        else { return }
        let viewportOffset = attributes.frame.minY - collectionView.contentOffset.y
        isPerformingCollectionUpdate = true
        UIView.performWithoutAnimation {
            collectionView.reconfigureItems(at: [indexPath])
            collectionView.performBatchUpdates(nil) { [weak self] _ in
                self?.finishCollectionUpdate(
                    .preserveBlock(blockID, viewportOffset: viewportOffset)
                )
            }
        }
    }

    private func restoreViewportPosition(of blockID: AgentBlockID, offset: CGFloat) {
        guard let indexPath = indexPath(for: blockID),
            let attributes = collectionView.layoutAttributesForItem(at: indexPath)
        else { return }
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: attributes.frame.minY - offset),
            animated: false
        )
    }

    private func reconfigureApproval(_ approvalID: AgentApprovalID) {
        for turn in store.snapshot.turns {
            for block in turn.blocks {
                if case .approval(let approval) = block.content,
                    approval.approvalID == approvalID
                {
                    reconfigure(block.id)
                    return
                }
            }
        }
    }

    private func cleanupResolvedApprovalState() {
        let unresolved = Set(
            store.snapshot.turns.flatMap(\.blocks).compactMap { block -> AgentApprovalID? in
                guard case .approval(let approval) = block.content, approval.resolution == nil
                else {
                    return nil
                }
                return approval.approvalID
            })
        resolvingApprovalIDs.formIntersection(unresolved)
    }

    @objc private func sendFromKeyboard() {
        composer.submitCurrentInput()
    }

    @objc private func focusComposer() { composer.focus() }

    @objc private func stopFromKeyboard() {
        guard isConversationRunning else { return }
        handleComposer(.stop)
    }

    @objc private func applicationDidEnterBackground() {
        updateScheduler.setActive(false)
    }

    @objc private func applicationWillEnterForeground() {
        updateScheduler.setActive(true)
    }

    @objc private func contentSizeCategoryDidChange() {
        guard isViewLoaded, view.window != nil else { return }
        let anchor = beginViewportResize()
        endViewportResize(restoring: anchor)
    }
}

extension AgentConversationViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        displayedTurns.count
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        guard displayedTurns.indices.contains(section) else { return 0 }
        return displayedTurns[section].blocks.count
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let (turn, block) = displayedTurnAndBlock(at: indexPath) else {
            return UICollectionViewCell()
        }
        let cell = rendererRegistry.renderer(for: block).dequeueConfiguredCell(
            from: collectionView,
            at: indexPath,
            context: makeRenderContext(turn: turn, block: block)
        )
        if let cell = cell as? AgentBlockCell {
            cell.didChangeHeight = { [weak self, weak cell] in
                guard let self, let cell,
                    self.collectionView.indexPath(for: cell) == self.indexPath(for: block.id)
                else { return }
                self.handleCellHeightChange(block.id)
            }
        }
        return cell
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let (turn, block) = displayedTurnAndBlock(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(
            identifier: block.id.rawValue as NSString,
            previewProvider: nil
        ) { [weak self] _ in
            guard let self else { return nil }
            return AgentBlockContextMenu.make(
                for: self.makeRenderContext(turn: turn, block: block)
            )
        }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
            displayedTurns.indices.contains(indexPath.section),
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: AgentTurnHeaderView.reuseIdentifier,
                for: indexPath
            ) as? AgentTurnHeaderView
        else { return UICollectionReusableView() }
        header.configure(turn: displayedTurns[indexPath.section])
        return header
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isHistoryRequestArmed = true
        scrollCoordinator.userWillBeginDragging()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollCoordinator.userDidScroll()
        let topThreshold = -scrollView.adjustedContentInset.top + 160
        if scrollView.contentOffset.y <= topThreshold,
            isHistoryRequestArmed,
            store.snapshot.hasEarlierHistory,
            configuration.runtimeCapabilities.contains(.history),
            !isLoadingHistory,
            actionHandler != nil
        {
            isHistoryRequestArmed = false
            setHistoryLoading(true)
            perform(
                .runtime(
                    .loadEarlier(
                        .init(
                            conversationID: store.snapshot.id,
                            cursor: store.snapshot.earlierHistoryCursor
                        )
                    )
                ),
                failure: { [weak self] in
                    self?.setHistoryLoading(false)
                }
            )
        }
    }

    public func scrollViewDidEndDragging(
        _ scrollView: UIScrollView, willDecelerate decelerate: Bool
    ) {
        if !decelerate { finishScrollInteraction() }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishScrollInteraction()
    }

}

private enum AgentCollectionCompletionIntent {
    case none
    case followLatest
    case restoreHistory(AgentLayoutAnchor)
    case preserveBlock(AgentBlockID, viewportOffset: CGFloat)
}

struct AgentTimelineBatchChanges {
    let deletedSections: IndexSet
    let insertedSections: IndexSet
    let deletedItems: [IndexPath]
    let insertedItems: [IndexPath]
    let appendsAtEnd: Bool

    var hasChanges: Bool {
        !deletedSections.isEmpty || !insertedSections.isEmpty
            || !deletedItems.isEmpty || !insertedItems.isEmpty
    }

    init?(from previous: [AgentTurn], to updated: [AgentTurn]) {
        let previousTurnIDs = previous.map(\.id)
        let updatedTurnIDs = updated.map(\.id)
        let previousTurnIDSet = Set(previousTurnIDs)
        let updatedTurnIDSet = Set(updatedTurnIDs)

        let retainedPreviousTurnIDs = previousTurnIDs.filter(updatedTurnIDSet.contains)
        let retainedUpdatedTurnIDs = updatedTurnIDs.filter(previousTurnIDSet.contains)
        guard retainedPreviousTurnIDs == retainedUpdatedTurnIDs else { return nil }

        deletedSections = IndexSet(
            previousTurnIDs.enumerated().compactMap { offset, id in
                updatedTurnIDSet.contains(id) ? nil : offset
            }
        )
        insertedSections = IndexSet(
            updatedTurnIDs.enumerated().compactMap { offset, id in
                previousTurnIDSet.contains(id) ? nil : offset
            }
        )

        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let updatedByID = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        let previousSectionByID = Dictionary(
            uniqueKeysWithValues: previousTurnIDs.enumerated().map { ($0.element, $0.offset) }
        )
        let updatedSectionByID = Dictionary(
            uniqueKeysWithValues: updatedTurnIDs.enumerated().map { ($0.element, $0.offset) }
        )

        var deletedItems: [IndexPath] = []
        var insertedItems: [IndexPath] = []
        for turnID in retainedPreviousTurnIDs {
            guard let previousTurn = previousByID[turnID],
                let updatedTurn = updatedByID[turnID],
                let previousSection = previousSectionByID[turnID],
                let updatedSection = updatedSectionByID[turnID]
            else { return nil }

            let previousBlockIDs = previousTurn.blocks.map(\.id)
            let updatedBlockIDs = updatedTurn.blocks.map(\.id)
            let previousBlockIDSet = Set(previousBlockIDs)
            let updatedBlockIDSet = Set(updatedBlockIDs)
            guard
                previousBlockIDs.filter(updatedBlockIDSet.contains)
                    == updatedBlockIDs.filter(previousBlockIDSet.contains)
            else { return nil }

            deletedItems.append(
                contentsOf: previousBlockIDs.enumerated().compactMap { item, id in
                    updatedBlockIDSet.contains(id)
                        ? nil : IndexPath(item: item, section: previousSection)
                }
            )
            insertedItems.append(
                contentsOf: updatedBlockIDs.enumerated().compactMap { item, id in
                    previousBlockIDSet.contains(id)
                        ? nil : IndexPath(item: item, section: updatedSection)
                }
            )
        }

        self.deletedItems = deletedItems
        self.insertedItems = insertedItems
        let hasInsertion = !insertedSections.isEmpty || !insertedItems.isEmpty
        let existingTurnsAppendOnlyAtTail = previous.enumerated().allSatisfy {
            section, previousTurn in
            guard let updatedTurn = updatedByID[previousTurn.id] else { return false }
            let previousBlockIDs = previousTurn.blocks.map(\.id)
            let updatedBlockIDs = updatedTurn.blocks.map(\.id)
            if section == previous.count - 1 {
                return Array(updatedBlockIDs.prefix(previousBlockIDs.count))
                    == previousBlockIDs
            }
            return updatedBlockIDs == previousBlockIDs
        }
        appendsAtEnd =
            hasInsertion
            && deletedSections.isEmpty
            && deletedItems.isEmpty
            && Array(updatedTurnIDs.prefix(previousTurnIDs.count)) == previousTurnIDs
            && existingTurnsAppendOnlyAtTail
    }
}
