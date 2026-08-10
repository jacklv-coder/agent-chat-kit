import UIKit

@MainActor
final class ScenarioListViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AgentChatKit"
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
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
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(
            DemoConversationContainerViewController(
                scenario: DemoScenario.allCases[indexPath.row]
            ),
            animated: true
        )
    }
}
