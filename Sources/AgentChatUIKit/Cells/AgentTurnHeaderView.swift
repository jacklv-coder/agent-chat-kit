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
final class AgentTableTurnMetadataCell: UITableViewCell {
    static let reuseIdentifier = "AgentTableTurnMetadataCell"

    private let metadataContainer = UIView()
    private let timestampLabel = UILabel()
    private var maximumWidthConstraint: NSLayoutConstraint!
    private var contentWidthConstraint: NSLayoutConstraint!
    private var leadingTimestampConstraint: NSLayoutConstraint!
    private var trailingTimestampConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        metadataContainer.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.font = .preferredFont(forTextStyle: .caption2)
        timestampLabel.adjustsFontForContentSizeCategory = true
        timestampLabel.numberOfLines = 1
        timestampLabel.accessibilityIdentifier = "AgentTurnTimestamp"
        metadataContainer.addSubview(timestampLabel)
        contentView.addSubview(metadataContainer)
        maximumWidthConstraint = metadataContainer.widthAnchor.constraint(
            lessThanOrEqualToConstant: 900
        )
        contentWidthConstraint = metadataContainer.widthAnchor.constraint(
            equalTo: contentView.widthAnchor,
            constant: -32
        )
        contentWidthConstraint.priority = .defaultHigh
        leadingTimestampConstraint = timestampLabel.leadingAnchor.constraint(
            equalTo: metadataContainer.leadingAnchor
        )
        trailingTimestampConstraint = timestampLabel.trailingAnchor.constraint(
            equalTo: metadataContainer.trailingAnchor
        )
        NSLayoutConstraint.activate([
            metadataContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            metadataContainer.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentView.leadingAnchor,
                constant: 0
            ),
            metadataContainer.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor,
                constant: 0
            ),
            metadataContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            metadataContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            maximumWidthConstraint,
            contentWidthConstraint,
            timestampLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: metadataContainer.leadingAnchor
            ),
            timestampLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: metadataContainer.trailingAnchor
            ),
            timestampLabel.topAnchor.constraint(equalTo: metadataContainer.topAnchor),
            timestampLabel.bottomAnchor.constraint(
                equalTo: metadataContainer.bottomAnchor,
                constant: -4
            ),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        leadingTimestampConstraint.isActive = false
        trailingTimestampConstraint.isActive = false
        timestampLabel.text = nil
        timestampLabel.accessibilityLabel = nil
    }

    func configure(turn: AgentTurn, theme: AgentChatTheme) {
        leadingTimestampConstraint.isActive = false
        trailingTimestampConstraint.isActive = false
        let role: String
        switch turn.role {
        case .user:
            role = AgentStrings.you
            trailingTimestampConstraint.isActive = true
            timestampLabel.textAlignment = .right
        case .assistant:
            role = AgentStrings.assistant
            leadingTimestampConstraint.isActive = true
            timestampLabel.textAlignment = .left
        case .system:
            role = AgentStrings.system
            leadingTimestampConstraint.isActive = true
            timestampLabel.textAlignment = .left
        }
        let time = turn.createdAt.formatted(date: .omitted, time: .shortened)
        timestampLabel.text = time
        timestampLabel.textColor = theme.colors.secondaryText
        timestampLabel.accessibilityLabel = "\(role), \(time)"
        maximumWidthConstraint.constant = theme.metrics.maximumContentWidth
        contentWidthConstraint.constant = -theme.metrics.pageInset * 2
    }
}
