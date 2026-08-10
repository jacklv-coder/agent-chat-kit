import Foundation

/// A user-safe failure description supplied by Core or a runtime.
public struct AgentFailure: Error, Hashable, Codable, Sendable {
    /// A stable machine-readable code.
    public var code: String
    /// A user-safe message.
    public var message: String
    /// Whether retry may succeed.
    public var isRetryable: Bool

    /// Creates a failure description.
    public init(code: String, message: String, isRetryable: Bool = false) {
        self.code = code
        self.message = message
        self.isRetryable = isRetryable
    }
}

/// The connection and execution state of a conversation.
public enum AgentConversationState: Hashable, Codable, Sendable {
    /// No connection has been started.
    case idle
    /// A connection is being established.
    case connecting
    /// The runtime connection is active.
    case connected
    /// The last state is retained while the runtime is unavailable.
    case offline(message: String?)
    /// The runtime ended with a terminal failure.
    case failed(AgentFailure)
}

/// An immutable-at-the-boundary snapshot of a conversation.
public struct AgentConversationSnapshot: Hashable, Codable, Sendable {
    /// The conversation identifier.
    public var id: AgentConversationID
    /// An optional display title.
    public var title: String?
    /// Ordered turns from oldest to newest.
    public var turns: [AgentTurn]
    /// The current conversation state.
    public var state: AgentConversationState
    /// The cursor used to request the next earlier page.
    public var earlierHistoryCursor: AgentHistoryCursor?
    /// Whether the runtime reports additional earlier history.
    public var hasEarlierHistory: Bool
    /// Runtime-neutral metadata.
    public var metadata: [String: JSONValue]

    /// Creates a conversation snapshot.
    public init(
        id: AgentConversationID,
        title: String? = nil,
        turns: [AgentTurn] = [],
        state: AgentConversationState = .idle,
        earlierHistoryCursor: AgentHistoryCursor? = nil,
        hasEarlierHistory: Bool = false,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.title = title
        self.turns = turns
        self.state = state
        self.earlierHistoryCursor = earlierHistoryCursor
        self.hasEarlierHistory = hasEarlierHistory
        self.metadata = metadata
    }

    /// Creates the initial empty snapshot for a conversation.
    public static func empty(conversationID: AgentConversationID) -> Self {
        Self(id: conversationID)
    }
}

/// The author of a turn.
public enum AgentTurnRole: String, Codable, Sendable {
    /// Input authored by the user.
    case user
    /// Output authored by the assistant runtime.
    case assistant
    /// System-visible content.
    case system
}

/// The lifecycle of a turn.
public enum AgentTurnState: Hashable, Codable, Sendable {
    /// The turn is waiting to start.
    case pending
    /// Text is streaming.
    case streaming
    /// Tools are running.
    case running
    /// User approval is required.
    case waitingForApproval
    /// The turn completed successfully.
    case completed
    /// The turn failed.
    case failed(AgentFailure)
    /// The turn was cancelled.
    case cancelled
}

/// An ordered conversation turn containing independently rendered blocks.
public struct AgentTurn: Identifiable, Hashable, Codable, Sendable {
    /// The turn identifier.
    public var id: AgentTurnID
    /// The turn author.
    public var role: AgentTurnRole
    /// Ordered content blocks.
    public var blocks: [AgentBlock]
    /// The turn lifecycle state.
    public var state: AgentTurnState
    /// The runtime creation timestamp.
    public var createdAt: Date
    /// The runtime completion timestamp.
    public var completedAt: Date?
    /// Runtime-neutral metadata.
    public var metadata: [String: JSONValue]

    /// Creates a turn.
    public init(
        id: AgentTurnID,
        role: AgentTurnRole,
        blocks: [AgentBlock] = [],
        state: AgentTurnState = .pending,
        createdAt: Date,
        completedAt: Date? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.state = state
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.metadata = metadata
    }
}

