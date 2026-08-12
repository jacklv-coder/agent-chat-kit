import AgentChatCore
import UIKit

/// A UITableView-based conversation page for hosts that prefer traditional row updates.
@MainActor
public final class AgentTableConversationViewController: UIViewController {
    /// Receives host-owned interactions such as attachment picking.
    public weak var delegate: (any AgentTableConversationViewControllerDelegate)?
    /// Routes runtime commands and host navigation without exposing either to cells.
    public var actionHandler: AgentActionHandler?

    private let store: AgentConversationStore
    private var configuration: AgentConversationConfiguration
    private var theme: AgentChatTheme
    private let rendererRegistry: AgentBlockRendererRegistry
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let composer: AgentComposerView
    private let connectionBanner = UILabel()
    private let jumpToLatestButton = UIButton(type: .system)
    private let historyLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private var displayedTurns: [AgentTurn] = []
    private var updateScheduler: AgentUpdateScheduler!
    private var scrollCoordinator: AgentTableScrollCoordinator!
    private var patchTask: Task<Void, Never>?
    private var composerTask: Task<Void, Never>?
    private var expandedBlockIDs: Set<AgentBlockID> = []
    private var initializedExpansionBlockIDs: Set<AgentBlockID> = []
    private var resolvingApprovalIDs: Set<AgentApprovalID> = []
    private var isLoadingHistory = false
    private var isHistoryRequestArmed = false
    private var isPerformingTableUpdate = false
    private var pendingTableUpdate: AgentScheduledUpdate?
    private var pendingRowReconfigurationBlockIDs: Set<AgentBlockID> = []
    private var pendingHeightChangeBlockIDs: Set<AgentBlockID> = []
    private var needsInitialScrollToLatest = true
    private var bannerHeightConstraint: NSLayoutConstraint?

    /// Creates a scene-scoped UITableView conversation controller.
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
        self.composer = AgentComposerView(maximumHeight: configuration.maximumComposerHeight)
        super.init(nibName: nil, bundle: nil)
        composer.importHandler = { [weak self] providers, sourceView in
            guard let self else { return }
            self.delegate?.tableConversationViewController(
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
        displayedTurns = presentationTurns
        synchronizeDefaultExpansionState()
        tableView.reloadData()
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

    /// Replaces the current visual theme and reloads visible rows without animation.
    public func apply(theme: AgentChatTheme) {
        self.theme = theme
        view.backgroundColor = theme.colors.background
        tableView.backgroundColor = theme.colors.background
        UIView.performWithoutAnimation { tableView.reloadData() }
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

    /// Replaces host-defined composer controls.
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
        tableView.backgroundColor = theme.colors.background
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .interactive
        tableView.contentInsetAdjustmentBehavior = .always
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 28
        tableView.sectionFooterHeight = 8
        tableView.estimatedSectionFooterHeight = 8
        tableView.accessibilityIdentifier = "AgentTableConversationTimeline"

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
        jumpToLatestButton.translatesAutoresizingMaskIntoConstraints = false
        jumpToLatestButton.isHidden = true
        jumpToLatestButton.accessibilityIdentifier = "AgentConversationJumpToLatestButton"
        jumpToLatestButton.addAction(
            UIAction { [weak self] _ in self?.scrollCoordinator.scrollToLatest() },
            for: .touchUpInside
        )

        historyLoadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        historyLoadingIndicator.hidesWhenStopped = true
        historyLoadingIndicator.accessibilityIdentifier = "AgentHistoryLoadingIndicator"

        view.addSubview(connectionBanner)
        view.addSubview(tableView)
        view.addSubview(composer)
        view.addSubview(historyLoadingIndicator)
        view.addSubview(jumpToLatestButton)
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        NSLayoutConstraint.activate([
            connectionBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            connectionBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            connectionBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: connectionBanner.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
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
                equalTo: tableView.topAnchor, constant: 10),
        ])
    }

    private func configureDataSource() {
        rendererRegistry.registerAll(in: tableView)
        tableView.register(
            AgentTableTurnHeaderView.self,
            forHeaderFooterViewReuseIdentifier: AgentTableTurnHeaderView.reuseIdentifier
        )
        tableView.dataSource = self
        tableView.delegate = self
    }

    private func configureCoordinators() {
        scrollCoordinator = AgentTableScrollCoordinator(
            tableView: tableView,
            followingThreshold: configuration.followingThreshold,
            rowIdentifier: { [weak self] in self?.blockID(at: $0) },
            indexPath: { [weak self] in self?.indexPath(for: $0) },
            orderedBlockIDs: { [weak self] in
                self?.displayedTurns.flatMap { $0.blocks.map(\.id) } ?? []
            }
        )
        scrollCoordinator.didChangeUnreadCount = { [weak self] count in
            self?.updateJumpButton(unreadCount: count)
        }
        updateScheduler = AgentUpdateScheduler { [weak self] update in self?.apply(update) }
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
            for await action in composer.actionStream {
                guard !Task.isCancelled else { return }
                self.handleComposer(action)
            }
        }
    }

