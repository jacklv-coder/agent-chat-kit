import AgentChatKit
import AgentChatTesting
import UIKit
import UniformTypeIdentifiers

@MainActor
final class DemoConversationContainerViewController: UIViewController {
    enum TimelineImplementation: Equatable {
        case collectionView
        case tableView
    }

    private let scenario: DemoScenario
    private let timelineImplementation: TimelineImplementation
    private let toolPresentationStyle: AgentToolPresentationStyle
    private let playbackController: AgentScenarioPlaybackController
    private let scriptedEventCount: Int
    private let store: AgentConversationStore
    private let session: AgentChatSession
    private let conversationController: UIViewController
    private let imageProvider: DemoImageProvider
    private var usesDarkTheme = false
    private var pendingAttachments: [AgentAttachment] = []
    private var composerAccessories = DemoConversationContainerViewController.defaultAccessories
    private var diagnosticsOverlay: DemoDiagnosticsOverlay?

    init(
        scenario: DemoScenario,
        playbackController: AgentScenarioPlaybackController = .init(),
        timelineImplementation: TimelineImplementation = .tableView,
        toolPresentationStyle: AgentToolPresentationStyle = .capsule
    ) {
        self.scenario = scenario
        self.timelineImplementation = timelineImplementation
        self.toolPresentationStyle = toolPresentationStyle
        self.playbackController = playbackController
        let scenarioDefinition = scenario.makeScenario()
        self.scriptedEventCount = scenarioDefinition.events.count
        let imageProvider = DemoImageProvider()
        self.imageProvider = imageProvider
        let runtime = MockAgentRuntime(
            scenario: scenarioDefinition,
            playbackController: playbackController
        )
        let store = AgentConversationStore(
            snapshot: .empty(conversationID: scenario.conversationID)
        )
        self.store = store
        self.session = AgentChatSession(
            adapter: runtime,
            configuration: .init(conversationID: scenario.conversationID),
            store: store
        )
        let registry = AgentBlockRendererRegistry.default
        registry.register(DemoWeatherRenderer())
        let configuration = AgentConversationConfiguration(
            runtimeCapabilities: [
                .streamingText, .tools, .commands, .fileOperations, .diffs,
                .approvals, .attachments, .history, .retry, .interrupt, .customBlocks,
            ],
            composerAccessories: Self.defaultAccessories,
            composerContextDescription: "Demo",
            imageProvider: imageProvider,
            toolPresentationStyle: toolPresentationStyle
        )
        switch timelineImplementation {
        case .collectionView:
            self.conversationController = AgentConversationViewController(
                store: store,
                configuration: configuration,
                rendererRegistry: registry
            )
        case .tableView:
            self.conversationController = AgentTableConversationViewController(
                store: store,
                configuration: configuration,
                rendererRegistry: registry
            )
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        let session = session
        Task { await session.stop() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title =
            timelineImplementation == .tableView
            ? "\(scenario.rawValue) · TableView"
            : scenario.rawValue
        view.backgroundColor = .systemBackground
        if let controller = conversationController as? AgentConversationViewController {
            controller.delegate = self
        } else if let controller = conversationController as? AgentTableConversationViewController {
            controller.delegate = self
        }
        addChild(conversationController)
        conversationController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(conversationController.view)
        NSLayoutConstraint.activate([
            conversationController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            conversationController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            conversationController.view.topAnchor.constraint(equalTo: view.topAnchor),
            conversationController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        conversationController.didMove(toParent: self)
        configureDiagnosticsOverlay()
        setActionHandler { [session, weak self] action in
            switch action {
            case .runtime(let command):
                try await session.send(command)
            case .host(let hostAction):
                self?.show(hostAction)
            }
        }
        configureNavigationItems()
        Task { [weak self, session] in
            do {
                try await session.start()
            } catch {
                self?.showError(error)
            }
        }
    }

    private func setActionHandler(_ handler: @escaping AgentActionHandler) {
        if let controller = conversationController as? AgentConversationViewController {
            controller.actionHandler = handler
        } else if let controller = conversationController as? AgentTableConversationViewController {
            controller.actionHandler = handler
        }
    }

    private func configureNavigationItems() {
        let theme = UIBarButtonItem(
            image: UIImage(systemName: "circle.lefthalf.filled"),
            style: .plain,
            target: self,
            action: #selector(toggleTheme)
        )
        theme.accessibilityLabel = "Toggle theme"
        let lab = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            menu: makeTestLabMenu()
        )
        lab.accessibilityLabel = "Test Lab"
        lab.accessibilityIdentifier = "AgentChatDemoTestLab"
        navigationItem.rightBarButtonItems = [theme, lab]
    }

    private func makeTestLabMenu() -> UIMenu {
        let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }
            Task { @MainActor [weak self] in
                guard let self else {
                    completion([])
                    return
                }
                let state = await self.playbackController.state()
                completion(self.makeTestLabElements(playbackState: state))
            }
        }
        return UIMenu(title: "AgentChat Test Lab", children: [deferred])
    }

    private func makeTestLabElements(
        playbackState: AgentScenarioPlaybackController.State
    ) -> [UIMenuElement] {
        var elements: [UIMenuElement] = []
        if scenario == .completeConversation {
            let sample = UIAction(
                title: "Run Sample Response",
                image: UIImage(systemName: "sparkles"),
                attributes: isConversationRunning ? .disabled : []
            ) { [weak self] _ in
                self?.runSampleResponse()
            }
            sample.accessibilityIdentifier = "AgentChatDemoRunSampleResponse"
            elements.append(
                UIMenu(title: "Demo", options: .displayInline, children: [sample])
            )
        }

        let alternateTimelineTitle =
            timelineImplementation == .collectionView
            ? "Open TableView Version"
            : "Open CollectionView Version"
        let alternateTimeline = UIAction(
            title: alternateTimelineTitle,
            image: UIImage(systemName: "rectangle.2.swap")
        ) { [weak self] _ in
            self?.openAlternateTimeline()
        }
        alternateTimeline.accessibilityIdentifier = "AgentChatDemoAlternateTimeline"
        elements.append(
            UIMenu(title: "Timeline", options: .displayInline, children: [alternateTimeline])
        )

        let appearanceActions: [UIAction] = [
            (.capsule, "Capsule", "capsule"),
            (.inline, "Inline", "list.bullet"),
        ].map { style, title, icon in
            UIAction(
                title: title,
                image: UIImage(systemName: icon),
                state: toolPresentationStyle == style ? .on : .off
            ) { [weak self] _ in
                self?.openToolPresentation(style)
            }
        }
        elements.append(
            UIMenu(
                title: "Tool Appearance",
                options: [.displayInline, .singleSelection],
                children: appearanceActions
            )
        )

        let scenarios = UIMenu(
            title: "Scenarios",
            options: .displayInline,
            children: [
                UIAction(
                    title: "Browse All Scenarios",
                    image: UIImage(systemName: "list.bullet.rectangle")
                ) { [weak self] _ in
                    self?.openScenarioBrowser()
                }
            ]
        )
        elements.append(scenarios)

        let isPlaybackComplete =
            scriptedEventCount > 0
            && playbackState.emittedEventCount >= scriptedEventCount
        let statusTitle: String
        let statusImage: String
        if isPlaybackComplete {
            statusTitle = "Playback: Completed"
            statusImage = "checkmark.circle.fill"
        } else if playbackState.isPaused {
            statusTitle = "Playback: Paused"
            statusImage = "pause.circle.fill"
        } else {
            statusTitle = "Playback: Playing"
            statusImage = "play.circle.fill"
        }
        let status = UIAction(
            title:
                "\(statusTitle) · \(min(playbackState.emittedEventCount, scriptedEventCount))/\(scriptedEventCount)",
            image: UIImage(systemName: statusImage),
            attributes: .disabled
        ) { _ in }
        status.accessibilityIdentifier = "AgentChatDemoPlaybackStatus"

        let resume = UIAction(
            title: "Resume",
            image: UIImage(systemName: "play.fill"),
            attributes: isPlaybackComplete || !playbackState.isPaused ? .disabled : []
        ) { [playbackController] _ in
            Task { await playbackController.resume() }
        }
        resume.accessibilityIdentifier = "AgentChatDemoPlaybackResume"

        let pause = UIAction(
            title: "Pause",
            image: UIImage(systemName: "pause.fill"),
            attributes: isPlaybackComplete || playbackState.isPaused ? .disabled : []
        ) { [playbackController] _ in
            Task { await playbackController.pause() }
        }
        pause.accessibilityIdentifier = "AgentChatDemoPlaybackPause"

        let step = UIAction(
            title: "Step",
            image: UIImage(systemName: "forward.frame.fill"),
            attributes: isPlaybackComplete || !playbackState.isPaused ? .disabled : []
        ) { [playbackController] _ in
            Task { await playbackController.step() }
        }
        step.accessibilityIdentifier = "AgentChatDemoPlaybackStep"

        let replay = UIAction(
            title: "Replay Scenario",
            image: UIImage(systemName: "arrow.clockwise")
        ) { [weak self] _ in
            self?.replaceScenario(startPaused: false)
        }
        replay.accessibilityIdentifier = "AgentChatDemoPlaybackReplay"

        let resetPaused = UIAction(
            title: "Reset Paused",
            image: UIImage(systemName: "arrow.counterclockwise")
        ) { [weak self] _ in
            self?.replaceScenario(startPaused: true)
        }
        resetPaused.accessibilityIdentifier = "AgentChatDemoPlaybackResetPaused"

        let playback = UIMenu(
            title: "Playback",
            options: .displayInline,
            children: [
                status, resume, pause, step, replay, resetPaused,
                UIAction(
                    title: "Toggle Diagnostics",
                    image: UIImage(systemName: "gauge.with.dots.needle.67percent")
                ) {
                    [weak self] _ in
                    guard let overlay = self?.diagnosticsOverlay else { return }
                    overlay.isHidden.toggle()
                },
            ]
        )
        elements.append(playback)

        let rates = UIMenu(
            title: "Speed",
            children: [
                rateAction(title: "Instant", rate: 0, selectedRate: playbackState.rate),
                rateAction(title: "0.5×", rate: 0.5, selectedRate: playbackState.rate),
                rateAction(title: "1×", rate: 1, selectedRate: playbackState.rate),
                rateAction(title: "2×", rate: 2, selectedRate: playbackState.rate),
            ]
        )
        elements.append(rates)

        let fixture = UIMenu(
            title: "Fixture",
            options: .displayInline,
            children: [
                UIAction(title: "Copy Scenario JSON", image: UIImage(systemName: "doc.on.doc")) {
                    [weak self] _ in self?.copyScenarioJSON()
                }
            ]
        )
        elements.append(fixture)
        return elements
    }

    private func openScenarioBrowser() {
        navigationController?.pushViewController(
            preservingTabBarVisibility(
                ScenarioListViewController(
                    timelineImplementation: timelineImplementation,
                    toolPresentationStyle: toolPresentationStyle
                )
            ),
            animated: true
        )
    }

    private func openAlternateTimeline() {
        let implementation: TimelineImplementation =
            timelineImplementation == .collectionView
            ? .tableView
            : .collectionView
        Task { @MainActor [weak self] in
            guard let self, let navigationController else { return }
            let state = await playbackController.state()
            navigationController.pushViewController(
                preservingTabBarVisibility(
                    DemoConversationContainerViewController(
                        scenario: scenario,
                        playbackController: .init(isPaused: state.isPaused, rate: state.rate),
                        timelineImplementation: implementation,
                        toolPresentationStyle: toolPresentationStyle
                    )
                ),
                animated: true
            )
        }
    }

    private func openToolPresentation(_ style: AgentToolPresentationStyle) {
        guard style != toolPresentationStyle else { return }
        Task { @MainActor [weak self] in
            guard let self, let navigationController else { return }
            let state = await playbackController.state()
            let replacement = preservingTabBarVisibility(
                DemoConversationContainerViewController(
                    scenario: scenario,
                    playbackController: .init(isPaused: state.isPaused, rate: state.rate),
                    timelineImplementation: timelineImplementation,
                    toolPresentationStyle: style
                )
            )
            var controllers = navigationController.viewControllers
            guard !controllers.isEmpty else { return }
            controllers[controllers.count - 1] = replacement
            navigationController.setViewControllers(controllers, animated: false)
        }
    }

    private func rateAction(title: String, rate: Double, selectedRate: Double) -> UIAction {
        let action = UIAction(title: title) { [playbackController] _ in
            Task { await playbackController.setRate(rate) }
        }
        action.state = selectedRate == rate ? .on : .off
        return action
    }

    private func configureDiagnosticsOverlay() {
        let timeline =
            conversationController.view.allDescendants
            .first { $0 is UICollectionView || $0 is UITableView } as? UIScrollView
        let overlay = DemoDiagnosticsOverlay(
            playbackController: playbackController,
            scrollView: timeline
        )
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isHidden = true
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
        ])
        diagnosticsOverlay = overlay
    }

    private func replaceScenario(startPaused: Bool) {
        Task { @MainActor [weak self] in
            guard let self, let navigationController else { return }
            let state = await playbackController.state()
            let replacement = preservingTabBarVisibility(
                DemoConversationContainerViewController(
                    scenario: scenario,
                    playbackController: .init(isPaused: startPaused, rate: state.rate),
                    timelineImplementation: timelineImplementation,
                    toolPresentationStyle: toolPresentationStyle
                )
            )
            var controllers = navigationController.viewControllers
            guard !controllers.isEmpty else { return }
            controllers[controllers.count - 1] = replacement
            navigationController.setViewControllers(controllers, animated: false)
        }
    }

    private func runSampleResponse() {
        guard scenario == .completeConversation, !isConversationRunning else { return }
        let conversationID = scenario.conversationID
        Task { [weak self, session] in
            do {
                try await session.send(
                    .submit(
                        .init(
                            conversationID: conversationID,
                            text: "运行完整示例，依次展示思考、工具活动与流式 Markdown。",
                            metadata: ["demo.trigger": .string("test-lab")]
                        )
                    )
                )
            } catch {
                self?.showError(error)
            }
        }
    }

    private var isConversationRunning: Bool {
        guard let state = store.snapshot.turns.last?.state else { return false }
        switch state {
        case .streaming, .running, .waitingForApproval: return true
        default: return false
        }
    }

    private func preservingTabBarVisibility<Controller: UIViewController>(
        _ controller: Controller
    ) -> Controller {
        controller.hidesBottomBarWhenPushed = hidesBottomBarWhenPushed
        return controller
    }

    private func copyScenarioJSON() {
        do {
            let data = try scenario.makeDocument().encodedJSON()
            UIPasteboard.general.string = String(decoding: data, as: UTF8.self)
            navigationItem.prompt = "Scenario JSON copied"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.navigationItem.prompt = nil
            }
        } catch {
            showError(error)
        }
    }

    @objc private func toggleTheme() {
        usesDarkTheme.toggle()
        overrideUserInterfaceStyle = usesDarkTheme ? .dark : .light
        if let controller = conversationController as? AgentConversationViewController {
            controller.apply(theme: .system)
        } else if let controller = conversationController as? AgentTableConversationViewController {
            controller.apply(theme: .system)
        }
    }

    private func show(_ action: AgentHostAction) {
        if case .previewImage(let reference, let alternativeText) = action {
            let preview = DemoImagePreviewViewController(
                reference: reference,
                alternativeText: alternativeText,
                provider: imageProvider
            )
            let navigationController = UINavigationController(rootViewController: preview)
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true)
            return
        }
        if case .custom(let kind, let payload) = action,
            kind == "agentchat.composer.accessory",
            case .object(let object) = payload,
            case .string(let id) = object["id"]
        {
            showAccessoryPicker(id: id)
            return
        }
        let alert = UIAlertController(
            title: "Host action",
            message: String(describing: action),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showAccessoryPicker(id: String) {
        let values: [String]
        switch id {
        case "model": values = ["GPT-5", "Claude", "Local"]
        case "reasoning": values = ["Low", "Medium", "High"]
        case "workspace": values = ["Demo", "App", "Package"]
        default: values = ["Default"]
        }
        let sheet = UIAlertController(
            title: composerAccessories.first(where: { $0.id == id })?.title,
            message: "This control is supplied by the host app.",
            preferredStyle: .actionSheet
        )
        for value in values {
            sheet.addAction(
                UIAlertAction(title: value, style: .default) { [weak self] _ in
                    guard let self,
                        let index = self.composerAccessories.firstIndex(where: { $0.id == id })
                    else { return }
                    self.composerAccessories[index].title = value
                    self.composerAccessories[index].isSelected = true
                    self.setComposerAccessories(self.composerAccessories)
                })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem =
            navigationItem.rightBarButtonItems?.last
        present(sheet, animated: true)
    }

    private func appendAttachments(_ attachments: [AgentAttachment]) {
        for attachment in attachments
        where !pendingAttachments.contains(where: { $0.id == attachment.id }) {
            pendingAttachments.append(attachment)
        }
        if let controller = conversationController as? AgentConversationViewController {
            controller.setComposerAttachments(pendingAttachments)
        } else if let controller = conversationController as? AgentTableConversationViewController {
            controller.setComposerAttachments(pendingAttachments)
        }
    }

    private func setComposerAccessories(_ accessories: [AgentComposerAccessory]) {
        if let controller = conversationController as? AgentConversationViewController {
            controller.setComposerAccessories(accessories)
        } else if let controller = conversationController as? AgentTableConversationViewController {
            controller.setComposerAccessories(accessories)
        }
    }

    private func showError(_ error: any Error) {
        let alert = UIAlertController(
            title: "Runtime error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private static let defaultAccessories = [
        AgentComposerAccessory(id: "model", title: "GPT-5", systemImageName: "cpu"),
        AgentComposerAccessory(
            id: "reasoning",
            title: "Medium",
            systemImageName: "brain"
        ),
        AgentComposerAccessory(
            id: "workspace",
            title: "Demo",
            systemImageName: "folder"
        ),
    ]
}

extension DemoConversationContainerViewController: AgentConversationViewControllerDelegate {
    func conversationViewControllerDidRequestAttachments(
        _ controller: AgentConversationViewController,
        sourceView: UIView
    ) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func conversationViewController(
        _ controller: AgentConversationViewController,
        didPaste itemProviders: [NSItemProvider],
        sourceView: UIView
    ) {
        let attachments = itemProviders.enumerated().map { index, provider in
            let typeIdentifier = provider.registeredTypeIdentifiers.first
            let mediaType = typeIdentifier.flatMap(UTType.init)?.preferredMIMEType
            return AgentAttachment(
                id: .init(rawValue: "paste-\(UUID().uuidString)"),
                name: provider.suggestedName ?? "Pasted item \(index + 1)",
                mediaType: mediaType,
                reference: .localIdentifier("demo-paste-\(UUID().uuidString)")
            )
        }
        appendAttachments(attachments)
    }

    func conversationViewController(
        _ controller: AgentConversationViewController,
        didRequestRetryFor attachmentID: AgentAttachmentID
    ) {
        controller.setComposerAttachmentStatus(.uploading(progress: nil), for: attachmentID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            controller.setComposerAttachmentStatus(.ready, for: attachmentID)
        }
    }

    func conversationViewController(
        _ controller: AgentConversationViewController,
        didUpdateDraftAttachments attachments: [AgentAttachment]
    ) {
        pendingAttachments = attachments
    }
}

extension DemoConversationContainerViewController: AgentTableConversationViewControllerDelegate {
    func tableConversationViewControllerDidRequestAttachments(
        _ controller: AgentTableConversationViewController,
        sourceView: UIView
    ) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func tableConversationViewController(
        _ controller: AgentTableConversationViewController,
        didPaste itemProviders: [NSItemProvider],
        sourceView: UIView
    ) {
        let attachments = itemProviders.enumerated().map { index, provider in
            let typeIdentifier = provider.registeredTypeIdentifiers.first
            let mediaType = typeIdentifier.flatMap(UTType.init)?.preferredMIMEType
            return AgentAttachment(
                id: .init(rawValue: "paste-\(UUID().uuidString)"),
                name: provider.suggestedName ?? "Pasted item \(index + 1)",
                mediaType: mediaType,
                reference: .localIdentifier("demo-paste-\(UUID().uuidString)")
            )
        }
        appendAttachments(attachments)
    }

    func tableConversationViewController(
        _ controller: AgentTableConversationViewController,
        didRequestRetryFor attachmentID: AgentAttachmentID
    ) {
        controller.setComposerAttachmentStatus(.uploading(progress: nil), for: attachmentID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            controller.setComposerAttachmentStatus(.ready, for: attachmentID)
        }
    }

    func tableConversationViewController(
        _ controller: AgentTableConversationViewController,
        didUpdateDraftAttachments attachments: [AgentAttachment]
    ) {
        pendingAttachments = attachments
    }
}

extension DemoConversationContainerViewController: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        let attachments = urls.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let identifier = UUID().uuidString
            return AgentAttachment(
                id: .init(rawValue: "file-\(identifier)"),
                name: url.lastPathComponent,
                mediaType: values?.contentType?.preferredMIMEType,
                byteCount: values?.fileSize.map(Int64.init),
                reference: .localIdentifier("demo-file-\(identifier)")
            )
        }
        appendAttachments(attachments)
    }
}

extension UIView {
    fileprivate var allDescendants: [UIView] { subviews + subviews.flatMap(\.allDescendants) }
}
