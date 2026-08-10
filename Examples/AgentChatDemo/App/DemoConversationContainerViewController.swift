import AgentChatKit
import AgentChatTesting
import UIKit

@MainActor
final class DemoConversationContainerViewController: UIViewController {
    private let scenario: DemoScenario
    private let session: AgentChatSession
    private let conversationController: AgentConversationViewController
    private var usesDarkTheme = false

    init(scenario: DemoScenario) {
        self.scenario = scenario
        let runtime = MockAgentRuntime(scenario: scenario.makeScenario())
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
                ]
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
        conversationController.actionHandler = { [session, weak self] action in
            switch action {
            case .runtime(let command):
                try await session.send(command)
            case .host(let hostAction):
                self?.show(hostAction)
            }
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "circle.lefthalf.filled"),
            style: .plain,
            target: self,
            action: #selector(toggleTheme)
        )
        Task { [weak self, session] in
            do {
                try await session.start()
            } catch {
                self?.showError(error)
            }
        }
    }

    @objc private func toggleTheme() {
        usesDarkTheme.toggle()
        overrideUserInterfaceStyle = usesDarkTheme ? .dark : .light
        conversationController.apply(theme: .system)
    }

    private func show(_ action: AgentHostAction) {
        let alert = UIAlertController(
            title: "Host action",
            message: String(describing: action),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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
}
