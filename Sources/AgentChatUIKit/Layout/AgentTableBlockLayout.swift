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
}

@MainActor
enum AgentTableBlockLayoutCalculator {
    static func userTextHeight(
        _ value: UserTextBlock,
        context: AgentBlockRenderContext
    ) -> CGFloat {
        let bodyFont = UIFont.preferredFont(forTextStyle: context.theme.typography.body)
        let detailFont = UIFont.preferredFont(forTextStyle: context.theme.typography.detail)
        let maximumTextWidth = max(1, context.availableWidth * 0.78 - 24)
        let attachmentTexts = value.attachments.map { "📎 \($0.name)" }
        let naturalWidths = [naturalWidth(value.text, font: bodyFont)]
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

    private static func markdownBlockHeight(
        _ block: AgentMarkdownRenderBlock,
        context: AgentBlockRenderContext
    ) -> CGFloat {
        switch block {
        case .heading(let level, let content):
            let style: UIFont.TextStyle = level == 1 ? .title2 : (level == 2 ? .title3 : .headline)
            return textHeight(
                AgentMarkdownPlainTextRenderer.inline(content),
                font: .preferredFont(forTextStyle: style),
                width: context.availableWidth
            )
        case .thematicBreak:
            return 1 / UIScreen.main.scale
        case .codeBlock(let language, let code):
            let text = [language, code].compactMap { $0 }.joined(separator: "\n")
            let font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: .monospacedSystemFont(
                    ofSize: context.theme.typography.codePointSize,
                    weight: .regular
                )
            )
            return textHeight(text, font: font, width: max(1, context.availableWidth - 16)) + 16
        case .table(let table):
            return AgentMarkdownTableView.height(
                for: table,
                availableWidth: context.availableWidth,
                bodyTextStyle: context.theme.typography.body
            )
        default:
            return textHeight(
                AgentMarkdownPlainTextRenderer.render(block),
                font: .preferredFont(forTextStyle: context.theme.typography.body),
                width: context.availableWidth
            )
        }
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