/// An extensible, namespaced block kind.
public struct AgentBlockKind: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    /// The namespaced serialized kind.
    public let rawValue: String
    /// Creates a block kind.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates a block kind from a string literal.
    public init(stringLiteral value: String) { rawValue = value }
    /// The namespaced serialized kind.
    public var description: String { rawValue }

    /// User-authored text.
    public static let userText = Self(rawValue: "user.text")
    /// Assistant Markdown.
    public static let markdown = Self(rawValue: "assistant.markdown")
    /// A user-readable activity summary.
    public static let activity = Self(rawValue: "agent.activity")
    /// A generic tool invocation.
    public static let tool = Self(rawValue: "tool.generic")
    /// A command invocation and output.
    public static let command = Self(rawValue: "tool.command")
    /// A file search.
    public static let fileSearch = Self(rawValue: "tool.file-search")
    /// A file operation summary.
    public static let fileOperation = Self(rawValue: "tool.file-operation")
    /// A unified diff.
    public static let diff = Self(rawValue: "tool.diff")
    /// A human approval request.
    public static let approval = Self(rawValue: "agent.approval")
    /// A host-owned artifact.
    public static let artifact = Self(rawValue: "agent.artifact")
    /// Referenced image content.
    public static let image = Self(rawValue: "content.image")
    /// A user-safe error.
    public static let error = Self(rawValue: "agent.error")
}

/// The lifecycle of a block.
public enum AgentBlockState: Hashable, Codable, Sendable {
    /// The block is queued.
    case queued
    /// Content is streaming.
    case streaming
    /// Work is running, optionally with normalized progress.
    case running(progress: Double?)
    /// User approval is required.
    case waitingForApproval
    /// Work succeeded.
    case succeeded
    /// Work failed.
    case failed(AgentFailure)
    /// Work was cancelled.
    case cancelled
}

/// An independently rendered block in a conversation turn.
public struct AgentBlock: Identifiable, Hashable, Codable, Sendable {
    /// The block identifier.
    public var id: AgentBlockID
    /// The renderer-selection kind.
    public var kind: AgentBlockKind
    /// Portable block content.
    public var content: AgentBlockContent
    /// The block lifecycle state.
    public var state: AgentBlockState
    /// A monotonically increasing revision.
    public var revision: Int64
    /// The runtime creation timestamp.
    public var createdAt: Date
    /// The runtime last-update timestamp.
    public var updatedAt: Date
    /// Runtime-neutral metadata.
    public var metadata: [String: JSONValue]

    /// Creates a content block.
    public init(
        id: AgentBlockID,
        kind: AgentBlockKind,
        content: AgentBlockContent,
        state: AgentBlockState = .queued,
        revision: Int64 = 0,
        createdAt: Date,
        updatedAt: Date? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.state = state
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.metadata = metadata
    }

    /// Whether an in-package kind agrees with its content case.
    public var hasCompatibleKindAndContent: Bool {
        switch (kind, content) {
        case (.userText, .userText), (.markdown, .markdown), (.activity, .activity),
            (.tool, .tool), (.command, .command), (.fileSearch, .fileSearch),
            (.fileOperation, .fileOperation), (.diff, .diff), (.approval, .approval),
            (.artifact, .artifact), (.image, .image), (.error, .error):
            true
        case (_, .custom(let custom)): custom.kind == kind.rawValue
        default:
            false
        }
    }

    private static let builtInKinds: Set<AgentBlockKind> = [
        .userText, .markdown, .activity, .tool, .command, .fileSearch, .fileOperation,
        .diff, .approval, .artifact, .image, .error,
    ]
}

/// Portable content for built-in and custom blocks.
public enum AgentBlockContent: Hashable, Codable, Sendable {
    /// User-authored content.
    case userText(UserTextBlock)
    /// Assistant Markdown.
    case markdown(MarkdownBlock)
    /// A user-readable activity summary.
    case activity(ActivityBlock)
    /// A generic tool.
    case tool(ToolBlock)
    /// A command and bounded output.
    case command(CommandBlock)
    /// A file search.
    case fileSearch(FileSearchBlock)
    /// A file operation summary.
    case fileOperation(FileOperationBlock)
    /// A unified diff.
    case diff(DiffBlock)
    /// A human approval request.
    case approval(ApprovalBlock)
    /// A host-owned artifact.
    case artifact(ArtifactBlock)
    /// Referenced image content.
    case image(ImageBlock)
    /// A user-safe error.
    case error(ErrorBlock)
    /// Runtime- or host-specific JSON content.
    case custom(CustomBlock)
}
