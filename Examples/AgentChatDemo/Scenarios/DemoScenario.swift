import AgentChatKit
import AgentChatTesting
import Foundation

enum DemoScenario: String, CaseIterable {
    case completeShowcase = "Complete Cell Showcase"
    case currentConversation = "Current Chat Replay"
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
        case .completeShowcase: "Every built-in block plus custom, fallback, and interactive cells"
        case .currentConversation: "Real Chinese turns, Markdown, links, and tool activity cells"
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
        if self == .completeShowcase {
            return completeShowcaseSnapshot(date: date)
        }
        if self == .currentConversation {
            return currentConversationSnapshot(date: date)
        }
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
        case .completeShowcase, .currentConversation, .basicStreaming, .longConversation:
            []
        }
    }

    private func completeShowcaseSnapshot(date: Date) -> AgentConversationSnapshot {
        let attachments = [
            AgentAttachment(
                id: "requirements",
                name: "requirements.md",
                mediaType: "text/markdown",
                byteCount: 4_096,
                reference: .localIdentifier("demo-attachment-requirements")
            ),
            AgentAttachment(
                id: "mockup",
                name: "timeline-mockup.png",
                mediaType: "image/png",
                byteCount: 128_000,
                reference: .localIdentifier("demo-attachment-mockup")
            ),
        ]

        let introduction = AgentTurn(
            id: "showcase-system",
            role: .system,
            blocks: [
                block(
                    id: "showcase-introduction",
                    content: .markdown(
                        .init(
                            markdown: """
                                # Complete Cell Showcase

                                This offline conversation contains every `AgentBlockContent` case.
                                Try links, file rows, approval, retry, artifact, theme switching, and the composer.
                                """,
                            isFinal: true
                        )
                    )
                )
            ],
            state: .completed,
            createdAt: date
        )

        let userRequest = AgentTurn(
            id: "showcase-user",
            role: .user,
            blocks: [
                block(
                    id: "showcase-user-text",
                    content: .userText(
                        .init(
                            text:
                                "Please review the attached requirements and implement the timeline.",
                            attachments: attachments
                        )
                    )
                )
            ],
            state: .completed,
            createdAt: date.addingTimeInterval(1),
            completedAt: date.addingTimeInterval(1)
        )

        let response = AgentTurn(
            id: "showcase-response",
            role: .assistant,
            blocks: [
                block(
                    id: "showcase-markdown",
                    content: .markdown(.init(markdown: markdownShowcase, isFinal: true))
                ),
                block(
                    id: "showcase-image",
                    content: .image(
                        .init(
                            reference: .localIdentifier("demo-generated-preview"),
                            alternativeText: "Conversation timeline preview"
                        )
                    )
                ),
                block(
                    id: "showcase-artifact",
                    content: .artifact(
                        .init(
                            id: "showcase-report",
                            title: "Implementation report",
                            mediaType: "text/markdown",
                            reference: .runtimeURI("artifact://showcase/report"),
                            summary: "Tap Open to exercise host-owned artifact routing."
                        )
                    )
                ),
                customBlock(kind: "demo.weather", title: "Weather in Hangzhou"),
            ],
            state: .completed,
            createdAt: date.addingTimeInterval(2),
            completedAt: date.addingTimeInterval(3)
        )

        let operations = AgentTurn(
            id: "showcase-operations",
            role: .assistant,
            blocks: [
                block(
                    id: "showcase-activity-running",
                    content: .activity(
                        .init(
                            title: "Applying implementation plan",
                            detail: "The progress indicator is supplied by the runtime."
                        )
                    ),
                    state: .running(progress: 0.68)
                ),
                block(
                    id: "showcase-tool",
                    content: .tool(
                        .init(
                            toolName: "repository.inspect",
                            title: "Inspect repository",
                            summary: "Read package structure and target metadata.",
                            input: .object([
                                "root": .string("/project"),
                                "includeHidden": .bool(false),
                            ]),
                            output: .object([
                                "swiftFiles": .number(42),
                                "targets": .array([
                                    .string("AgentChatCore"),
                                    .string("AgentChatUIKit"),
                                ]),
                            ]),
                            displayMode: .expanded
                        )
                    )
                ),
                commandBlock(
                    output: "Resolving dependencies…\nBuilding targets…\nAll tests passed.\n"),
                block(
                    id: "showcase-search",
                    content: .fileSearch(
                        .init(
                            query: "AgentConversationViewController",
                            root: "Sources",
                            matches: [
                                .init(
                                    path:
                                        "Sources/AgentChatUIKit/Conversation/AgentConversationViewController.swift",
                                    excerpt: "public final class AgentConversationViewController",
                                    line: 6
                                ),
                                .init(
                                    path: "Tests/AgentChatUIKitTests/AgentTimelineTests.swift",
                                    excerpt: "final class AgentTimelineTests",
                                    line: 7
                                ),
                            ],
                            totalCount: 2
                        )
                    )
                ),
                block(
                    id: "showcase-file-create",
                    content: .fileOperation(
                        .init(
                            operation: .create,
                            path: "Sources/Feature/NewTimelineCell.swift",
                            summary: "Created a new renderer."
                        )
                    )
                ),
                block(
                    id: "showcase-file-update",
                    content: .fileOperation(
                        .init(
                            operation: .update,
                            path: "Sources/Feature/Timeline.swift",
                            summary: "Updated stable-ID reconciliation."
                        )
                    )
                ),
                block(
                    id: "showcase-file-move",
                    content: .fileOperation(
                        .init(
                            operation: .move,
                            path: "Sources/OldCell.swift",
                            destinationPath: "Sources/Cells/AgentCell.swift"
                        )
                    )
                ),
                block(
                    id: "showcase-file-delete",
                    content: .fileOperation(
                        .init(operation: .delete, path: "Sources/LegacyLayout.swift")
                    )
                ),
                block(id: "showcase-diff", content: .diff(diffBlock)),
            ],
            state: .running,
            createdAt: date.addingTimeInterval(4)
        )

        let safety = AgentTurn(
            id: "showcase-safety",
            role: .assistant,
            blocks: [
                block(
                    id: "showcase-approval",
                    content: .approval(
                        .init(
                            approvalID: "showcase-approval-request",
                            title: "Publish the reviewed changes?",
                            message:
                                "Approval buttons disable immediately and resolve through the mock runtime.",
                            risk: .high,
                            choices: [
                                .init(id: "publish", title: "Publish", role: .approve),
                                .init(id: "cancel", title: "Cancel", role: .reject),
                            ]
                        )
                    ),
                    state: .waitingForApproval
                ),
                block(
                    id: "showcase-error",
                    content: .error(
                        .init(
                            failure: .init(
                                code: "demo.network-timeout",
                                message: "A secondary preview request timed out safely.",
                                isRetryable: true
                            ),
                            retryTitle: "Retry preview"
                        )
                    ),
                    state: .failed(
                        .init(
                            code: "demo.network-timeout",
                            message: "Preview unavailable",
                            isRetryable: true
                        )
                    )
                ),
                block(
                    id: "showcase-unknown-fallback",
                    content: .custom(
                        .init(
                            kind: "company.release-summary",
                            payload: .object([
                                "environment": .string("staging"),
                                "checks": .array([.string("build"), .string("tests")]),
                                "ready": .bool(true),
                            ]),
                            fallbackTitle: "Unknown custom release summary",
                            fallbackSummary:
                                "No renderer is registered, so the safe fallback exposes a copy action."
                        )
                    )
                ),
            ],
            state: .waitingForApproval,
            createdAt: date.addingTimeInterval(5)
        )

        let interactivePrompt = AgentTurn(
            id: "showcase-interactive-prompt",
            role: .assistant,
            blocks: [
                block(
                    id: "showcase-interactive-markdown",
                    content: .markdown(
                        .init(
                            markdown:
                                "在底部输入任意内容，可以观看思考、搜索、命令、文件读取和 Markdown 结果依次流式出现。",
                            isFinal: true
                        )
                    )
                )
            ],
            state: .completed,
            createdAt: date.addingTimeInterval(6),
            completedAt: date.addingTimeInterval(6)
        )

        return .init(
            id: conversationID,
            title: rawValue,
            turns: [introduction, userRequest, response, operations, safety, interactivePrompt],
            state: .connected
        )
    }

    private func currentConversationSnapshot(date: Date) -> AgentConversationSnapshot {
        let entries: [(role: AgentTurnRole, text: String)] = [
            (
                .user,
                "根据这个项目里面的文档开发这个项目。"
            ),
            (
                .user,
                """
                我的 GitHub：[jacklv-coder](https://github.com/jacklv-coder)

                使用 SSH 把这个项目提交上去。
                """
            ),
            (
                .user,
                """
                Chat Layout 不是必要依赖。对于单列消息流，我会采用原生列表布局，并自建滚动锚定、流式高度更新和顶部插入保持位置的控制器，从而降低耦合与长期维护成本。
                """
            ),
            (
                .user,
                "实现文档更新了一个版本：AgentChatKit_iOS_iPadOS_v1_1_Engineering_Spec.md"
            ),
            (
                .assistant,
                """
                # v1.1 首轮工程实现

                项目已通过 SSH 提交：

                - GitHub：[jacklv-coder/agent-chat-kit](https://github.com/jacklv-coder/agent-chat-kit)
                - SSH 远端：git@github.com:jacklv-coder/agent-chat-kit.git
                - Debug 与 Release 构建通过
                - Core、Markdown、UIKit、Integration 和 Performance 测试通过
                - Thread Sanitizer、Demo、Swift Format 和 DocC 均通过

                时间线采用原生 UICollectionViewCompositionalLayout、自研滚动锚定和更新调度器，不依赖第三方 Chat Layout。
                """
            ),
            (
                .user,
                "能在这个 Demo 里面增加一个比较完整的案例吗？比如所有场景都有的，展示各种 Cell。"
            ),
            (
                .assistant,
                """
                已新增 **Complete Cell Showcase** 综合案例，包含全部 13 种 Block：

                - 用户消息与附件、Markdown、Activity、Tool、Command
                - 文件搜索、创建、更新、移动、删除与 Unified Diff
                - 图片、Artifact、审批、失败重试
                - 自定义天气 Renderer 和未知类型安全回退

                审批、Artifact、文件跳转、复制 Payload、重试、Composer 和主题切换均可交互。
                """
            ),
            (
                .user,
                """
                下面的都有对应的 Cell 吗？

                ├── Markdown Block
                ├── Thinking Block
                ├── File Search Block
                ├── Shell Tool Block
                ├── File Read Block
                ├── File Write Block
                ├── Browser Block
                └── Info Block
                """
            ),
            (
                .assistant,
                """
                不是全部都有独立专用 Cell。大部分类型共用 AgentBlockCell，通过 AgentBlockContent 分支渲染。

                | 需求类型 | 当前对应实现 | 综合 Demo |
                | --- | --- | --- |
                | Markdown Block | .markdown | 已有 |
                | Thinking Block | .activity 安全摘要 | 部分对应 |
                | File Search Block | .fileSearch | 已有 |
                | Shell Tool Block | .command | 已有 |
                | File Read Block | .fileOperation(.read) | Renderer 支持 |
                | File Write Block | .fileOperation(.create/.update) | 已有 |
                | Browser Block | .tool 或自定义 Renderer | 无专用类型 |
                | Info Block | .activity 或 .custom | 无专用类型 |
                """
            ),
            (
                .user,
                "这些 Cell 对比 OpenMinis 里面的状态都可以对应上吗？"
            ),
            (
                .assistant,
                """
                # OpenMinis 状态对比

                生命周期状态基本能够映射，但 Cell 能力目前不能 1:1 对齐。

                | OpenMinis | AgentChatKit | 结果 |
                | --- | --- | --- |
                | streaming(bytes:) | .streaming | 状态可映射，尚未展示字节数 |
                | running | .running(progress: nil) | 可映射 |
                | success | .succeeded | 可映射 |
                | failed(message:) | .failed(AgentFailure) | 可映射 |
                | cancelled | .cancelled | 可映射 |

                主要差距是可展开 Thinking、File Read/Write 详情、Browser URL/截图/会话，以及 Info 专用样式。
                """
            ),
            (
                .user,
                "能不能把我们当前这个会话内容作为测试数据，看看这些数据在 Demo 里面展示的样式？"
            ),
            (
                .assistant,
                """
                当前页面就是这段会话的离线重放数据。

                可以重点检查：

                1. 连续用户消息的气泡宽度和间距；
                2. 中文长段落与英文标识混排；
                3. 列表、目录树和表格的换行；
                4. 长会话滚动锚定和 Cell 复用；
                5. 深色模式、Dynamic Type 与文本选择。
                """
            ),
        ]

        var turns = entries.enumerated().map { index, entry in
            let content: AgentBlockContent
            switch entry.role {
            case .user:
                content = .userText(.init(text: entry.text))
            case .assistant, .system:
                content = .markdown(.init(markdown: entry.text, isFinal: true))
            }
            let timestamp = date.addingTimeInterval(Double(index))
            return AgentTurn(
                id: .init(rawValue: "replay-turn-\(index)"),
                role: entry.role,
                blocks: [
                    block(
                        id: .init(rawValue: "replay-block-\(index)"),
                        content: content
                    )
                ],
                state: .completed,
                createdAt: timestamp,
                completedAt: timestamp
            )
        }

        var screenshotOutput = AgentTextBuffer()
        screenshotOutput.append(
            "Wrote screenshot to /tmp/agentchat-complete-showcase.png\n"
        )
        let toolActivityTimestamp = date.addingTimeInterval(Double(entries.count))
        let toolActivity = AgentTurn(
            id: "replay-tool-activity",
            role: .assistant,
            blocks: [
                block(
                    id: "replay-activity-command",
                    content: .activity(
                        .init(
                            title: "运行了命令",
                            detail: "检查 Demo 场景和项目结构。"
                        )
                    )
                ),
                block(
                    id: "replay-command-screenshot",
                    content: .command(
                        .init(
                            command:
                                "xcrun simctl io booted screenshot /tmp/agentchat-complete-showcase.png",
                            workingDirectory: "/project",
                            output: screenshotOutput,
                            exitCode: 0,
                            duration: 0.2
                        )
                    )
                ),
                block(
                    id: "replay-image-inspection",
                    content: .image(
                        .init(
                            reference: .localIdentifier(
                                "agentchat-complete-showcase-screenshot"
                            ),
                            alternativeText: "已查看 1 张图像"
                        )
                    )
                ),
                block(
                    id: "replay-file-edit",
                    content: .fileOperation(
                        .init(
                            operation: .update,
                            path: "Examples/AgentChatDemo/Scenarios/DemoScenario.swift",
                            summary: "编辑了文件并更新了综合展示场景。"
                        )
                    )
                ),
                block(
                    id: "replay-skill-read",
                    content: .tool(
                        .init(
                            toolName: "skill.read",
                            title: "已读取 Computer Use 技能",
                            summary: "加载本机界面控制与视觉验收工作流。",
                            displayMode: .compact
                        )
                    )
                ),
                block(
                    id: "replay-simulator-tool",
                    content: .tool(
                        .init(
                            toolName: "com.apple.iphonesimulator",
                            title: "已使用 com.apple.iphonesimulator 集成加载了工具",
                            summary: "打开 Simulator 并检查 Demo 的真实渲染结果。",
                            input: .object([
                                "scenario": .string("Complete Cell Showcase")
                            ]),
                            output: .object(["status": .string("loaded")]),
                            displayMode: .compact
                        )
                    )
                ),
            ],
            state: .completed,
            createdAt: toolActivityTimestamp,
            completedAt: toolActivityTimestamp
        )
        turns.append(toolActivity)

        return .init(
            id: conversationID,
            title: rawValue,
            turns: turns,
            state: .connected
        )
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