    private func apply(_ update: AgentScheduledUpdate) {
        guard !isPerformingTableUpdate else {
            mergePendingTableUpdate(update)
            return
        }

        updateConnectionBanner()
        updateComposerState()
        cleanupResolvedApprovalState()
        if update.patches.contains(where: {
            if case .historyStateChanged = $0 { return true }
            return false
        }) {
            setHistoryLoading(false)
        }

        if update.requiresStructuralReconciliation {
            let updatedTurns = presentationTurns
            let isPrepend = update.patches.contains {
                if case .prependTurns = $0 { return true }
                return false
            }
            let anchor = isPrepend ? scrollCoordinator.beginHistoryPrepend() : nil
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
                forceReload: update.patches.contains {
                    if case .replaceAll = $0 { return true }
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
        let updatedRows = update.reconfiguredBlockIDs
            .filter(existing.contains)
            .compactMap(indexPath(for:))
        let turnIDs = Set(
            update.patches.compactMap { patch -> AgentTurnID? in
                if case .reconfigureTurn(let turnID) = patch { return turnID }
                return nil
            })
        reconfigureVisibleTurnHeaders(ids: turnIDs)
        guard !updatedRows.isEmpty else { return }

        isPerformingTableUpdate = true
        let shouldFollow = scrollCoordinator.shouldAutomaticallyFollowLatest
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates {
                tableView.reloadRows(at: updatedRows, with: .none)
            } completion: { [weak self] _ in
                self?.finishTableUpdate(shouldFollow ? .followLatest : .none)
            }
        }
    }

    private func applyStructuralChanges(
        to updatedTurns: [AgentTurn],
        anchor: AgentLayoutAnchor?,
        followLatest: Bool,
        forceReload: Bool
    ) {
        isPerformingTableUpdate = true
        synchronizeDefaultExpansionState()
        let previousTurns = displayedTurns
        guard !forceReload,
            let changes = AgentTimelineBatchChanges(from: previousTurns, to: updatedTurns)
        else {
            displayedTurns = updatedTurns
            UIView.performWithoutAnimation { tableView.reloadData() }
            finishTableUpdate(completionIntent(anchor: anchor, followLatest: followLatest))
            return
        }

        guard changes.hasChanges else {
            displayedTurns = updatedTurns
            reloadVisibleRows()
            finishTableUpdate(completionIntent(anchor: anchor, followLatest: followLatest))
            return
        }

        displayedTurns = updatedTurns
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates {
                tableView.deleteRows(at: changes.deletedItems, with: .none)
                tableView.deleteSections(changes.deletedSections, with: .none)
                tableView.insertSections(changes.insertedSections, with: .none)
                tableView.insertRows(at: changes.insertedItems, with: .none)
            } completion: { [weak self] _ in
                guard let self else { return }
                self.reloadVisibleRows()
                self.finishTableUpdate(
                    self.completionIntent(anchor: anchor, followLatest: followLatest)
                )
            }
        }
    }

    private func mergePendingTableUpdate(_ update: AgentScheduledUpdate) {
        var pending = pendingTableUpdate ?? AgentScheduledUpdate()
        pending.requiresStructuralReconciliation =
            pending.requiresStructuralReconciliation || update.requiresStructuralReconciliation
        pending.reconfiguredBlockIDs.formUnion(update.reconfiguredBlockIDs)
        pending.patches.append(contentsOf: update.patches)
        pendingTableUpdate = pending
    }

    private func completionIntent(
        anchor: AgentLayoutAnchor?,
        followLatest: Bool
    ) -> AgentTableCompletionIntent {
        if let anchor { return .restoreHistory(anchor) }
        return followLatest ? .followLatest : .none
    }

