import AgentChatCore
import AgentChatMarkdown
import UIKit

@MainActor
final class AgentPreparedMarkdownCache {
    private let capacity: Int
    private var values: [AgentMarkdownCacheKey: AgentMarkdownRenderDocument] = [:]
    private var order: [AgentMarkdownCacheKey] = []

    init(capacity: Int = 512) { self.capacity = max(1, capacity) }

    func document(for key: AgentMarkdownCacheKey) -> AgentMarkdownRenderDocument? {
        guard let document = values[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return document
    }

    func insert(_ document: AgentMarkdownRenderDocument, for key: AgentMarkdownCacheKey) {
        values[key] = document
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
    }

    func removeAll() {
        values.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }
}

@MainActor
enum AgentTableBlockLayoutCalculator {
    static func userTextHeight(
        _ value: UserTextBlock,
        context: AgentBlockRenderContext
    ) -> CGFloat {
        let bodyFont = preferredFont(forTextStyle: context.theme.typography.body, context: context)
        let detailFont = preferredFont(
            forTextStyle: context.theme.typography.detail,
            context: context
        )
        let maximumTextWidth = max(1, context.availableWidth * 0.78 - 24)
        let attachmentTexts = value.attachments.map { "📎 \($0.name)" }
        let naturalWidths =
            [naturalWidth(value.text, font: bodyFont)]
            + attachmentTexts.map { naturalWidth($0, font: detailFont) }
        let textWidth = min(maximumTextWidth, max(1, naturalWidths.max() ?? 1))
        var contentHeight = textHeight(value.text, font: bodyFont, width: textWidth)
        for attachment in attachmentTexts {
            if contentHeight > 0 { contentHeight += 7 }
            contentHeight += textHeight(attachment, font: detailFont, width: textWidth)
        }
        // AgentBlockContentView (4 + 4) + user bubble (12 + 12).
        return ceil(8 + 24 + contentHeight)
    }

    static func markdownHeight(
        _ document: AgentMarkdownRenderDocument,
        context: AgentBlockRenderContext
    ) -> CGFloat {
        let heights = document.blocks.map { markdownBlockHeight($0, context: context) }
        let spacing = CGFloat(max(0, heights.count - 1)) * 10
        // AgentBlockContentView (4 + 4) + transparent Markdown container (10 + 10).
        return ceil(8 + 20 + heights.reduce(0, +) + spacing)
    }

    static func markdownRequiresSelfSizing(
        _ document: AgentMarkdownRenderDocument,
        context: AgentBlockRenderContext
    ) -> Bool {
        document.blocks.contains { block in
            switch block {
            case .paragraph(let content), .heading(_, let content):
                return inlineRequiresSelfSizing(content)
            case .blockQuote, .orderedList, .unorderedList:
                return true
            case .codeBlock(_, let code):
                let font = codeFont(context: context)
                return AgentMarkdownCodeBlockView.renderedLineCount(
                    for: code,
                    availableWidth: context.availableWidth,
                    font: font
                )
                    > AgentMarkdownCodeBlockView.collapsedLineCount
            case .thematicBreak, .table, .image, .unsupported:
                return false
            }
        }
    }

    private static func inlineRequiresSelfSizing(_ content: [AgentMarkdownInline]) -> Bool {
        content.contains { value in
            switch value {
            case .emphasis, .strong, .code, .image:
                return true
            case .strikethrough(let nested), .link(_, _, let nested):
                return inlineRequiresSelfSizing(nested)
            case .text, .softBreak, .hardBreak, .unsupported:
                return false
            }
        }
    }

    private static func markdownBlockHeight(
        _ block: AgentMarkdownRenderBlock,
        context: AgentBlockRenderContext
    ) -> CGFloat {
        switch block {
        case .heading(let level, let content):
            let style: UIFont.TextStyle = level == 1 ? .title2 : (level == 2 ? .title3 : .headline)
            return textHeight(
                AgentMarkdownPlainTextRenderer.inline(content),
                font: preferredFont(forTextStyle: style, context: context),
                width: context.availableWidth
            )
        case .thematicBreak:
            return 1 / UIScreen.main.scale
        case .codeBlock(_, let code):
            let font = codeFont(context: context)
            let lineCount = AgentMarkdownCodeBlockView.renderedLineCount(
                for: code,
                availableWidth: context.availableWidth,
                font: font
            )
            return AgentMarkdownCodeBlockView.height(lineCount: lineCount, font: font)
        case .table(let table):
            return AgentMarkdownTableView.height(
                for: table,
                availableWidth: context.availableWidth,
                bodyTextStyle: context.theme.typography.body,
                contentSizeCategory: fontTraits(context).preferredContentSizeCategory
            )
        case .image:
            let width = min(max(1, context.availableWidth), 560)
            return max(140, width * 0.5625)
        default:
            return textHeight(
                AgentMarkdownPlainTextRenderer.render(block),
                font: preferredFont(
                    forTextStyle: context.theme.typography.body,
                    context: context
                ),
                width: context.availableWidth
            )
        }
    }

    private static func preferredFont(
        forTextStyle style: UIFont.TextStyle,
        context: AgentBlockRenderContext
    ) -> UIFont {
        UIFont.preferredFont(forTextStyle: style, compatibleWith: fontTraits(context))
    }

    private static func codeFont(context: AgentBlockRenderContext) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedSystemFont(
                ofSize: context.theme.typography.codePointSize,
                weight: .regular
            ),
            compatibleWith: fontTraits(context)
        )
    }

    private static func fontTraits(_ context: AgentBlockRenderContext) -> UITraitCollection {
        UITraitCollection(
            preferredContentSizeCategory: UIContentSizeCategory(
                rawValue: context.environment.contentSizeCategory
            )
        )
    }

    private static func naturalWidth(_ text: String, font: UIFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let rect = (text as NSString).boundingRect(
            with: .init(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height)
    }
}
