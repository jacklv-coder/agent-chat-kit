import AgentChatKit
import Foundation
import os

/// A complete, offline adapter that demonstrates the runtime contract without hiding setup code.
actor ReferenceRuntimeAdapter: AgentRuntimeAdapter {
    func connect(configuration: AgentRuntimeConfiguration) async throws
        -> any AgentRuntimeConnection
    {
        ReferenceRuntimeConnection(conversationID: configuration.conversationID)
    }
}

private final class ReferenceRuntimeConnection: AgentRuntimeConnection, Sendable {
    let capabilities: AgentRuntimeCapabilities = [.streamingText, .interrupt]

    private let stream: AsyncThrowingStream<AgentRuntimeEvent, any Error>
    private let consumed = OSAllocatedUnfairLock(initialState: false)
    private let controller: ReferenceRuntimeController

    init(conversationID: AgentConversationID) {
        let pair = AsyncThrowingStream<AgentRuntimeEvent, any Error>.makeStream()
        stream = pair.stream
        controller = ReferenceRuntimeController(
            conversationID: conversationID,
            continuation: pair.continuation
        )
        Task { [controller] in await controller.start() }
    }

    func makeEventStream() -> AsyncThrowingStream<AgentRuntimeEvent, any Error> {
        let isFirst = consumed.withLock { consumed in
            guard !consumed else { return false }
            consumed = true
            return true
        }
        guard isFirst else {
            return AsyncThrowingStream { $0.finish(throwing: ReferenceRuntimeError.streamConsumed) }
        }
        return stream
    }

    func send(_ command: AgentRuntimeCommand) async throws {
        try await controller.send(command)
    }

    func close() async { await controller.close() }
}

private actor ReferenceRuntimeController {
    private let conversationID: AgentConversationID
    private let continuation: AsyncThrowingStream<AgentRuntimeEvent, any Error>.Continuation
    private var sequence: Int64 = 0
    private var eventCount: Int64 = 0
    private var requestCount = 0
    private var activeResponse: Task<Void, Never>?
    private var activeTurn: AgentTurn?
    private var isClosed = false

    init(
        conversationID: AgentConversationID,
        continuation: AsyncThrowingStream<AgentRuntimeEvent, any Error>.Continuation
    ) {
        self.conversationID = conversationID
        self.continuation = continuation
    }

    func start() {
        emit(.snapshot(.init(id: conversationID, state: .connected)))
    }

    func send(_ command: AgentRuntimeCommand) throws {
        guard !isClosed else { throw ReferenceRuntimeError.closed }
        switch command {
        case .submit(let request):
            requestCount += 1
            activeResponse?.cancel()
            let requestIndex = requestCount
            activeResponse = Task { [weak self] in
                await self?.respond(to: request, requestIndex: requestIndex)
            }
        case .interrupt:
            activeResponse?.cancel()
            activeResponse = nil
            guard var turn = activeTurn else { return }
            turn.state = .cancelled
            turn.completedAt = Date()
            for index in turn.blocks.indices where turn.blocks[index].state.isActive {
                turn.blocks[index].state = .cancelled
                turn.blocks[index].revision += 1
            }
            activeTurn = turn
            emit(.turnUpdated(turn))
        default:
            break
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        activeResponse?.cancel()
        activeResponse = nil
        continuation.finish()
    }

    private func respond(to request: AgentSubmitRequest, requestIndex: Int) async {
        let timestamp = Date()
        let userTurn = AgentTurn(
            id: .init(rawValue: "quick-user-\(requestIndex)"),
            role: .user,
            blocks: [
                .init(
                    id: .init(rawValue: "quick-user-block-\(requestIndex)"),
                    kind: .userText,
                    content: .userText(
                        .init(text: request.text, attachments: request.attachments)
                    ),
                    state: .succeeded,
                    createdAt: timestamp
                )
            ],
            state: .completed,
            createdAt: timestamp,
            completedAt: timestamp
        )
        emit(.turnInserted(userTurn))

        let thinkingID = AgentBlockID(rawValue: "quick-thinking-\(requestIndex)")
        let markdownID = AgentBlockID(rawValue: "quick-markdown-\(requestIndex)")
        var turn = AgentTurn(
            id: .init(rawValue: "quick-assistant-\(requestIndex)"),
            role: .assistant,
            blocks: [
                .init(
                    id: thinkingID,
                    kind: .activity,
                    content: .activity(
                        .init(title: "Thinking", detail: "Preparing a reference response")
                    ),
                    state: .running(progress: nil),
                    createdAt: timestamp
                )
            ],
            state: .running,
            createdAt: timestamp
        )
        activeTurn = turn
        emit(.turnInserted(turn))

        guard await pause(milliseconds: 350) else { return }
        turn.blocks[0].content = .activity(
            .init(title: "Thought", detail: "The adapter emits structured UI events.")
        )
        turn.blocks[0].state = .succeeded
        turn.blocks[0].revision = 1
        activeTurn = turn
        emit(.blockReplaced(turnID: turn.id, block: turn.blocks[0]))

        let markdown = AgentBlock(
            id: markdownID,
            kind: .markdown,
            content: .markdown(.init(markdown: "", isFinal: false)),
            state: .streaming,
            createdAt: Date()
        )
        turn.blocks.append(markdown)
        turn.state = .streaming
        activeTurn = turn
        emit(.blockInserted(turnID: turn.id, block: markdown))

        let safeInput = request.text.replacingOccurrences(of: "|", with: "\\|")
        let chunks = [
            "## Runtime connected\n\nYou sent: **\(safeInput)**\n\n",
            "| Layer | Responsibility |\n| --- | --- |\n",
            "| Host runtime | Models, tools, transport |\n",
            "| AgentChatKit | State reduction and native UI |",
        ]
        var revision: Int64 = 0
        var completeText = ""
        for chunk in chunks {
            guard await pause(milliseconds: 220) else { return }
            completeText += chunk
            emit(
                .blockDelta(
                    .init(
                        turnID: turn.id,
                        blockID: markdownID,
                        baseRevision: revision,
                        nextRevision: revision + 1,
                        operation: .appendMarkdown(chunk)
                    )
                )
            )
            revision += 1
        }

        var completedMarkdown = markdown
        completedMarkdown.content = .markdown(.init(markdown: completeText, isFinal: true))
        completedMarkdown.state = .succeeded
        completedMarkdown.revision = revision + 1
        turn.blocks[1] = completedMarkdown
        turn.state = .completed
        turn.completedAt = Date()
        activeTurn = turn
        emit(.blockReplaced(turnID: turn.id, block: completedMarkdown))
        emit(.turnUpdated(turn))
        activeResponse = nil
    }

    private func emit(_ payload: AgentRuntimeEventPayload) {
        guard !isClosed else { return }
        sequence += 1
        eventCount += 1
        continuation.yield(
            .init(
                id: .init(rawValue: "quick-event-\(eventCount)"),
                sequence: sequence,
                conversationID: conversationID,
                timestamp: Date(),
                payload: payload
            )
        )
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

private enum ReferenceRuntimeError: Error {
    case streamConsumed
    case closed
}

extension AgentBlockState {
    fileprivate var isActive: Bool {
        switch self {
        case .queued, .streaming, .running, .waitingForApproval: true
        case .succeeded, .failed, .cancelled: false
        }
    }
}
