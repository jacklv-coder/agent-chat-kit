import UIKit

/// Semantic colors used by AgentChatUIKit.
@MainActor
public struct AgentChatColors {
    /// Timeline background.
    public var background: UIColor
    /// Primary text.
    public var primaryText: UIColor
    /// Secondary text and status detail.
    public var secondaryText: UIColor
    /// User-content background.
    public var userBackground: UIColor
    /// Tool and generic-card background.
    public var cardBackground: UIColor
    /// Accent and interactive controls.
    public var accent: UIColor
    /// Failure and high-risk controls.
    public var destructive: UIColor

    /// Creates semantic colors.
    public init(
        background: UIColor,
        primaryText: UIColor,
        secondaryText: UIColor,
        userBackground: UIColor,
        cardBackground: UIColor,
        accent: UIColor,
        destructive: UIColor
    ) {
        self.background = background
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.userBackground = userBackground
        self.cardBackground = cardBackground
        self.accent = accent
        self.destructive = destructive
    }
}

/// Dynamic Type text styles used by AgentChatUIKit.
@MainActor
public struct AgentChatTypography {
    /// Body text style.
    public var body: UIFont.TextStyle
    /// Tool title text style.
    public var headline: UIFont.TextStyle
    /// Secondary detail text style.
    public var detail: UIFont.TextStyle
    /// Code font base size before metrics scaling.
    public var codePointSize: CGFloat

    /// Creates typography tokens.
    public init(
        body: UIFont.TextStyle = .body,
        headline: UIFont.TextStyle = .headline,
        detail: UIFont.TextStyle = .subheadline,
        codePointSize: CGFloat = 14
    ) {
        self.body = body
        self.headline = headline
        self.detail = detail
        self.codePointSize = codePointSize
    }
}

/// Layout metrics used by AgentChatUIKit.
@MainActor
public struct AgentChatMetrics {
    /// Compact horizontal page inset.
    public var pageInset: CGFloat
    /// Maximum centered content width on iPad.
    public var maximumContentWidth: CGFloat
    /// Inter-block vertical spacing.
    public var blockSpacing: CGFloat
    /// User-content corner radius.
    public var cornerRadius: CGFloat

    /// Creates layout metrics.
    public init(
        pageInset: CGFloat = 16,
        maximumContentWidth: CGFloat = 900,
        blockSpacing: CGFloat = 8,
        cornerRadius: CGFloat = 14
    ) {
        self.pageInset = pageInset
        self.maximumContentWidth = maximumContentWidth
        self.blockSpacing = blockSpacing
        self.cornerRadius = cornerRadius
    }
}

/// Themeable icons used by AgentChatUIKit controls.
@MainActor
public struct AgentChatIcons {
    /// Composer send icon.
    public var send: UIImage?
    /// Composer stop icon.
    public var stop: UIImage?
    /// Attachment icon.
    public var attachment: UIImage?
    /// Jump-to-latest icon.
    public var jumpToLatest: UIImage?

    /// Creates icon tokens.
    public init(
        send: UIImage?,
        stop: UIImage?,
        attachment: UIImage?,
        jumpToLatest: UIImage?
    ) {
        self.send = send
        self.stop = stop
        self.attachment = attachment
        self.jumpToLatest = jumpToLatest
    }

    /// System Symbol defaults.
    public static var system: Self {
        .init(
            send: UIImage(systemName: "arrow.up"),
            stop: UIImage(systemName: "stop.fill"),
            attachment: UIImage(systemName: "paperclip"),
            jumpToLatest: UIImage(systemName: "arrow.down")
        )
    }
}

/// Theme tokens for a conversation UI.
@MainActor
public struct AgentChatTheme {
    /// Semantic colors.
    public var colors: AgentChatColors
    /// Dynamic Type styles.
    public var typography: AgentChatTypography
    /// Layout metrics.
    public var metrics: AgentChatMetrics
    /// Themeable control icons.
    public var icons: AgentChatIcons
    /// A caller-incremented cache invalidation version.
    public var version: Int

    /// Creates a theme.
    public init(
        colors: AgentChatColors,
        typography: AgentChatTypography = .init(),
        metrics: AgentChatMetrics = .init(),
        icons: AgentChatIcons = .system,
        version: Int = 1
    ) {
        self.colors = colors
        self.typography = typography
        self.metrics = metrics
        self.icons = icons
        self.version = version
    }

    /// The adaptive system theme.
    public static var system: Self {
        Self(
            colors: .init(
                background: .systemBackground,
                primaryText: .label,
                secondaryText: .secondaryLabel,
                userBackground: .secondarySystemFill,
                cardBackground: .secondarySystemBackground,
                accent: .systemBlue,
                destructive: .systemRed
            )
        )
    }
}
