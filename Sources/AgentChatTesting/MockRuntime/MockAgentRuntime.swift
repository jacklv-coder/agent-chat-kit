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
            let userTurnID = AgentTurnID(rawValue: "mock-user-\(received.count)")
            let userBlock = AgentBlock(
                id: .init(rawValue: "mock-user-block-\(received.count)"),
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
            let assistantTurnID = AgentTurnID(rawValue: "mock-assistant-\(received.count)")
            let assistantBlock = AgentBlock(
                id: .init(rawValue: "mock-assistant-block-\(received.count)"),
                kind: .markdown,
                content: .markdown(
                    .init(
                        markdown: "Offline mock runtime received your message.",
                        isFinal: true
                    )
                ),
                state: .succeeded,
                createdAt: nextCommandTimestamp
            )
            await emitGenerated(
                conversationID: request.conversationID,
                payload: .turnInserted(
                    .init(
                        id: assistantTurnID,
                        role: .assistant,
                        blocks: [assistantBlock],
                        state: .completed,
                        createdAt: nextCommandTimestamp,
                        completedAt: nextCommandTimestamp
                    )
                )
            )

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
}
