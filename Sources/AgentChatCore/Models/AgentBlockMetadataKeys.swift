import Foundation

/// Optional, runtime-neutral metadata keys understood by the default presentation.
///
/// Adapters can provide these hints without changing the portable block payload. Renderers must
/// continue to work when every key is absent.
public enum AgentBlockMetadataKey {
    /// A short, user-facing action title, such as "Build demo application".
    public static let displayTitle = "agent.presentation.title"
    /// A quiet secondary line displayed beneath the action title.
    public static let displaySubtitle = "agent.presentation.subtitle"
    /// A longer user-safe detail shown only while the block is expanded.
    public static let expandedDetail = "agent.presentation.expanded-detail"
    /// Activity semantic kind. Use `reasoning` for a user-safe reasoning summary.
    public static let activityKind = "agent.activity.kind"
}
