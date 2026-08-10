import AgentChatCore
import Foundation

/// An immutable, platform-independent Markdown render document.
public struct AgentMarkdownRenderDocument: Hashable, Codable, Sendable {
    /// Ordered render blocks.
    public var blocks: [AgentMarkdownRenderBlock]
    /// Creates a render document.
    public init(blocks: [AgentMarkdownRenderBlock]) { self.blocks = blocks }
}

/// A platform-independent Markdown block.
public enum AgentMarkdownRenderBlock: Hashable, Codable, Sendable {
    /// A paragraph.
    case paragraph([AgentMarkdownInline])
    /// A heading with its CommonMark level.
    case heading(level: Int, content: [AgentMarkdownInline])
    /// A nested block quote.
    case blockQuote([AgentMarkdownRenderBlock])
    /// An ordered list.
    case orderedList(start: Int, items: [AgentMarkdownListItem])
    /// An unordered or task list.
    case unorderedList(items: [AgentMarkdownListItem])
    /// A thematic separator.
    case thematicBreak
    /// A fenced or indented code block.
    case codeBlock(language: String?, code: String)
    /// A GitHub-flavored Markdown table.
    case table(AgentMarkdownTable)
    /// A standalone image reference.
    case image(source: String?, alternativeText: String)
    /// Safe plain-text fallback for unsupported or raw HTML markup.
    case unsupported(raw: String)
}

/// A list item, including optional task state.
public struct AgentMarkdownListItem: Hashable, Codable, Sendable {
    /// `nil` for a normal item and a boolean for a task item.
    public var isChecked: Bool?
    /// Nested blocks in the item.
    public var blocks: [AgentMarkdownRenderBlock]
    /// Creates a list item.
    public init(isChecked: Bool? = nil, blocks: [AgentMarkdownRenderBlock]) {
        self.isChecked = isChecked
        self.blocks = blocks
    }
}

/// A Markdown inline span.
public indirect enum AgentMarkdownInline: Hashable, Codable, Sendable {
    /// Plain text.
    case text(String)
    /// Emphasized content.
    case emphasis([AgentMarkdownInline])
    /// Strong content.
    case strong([AgentMarkdownInline])
    /// Struck-through content.
    case strikethrough([AgentMarkdownInline])
    /// Inline code.
    case code(String)
    /// A link candidate that still requires host authorization.
    case link(destination: String?, title: String?, content: [AgentMarkdownInline])
    /// An inline image reference.
    case image(source: String?, alternativeText: String)
    /// A soft line break.
    case softBreak
    /// A hard line break.
    case hardBreak
    /// Safe plain-text fallback for unsupported inline markup.
    case unsupported(String)
}

/// A platform-independent table.
public struct AgentMarkdownTable: Hashable, Codable, Sendable {
    /// Table column alignment.
    public enum Alignment: String, Codable, Sendable {
        /// Leading-edge alignment that follows layout direction.
        case leading
        /// Center alignment.
        case center
        /// Trailing-edge alignment that follows layout direction.
        case trailing
        /// No explicit alignment.
        case unspecified
    }
    /// Header cells.
    public var header: [[AgentMarkdownInline]]
    /// Body rows and cells.
    public var rows: [[[AgentMarkdownInline]]]
    /// Per-column alignment.
    public var alignments: [Alignment]
    /// Creates a render table.
    public init(
        header: [[AgentMarkdownInline]],
        rows: [[[AgentMarkdownInline]]],
        alignments: [Alignment]
    ) {
        self.header = header
        self.rows = rows
        self.alignments = alignments
    }
}

/// A cache key that includes every layout- or appearance-sensitive input.
public struct AgentMarkdownCacheKey: Hashable, Codable, Sendable {
    /// The source block.
    public var blockID: AgentBlockID
    /// The source revision.
    public var revision: Int64
    /// Available width quantized to display points.
    public var width: Int
    /// A portable content-size-category identifier.
    public var contentSizeCategory: String
    /// The theme version.
    public var themeVersion: Int
    /// Creates a cache key.
    public init(
        blockID: AgentBlockID,
        revision: Int64,
        width: Int,
        contentSizeCategory: String,
        themeVersion: Int
    ) {
        self.blockID = blockID
        self.revision = revision
        self.width = width
        self.contentSizeCategory = contentSizeCategory
        self.themeVersion = themeVersion
    }
}