    private func finishTableUpdate(_ intent: AgentTableCompletionIntent) {
        tableView.layoutIfNeeded()
        switch intent {
        case .none:
            break
        case .followLatest:
            if scrollCoordinator.shouldAutomaticallyFollowLatest {
                scrollCoordinator.scrollToLatest()
            }
        case .restoreHistory(let anchor):
            scrollCoordinator.restore(anchor)
        case .preserveBlock(let blockID, let viewportOffset):
            restoreViewportPosition(of: blockID, offset: viewportOffset)
        }
        completeTableUpdate()
    }

    private func completeTableUpdate() {
        isPerformingTableUpdate = false
        while !isPerformingTableUpdate {
            if let pending = pendingTableUpdate {
                pendingTableUpdate = nil
                apply(pending)
                return
            }
            if let blockID = pendingRowReconfigurationBlockIDs.first {
                pendingRowReconfigurationBlockIDs.remove(blockID)
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

    private func reloadVisibleRows() {
        guard let rows = tableView.indexPathsForVisibleRows, !rows.isEmpty else { return }
        UIView.performWithoutAnimation { tableView.reloadRows(at: rows, with: .none) }
        reconfigureVisibleTurnHeaders(ids: Set(displayedTurns.map(\.id)))
    }

    private func route(_ action: AgentBlockUIAction) {
        switch action {
        case .toggleExpanded(let blockID):
            if !expandedBlockIDs.insert(blockID).inserted { expandedBlockIDs.remove(blockID) }
            reconfigure(blockID)
        case .copy(let blockID):
            if let block = turnAndBlock(for: blockID)?.block {
                UIPasteboard.general.string = copyText(for: block)
            }
        case .openArtifact(let id):
            perform(.host(.openArtifact(id)))
        case .openFile(let reference):
            perform(.host(.openResource(reference)))
        case .previewImage(let reference, let alternativeText):
            perform(.host(.previewImage(reference: reference, alternativeText: alternativeText)))
        case .openLink(let url):
            guard let scheme = url.scheme?.lowercased(),
                ["http", "https", "mailto"].contains(scheme)
            else { return }
            perform(.host(.openURL(url)))
        case .retry(let blockID):
            perform(.runtime(.retry(.init(conversationID: store.snapshot.id, blockID: blockID))))
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
            delegate?.tableConversationViewController(self, didUpdateDraftAttachments: [])
            perform(
                .runtime(.submit(request)),
                failure: { [weak self] in
                    guard let self else { return }
                    self.composer.apply(pendingState)
                    self.delegate?.tableConversationViewController(
                        self,
                        didUpdateDraftAttachments: pendingState.attachments
                    )
                }
            )
        case .stop:
            guard configuration.runtimeCapabilities.contains(.interrupt) else { return }
            perform(.runtime(.interrupt(.init(conversationID: store.snapshot.id))))
        case .pickAttachments:
            guard configuration.runtimeCapabilities.contains(.attachments) else { return }
            delegate?.tableConversationViewControllerDidRequestAttachments(
                self, sourceView: composer)
        case .removeAttachment(let attachmentID):
            var state = currentComposerState()
            state.attachments.removeAll { $0.id == attachmentID }
            state.attachmentStatuses[attachmentID] = nil
            composer.apply(state)
            delegate?.tableConversationViewController(
                self,
                didUpdateDraftAttachments: state.attachments
            )
        case .retryAttachment(let attachmentID):
            delegate?.tableConversationViewController(
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
            (tableView.bounds.width - theme.metrics.maximumContentWidth) / 2
        )
        return max(1, tableView.bounds.width - inset * 2)
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
            displayedTurns[indexPath.section].blocks.indices.contains(indexPath.row)
        else { return nil }
        let turn = displayedTurns[indexPath.section]
        return (turn, turn.blocks[indexPath.row])
    }

    private func blockID(at indexPath: IndexPath) -> AgentBlockID? {
        displayedTurnAndBlock(at: indexPath)?.block.id
    }

    private func indexPath(for blockID: AgentBlockID) -> IndexPath? {
        for (section, turn) in displayedTurns.enumerated() {
            if let row = turn.blocks.firstIndex(where: { $0.id == blockID }) {
                return IndexPath(row: row, section: section)
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
            actionSink: AgentBlockActionSink { [weak self] action in self?.route(action) }
        )
    }

    private func reconfigureVisibleTurnHeaders(ids: Set<AgentTurnID>) {
        guard !ids.isEmpty else { return }
        for section in displayedTurns.indices where ids.contains(displayedTurns[section].id) {
            guard
                let header = tableView.headerView(forSection: section) as? AgentTableTurnHeaderView
            else { continue }
            header.configure(
                turn: displayedTurns[section],
                maximumContentWidth: theme.metrics.maximumContentWidth,
                sideInset: theme.metrics.pageInset
            )
        }
    }

    private func handleCellHeightChange(_ blockID: AgentBlockID) {
        guard !isPerformingTableUpdate else {
            pendingHeightChangeBlockIDs.insert(blockID)
            return
        }
        guard let path = indexPath(for: blockID),
            tableView.indexPathsForVisibleRows?.contains(path) == true
        else { return }

        isPerformingTableUpdate = true
        let shouldFollow = scrollCoordinator.shouldAutomaticallyFollowLatest
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil) { [weak self] _ in
                self?.finishTableUpdate(shouldFollow ? .followLatest : .none)
            }
        }
    }

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
        guard !isPerformingTableUpdate else {
            pendingRowReconfigurationBlockIDs.insert(blockID)
            return
        }
        guard let path = indexPath(for: blockID) else { return }
        let viewportOffset = tableView.rectForRow(at: path).minY - tableView.contentOffset.y
        isPerformingTableUpdate = true
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates {
                tableView.reloadRows(at: [path], with: .none)
            } completion: { [weak self] _ in
                self?.finishTableUpdate(
                    .preserveBlock(blockID, viewportOffset: viewportOffset)
                )
            }
        }
    }

    private func restoreViewportPosition(of blockID: AgentBlockID, offset: CGFloat) {
        guard let path = indexPath(for: blockID) else { return }
        let y = tableView.rectForRow(at: path).minY - offset
        tableView.setContentOffset(CGPoint(x: tableView.contentOffset.x, y: y), animated: false)
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
                else { return nil }
                return approval.approvalID
            }
        )
        resolvingApprovalIDs.formIntersection(unresolved)
    }

    private func copyText(for block: AgentBlock) -> String {
        switch block.content {
        case .userText(let value): value.text
        case .markdown(let value): value.markdown
        case .command(let value): value.output.text.isEmpty ? value.command : value.output.text
        case .custom(let value):
            (try? String(data: JSONEncoder().encode(value.payload), encoding: .utf8))
                ?? value.fallbackTitle
        default: String(describing: block.content)
        }
    }

    @objc private func sendFromKeyboard() { composer.submitCurrentInput() }
    @objc private func focusComposer() { composer.focus() }

    @objc private func stopFromKeyboard() {
        guard isConversationRunning else { return }
        handleComposer(.stop)
    }

    @objc private func applicationDidEnterBackground() { updateScheduler.setActive(false) }
    @objc private func applicationWillEnterForeground() { updateScheduler.setActive(true) }
}

