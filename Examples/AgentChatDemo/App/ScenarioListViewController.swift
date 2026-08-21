import AgentChatKit
import UIKit

@MainActor
final class ScenarioListViewController: UITableViewController {
    private let timelineImplementation:
        DemoConversationContainerViewController.TimelineImplementation
    private let toolPresentationStyle: AgentToolPresentationStyle

    init(
        timelineImplementation: DemoConversationContainerViewController.TimelineImplementation =
            .tableView,
        toolPresentationStyle: AgentToolPresentationStyle = .capsule
    ) {
        self.timelineImplementation = timelineImplementation
        self.toolPresentationStyle = toolPresentationStyle
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Test Lab"
        navigationItem.largeTitleDisplayMode = .always
        tableView.accessibilityIdentifier = "AgentChatDemoScenarioList"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "scenario")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        DemoScenario.allCases.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "scenario", for: indexPath)
        var content = cell.defaultContentConfiguration()
        let scenario = DemoScenario.allCases[indexPath.row]
        content.text = scenario.rawValue
        content.secondaryText = scenario.summary
        content.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "AgentChatDemoScenario.\(scenario.identifier)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let controller = DemoConversationContainerViewController(
            scenario: DemoScenario.allCases[indexPath.row],
            timelineImplementation: timelineImplementation,
            toolPresentationStyle: toolPresentationStyle
        )
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }
}
