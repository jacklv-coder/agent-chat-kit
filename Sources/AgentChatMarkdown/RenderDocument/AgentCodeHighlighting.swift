import Foundation

/// A portable syntax-highlighting appearance.
public enum AgentCodeTheme: String, Codable, Sendable {
    /// A light-background code appearance.
    case light
    /// A dark-background code appearance.
    case dark
    /// A high-contrast code appearance.
    case highContrast
}

/// A styled UTF-16 range in highlighted code.
public struct AgentHighlightedCodeSpan: Hashable, Codable, Sendable {
    /// The UTF-16 start offset.
    public var location: Int
    /// The UTF-16 length.
    public var length: Int
    /// A semantic token name such as `keyword` or `comment`.
    public var token: String
    /// Creates a highlighted span.
    public init(location: Int, length: Int, token: String) {
        self.location = location
        self.length = length
        self.token = token
    }
}

/// Highlighted code without platform font or color types.
public struct AgentHighlightedCode: Hashable, Codable, Sendable {
    /// The original code.
    public var code: String
    /// Semantic highlighted spans.
    public var spans: [AgentHighlightedCodeSpan]
    /// Creates highlighted code.
    public init(code: String, spans: [AgentHighlightedCodeSpan] = []) {
        self.code = code
        self.spans = spans
    }
}

/// A host-injected, concurrency-safe syntax highlighter.
public protocol AgentCodeHighlighting: Sendable {
    /// Highlights source code without being required for basic display.
    func highlight(code: String, language: String?, theme: AgentCodeTheme) async throws
        -> AgentHighlightedCode
}

/// A stable highlighter that always returns selectable plain code.
public struct PlainCodeHighlighter: AgentCodeHighlighting {
    /// Creates the plain-code highlighter.
    public init() {}
    /// Returns the original code with no styled spans.
    public func highlight(code: String, language: String?, theme: AgentCodeTheme) async throws
        -> AgentHighlightedCode
    {
        AgentHighlightedCode(code: code)
    }
}
