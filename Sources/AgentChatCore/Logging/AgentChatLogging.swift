import Foundation

/// Payload-free diagnostic metadata emitted by AgentChatKit.
public struct AgentChatLogEvent: Hashable, Codable, Sendable {
    /// Diagnostic severity.
    public enum Level: String, Codable, Sendable {
        /// Development-only diagnostic metadata.
        case debug
        /// Informational lifecycle metadata.
        case info
        /// Recoverable abnormal metadata.
        case warning
        /// Terminal or failed-operation metadata.
        case error
    }
    /// The severity.
    public var level: Level
    /// A stable event name.
    public var name: String
    /// Non-sensitive scalar metadata, such as counts and durations.
    public var metadata: [String: JSONValue]
    /// Creates a payload-free log event.
    public init(level: Level, name: String, metadata: [String: JSONValue] = [:]) {
        self.level = level
        self.name = name
        self.metadata = metadata
    }
}

/// A host-injected sink for payload-free diagnostic events.
public protocol AgentChatLogging: Sendable {
    /// Records diagnostic metadata.
    func log(_ event: AgentChatLogEvent)
}

/// The safe default logger that records nothing.
public struct NoOpAgentChatLogger: AgentChatLogging {
    /// Creates the no-op logger.
    public init() {}
    /// Discards the event.
    public func log(_ event: AgentChatLogEvent) {}
}
