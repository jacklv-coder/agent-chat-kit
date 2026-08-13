import AgentChatTesting
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--agentchat-uitest") {
            let identifier =
                process.environment["AGENTCHAT_SCENARIO"]
                ?? DemoScenario.completeShowcase.identifier
            let scenario = DemoScenario.scenario(identifier: identifier) ?? .completeShowcase
            let mode = process.environment["AGENTCHAT_PLAYBACK_MODE"] ?? "instant"
            let rate =
                mode == "instant"
                ? 0
                : Double(process.environment["AGENTCHAT_PLAYBACK_RATE"] ?? "1") ?? 1
            let playback = AgentScenarioPlaybackController(
                isPaused: mode == "paused",
                rate: rate
            )
            let timeline: DemoConversationContainerViewController.TimelineImplementation =
                process.environment["AGENTCHAT_TIMELINE"] == "table"
                ? .tableView
                : .collectionView
            let rootController = DemoConversationContainerViewController(
                scenario: scenario,
                playbackController: playback,
                timelineImplementation: timeline
            )
            window.rootViewController = UINavigationController(rootViewController: rootController)
        } else {
            window.rootViewController = DemoRootTabBarController()
        }
        window.makeKeyAndVisible()
        self.window = window
    }
}
