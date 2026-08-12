import AgentChatCore
import UIKit

@MainActor
enum AgentBlockContextMenu {
    static func make(for context: AgentBlockRenderContext) -> UIMenu {
        var actions: [UIMenuElement] = [
            UIAction(
                title: AgentStrings.copy,
                image: UIImage(systemName: "doc.on.doc"),
                identifier: .init("agentchat.copy")
            ) { _ in
                context.actionSink.send(.copy(context.block.id))
            }
        ]

        if isExpandable(context.block.content) {
            let isExpanded = context.environment.expandedBlockIDs.contains(context.block.id)
            actions.append(
                UIAction(
                    title: isExpanded ? AgentStrings.collapse : AgentStrings.expand,
                    image: UIImage(systemName: isExpanded ? "chevron.up" : "chevron.down"),
                    identifier: .init("agentchat.expand")
                ) { _ in
                    context.actionSink.send(.toggleExpanded(context.block.id))
                }
            )
        }

        switch context.block.content {
        case .fileOperation(let value):
            actions.append(openFileAction(.localIdentifier(value.path), context: context))
        case .fileSearch(let value):
            if let first = value.matches.first {
                actions.append(openFileAction(.localIdentifier(first.path), context: context))
            }
        case .artifact(let value):
            actions.append(
                UIAction(
                    title: AgentStrings.open,
                    image: UIImage(systemName: "arrow.up.forward.app"),
                    identifier: .init("agentchat.open-artifact")
                ) { _ in
                    context.actionSink.send(.openArtifact(value.id))
                }
            )
        case .approval(let value) where value.resolution == nil:
            let isResolving = context.environment.resolvingApprovalIDs.contains(value.approvalID)
            let choices = value.choices.map { choice in
                let response = AgentApprovalResponse(
                    conversationID: context.conversationID,
                    approvalID: value.approvalID,
                    choiceID: choice.id
                )
                return UIAction(
                    title: choice.title,
                    image: UIImage(
                        systemName: choice.role == .reject ? "xmark.circle" : "checkmark.circle"
                    ),
                    identifier: .init("agentchat.approval.\(choice.id)"),
                    attributes: isResolving ? [.disabled] : [],
                    state: .off
                ) { _ in
                    if choice.role == .reject {
                        context.actionSink.send(.reject(response))
                    } else {
                        context.actionSink.send(.approve(response))
                    }
                }
            }
            actions.append(
                UIMenu(
                    title: value.title,
                    image: UIImage(systemName: "checkmark.shield"),
                    identifier: .init("agentchat.approval"),
                    options: .displayInline,
                    children: choices
                )
            )
        default:
            break
        }

        if context.environment.canRetry, isRetryable(context.block) {
            actions.append(
                UIAction(
                    title: AgentStrings.retry,
                    image: UIImage(systemName: "arrow.clockwise"),
                    identifier: .init("agentchat.retry")
                ) { _ in
                    context.actionSink.send(.retry(context.block.id))
                }
            )
        }
        return UIMenu(title: "", children: actions)
    }

    private static func openFileAction(
        _ reference: AgentResourceReference,
        context: AgentBlockRenderContext
    ) -> UIAction {
        UIAction(
            title: AgentStrings.open,
            image: UIImage(systemName: "doc"),
            identifier: .init("agentchat.open-file")
        ) { _ in
            context.actionSink.send(.openFile(reference))
        }
    }

    private static func isExpandable(_ content: AgentBlockContent) -> Bool {
        switch content {
        case .activity, .tool, .command, .fileSearch, .fileOperation, .image, .diff:
            true
        default:
            false
        }
    }

    private static func isRetryable(_ block: AgentBlock) -> Bool {
        if case .failed(let failure) = block.state { return failure.isRetryable }
        if case .error(let value) = block.content { return value.failure.isRetryable }
        return false
    }
}

@MainActor
enum AgentBlockCopyText {
    static func text(for block: AgentBlock) -> String {
        switch block.content {
        case .userText(let value): value.text
        case .markdown(let value): value.markdown
        case .command(let value): value.output.text.isEmpty ? value.command : value.output.text
        case .tool(let value): encodedJSON(value) ?? value.title
        case .custom(let value): encodedJSON(value.payload) ?? value.fallbackTitle
        default: String(describing: block.content)
        }
    }

    private static func encodedJSON<Value: Encodable>(_ value: Value) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? String(data: encoder.encode(value), encoding: .utf8)
    }
}
