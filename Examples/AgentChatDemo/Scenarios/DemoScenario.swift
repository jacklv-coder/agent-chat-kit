import AgentChatKit
import AgentChatTesting
import Foundation

enum DemoScenario: String, CaseIterable {
    case basicStreaming = "Basic Streaming"
    case markdownShowcase = "Markdown Showcase"
    case fileSearch = "File Search"
    case shellCommand = "Shell Command"
    case longCommandOutput = "Long Command Output"
    case fileChanges = "File Changes"
    case unifiedDiff = "Unified Diff"
    case approval = "Approval"
    case failureAndRetry = "Failure and Retry"
    case interrupt = "Interrupt"
    case offlineAndReconnect = "Offline and Reconnect"
    case historyPagination = "History Pagination"
    case unknownToolFallback = "Unknown Tool Fallback"
    case customRenderer = "Custom Renderer"
    case longConversation = "Long Conversation"
    case iPadStageManager = "iPad Stage Manager"
    case accessibility = "Accessibility"
    case chineseContent = "Chinese Content"

    var conversationID: AgentConversationID {
        .init(rawValue: rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))
    }

    var summary: String {
        switch self {
        case .basicStreaming: "Revisioned Markdown deltas at a realistic cadence"
        case .markdownShowcase: "Headings, lists, tables, links, quotes, and code"
        case .fileSearch: "Runtime-supplied file matches without file access"
        case .shellCommand: "Display-only command and sanitized output"
        case .longCommandOutput: "Bounded 200KB / 2,000-line inline output"
        case .fileChanges: "Create, update, move, and delete summaries"
        case .unifiedDiff: "Multi-file additions and deletions"
        case .approval: "One-shot high-risk approval interaction"
        case .failureAndRetry: "Retryable user-safe error"
        case .interrupt: "Running state and Stop command"
        case .offlineAndReconnect: "Retained content with connection banner"
        case .historyPagination: "Earlier-history cursor and prepended turns"
        case .unknownToolFallback: "Safe generic custom-block fallback"
        case .customRenderer: "Host renderer for demo.weather"
        case .longConversation: "100 turns for quick scrolling checks"
        case .iPadStageManager: "Centered 900pt content and resize guidance"
        case .accessibility: "Dynamic Type and descriptive actions"
        case .chineseContent: "简体中文与 Emoji 内容"
        }
    }

    func makeScenario() -> AgentScenario {
        switch self {
        case .basicStreaming:
            return streamingScenario()
        case .approval:
            return approvalScenario()
        default:
            let event = runtimeEvent(
                sequence: 1,
                payload: .snapshot(snapshot())
            )
            return .init(events: [.init(event: event, delayNanoseconds: 20_000_000)])
        }
    }

    private func streamingScenario() -> AgentScenario {
        let date = Date(timeIntervalSince1970: 0)
        let turn = AgentTurn(
            id: "assistant",
            role: .assistant,
            blocks: [block(id: "stream", content: .markdown(.init(markdown: "", isFinal: false)))],
            state: .streaming,
            createdAt: date
        )
        let events = [
            runtimeEvent(sequence: 1, payload: .turnInserted(turn)),
            runtimeEvent(
                sequence: 2,
                payload: .blockDelta(
                    .init(
                        turnID: "assistant",
                        blockID: "stream",
                        baseRevision: 0,
                        nextRevision: 1,
                        operation: .appendMarkdown("Hello from ")
                    )
                )
            ),
            runtimeEvent(
                sequence: 3,
                payload: .blockDelta(
                    .init(
                        turnID: "assistant",
                        blockID: "stream",
                        baseRevision: 1,
                        nextRevision: 2,
                        operation: .appendMarkdown("AgentChatKit.\n\n- Stable IDs\n- Native layout")
                    )
                )
            ),
            runtimeEvent(
                sequence: 4,
                payload: .blockDelta(
                    .init(
                        turnID: "assistant",
                        blockID: "stream",
                        baseRevision: 2,
                        nextRevision: 3,
                        operation: .replaceContent(
                            .markdown(
                                .init(
                                    markdown:
                                        "Hello from AgentChatKit.\n\n- Stable IDs\n- Native layout",
                                    isFinal: true
                                )
                            )
                        )
                    )
                )
            ),
        ]
        return .init(events: events.map { .init(event: $0, delayNanoseconds: 180_000_000) })
    }

    private func approvalScenario() -> AgentScenario {
        let snapshotEvent = runtimeEvent(sequence: 1, payload: .snapshot(snapshot()))
        return .init(events: [.init(event: snapshotEvent, delayNanoseconds: 20_000_000)])
    }

    private func snapshot() -> AgentConversationSnapshot {
        let date = Date(timeIntervalSince1970: 0)
        if self == .longConversation {
            return .init(
                id: conversationID,
                title: rawValue,
                turns: (0..<100).map { index in
                    .init(
                        id: .init(rawValue: "turn-\(index)"),
                        role: index.isMultiple(of: 2) ? .user : .assistant,
                        blocks: [
                            block(
                                id: .init(rawValue: "block-\(index)"),
                                content: index.isMultiple(of: 2)
                                    ? .userText(.init(text: "User turn \(index)"))
                                    : .markdown(
                                        .init(
                                            markdown: "Assistant turn **\(index)**", isFinal: true))
                            )
                        ],
                        state: .completed,
                        createdAt: date.addingTimeInterval(Double(index))
                    )
                },
                state: .connected
            )
        }

        let blocks = contentBlocks()
        let turn = AgentTurn(
            id: "assistant",
            role: .assistant,
            blocks: blocks,
            state: self == .interrupt ? .running : .completed,
            createdAt: date
        )
        return .init(
            id: conversationID,
            title: rawValue,
            turns: [turn],
            state: self == .offlineAndReconnect
                ? .offline(message: "Demo runtime is offline; the last snapshot remains visible.")
                : .connected,
            earlierHistoryCursor: self == .historyPagination ? "earlier-page" : nil,
            hasEarlierHistory: self == .historyPagination
        )
    }

    private func contentBlocks() -> [AgentBlock] {
        switch self {
        case .markdownShowcase:
            [
                block(
                    id: "markdown",
                    content: .markdown(.init(markdown: markdownShowcase, isFinal: true)))
            ]
        case .fileSearch:
            [
                block(
                    id: "search",
                    content: .fileSearch(
                        .init(
                            query: "AgentConversationReducer",
                            root: "Sources",
                            matches: [
                                .init(
                                    path:
                                        "Sources/AgentChatCore/Reducer/AgentConversationReducer.swift",
                                    line: 1),
                                .init(
                                    path:
                                        "Tests/AgentChatCoreTests/AgentConversationReducerTests.swift",
                                    line: 1),
                            ],
                            totalCount: 2
                        )
                    )
                )
            ]
        case .shellCommand:
            [commandBlock(output: "Building...\nAll tests passed.\n")]
        case .longCommandOutput:
            [commandBlock(output: (0..<2_100).map { "line \($0)" }.joined(separator: "\n"))]
        case .fileChanges:
            [
                block(
                    id: "create",
                    content: .fileOperation(.init(operation: .create, path: "Sources/New.swift"))),
                block(
                    id: "update",
                    content: .fileOperation(.init(operation: .update, path: "README.md"))),
                block(
                    id: "move",
                    content: .fileOperation(
                        .init(operation: .move, path: "Old.swift", destinationPath: "New.swift")
                    )
                ),
            ]
        case .unifiedDiff:
            [block(id: "diff", content: .diff(diffBlock))]
        case .approval:
            [
                block(
                    id: "approval-block",
                    content: .approval(
                        .init(
                            approvalID: "approval",
                            title: "Publish the release?",
                            message: "This would make the package visible to other developers.",
                            risk: .high,
                            choices: [
                                .init(id: "allow", title: "Publish", role: .approve),
                                .init(id: "reject", title: "Cancel", role: .reject),
                            ]
                        )
                    ),
                    state: .waitingForApproval
                )
            ]
        case .failureAndRetry:
            [
                block(
                    id: "error",
                    content: .error(
                        .init(
                            failure: .init(
                                code: "demo.failure",
                                message: "The demo operation failed safely.",
                                isRetryable: true
                            )
                        )
                    ),
                    state: .failed(
                        .init(code: "demo.failure", message: "Failed", isRetryable: true))
                )
            ]
        case .interrupt:
            [
                block(
                    id: "running",
                    content: .activity(
                        .init(title: "Running a long demo task", detail: "Tap Stop to interrupt.")),
                    state: .running(progress: 0.42)
                )
            ]
        case .unknownToolFallback:
            [customBlock(kind: "company.unknown-tool", title: "Unknown enterprise tool")]
        case .customRenderer:
            [customBlock(kind: "demo.weather", title: "Weather in Hangzhou")]
        case .iPadStageManager:
            [
                block(
                    id: "ipad",
                    content: .markdown(
                        .init(
                            markdown:
                                "# Resize this window\n\nThe content column remains centered up to 900pt.",
                            isFinal: true
                        )
                    )
                )
            ]
        case .accessibility:
            [
                block(
                    id: "a11y",
                    content: .markdown(
                        .init(
                            markdown:
                                "# Accessibility\n\nTry VoiceOver, Reduce Motion, and an accessibility text size.",
                            isFinal: true
                        )
                    )
                )
            ]
        case .chineseContent:
            [
                block(
                    id: "zh",
                    content: .markdown(
                        .init(markdown: "# 你好 👋\n\n这是一个支持 **简体中文** 的 Agent 会话组件。", isFinal: true)
                    )
                )
            ]
        case .offlineAndReconnect:
            [
                block(
                    id: "offline",
                    content: .markdown(.init(markdown: "Last retained response.", isFinal: true)))
            ]
        case .historyPagination:
            [
                block(
                    id: "history",
                    content: .markdown(
                        .init(
                            markdown: "Scroll to the top to request earlier history.", isFinal: true
                        )))
            ]
        case .basicStreaming, .longConversation:
            []
        }
    }

    private func block(
        id: AgentBlockID,
        content: AgentBlockContent,
        state: AgentBlockState = .succeeded
    ) -> AgentBlock {
        AgentBlock(
            id: id,
            kind: kind(for: content),
            content: content,
            state: state,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func kind(for content: AgentBlockContent) -> AgentBlockKind {
        switch content {
        case .userText: .userText
        case .markdown: .markdown
        case .activity: .activity
        case .tool: .tool
        case .command: .command
        case .fileSearch: .fileSearch
        case .fileOperation: .fileOperation
        case .diff: .diff
        case .approval: .approval
        case .artifact: .artifact
        case .image: .image
        case .error: .error
        case .custom(let custom): .init(rawValue: custom.kind)
        }
    }

    private func commandBlock(output: String) -> AgentBlock {
        var buffer = AgentTextBuffer()
        buffer.append(output)
        return block(
            id: "command",
            content: .command(
                .init(
                    command: "swift test", workingDirectory: "/project", output: buffer, exitCode: 0
                )
            )
        )
    }

    private func customBlock(kind: String, title: String) -> AgentBlock {
        block(
            id: .init(rawValue: kind),
            content: .custom(
                .init(
                    kind: kind,
                    payload: .object(["temperature": .number(18)]),
                    fallbackTitle: title,
                    fallbackSummary: "This remains visible without a custom renderer."
                )
            )
        )
    }

    private func runtimeEvent(
        sequence: Int64,
        payload: AgentRuntimeEventPayload
    ) -> AgentRuntimeEvent {
        .init(
            id: .init(rawValue: "\(conversationID.rawValue)-event-\(sequence)"),
            sequence: sequence,
            conversationID: conversationID,
            timestamp: Date(timeIntervalSince1970: Double(sequence)),
            payload: payload
        )
    }

    private var markdownShowcase: String {
        """
        # Markdown Showcase

        **Strong**, *emphasis*, ~~strikethrough~~, and `inline code`.

        - [x] Native UIKit
        - [ ] Host integration

        > Raw HTML is never executed.

        | Feature | Status |
        | --- | --- |
        | Streaming | Ready |
        | iPad | Adaptive |

        ```swift
        let controller = AgentConversationViewController(store: store)
        ```
        """
    }

    private var diffBlock: DiffBlock {
        let hunk = AgentDiffHunk(
            header: "@@ -1,2 +1,2 @@",
            lines: [
                .init(kind: .context, text: "import UIKit", oldLine: 1, newLine: 1),
                .init(kind: .deletion, text: "let old = true", oldLine: 2),
                .init(kind: .addition, text: "let nativeLayout = true", newLine: 2),
            ]
        )
        return .init(
            title: "Adopt native layout",
            files: [.init(oldPath: "Timeline.swift", newPath: "Timeline.swift", hunks: [hunk])],
            rawUnifiedDiff:
                "--- a/Timeline.swift\n+++ b/Timeline.swift\n@@ -1,2 +1,2 @@\n import UIKit\n-let old = true\n+let nativeLayout = true"
        )
    }
}
