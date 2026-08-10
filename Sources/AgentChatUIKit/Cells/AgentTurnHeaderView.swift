import AgentChatCore
import UIKit

@MainActor
final class AgentTurnHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "AgentTurnHeaderView"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(turn: AgentTurn) {
        let role: String
        switch turn.role {
        case .user: role = AgentStrings.you
        case .assistant: role = AgentStrings.assistant
        case .system: role = AgentStrings.system
        }
        label.text = "\(role) · \(turn.createdAt.formatted(date: .omitted, time: .shortened))"
        accessibilityLabel = label.text
    }
}
