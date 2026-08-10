import AgentChatCore
import Foundation

/// Generates stable event envelopes for fixtures, demos, and integration tests.
public struct AgentEventSequenceBuilder: Sendable {
    /// The generated conversation.
    public let conversationID: AgentConversationID
    private var nextSequence: Int64
    private var eventCount: Int64
    private let epoch: Date

    /// Creates a deterministic envelope builder.
    public init(
        conversationID: AgentConversationID,
        firstSequence: Int64 = 1,
        epoch: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.conversationID = conversationID
        self.nextSequence = firstSequence
        self.eventCount = 0
        self.epoch = epoch
    }

    /// Wraps a payload and advances the sequence.
    public mutating func event(
        _ payload: AgentRuntimeEventPayload,
        after seconds: TimeInterval = 0
    ) -> AgentRuntimeEvent {
        eventCount += 1
        defer { nextSequence += 1 }
        return AgentRuntimeEvent(
            id: .init(rawValue: "event-\(eventCount)"),
            sequence: nextSequence,
            conversationID: conversationID,
            timestamp: epoch.addingTimeInterval(seconds),
            payload: payload
        )
    }
}
