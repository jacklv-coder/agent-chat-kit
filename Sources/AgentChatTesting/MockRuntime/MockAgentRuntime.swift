import AgentChatCore
import Foundation
import os

/// An offline scripted runtime adapter for demos and integration tests.
public actor MockAgentRuntime: AgentRuntimeAdapter {
    private let scenario: AgentScenario
    private let capabilities: AgentRuntimeCapabilities
    private var latestConnection: MockAgentRuntimeConnection?

    /// Creates a mock runtime.
    public init(
        scenario: AgentScenario,
        capabilities: AgentRuntimeCapabilities = [
            .streamingText, .tools, .commands, .fileOperations, .diffs, .approvals,
            .attachments, .history, .retry, .interrupt, .customBlocks,
        ]
    ) {
        self.scenario = scenario
        self.capabilities = capabilities
    }

    /// Creates a fresh scripted connection.
    public func connect(configuration: AgentRuntimeConfiguration) async throws
        -> any AgentRuntimeConnection
    {
        let connection = MockAgentRuntimeConnection(
            scenario: scenario,
            capabilities: capabilities
        )
        latestConnection = connection
        return connection
    }

    /// Returns commands received by the latest connection.
    public func receivedCommands() async -> [AgentRuntimeCommand] {
        await latestConnection?.receivedCommands() ?? []
    }
}

/// A single-consumer scripted runtime connection.
public final class MockAgentRuntimeConnection: AgentRuntimeConnection, Sendable {
    /// Features exposed to the UI.
    public let capabilities: AgentRuntimeCapabilities

    private let stream: AsyncThrowingStream<AgentRuntimeEvent, any Error>
    private let streamConsumed = OSAllocatedUnfairLock(initialState: false)
    private let controller: MockConnectionController

    /// Creates and starts a scripted connection.
    public init(scenario: AgentScenario, capabilities: AgentRuntimeCapabilities) {
        self.capabilities = capabilities
        let pair = AsyncThrowingStream<AgentRuntimeEvent, any Error>.makeStream()
        self.stream = pair.stream
        self.controller = MockConnectionController(
            scenario: scenario,
            continuation: pair.continuation
        )
        Task { await controller.start() }
    }

    /// Returns the one permitted event stream, or a failing stream for later consumers.
    public func makeEventStream() -> AsyncThrowingStream<AgentRuntimeEvent, any Error> {
        let isFirst = streamConsumed.withLock { consumed in
            guard consumed == false else { return false }
            consumed = true
            return true
        }
        guard isFirst else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: MockRuntimeError.eventStreamAlreadyConsumed)
            }
        }
        return stream
    }

    /// Records a command without performing external work.
    public func send(_ command: AgentRuntimeCommand) async throws {
        try await controller.receive(command)
    }

    /// Cancels scenario emission idempotently.
    public func close() async { await controller.close() }

    /// Returns recorded commands.
    public func receivedCommands() async -> [AgentRuntimeCommand] {
        await controller.commands()
    }
}

/// Failures intentionally produced by the mock runtime.
public enum MockRuntimeError: Error, Hashable, Sendable {
    /// The connection event stream was requested more than once.
    case eventStreamAlreadyConsumed
    /// A command was sent after close.
    case connectionClosed
}

