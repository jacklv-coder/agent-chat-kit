import Foundation

/// A stable, ordered runtime event envelope.
public struct AgentRuntimeEvent: Hashable, Codable, Sendable {
    /// A conversation-lifecycle-unique event identifier.
    public var id: AgentEventID
    /// A monotonically increasing connection sequence.
    public var sequence: Int64
    /// The affected conversation.
    public var conversationID: AgentConversationID
    /// The runtime event timestamp.
    public var timestamp: Date
    /// The event data.
    public var payload: AgentRuntimeEventPayload

    /// Creates an event envelope.
    public init(
        id: AgentEventID,
        sequence: Int64,
        conversationID: AgentConversationID,
        timestamp: Date,
        payload: AgentRuntimeEventPayload
    ) {
        self.id = id
        self.sequence = sequence
        self.conversationID = conversationID
        self.timestamp = timestamp
        self.payload = payload
    }
}

/// Runtime events reduced into conversation state.
public enum AgentRuntimeEventPayload: Hashable, Codable, Sendable {
    /// Replaces the authoritative snapshot and ordering baseline.
    case snapshot(AgentConversationSnapshot)
    /// Changes only the conversation state.
    case conversationStateChanged(AgentConversationState)
    /// Inserts a turn.
    case turnInserted(AgentTurn)
    /// Replaces a turn when it is not stale.
    case turnUpdated(AgentTurn)
    /// Removes a turn idempotently.
    case turnRemoved(AgentTurnID)
    /// Inserts a block into a turn.
    case blockInserted(turnID: AgentTurnID, block: AgentBlock)
    /// Replaces a block when its revision is newer.
    case blockReplaced(turnID: AgentTurnID, block: AgentBlock)
    /// Applies an incremental block operation.
    case blockDelta(AgentBlockDelta)
    /// Removes a block idempotently.
    case blockRemoved(turnID: AgentTurnID, blockID: AgentBlockID)
    /// Inserts an approval request.
    case approvalRequested(turnID: AgentTurnID, block: AgentBlock)
    /// Applies a runtime-confirmed approval resolution.
    case approvalResolved(AgentApprovalResolution)
    /// Prepends an earlier history page.
    case historyPage(AgentHistoryPage)
    /// Reports a non-terminal runtime notice.
    case recoverableError(AgentRuntimeNotice)
    /// Reports a terminal runtime failure.
    case terminalError(AgentFailure)
}

/// A revisioned incremental operation for one block.
public struct AgentBlockDelta: Hashable, Codable, Sendable {
    /// The containing turn.
    public var turnID: AgentTurnID
    /// The target block.
    public var blockID: AgentBlockID
    /// The expected current revision, if known.
    public var baseRevision: Int64?
    /// The resulting revision.
    public var nextRevision: Int64
    /// The incremental operation.
    public var operation: AgentBlockDeltaOperation

    /// Creates a block delta.
    public init(
        turnID: AgentTurnID,
        blockID: AgentBlockID,
        baseRevision: Int64? = nil,
        nextRevision: Int64,
        operation: AgentBlockDeltaOperation
    ) {
        self.turnID = turnID
        self.blockID = blockID
        self.baseRevision = baseRevision
        self.nextRevision = nextRevision
        self.operation = operation
    }
}

/// Supported incremental block mutations.
public enum AgentBlockDeltaOperation: Hashable, Codable, Sendable {
    /// Appends Markdown source.
    case appendMarkdown(String)
    /// Appends sanitized, bounded command output.
    case appendCommandOutput(String)
    /// Replaces portable block content.
    case replaceContent(AgentBlockContent)
    /// Changes lifecycle state.
    case setState(AgentBlockState)
    /// Changes normalized running progress.
    case setProgress(Double?)
    /// Merges metadata keys.
    case mergeMetadata([String: JSONValue])
}

/// An earlier history page supplied by a runtime.
public struct AgentHistoryPage: Hashable, Codable, Sendable {
    /// Turns ordered oldest to newest.
    public var turns: [AgentTurn]
    /// Cursor for the next earlier page.
    public var earlierCursor: AgentHistoryCursor?
    /// Whether another earlier page exists.
    public var hasEarlierHistory: Bool
    /// Creates a history page.
    public init(
        turns: [AgentTurn],
        earlierCursor: AgentHistoryCursor? = nil,
        hasEarlierHistory: Bool
    ) {
        self.turns = turns
        self.earlierCursor = earlierCursor
        self.hasEarlierHistory = hasEarlierHistory
    }
}

/// A user-safe, recoverable notice.
public struct AgentRuntimeNotice: Hashable, Codable, Sendable {
    /// A stable machine-readable code.
    public var code: String
    /// A user-safe message.
    public var message: String
    /// Creates a notice.
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
