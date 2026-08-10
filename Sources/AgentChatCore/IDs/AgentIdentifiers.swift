import Foundation

/// A stable identifier for a conversation.
public struct AgentConversationID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    /// The serialized identifier.
    public let rawValue: String
    /// Creates an identifier from its serialized value.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates an identifier from a string literal.
    public init(stringLiteral value: String) { rawValue = value }
    /// The serialized identifier.
    public var description: String { rawValue }
}

/// A stable identifier for a turn.
public struct AgentTurnID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    /// The serialized identifier.
    public let rawValue: String
    /// Creates an identifier from its serialized value.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates an identifier from a string literal.
    public init(stringLiteral value: String) { rawValue = value }
    /// The serialized identifier.
    public var description: String { rawValue }
}

/// A stable identifier for a content block.
public struct AgentBlockID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    /// The serialized identifier.
    public let rawValue: String
    /// Creates an identifier from its serialized value.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates an identifier from a string literal.
    public init(stringLiteral value: String) { rawValue = value }
    /// The serialized identifier.
    public var description: String { rawValue }
}

/// A stable identifier for an approval request.
public struct AgentApprovalID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    /// The serialized identifier.
    public let rawValue: String
    /// Creates an identifier from its serialized value.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates an identifier from a string literal.
    public init(stringLiteral value: String) { rawValue = value }
    /// The serialized identifier.
    public var description: String { rawValue }
}

/// A stable identifier for an agent run.
public struct AgentRunID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    /// The serialized identifier.
    public let rawValue: String
    /// Creates an identifier from its serialized value.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates an identifier from a string literal.
    public init(stringLiteral value: String) { rawValue = value }
    /// The serialized identifier.
    public var description: String { rawValue }
}

/// A stable identifier for a runtime event.
public struct AgentEventID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    /// The serialized identifier.
    public let rawValue: String
    /// Creates an identifier from its serialized value.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates an identifier from a string literal.
    public init(stringLiteral value: String) { rawValue = value }
    /// The serialized identifier.
    public var description: String { rawValue }
}

/// A stable identifier for an artifact.
public struct AgentArtifactID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    /// The serialized identifier.
    public let rawValue: String
    /// Creates an identifier from its serialized value.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates an identifier from a string literal.
    public init(stringLiteral value: String) { rawValue = value }
    /// The serialized identifier.
    public var description: String { rawValue }
}

/// A stable identifier for an attachment.
public struct AgentAttachmentID: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    /// The serialized identifier.
    public let rawValue: String
    /// Creates an identifier from its serialized value.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates an identifier from a string literal.
    public init(stringLiteral value: String) { rawValue = value }
    /// The serialized identifier.
    public var description: String { rawValue }
}

/// An opaque cursor supplied by a runtime for earlier history.
public struct AgentHistoryCursor: RawRepresentable, Hashable, Codable, Sendable,
    ExpressibleByStringLiteral
{
    /// The serialized cursor.
    public let rawValue: String
    /// Creates a cursor.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Creates a cursor from a string literal.
    public init(stringLiteral value: String) { rawValue = value }
}
