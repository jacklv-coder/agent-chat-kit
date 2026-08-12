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

@MainActor
final class AgentTableTurnHeaderView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "AgentTableTurnHeaderView"
    private let label = UILabel()
    private var maximumWidthConstraint: NSLayoutConstraint!
    private var contentWidthConstraint: NSLayoutConstraint!

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        backgroundConfiguration = UIBackgroundConfiguration.clear()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        contentView.addSubview(label)
        maximumWidthConstraint = label.widthAnchor.constraint(lessThanOrEqualToConstant: 900)
        contentWidthConstraint = label.widthAnchor.constraint(
            equalTo: contentView.widthAnchor,
            constant: -32
        )
        contentWidthConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentView.leadingAnchor,
                constant: 16
            ),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor,
                constant: -16
            ),
            maximumWidthConstraint,
            contentWidthConstraint,
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(
        turn: AgentTurn,
        maximumContentWidth: CGFloat,
        sideInset: CGFloat
    ) {
        let role: String
        switch turn.role {
        case .user: role = AgentStrings.you
        case .assistant: role = AgentStrings.assistant
        case .system: role = AgentStrings.system
        }
        label.text = "\(role) · \(turn.createdAt.formatted(date: .omitted, time: .shortened))"
        maximumWidthConstraint.constant = maximumContentWidth
        contentWidthConstraint.constant = -sideInset * 2
        accessibilityLabel = label.text
    }
}
