import Foundation

/// A request to create a conversation.
public struct CreateConversationRequest: Hashable, Codable, Sendable {
    /// The desired identifier, when assigned by the host.
    public var conversationID: AgentConversationID?
    /// The optional initial title.
    public var title: String?
    /// Runtime-neutral metadata.
    public var metadata: [String: JSONValue]
    /// Creates a request.
    public init(
        conversationID: AgentConversationID? = nil,
        title: String? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        self.conversationID = conversationID
        self.title = title
        self.metadata = metadata
    }
}

/// User input submitted to a runtime.
public struct AgentSubmitRequest: Hashable, Codable, Sendable {
    /// The destination conversation.
    public var conversationID: AgentConversationID
    /// The authored text.
    public var text: String
    /// Attachment metadata.
    public var attachments: [AgentAttachment]
    /// Runtime-neutral metadata.
    public var metadata: [String: JSONValue]
    /// Creates a submit request.
    public init(
        conversationID: AgentConversationID,
        text: String,
        attachments: [AgentAttachment] = [],
        metadata: [String: JSONValue] = [:]
    ) {
        self.conversationID = conversationID
        self.text = text
        self.attachments = attachments
        self.metadata = metadata
    }
}

/// A request to interrupt active work.
public struct AgentInterruptRequest: Hashable, Codable, Sendable {
    /// The conversation to interrupt.
    public var conversationID: AgentConversationID
    /// An optional specific run.
    public var runID: AgentRunID?
    /// Creates an interrupt request.
    public init(conversationID: AgentConversationID, runID: AgentRunID? = nil) {
        self.conversationID = conversationID
        self.runID = runID
    }
}

/// A request to retry a failed turn or block.
public struct AgentRetryRequest: Hashable, Codable, Sendable {
    /// The conversation containing the failure.
    public var conversationID: AgentConversationID
    /// An optional failed turn.
    public var turnID: AgentTurnID?
    /// An optional failed block.
    public var blockID: AgentBlockID?
    /// Creates a retry request.
    public init(
        conversationID: AgentConversationID,
        turnID: AgentTurnID? = nil,
        blockID: AgentBlockID? = nil
    ) {
        self.conversationID = conversationID
        self.turnID = turnID
        self.blockID = blockID
    }
}

/// A one-shot response to an approval request.
public struct AgentApprovalResponse: Hashable, Codable, Sendable {
    /// The conversation containing the approval.
    public var conversationID: AgentConversationID
    /// The approval identifier.
    public var approvalID: AgentApprovalID
    /// The selected choice identifier.
    public var choiceID: String
    /// Runtime-neutral metadata.
    public var metadata: [String: JSONValue]
    /// Creates an approval response.
    public init(
        conversationID: AgentConversationID,
        approvalID: AgentApprovalID,
        choiceID: String,
        metadata: [String: JSONValue] = [:]
    ) {
        self.conversationID = conversationID
        self.approvalID = approvalID
        self.choiceID = choiceID
        self.metadata = metadata
    }
}

/// A structured answer requested by a runtime-owned interaction.
public struct AgentStructuredAnswer: Hashable, Codable, Sendable {
    /// The conversation receiving the answer.
    public var conversationID: AgentConversationID
    /// A stable runtime question identifier.
    public var questionID: String
    /// The portable answer.
    public var value: JSONValue
    /// Creates a structured answer.
    public init(conversationID: AgentConversationID, questionID: String, value: JSONValue) {
        self.conversationID = conversationID
        self.questionID = questionID
        self.value = value
    }
}

/// A request for an earlier history page.
public struct AgentHistoryRequest: Hashable, Codable, Sendable {
    /// The conversation to page.
    public var conversationID: AgentConversationID
    /// The opaque earlier-history cursor.
    public var cursor: AgentHistoryCursor?
    /// The desired maximum number of turns.
    public var limit: Int
    /// Creates a history request.
    public init(
        conversationID: AgentConversationID,
        cursor: AgentHistoryCursor? = nil,
        limit: Int = 50
    ) {
        self.conversationID = conversationID
        self.cursor = cursor
        self.limit = max(1, limit)
    }
}

/// A namespaced runtime-specific command.
public struct CustomRuntimeCommand: Hashable, Codable, Sendable {
    /// The namespaced command kind.
    public var kind: String
    /// Portable command payload.
    public var payload: JSONValue
    /// Creates a custom command.
    public init(kind: String, payload: JSONValue) {
        self.kind = kind
        self.payload = payload
    }
}

/// Commands that UI actions and hosts may send to a runtime adapter.
public enum AgentRuntimeCommand: Hashable, Codable, Sendable {
    /// Creates a new conversation.
    case createConversation(CreateConversationRequest)
    /// Resumes a known conversation.
    case resumeConversation(AgentConversationID)
    /// Submits user-authored input.
    case submit(AgentSubmitRequest)
    /// Interrupts active work.
    case interrupt(AgentInterruptRequest)
    /// Retries failed work.
    case retry(AgentRetryRequest)
    /// Accepts an approval choice.
    case approve(AgentApprovalResponse)
    /// Rejects an approval choice.
    case reject(AgentApprovalResponse)
    /// Sends a structured answer.
    case answer(AgentStructuredAnswer)
    /// Requests earlier history.
    case loadEarlier(AgentHistoryRequest)
    /// Requests an authoritative snapshot.
    case requestSnapshot(AgentConversationID)
    /// Sends a namespaced runtime-specific command.
    case custom(CustomRuntimeCommand)
}
