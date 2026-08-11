import AgentChatKit
import AgentChatTesting
import UIKit
import UniformTypeIdentifiers

@MainActor
final class DemoConversationContainerViewController: UIViewController {
    private let scenario: DemoScenario
    private let playbackController: AgentScenarioPlaybackController
    private let session: AgentChatSession
    private let conversationController: AgentConversationViewController
    private let imageProvider: DemoImageProvider
    private var usesDarkTheme = false
    private var pendingAttachments: [AgentAttachment] = []
    private var composerAccessories = DemoConversationContainerViewController.defaultAccessories
    private var diagnosticsOverlay: DemoDiagnosticsOverlay?

    init(
        scenario: DemoScenario,
        playbackController: AgentScenarioPlaybackController = .init()
    ) {
        self.scenario = scenario
        self.playbackController = playbackController
        let imageProvider = DemoImageProvider()
        self.imageProvider = imageProvider
        let runtime = MockAgentRuntime(
            scenario: scenario.makeScenario(),
            playbackController: playbackController
        )
        let store = AgentConversationStore(
            snapshot: .empty(conversationID: scenario.conversationID)
        )
        self.session = AgentChatSession(
            adapter: runtime,
            configuration: .init(conversationID: scenario.conversationID),
            store: store
        )
        let registry = AgentBlockRendererRegistry.default
        registry.register(DemoWeatherRenderer())
        self.conversationController = AgentConversationViewController(
            store: store,
            configuration: .init(
                runtimeCapabilities: [
                    .streamingText, .tools, .commands, .fileOperations, .diffs,
                    .approvals, .attachments, .history, .retry, .interrupt, .customBlocks,
                ],
                composerAccessories: Self.defaultAccessories,
                composerContextDescription: "Demo",
                imageProvider: imageProvider
            ),
            rendererRegistry: registry
        )
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
        title = scenario.rawValue
        view.backgroundColor = .systemBackground
        conversationController.delegate = self
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
        conversationController.actionHandler = { [session, weak self] action in
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
        let playback = UIMenu(
            title: "Playback",
            options: .displayInline,
            children: [
                UIAction(title: "Play", image: UIImage(systemName: "play.fill")) {
                    [playbackController] _ in
                    Task { await playbackController.resume() }
                },
                UIAction(title: "Pause", image: UIImage(systemName: "pause.fill")) {
                    [playbackController] _ in
                    Task { await playbackController.pause() }
                },
                UIAction(title: "Step", image: UIImage(systemName: "forward.frame.fill")) {
                    [playbackController] _ in
                    Task { await playbackController.step() }
                },
                UIAction(title: "Reset", image: UIImage(systemName: "arrow.counterclockwise")) {
                    [weak self] _ in self?.resetScenario()
                },
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
        let rates = UIMenu(
            title: "Speed",
            children: [
                rateAction(title: "Instant", rate: 0),
                rateAction(title: "0.5×", rate: 0.5),
                rateAction(title: "1×", rate: 1),
                rateAction(title: "2×", rate: 2),
            ]
        )
        let fixture = UIMenu(
            title: "Fixture",
            options: .displayInline,
            children: [
                UIAction(title: "Copy Scenario JSON", image: UIImage(systemName: "doc.on.doc")) {
                    [weak self] _ in self?.copyScenarioJSON()
                }
            ]
        )
        return UIMenu(title: "AgentChat Test Lab", children: [playback, rates, fixture])
    }

    private func rateAction(title: String, rate: Double) -> UIAction {
        UIAction(title: title) { [playbackController] _ in
            Task {
                await playbackController.setRate(rate)
                await playbackController.resume()
            }
        }
    }

    private func configureDiagnosticsOverlay() {
        let collectionView = conversationController.view.allDescendants
            .compactMap { $0 as? UICollectionView }
            .first
        let overlay = DemoDiagnosticsOverlay(
            playbackController: playbackController,
            collectionView: collectionView
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

    private func resetScenario() {
        guard let navigationController else { return }
        let replacement = DemoConversationContainerViewController(scenario: scenario)
        var controllers = navigationController.viewControllers
        guard !controllers.isEmpty else { return }
        controllers[controllers.count - 1] = replacement
        navigationController.setViewControllers(controllers, animated: false)
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
        conversationController.apply(theme: .system)
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
                    self.conversationController.setComposerAccessories(self.composerAccessories)
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
        conversationController.setComposerAttachments(pendingAttachments)
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