extension AgentTableConversationViewController: UITableViewDataSource, UITableViewDelegate {
    public func numberOfSections(in tableView: UITableView) -> Int { displayedTurns.count }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayedTurns.indices.contains(section) else { return 0 }
        return displayedTurns[section].blocks.count
    }

    public func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let (turn, block) = displayedTurnAndBlock(at: indexPath) else {
            return UITableViewCell()
        }
        let cell = rendererRegistry.tableRenderer(for: block).dequeueConfiguredCell(
            from: tableView,
            at: indexPath,
            context: makeRenderContext(turn: turn, block: block)
        )
        if let cell = cell as? AgentTableBlockCell {
            cell.didChangeHeight = { [weak self, weak cell] in
                guard let self, let cell,
                    self.tableView.indexPath(for: cell) == self.indexPath(for: block.id)
                else { return }
                self.handleCellHeightChange(block.id)
            }
        }
        return cell
    }

    public func tableView(
        _ tableView: UITableView,
        viewForHeaderInSection section: Int
    ) -> UIView? {
        guard displayedTurns.indices.contains(section),
            let header = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: AgentTableTurnHeaderView.reuseIdentifier
            ) as? AgentTableTurnHeaderView
        else { return nil }
        header.configure(
            turn: displayedTurns[section],
            maximumContentWidth: theme.metrics.maximumContentWidth,
            sideInset: theme.metrics.pageInset
        )
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
                failure: { [weak self] in self?.setHistoryLoading(false) }
            )
        }
    }

    public func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate { finishScrollInteraction() }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishScrollInteraction()
    }
}

private enum AgentTableCompletionIntent {
    case none
    case followLatest
    case restoreHistory(AgentLayoutAnchor)
    case preserveBlock(AgentBlockID, viewportOffset: CGFloat)
}