private actor MockConnectionController {
    private let scenario: AgentScenario
    private let continuation: AsyncThrowingStream<AgentRuntimeEvent, any Error>.Continuation
    private var producer: Task<Void, Never>?
    private var received: [AgentRuntimeCommand] = []
    private var isClosed = false
    private let reducer: AgentConversationReducer
    private var latestSnapshot: AgentConversationSnapshot
    private var nextCommandSequence: Int64
    private var nextCommandTimestamp: Date
    private var generatedEventCount: Int64 = 0
    private var responseTasks: [Int: Task<Void, Never>] = [:]

    init(
        scenario: AgentScenario,
        continuation: AsyncThrowingStream<AgentRuntimeEvent, any Error>.Continuation
    ) {
        self.scenario = scenario
        self.continuation = continuation
        let firstEvent = scenario.events.first?.event
        let conversationID = firstEvent?.conversationID ?? "mock"
        let initial = AgentConversationSnapshot.empty(conversationID: conversationID)
        self.reducer = AgentConversationReducer(snapshot: initial)
        self.latestSnapshot = initial
        self.nextCommandSequence = (scenario.events.map(\.event.sequence).max() ?? 0) + 1
        self.nextCommandTimestamp = (scenario.events.map(\.event.timestamp).max() ?? .distantPast)
            .addingTimeInterval(1)
    }

    func start() {
        guard producer == nil, !isClosed else { return }
        producer = Task { [weak self, scenario] in
            do {
                for step in scenario.events {
                    try await Task.sleep(nanoseconds: step.delayNanoseconds)
                    try Task.checkCancellation()
                    await self?.emit(step.event)
                }
            } catch {
                return
            }
        }
    }

    func receive(_ command: AgentRuntimeCommand) async throws {
        guard !isClosed else { throw MockRuntimeError.connectionClosed }
        received.append(command)
        switch command {
        case .submit(let request):
            let requestIndex = received.count
            let userTurnID = AgentTurnID(rawValue: "mock-user-\(requestIndex)")
            let userBlock = AgentBlock(
                id: .init(rawValue: "mock-user-block-\(requestIndex)"),
                kind: .userText,
                content: .userText(
                    .init(text: request.text, attachments: request.attachments)
                ),
                state: .succeeded,
                createdAt: nextCommandTimestamp
            )
            await emitGenerated(
                conversationID: request.conversationID,
                payload: .turnInserted(
                    .init(
                        id: userTurnID,
                        role: .user,
                        blocks: [userBlock],
                        state: .completed,
                        createdAt: nextCommandTimestamp,
                        completedAt: nextCommandTimestamp
                    )
                )
            )
            let assistantTurnID = AgentTurnID(rawValue: "mock-assistant-\(requestIndex)")
            let thinkingBlock = AgentBlock(
                id: .init(rawValue: "mock-thinking-\(requestIndex)"),
                kind: .activity,
                content: .activity(
                    .init(
                        title: "正在思考",
                        detail: "正在分析消息并规划可展示的 Demo 响应。"
                    )
                ),
                state: .running(progress: nil),
                createdAt: nextCommandTimestamp
            )
            await emitGenerated(
                conversationID: request.conversationID,
                payload: .turnInserted(
                    .init(
                        id: assistantTurnID,
                        role: .assistant,
                        blocks: [thinkingBlock],
                        state: .running,
                        createdAt: nextCommandTimestamp
                    )
                )
            )
            responseTasks[requestIndex]?.cancel()
            responseTasks[requestIndex] = Task { [weak self] in
                await self?.produceInteractiveResponse(
                    request: request,
                    requestIndex: requestIndex,
                    turnID: assistantTurnID
                )
            }

        case .approve(let response), .reject(let response):
            await emitGenerated(
                conversationID: response.conversationID,
                payload: .approvalResolved(
                    .init(
                        approvalID: response.approvalID,
                        choiceID: response.choiceID,
                        resolvedAt: nextCommandTimestamp
                    )
                )
            )

        case .interrupt(let request):
            for task in responseTasks.values { task.cancel() }
            responseTasks.removeAll()
            guard var lastTurn = latestSnapshot.turns.last else { return }
            lastTurn.state = .cancelled
            lastTurn.completedAt = nextCommandTimestamp
            for index in lastTurn.blocks.indices {
                switch lastTurn.blocks[index].state {
                case .running, .queued, .streaming, .waitingForApproval:
                    lastTurn.blocks[index].state = .cancelled
                    lastTurn.blocks[index].revision += 1
                    lastTurn.blocks[index].updatedAt = nextCommandTimestamp
                default:
                    break
                }
            }
            await emitGenerated(
                conversationID: request.conversationID,
                payload: .turnUpdated(lastTurn)
            )

        default:
            break
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        producer?.cancel()
        producer = nil
        for task in responseTasks.values { task.cancel() }
        responseTasks.removeAll()
        continuation.finish()
    }

    func commands() -> [AgentRuntimeCommand] { received }

    private func emit(_ event: AgentRuntimeEvent) async {
        let result = await reducer.consume(event)
        latestSnapshot = result.snapshot
        continuation.yield(event)
    }

    private func emitGenerated(
        conversationID: AgentConversationID,
        payload: AgentRuntimeEventPayload
    ) async {
        generatedEventCount += 1
        let event = AgentRuntimeEvent(
            id: .init(rawValue: "mock-command-event-\(generatedEventCount)"),
            sequence: nextCommandSequence,
            conversationID: conversationID,
            timestamp: nextCommandTimestamp,
            payload: payload
        )
        nextCommandSequence += 1
        nextCommandTimestamp = nextCommandTimestamp.addingTimeInterval(1)
        await emit(event)
    }

    private func produceInteractiveResponse(
        request: AgentSubmitRequest,
        requestIndex: Int,
        turnID: AgentTurnID
    ) async {
        let thinkingID = AgentBlockID(rawValue: "mock-thinking-\(requestIndex)")
        let searchID = AgentBlockID(rawValue: "mock-search-\(requestIndex)")
        let commandID = AgentBlockID(rawValue: "mock-command-\(requestIndex)")
        let readID = AgentBlockID(rawValue: "mock-read-\(requestIndex)")
        let markdownID = AgentBlockID(rawValue: "mock-markdown-\(requestIndex)")
        let thinkingCreatedAt =
            latestSnapshot.turns.first(where: { $0.id == turnID })?.blocks.first(where: {
                $0.id == thinkingID
            })?.createdAt ?? nextCommandTimestamp

        guard await pause(milliseconds: 450) else { return }
        await emitGenerated(
            conversationID: request.conversationID,
            payload: .blockReplaced(
                turnID: turnID,
                block: AgentBlock(
                    id: thinkingID,
                    kind: .activity,
                    content: .activity(
                        .init(
                            title: "已完成思考",
                            detail: "已生成安全摘要；不会展示私有推理过程。"
                        )
                    ),
                    state: .succeeded,
                    revision: 1,
                    createdAt: thinkingCreatedAt
                )
            )
        )

        guard await pause(milliseconds: 320) else { return }
        await emitGenerated(
            conversationID: request.conversationID,
            payload: .blockInserted(
                turnID: turnID,
                block: AgentBlock(
                    id: searchID,
                    kind: .fileSearch,
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
                                    path: "Sources/AgentChatUIKit/Cells/AgentBlockCell.swift",
                                    excerpt: "final class AgentBlockCell",
                                    line: 6
                                ),
                            ],
                            totalCount: 2
                        )
                    ),
                    state: .succeeded,
                    createdAt: nextCommandTimestamp
                )
            )
        )

        guard await pause(milliseconds: 320) else { return }
        let commandCreatedAt = nextCommandTimestamp
        await emitGenerated(
            conversationID: request.conversationID,
            payload: .blockInserted(
                turnID: turnID,
                block: AgentBlock(
                    id: commandID,
                    kind: .command,
                    content: .command(
                        .init(command: "swift test --filter AgentTimelineTests")
                    ),
                    state: .running(progress: nil),
                    createdAt: commandCreatedAt
                )
            )
        )

        guard await pause(milliseconds: 420) else { return }
        await emitGenerated(
            conversationID: request.conversationID,
            payload: .blockDelta(
                .init(
                    turnID: turnID,
                    blockID: commandID,
                    baseRevision: 0,
                    nextRevision: 1,
                    operation: .appendCommandOutput("Building AgentChatKit…\n")
                )
            )
        )

        guard await pause(milliseconds: 320) else { return }
        var commandOutput = AgentTextBuffer()
        commandOutput.append("Building AgentChatKit…\nAll selected tests passed.\n")
        await emitGenerated(
            conversationID: request.conversationID,
            payload: .blockReplaced(
                turnID: turnID,
                block: AgentBlock(
                    id: commandID,
                    kind: .command,
                    content: .command(
                        .init(
                            command: "swift test --filter AgentTimelineTests",
                            workingDirectory: "/project",
                            output: commandOutput,
                            exitCode: 0,
                            duration: 0.7
                        )
                    ),
                    state: .succeeded,
                    revision: 2,
                    createdAt: commandCreatedAt
                )
            )
        )

        guard await pause(milliseconds: 300) else { return }
        await emitGenerated(
            conversationID: request.conversationID,
            payload: .blockInserted(
                turnID: turnID,
                block: AgentBlock(
                    id: readID,
                    kind: .fileOperation,
                    content: .fileOperation(
                        .init(
                            operation: .read,
                            path: "AgentChatKit_iOS_iPadOS_v1_1_Engineering_Spec.md",
                            summary: "读取了工程规范并核对交互要求。"
                        )
                    ),
                    state: .succeeded,
                    createdAt: nextCommandTimestamp
                )
            )
        )

        guard await pause(milliseconds: 320) else { return }
        await emitGenerated(
            conversationID: request.conversationID,
            payload: .blockInserted(
                turnID: turnID,
                block: AgentBlock(
                    id: markdownID,
                    kind: .markdown,
                    content: .markdown(.init(markdown: "", isFinal: false)),
                    state: .streaming,
                    createdAt: nextCommandTimestamp
                )
            )
        )

        let escapedInput = request.text.replacingOccurrences(of: "|", with: "\\|")
        let chunks = [
            "## Demo 实时响应\n\n已收到：**\(escapedInput)**\n\n",
            "| 阶段 | 展示结果 |\n| --- | --- |\n",
            "| 思考摘要 | 已完成 |\n| 文件搜索 | 找到 2 项 |\n",
            "| 命令执行 | 测试通过 |\n| Markdown 表格 | 原生 UIKit 渲染 |",
        ]
        var revision: Int64 = 0
        var finalMarkdown = ""
        for chunk in chunks {
            guard await pause(milliseconds: 240) else { return }
            finalMarkdown += chunk
            await emitGenerated(
                conversationID: request.conversationID,
                payload: .blockDelta(
                    .init(
                        turnID: turnID,
                        blockID: markdownID,
                        baseRevision: revision,
                        nextRevision: revision + 1,
                        operation: .appendMarkdown(chunk)
                    )
                )
            )
            revision += 1
        }

        await emitGenerated(
            conversationID: request.conversationID,
            payload: .blockDelta(
                .init(
                    turnID: turnID,
                    blockID: markdownID,
                    baseRevision: revision,
                    nextRevision: revision + 1,
                    operation: .replaceContent(
                        .markdown(.init(markdown: finalMarkdown, isFinal: true))
                    )
                )
            )
        )
        revision += 1
        await emitGenerated(
            conversationID: request.conversationID,
            payload: .blockDelta(
                .init(
                    turnID: turnID,
                    blockID: markdownID,
                    baseRevision: revision,
                    nextRevision: revision + 1,
                    operation: .setState(.succeeded)
                )
            )
        )

        guard var completedTurn = latestSnapshot.turns.first(where: { $0.id == turnID }) else {
            return
        }
        completedTurn.state = .completed
        completedTurn.completedAt = nextCommandTimestamp
        await emitGenerated(
            conversationID: request.conversationID,
            payload: .turnUpdated(completedTurn)
        )
        responseTasks[requestIndex] = nil
    }

    private func pause(milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            try Task.checkCancellation()
            return !isClosed
        } catch {
            return false
        }
    }
}
