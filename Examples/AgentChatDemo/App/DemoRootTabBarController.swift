import UIKit

@MainActor
final class DemoRootTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "AgentChatDemoRootTabs"

        let conversations = makeNavigationController(
            root: DemoConversationListViewController(),
            title: "Chats",
            systemImageName: "bubble.left.and.bubble.right"
        )
        let testLab = makeNavigationController(
            root: ScenarioListViewController(timelineImplementation: .tableView),
            title: "Test Lab",
            systemImageName: "wrench.and.screwdriver"
        )

        viewControllers = [conversations, testLab]
        selectedIndex = 0
    }

    private func makeNavigationController(
        root: UIViewController,
        title: String,
        systemImageName: String
    ) -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: root)
        navigationController.navigationBar.prefersLargeTitles = true
        root.loadViewIfNeeded()
        navigationController.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: systemImageName),
            selectedImage: UIImage(systemName: "\(systemImageName).fill")
        )
        return navigationController
    }
}
