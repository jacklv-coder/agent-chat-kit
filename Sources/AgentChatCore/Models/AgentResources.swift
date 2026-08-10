import Foundation

/// A runtime-neutral reference to content owned by the host or runtime.
public enum AgentResourceReference: Hashable, Codable, Sendable {
    /// An opaque host-local identifier.
    case localIdentifier(String)
    /// A remote URL that must be authorized by the host before opening.
    case remoteURL(URL)
    /// An opaque runtime resource URI.
    case runtimeURI(String)
}

/// Metadata describing an input attachment without owning its bytes or permissions.
public struct AgentAttachment: Identifiable, Hashable, Codable, Sendable {
    /// The attachment identifier.
    public var id: AgentAttachmentID
    /// The user-visible file name.
    public var name: String
    /// The optional media type.
    public var mediaType: String?
    /// The optional byte size.
    public var byteCount: Int64?
    /// A host- or runtime-owned resource reference.
    public var reference: AgentResourceReference

    /// Creates attachment metadata.
    public init(
        id: AgentAttachmentID,
        name: String,
        mediaType: String? = nil,
        byteCount: Int64? = nil,
        reference: AgentResourceReference
    ) {
        self.id = id
        self.name = name
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.reference = reference
    }
}

/// A file-search match supplied by a runtime.
public struct AgentFileMatch: Hashable, Codable, Sendable {
    /// The display path.
    public var path: String
    /// An optional human-readable excerpt.
    public var excerpt: String?
    /// An optional one-based line number.
    public var line: Int?

    /// Creates a file-search match.
    public init(path: String, excerpt: String? = nil, line: Int? = nil) {
        self.path = path
        self.excerpt = excerpt
        self.line = line
    }
}

/// One line in a parsed unified-diff hunk.
public struct AgentDiffLine: Hashable, Codable, Sendable {
    /// The line classification.
    public enum Kind: String, Codable, Sendable {
        /// An unchanged context line.
        case context
        /// An added destination line.
        case addition
        /// A deleted source line.
        case deletion
        /// A parser marker such as a missing-final-newline notice.
        case marker
    }
    /// The line classification.
    public var kind: Kind
    /// The content without the diff prefix.
    public var text: String
    /// The optional source line number.
    public var oldLine: Int?
    /// The optional destination line number.
    public var newLine: Int?

    /// Creates a parsed diff line.
    public init(kind: Kind, text: String, oldLine: Int? = nil, newLine: Int? = nil) {
        self.kind = kind
        self.text = text
        self.oldLine = oldLine
        self.newLine = newLine
    }
}

/// A hunk in a parsed unified diff.
public struct AgentDiffHunk: Hashable, Codable, Sendable {
    /// The hunk header.
    public var header: String
    /// Parsed hunk lines.
    public var lines: [AgentDiffLine]

    /// Creates a diff hunk.
    public init(header: String, lines: [AgentDiffLine]) {
        self.header = header
        self.lines = lines
    }
}

/// A file in a unified diff.
public struct AgentDiffFile: Hashable, Codable, Sendable {
    /// The source path, if present.
    public var oldPath: String?
    /// The destination path, if present.
    public var newPath: String?
    /// Whether the diff reports binary content.
    public var isBinary: Bool
    /// Parsed hunks.
    public var hunks: [AgentDiffHunk]

    /// Creates a diff file model.
    public init(
        oldPath: String? = nil,
        newPath: String? = nil,
        isBinary: Bool = false,
        hunks: [AgentDiffHunk] = []
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.isBinary = isBinary
        self.hunks = hunks
    }

    /// The number of added lines.
    public var additions: Int { hunks.flatMap(\.lines).count { $0.kind == .addition } }
    /// The number of deleted lines.
    public var deletions: Int { hunks.flatMap(\.lines).count { $0.kind == .deletion } }
}
