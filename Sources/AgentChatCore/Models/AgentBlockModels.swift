import Foundation

/// User-authored text and attachment metadata.
public struct UserTextBlock: Hashable, Codable, Sendable {
    /// The authored text.
    public var text: String
    /// Attachment metadata.
    public var attachments: [AgentAttachment]
    /// Creates user-authored content.
    public init(text: String, attachments: [AgentAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }
}

/// Assistant Markdown that may still be streaming.
public struct MarkdownBlock: Hashable, Codable, Sendable {
    /// The Markdown source.
    public var markdown: String
    /// Whether no more text will be appended.
    public var isFinal: Bool
    /// Creates Markdown content.
    public init(markdown: String, isFinal: Bool) {
        self.markdown = markdown
        self.isFinal = isFinal
    }
}

/// A user-readable activity summary, never private reasoning.
public struct ActivityBlock: Hashable, Codable, Sendable {
    /// The activity title.
    public var title: String
    /// Optional user-safe detail.
    public var detail: String?
    /// Creates an activity summary.
    public init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }
}

/// The preferred detail level for a generic tool.
public enum AgentToolDisplayMode: String, Codable, Sendable {
    /// Show a compact summary by default.
    case compact
    /// Show details expanded by default.
    case expanded
}

/// A runtime-neutral generic tool invocation.
public struct ToolBlock: Hashable, Codable, Sendable {
    /// The runtime tool name.
    public var toolName: String
    /// The user-visible title.
    public var title: String
    /// An optional user-safe summary.
    public var summary: String?
    /// Optional structured input.
    public var input: JSONValue?
    /// Optional structured output.
    public var output: JSONValue?
    /// The preferred detail level.
    public var displayMode: AgentToolDisplayMode

    /// Creates a generic tool block.
    public init(
        toolName: String,
        title: String,
        summary: String? = nil,
        input: JSONValue? = nil,
        output: JSONValue? = nil,
        displayMode: AgentToolDisplayMode = .compact
    ) {
        self.toolName = toolName
        self.title = title
        self.summary = summary
        self.input = input
        self.output = output
        self.displayMode = displayMode
    }
}

/// A command display model. AgentChatKit never executes the command.
public struct CommandBlock: Hashable, Codable, Sendable {
    /// The command text.
    public var command: String
    /// The display-only working directory.
    public var workingDirectory: String?
    /// Bounded, sanitized output.
    public var output: AgentTextBuffer
    /// The exit code after completion.
    public var exitCode: Int?
    /// The runtime-reported duration.
    public var duration: TimeInterval?

    /// Creates a command block.
    public init(
        command: String,
        workingDirectory: String? = nil,
        output: AgentTextBuffer = .init(),
        exitCode: Int? = nil,
        duration: TimeInterval? = nil
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.output = output
        self.exitCode = exitCode
        self.duration = duration
    }
}

/// A file-search request and runtime-supplied results.
public struct FileSearchBlock: Hashable, Codable, Sendable {
    /// The search query.
    public var query: String
    /// The display-only search root.
    public var root: String?
    /// Retained matches.
    public var matches: [AgentFileMatch]
    /// The runtime-reported total match count.
    public var totalCount: Int?

    /// Creates a file-search block.
    public init(
        query: String,
        root: String? = nil,
        matches: [AgentFileMatch] = [],
        totalCount: Int? = nil
    ) {
        self.query = query
        self.root = root
        self.matches = matches
        self.totalCount = totalCount
    }
}

/// A display-only file operation classification.
public enum AgentFileOperation: String, Codable, Sendable {
    /// A read operation.
    case read
    /// A create operation.
    case create
    /// An update operation.
    case update
    /// A delete operation.
    case delete
    /// A move operation.
    case move
}

/// A display-only file operation supplied by a runtime.
public struct FileOperationBlock: Hashable, Codable, Sendable {
    /// The operation classification.
    public var operation: AgentFileOperation
    /// The source or affected path.
    public var path: String
    /// The destination path for moves.
    public var destinationPath: String?
    /// An optional user-safe summary.
    public var summary: String?

    /// Creates a file operation block.
    public init(
        operation: AgentFileOperation,
        path: String,
        destinationPath: String? = nil,
        summary: String? = nil
    ) {
        self.operation = operation
        self.path = path
        self.destinationPath = destinationPath
        self.summary = summary
    }
}

/// A parsed or raw unified diff supplied for display.
public struct DiffBlock: Hashable, Codable, Sendable {
    /// An optional display title.
    public var title: String?
    /// Parsed files when provided by the runtime or Markdown module.
    public var files: [AgentDiffFile]
    /// Optional raw unified diff for background parsing and fallback.
    public var rawUnifiedDiff: String?

    /// Creates a diff block.
    public init(
        title: String? = nil,
        files: [AgentDiffFile] = [],
        rawUnifiedDiff: String? = nil
    ) {
        self.title = title
        self.files = files
        self.rawUnifiedDiff = rawUnifiedDiff
    }
}

