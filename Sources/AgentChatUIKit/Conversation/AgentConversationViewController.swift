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
    private let sizeCache = AgentItemSizeCache()

    private var dataSource: UICollectionViewDiffableDataSource<AgentTurnID, AgentBlockID>!
    private var updateScheduler: AgentUpdateScheduler!
    private var scrollCoordinator: AgentScrollCoordinator!
    private var patchTask: Task<Void, Never>?
    private var composerTask: Task<Void, Never>?
    private var expandedBlockIDs: Set<AgentBlockID> = []
    private var initializedExpansionBlockIDs: Set<AgentBlockID> = []
    private var resolvingApprovalIDs: Set<AgentApprovalID> = []
    private var isLoadingHistory = false
    private var previousViewSize: CGSize = .zero
    private var pendingGeometryAnchor: AgentLayoutAnchor?
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
            estimatedItemHeight: 80
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
        reconcileStructuralSnapshot(animated: false, anchor: nil, followLatest: true)
        observeStore()
        observeComposer()
        updateConnectionBanner()
        updateComposerState()
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if previousViewSize != .zero, previousViewSize != view.bounds.size,
            !scrollCoordinator.isFollowingLatest
        {
            pendingGeometryAnchor = scrollCoordinator.captureAnchor(edge: .top)
            sizeCache.invalidateAppearance()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let anchor = pendingGeometryAnchor {
            pendingGeometryAnchor = nil
            scrollCoordinator.restore(anchor)
        }
        previousViewSize = view.bounds.size
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        sizeCache.removeAll()
    }

    /// Replaces the current visual theme and invalidates appearance-sensitive caches.
    public func apply(theme: AgentChatTheme) {
        self.theme = theme
        view.backgroundColor = theme.colors.background
        collectionView.backgroundColor = theme.colors.background
        sizeCache.invalidateAppearance()
        collectionView.collectionViewLayout.invalidateLayout()
        reconcileVisibleItems()
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
        collectionView.delegate = self
        collectionView.contentInsetAdjustmentBehavior = .always

        connectionBanner.translatesAutoresizingMaskIntoConstraints = false
        connectionBanner.font = .preferredFont(forTextStyle: .subheadline)
        connectionBanner.adjustsFontForContentSizeCategory = true
        connectionBanner.textAlignment = .center
        connectionBanner.numberOfLines = 0
        connectionBanner.backgroundColor = .systemYellow.withAlphaComponent(0.22)
        connectionBanner.textColor = .label
        connectionBanner.isHidden = true
        bannerHeightConstraint = connectionBanner.heightAnchor.constraint(equalToConstant: 0)
        bannerHeightConstraint?.isActive = true

        composer.translatesAutoresizingMaskIntoConstraints = false

        var jumpConfiguration = UIButton.Configuration.filled()
        jumpConfiguration.title = AgentStrings.jumpToLatest
        jumpConfiguration.image = UIImage(systemName: "arrow.down")
        jumpConfiguration.imagePadding = 5
        jumpConfiguration.cornerStyle = .capsule
        jumpToLatestButton.configuration = jumpConfiguration
        jumpToLatestButton.translatesAutoresizingMaskIntoConstraints = false
        jumpToLatestButton.isHidden = true
        jumpToLatestButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.scrollCoordinator.scrollToLatest(
                    animated: !UIAccessibility.isReduceMotionEnabled
                )
            },
            for: .touchUpInside
        )

        view.addSubview(connectionBanner)
        view.addSubview(collectionView)
        view.addSubview(composer)
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
        ])
    }

    private func configureDataSource() {
        rendererRegistry.registerAll(in: collectionView)
        collectionView.register(
            AgentTurnHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: AgentTurnHeaderView.reuseIdentifier
        )

        dataSource = UICollectionViewDiffableDataSource<AgentTurnID, AgentBlockID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, blockID in
            guard let self,
                let (turn, block) = self.turnAndBlock(for: blockID)
            else { return nil }
            let context = AgentBlockRenderContext(
                conversationID: self.store.snapshot.id,
                turn: turn,
                block: block,
                availableWidth: self.availableContentWidth,
                theme: self.theme,
                environment: AgentRenderEnvironment(
                    contentSizeCategory: self.traitCollection.preferredContentSizeCategory.rawValue,
                    reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled,
                    resolvingApprovalIDs: self.resolvingApprovalIDs,
                    expandedBlockIDs: self.expandedBlockIDs
                ),
                imageProvider: self.configuration.imageProvider,
                actionSink: AgentBlockActionSink { [weak self] action in
                    self?.route(action)
                }
            )
            return self.rendererRegistry.renderer(for: block).dequeueConfiguredCell(
                from: collectionView,
                at: indexPath,
                context: context
            )
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionHeader,
                let self,
                let header = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: AgentTurnHeaderView.reuseIdentifier,
                    for: indexPath
                ) as? AgentTurnHeaderView,
                indexPath.section < self.dataSource.snapshot().sectionIdentifiers.count,
                let turn = self.store.snapshot.turns.first(where: {
                    $0.id == self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
                })
            else { return nil }
            header.configure(turn: turn)
            return header
        }
    }

    private func configureCoordinators() {
        scrollCoordinator = AgentScrollCoordinator(
            collectionView: collectionView,
            followingThreshold: configuration.followingThreshold,
            itemIdentifier: { [weak self] in self?.dataSource.itemIdentifier(for: $0) },
            indexPath: { [weak self] in self?.dataSource.indexPath(for: $0) },
            orderedBlockIDs: { [weak self] in
                self?.presentationTurns.flatMap { $0.blocks.map(\.id) } ?? []
            }
        )
        scrollCoordinator.didChangeUnreadCount = { [weak self] count in
            self?.updateJumpButton(unreadCount: count)
        }

        updateScheduler = AgentUpdateScheduler(
            classify: { [weak self] patch in self?.classify(patch) ?? .structural },
            flush: { [weak self] update in self?.apply(update) }
        )
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

    private func classify(_ patch: AgentPresentationPatch) -> AgentCollectionUpdateKind {
        switch patch {
        case .replaceAll, .insertTurn, .deleteTurn, .insertBlock, .deleteBlock, .prependTurns:
            return .structural
        case .reconfigureBlock(let blockID):
            guard let block = turnAndBlock(for: blockID)?.block else { return .structural }
            switch block.content {
            case .activity: return .contentOnly
            default: return .sizeAffecting
            }
        case .reconfigureTurn, .conversationStateChanged, .notice:
            return .contentOnly
        }
    }

    private func apply(_ update: AgentScheduledUpdate) {
        updateConnectionBanner()
        updateComposerState()
        cleanupResolvedApprovalState()

        if update.requiresStructuralReconciliation {
            let isPrepend = update.patches.contains { patch in
                if case .prependTurns = patch { return true }
                return false
            }
            let anchor =
                isPrepend
                ? scrollCoordinator.beginHistoryPrepend()
                : (scrollCoordinator.isFollowingLatest
                    ? nil : scrollCoordinator.captureAnchor(edge: .top))
            let shouldFollow = scrollCoordinator.isFollowingLatest
            let insertedCount = update.patches.reduce(into: 0) { count, patch in
                switch patch {
                case .insertBlock, .insertTurn: count += 1
                default: break
                }
            }
            reconcileStructuralSnapshot(
                animated: !UIAccessibility.isReduceMotionEnabled,
                anchor: anchor,
                followLatest: shouldFollow
            )
            if !shouldFollow, insertedCount > 0 {
                scrollCoordinator.receivedNewContent(count: insertedCount)
            }
            if isPrepend { isLoadingHistory = false }
            return
        }

        var snapshot = dataSource.snapshot()
        let existing = Set(snapshot.itemIdentifiers)
        let sizeIDs = update.sizeAffectingBlockIDs.filter(existing.contains)
        let contentIDs = update.contentOnlyBlockIDs.filter(existing.contains)
        for id in sizeIDs { sizeCache.invalidate(blockID: id) }
        if !sizeIDs.isEmpty || !contentIDs.isEmpty {
            snapshot.reconfigureItems(Array(sizeIDs.union(contentIDs)))
        }
        let turnIDs = update.patches.compactMap { patch -> AgentTurnID? in
            if case .reconfigureTurn(let turnID) = patch { return turnID }
            return nil
        }.filter { snapshot.sectionIdentifiers.contains($0) }
        if !turnIDs.isEmpty { snapshot.reloadSections(turnIDs) }

        let anchor =
            sizeIDs.isEmpty || scrollCoordinator.isFollowingLatest
            ? nil : scrollCoordinator.captureAnchor(edge: .top)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            if !sizeIDs.isEmpty { self.collectionView.collectionViewLayout.invalidateLayout() }
            self.collectionView.layoutIfNeeded()
            if let anchor {
                self.scrollCoordinator.restore(anchor)
            } else if self.scrollCoordinator.isFollowingLatest {
                self.scrollCoordinator.scrollToLatest(animated: false)
            }
        }
    }

    private func reconcileStructuralSnapshot(
        animated: Bool,
        anchor: AgentLayoutAnchor?,
        followLatest: Bool
    ) {
        synchronizeDefaultExpansionState()
        var snapshot = NSDiffableDataSourceSnapshot<AgentTurnID, AgentBlockID>()
        for turn in presentationTurns {
            snapshot.appendSections([turn.id])
            snapshot.appendItems(turn.blocks.map(\.id), toSection: turn.id)
        }
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self else { return }
            self.collectionView.layoutIfNeeded()
            if let anchor {
                self.scrollCoordinator.restore(anchor)
            } else if followLatest {
                self.scrollCoordinator.scrollToLatest(animated: false)
            }
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

    private func reconcileVisibleItems() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func route(_ action: AgentBlockUIAction) {
        switch action {
        case .toggleExpanded(let blockID):
            if !expandedBlockIDs.insert(blockID).inserted { expandedBlockIDs.remove(blockID) }
            reconfigure(blockID, animated: true)

        case .copy(let blockID):
            if let block = turnAndBlock(for: blockID)?.block {
                UIPasteboard.general.string = copyText(for: block)
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

    private func reconfigure(_ blockID: AgentBlockID, animated: Bool = false) {
        var snapshot = dataSource.snapshot()
        guard snapshot.itemIdentifiers.contains(blockID) else { return }
        snapshot.reconfigureItems([blockID])
        let shouldAnimate = animated && !UIAccessibility.isReduceMotionEnabled
        let anchor =
            scrollCoordinator.isFollowingLatest
            ? nil : scrollCoordinator.captureAnchor(edge: .top)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            self.collectionView.collectionViewLayout.invalidateLayout()
            let updates = {
                self.collectionView.layoutIfNeeded()
                if let anchor {
                    self.scrollCoordinator.restore(anchor)
                } else if self.scrollCoordinator.isFollowingLatest {
                    self.scrollCoordinator.scrollToLatest(animated: false)
                }
            }
            guard shouldAnimate else {
                updates()
                return
            }
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
                animations: updates
            )
        }
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

    private func copyText(for block: AgentBlock) -> String {
        switch block.content {
        case .userText(let value): value.text
        case .markdown(let value): value.markdown
        case .command(let value): value.output.text.isEmpty ? value.command : value.output.text
        case .custom(let value):
            (try? String(
                data: JSONEncoder().encode(value.payload),
                encoding: .utf8
            )) ?? value.fallbackTitle
        default: String(describing: block.content)
        }
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
        let anchor =
            scrollCoordinator.isFollowingLatest
            ? nil : scrollCoordinator.captureAnchor(edge: .top)
        updateScheduler.setActive(true)
        reconcileStructuralSnapshot(
            animated: false,
            anchor: anchor,
            followLatest: scrollCoordinator.isFollowingLatest
        )
    }
}

extension AgentConversationViewController: UICollectionViewDelegate {
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollCoordinator.userWillBeginDragging()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollCoordinator.userDidScroll()
        let topThreshold = -scrollView.adjustedContentInset.top + 160
        if scrollView.contentOffset.y <= topThreshold,
            store.snapshot.hasEarlierHistory,
            configuration.runtimeCapabilities.contains(.history),
            !isLoadingHistory,
            actionHandler != nil
        {
            isLoadingHistory = true
            perform(
                .runtime(
                    .loadEarlier(
                        .init(
                            conversationID: store.snapshot.id,
                            cursor: store.snapshot.earlierHistoryCursor
                        )
                    )
                )
            )
        }
    }

    public func scrollViewDidEndDragging(
        _ scrollView: UIScrollView, willDecelerate decelerate: Bool
    ) {
        if !decelerate { scrollCoordinator.userDidEndInteraction() }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollCoordinator.userDidEndInteraction()
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scrollCoordinator.programmaticScrollDidEnd()
    }
}
