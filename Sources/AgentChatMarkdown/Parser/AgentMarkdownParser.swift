import AgentChatCore
import Foundation
import Markdown

/// Parses Markdown off the main actor into package-owned Sendable values.
public actor AgentMarkdownParser {
    /// Creates a parser.
    public init() {}

    /// Parses complete or temporarily incomplete Markdown without executing HTML.
    public func parse(_ source: String) -> AgentMarkdownRenderDocument {
        let document = Document(parsing: source)
        return AgentMarkdownRenderDocument(blocks: convertBlocks(document.children))
    }

    /// Debounces incomplete streaming Markdown and parses final content immediately.
    public func parseStreaming(
        _ source: String,
        isFinal: Bool,
        debounceMilliseconds: Int = 60
    ) async throws -> AgentMarkdownRenderDocument {
        if !isFinal {
            let milliseconds = min(80, max(40, debounceMilliseconds))
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
            try Task.checkCancellation()
        }
        return parse(source)
    }

    private func convertBlocks(_ children: MarkupChildren) -> [AgentMarkdownRenderBlock] {
        children.flatMap { convertBlock($0) }
    }

    private func convertBlock(_ markup: any Markup) -> [AgentMarkdownRenderBlock] {
        if let paragraph = markup as? Paragraph {
            let content = convertInlines(paragraph.children)
            if content.count == 1, case .image(let source, let alternativeText) = content[0] {
                return [.image(source: source, alternativeText: alternativeText)]
            }
            return [.paragraph(content)]
        }
        if let heading = markup as? Heading {
            return [.heading(level: heading.level, content: convertInlines(heading.children))]
        }
        if let quote = markup as? BlockQuote {
            return [.blockQuote(convertBlocks(quote.children))]
        }
        if let ordered = markup as? OrderedList {
            return [
                .orderedList(
                    start: Int(ordered.startIndex),
                    items: ordered.children.compactMap(convertListItem)
                )
            ]
        }
        if let unordered = markup as? UnorderedList {
            return [.unorderedList(items: unordered.children.compactMap(convertListItem))]
        }
        if markup is ThematicBreak {
            return [.thematicBreak]
        }
        if let code = markup as? CodeBlock {
            return [.codeBlock(language: code.language, code: code.code)]
        }
        if let table = markup as? Table {
            return [.table(convertTable(table))]
        }
        if let html = markup as? HTMLBlock {
            return [.unsupported(raw: html.rawHTML)]
        }
        return [.unsupported(raw: markup.format())]
    }

    private func convertListItem(_ markup: any Markup) -> AgentMarkdownListItem? {
        guard let item = markup as? ListItem else { return nil }
        let checked: Bool?
        switch item.checkbox {
        case .checked: checked = true
        case .unchecked: checked = false
        case nil: checked = nil
        }
        return .init(isChecked: checked, blocks: convertBlocks(item.children))
    }

    private func convertTable(_ table: Table) -> AgentMarkdownTable {
        let header = table.head.children.compactMap { cell -> [AgentMarkdownInline]? in
            guard let cell = cell as? Table.Cell else { return nil }
            return convertInlines(cell.children)
        }
        let rows = table.body.children.compactMap { row -> [[AgentMarkdownInline]]? in
            guard let row = row as? Table.Row else { return nil }
            return row.children.compactMap { cell -> [AgentMarkdownInline]? in
                guard let cell = cell as? Table.Cell else { return nil }
                return convertInlines(cell.children)
            }
        }
        let alignments = table.columnAlignments.map { alignment in
            switch alignment {
            case .left: AgentMarkdownTable.Alignment.leading
            case .center: AgentMarkdownTable.Alignment.center
            case .right: AgentMarkdownTable.Alignment.trailing
            case nil: AgentMarkdownTable.Alignment.unspecified
            }
        }
        return .init(header: header, rows: rows, alignments: alignments)
    }

    private func convertInlines(_ children: MarkupChildren) -> [AgentMarkdownInline] {
        children.map(convertInline)
    }

    private func convertInline(_ markup: any Markup) -> AgentMarkdownInline {
        if let text = markup as? Text { return .text(text.string) }
        if let emphasis = markup as? Emphasis {
            return .emphasis(convertInlines(emphasis.children))
        }
        if let strong = markup as? Strong { return .strong(convertInlines(strong.children)) }
        if let strike = markup as? Strikethrough {
            return .strikethrough(convertInlines(strike.children))
        }
        if let code = markup as? InlineCode { return .code(code.code) }
        if let link = markup as? Link {
            return .link(
                destination: link.destination,
                title: link.title,
                content: convertInlines(link.children)
            )
        }
        if let image = markup as? Image {
            return .image(
                source: image.source,
                alternativeText: plainText(image.children)
            )
        }
        if markup is SoftBreak { return .softBreak }
        if markup is LineBreak { return .hardBreak }
        if let html = markup as? InlineHTML { return .unsupported(html.rawHTML) }
        return .unsupported(markup.format())
    }

    private func plainText(_ children: MarkupChildren) -> String {
        children.map { markup in
            if let text = markup as? Text { return text.string }
            if let code = markup as? InlineCode { return code.code }
            return plainText(markup.children)
        }.joined()
    }
}

/// A bounded actor-isolated render-document cache.
public actor AgentMarkdownDocumentCache {
    private let capacity: Int
    private var values: [AgentMarkdownCacheKey: AgentMarkdownRenderDocument] = [:]
    private var order: [AgentMarkdownCacheKey] = []

    /// Creates a cache with a bounded entry count.
    public init(capacity: Int = 256) { self.capacity = max(1, capacity) }

    /// Returns a cached document and refreshes its recency.
    public func document(for key: AgentMarkdownCacheKey) -> AgentMarkdownRenderDocument? {
        guard let value = values[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return value
    }

    /// Inserts or replaces a cached document.
    public func insert(_ document: AgentMarkdownRenderDocument, for key: AgentMarkdownCacheKey) {
        values[key] = document
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
    }

    /// Removes documents belonging to a set of block IDs.
    public func remove(blockIDs: Set<AgentBlockID>) {
        order.removeAll { key in
            if blockIDs.contains(key.blockID) {
                values.removeValue(forKey: key)
                return true
            }
            return false
        }
    }

    /// Releases all cached documents, such as after a memory warning.
    public func removeAll() {
        values.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }
}