/// The risk classification of an approval request.
public enum AgentApprovalRisk: String, Codable, Sendable {
    /// Low-risk, readily reversible work.
    case low
    /// Work with meaningful but bounded side effects.
    case medium
    /// High-impact or difficult-to-reverse work.
    case high
}

/// The semantic behavior of an approval choice.
public enum AgentApprovalChoiceRole: String, Codable, Sendable {
    /// Accepts the proposed work.
    case approve
    /// Rejects the proposed work.
    case reject
    /// Selects a runtime-defined alternative.
    case alternative
}

/// A choice offered by an approval request.
public struct AgentApprovalChoice: Identifiable, Hashable, Codable, Sendable {
    /// The runtime-stable choice identifier.
    public var id: String
    /// The user-visible label.
    public var title: String
    /// The semantic choice role.
    public var role: AgentApprovalChoiceRole
    /// Creates an approval choice.
    public init(id: String, title: String, role: AgentApprovalChoiceRole) {
        self.id = id
        self.title = title
        self.role = role
    }
}

/// A runtime-confirmed approval resolution.
public struct AgentApprovalResolution: Hashable, Codable, Sendable {
    /// The resolved approval identifier.
    public var approvalID: AgentApprovalID
    /// The chosen stable identifier.
    public var choiceID: String
    /// The runtime resolution timestamp.
    public var resolvedAt: Date
    /// Creates a confirmed resolution.
    public init(approvalID: AgentApprovalID, choiceID: String, resolvedAt: Date) {
        self.approvalID = approvalID
        self.choiceID = choiceID
        self.resolvedAt = resolvedAt
    }
}

/// A human approval request.
public struct ApprovalBlock: Hashable, Codable, Sendable {
    /// The approval identifier.
    public var approvalID: AgentApprovalID
    /// The user-visible title.
    public var title: String
    /// Optional explanatory detail.
    public var message: String?
    /// The runtime-supplied risk.
    public var risk: AgentApprovalRisk
    /// Available choices.
    public var choices: [AgentApprovalChoice]
    /// The runtime-confirmed resolution.
    public var resolution: AgentApprovalResolution?

    /// Creates an approval request.
    public init(
        approvalID: AgentApprovalID,
        title: String,
        message: String? = nil,
        risk: AgentApprovalRisk,
        choices: [AgentApprovalChoice],
        resolution: AgentApprovalResolution? = nil
    ) {
        self.approvalID = approvalID
        self.title = title
        self.message = message
        self.risk = risk
        self.choices = choices
        self.resolution = resolution
    }
}

/// A host-owned artifact reference.
public struct ArtifactBlock: Hashable, Codable, Sendable {
    /// The artifact identifier.
    public var id: AgentArtifactID
    /// The user-visible title.
    public var title: String
    /// Optional media type.
    public var mediaType: String?
    /// The host- or runtime-owned reference.
    public var reference: AgentResourceReference
    /// An optional user-safe summary.
    public var summary: String?

    /// Creates an artifact block.
    public init(
        id: AgentArtifactID,
        title: String,
        mediaType: String? = nil,
        reference: AgentResourceReference,
        summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.mediaType = mediaType
        self.reference = reference
        self.summary = summary
    }
}

/// Referenced image content. Loading remains the UIKit host's responsibility.
public struct ImageBlock: Hashable, Codable, Sendable {
    /// The host- or runtime-owned image reference.
    public var reference: AgentResourceReference
    /// Alternative text for accessibility and failure fallback.
    public var alternativeText: String
    /// Creates referenced image content.
    public init(reference: AgentResourceReference, alternativeText: String) {
        self.reference = reference
        self.alternativeText = alternativeText
    }
}

/// A user-safe block-local error.
public struct ErrorBlock: Hashable, Codable, Sendable {
    /// The failure description.
    public var failure: AgentFailure
    /// An optional retry action label.
    public var retryTitle: String?
    /// Creates an error block.
    public init(failure: AgentFailure, retryTitle: String? = nil) {
        self.failure = failure
        self.retryTitle = retryTitle
    }
}

/// Runtime- or host-specific content with a safe generic fallback.
public struct CustomBlock: Hashable, Codable, Sendable {
    /// The namespaced kind, matching the containing block kind.
    public var kind: String
    /// Portable JSON payload.
    public var payload: JSONValue
    /// The generic fallback title.
    public var fallbackTitle: String
    /// The optional generic fallback summary.
    public var fallbackSummary: String?

    /// Creates custom block content.
    public init(
        kind: String,
        payload: JSONValue,
        fallbackTitle: String,
        fallbackSummary: String? = nil
    ) {
        self.kind = kind
        self.payload = payload
        self.fallbackTitle = fallbackTitle
        self.fallbackSummary = fallbackSummary
    }
}
