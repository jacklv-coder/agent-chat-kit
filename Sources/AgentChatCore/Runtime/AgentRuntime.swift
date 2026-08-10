import Foundation

/// Connects AgentChatKit to an existing, runtime-specific agent implementation.
public protocol AgentRuntimeAdapter: Sendable {
    /// Creates an independent runtime connection.
    func connect(configuration: AgentRuntimeConfiguration) async throws
        -> any AgentRuntimeConnection
}

/// A single-consumer runtime connection.
public protocol AgentRuntimeConnection: Sendable {
    /// Features supported by the connection.
    var capabilities: AgentRuntimeCapabilities { get }

    /// Creates the event stream. A connection permits one consumer.
    func makeEventStream() -> AsyncThrowingStream<AgentRuntimeEvent, any Error>

    /// Sends a structured command to the runtime.
    func send(_ command: AgentRuntimeCommand) async throws

    /// Closes the connection. Implementations must be idempotent.
    func close() async
}

/// Runtime connection input that contains no transport-specific types.
public struct AgentRuntimeConfiguration: Hashable, Codable, Sendable {
    /// The conversation to create or resume.
    public var conversationID: AgentConversationID
    /// Runtime-specific portable configuration.
    public var metadata: [String: JSONValue]

    /// Creates runtime configuration.
    public init(
        conversationID: AgentConversationID = "default",
        metadata: [String: JSONValue] = [:]
    ) {
        self.conversationID = conversationID
        self.metadata = metadata
    }
}

/// Capabilities used to hide or disable unsupported UI actions.
public struct AgentRuntimeCapabilities: OptionSet, Hashable, Codable, Sendable {
    /// The bitset storage.
    public let rawValue: UInt64
    /// Creates a capability bitset.
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// Incremental assistant text.
    public static let streamingText = Self(rawValue: 1 << 0)
    /// Generic tools.
    public static let tools = Self(rawValue: 1 << 1)
    /// Command display events.
    public static let commands = Self(rawValue: 1 << 2)
    /// File operation display events.
    public static let fileOperations = Self(rawValue: 1 << 3)
    /// Diff display events.
    public static let diffs = Self(rawValue: 1 << 4)
    /// Human approval.
    public static let approvals = Self(rawValue: 1 << 5)
    /// Input attachments.
    public static let attachments = Self(rawValue: 1 << 6)
    /// Earlier-history pagination.
    public static let history = Self(rawValue: 1 << 7)
    /// Retry commands.
    public static let retry = Self(rawValue: 1 << 8)
    /// Interrupt commands.
    public static let interrupt = Self(rawValue: 1 << 9)
    /// Custom blocks and commands.
    public static let customBlocks = Self(rawValue: 1 << 10)
}
