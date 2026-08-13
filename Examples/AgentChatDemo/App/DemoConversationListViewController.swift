import UIKit

@MainActor
final class DemoConversationListViewController: UITableViewController {
    private struct Conversation {
        let scenario: DemoScenario
        let title: String
        let preview: String
        let relativeDate: String
        let systemImageName: String
        let tintColor: UIColor
    }

    private let conversations: [Conversation] = [
        .init(
            scenario: .completeConversation,
            title: "AgentChatKit Demo",
            preview: "完整消息流、工具活动、历史分页与实时输入",
            relativeDate: "Now",
            systemImageName: "sparkles",
            tintColor: .systemBlue
        ),
        .init(
            scenario: .currentConversation,
            title: "SDK Integration",
            preview: "真实中文会话回放与完整 Cell 状态",
            relativeDate: "2m",
            systemImageName: "chevron.left.forwardslash.chevron.right",
            tintColor: .systemIndigo
        ),
        .init(
            scenario: .markdownShowcase,
            title: "Markdown Review",
            preview: "标题、列表、表格、链接、引用与代码块",
            relativeDate: "8m",
            systemImageName: "text.document",
            tintColor: .systemTeal
        ),
        .init(
            scenario: .basicStreaming,
            title: "Streaming Response",
            preview: "观察增量 Markdown 与底部跟随行为",
            relativeDate: "1h",
            systemImageName: "waveform",
            tintColor: .systemOrange
        ),
        .init(
            scenario: .longConversation,
            title: "Long Conversation",
            preview: "100 条消息的滚动与复用性能检查",
            relativeDate: "Yesterday",
            systemImageName: "list.bullet.rectangle",
            tintColor: .systemPurple
        ),
    ]

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Conversations"
        navigationItem.largeTitleDisplayMode = .always
        tableView.accessibilityIdentifier = "AgentChatDemoConversationList"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "conversation")
        tableView.estimatedRowHeight = 76
        tableView.rowHeight = UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        conversations.count
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        "Recent"
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        "Offline conversations powered by AgentChatTesting. Send any message to replay a complete agent response."
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let conversation = conversations[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "conversation", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = conversation.title
        content.secondaryText = "\(conversation.relativeDate) · \(conversation.preview)"
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: conversation.systemImageName)
        content.imageProperties.tintColor = conversation.tintColor
        content.imageProperties.preferredSymbolConfiguration = .init(pointSize: 19, weight: .medium)
        content.imageProperties.reservedLayoutSize = CGSize(width: 42, height: 42)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier =
            "AgentChatDemoConversation.\(conversation.scenario.identifier)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let controller = DemoConversationContainerViewController(
            scenario: conversations[indexPath.row].scenario,
            timelineImplementation: .tableView
        )
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }
}
