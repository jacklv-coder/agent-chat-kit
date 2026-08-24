import AgentChatKit
import UIKit

@MainActor
final class QuickStartConversationViewController: UIViewController {
    private let session: AgentChatSession
    private let conversationController: AgentConversationViewController

    init() {
        let conversationID: AgentConversationID = "quick-start"
        let store = AgentConversationStore(snapshot: .empty(conversationID: conversationID))
        self.session = AgentChatSession(
            adapter: ReferenceRuntimeAdapter(),
            configuration: .init(conversationID: conversationID),
            store: store
        )
        self.conversationController = AgentConversationViewController(
            store: store,
            configuration: .init(runtimeCapabilities: [.streamingText, .interrupt])
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
        title = "QuickStart"
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
        conversationController.actionHandler = { [session] action in
            guard case .runtime(let command) = action else { return }
            try await session.send(command)
        }
        Task { [weak self, session] in
            do {
                try await session.start()
            } catch {
                self?.present(error: error)
            }
        }
    }

    private func present(error: any Error) {
        let alert = UIAlertController(
            title: "Runtime error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
