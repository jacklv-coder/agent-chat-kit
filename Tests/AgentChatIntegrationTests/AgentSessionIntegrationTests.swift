import AgentChatCore
import AgentChatTesting
import XCTest

@MainActor
final class AgentSessionIntegrationTests: XCTestCase {
    func testScriptedRuntimeFlowsThroughSessionReducerAndStore() async throws {
        var builder = AgentEventSequenceBuilder(conversationID: "conversation")
        let date = Date(timeIntervalSince1970: 0)
        let turn = AgentTurn(
            id: "turn",
            role: .assistant,
            blocks: [
                .init(
                    id: "markdown",
                    kind: .markdown,
                    content: .markdown(.init(markdown: "Hello", isFinal: false)),
                    state: .streaming,
                    createdAt: date
                )
            ],
            state: .streaming,
            createdAt: date
        )
        let insert = builder.event(.turnInserted(turn))
        let delta = builder.event(
            .blockDelta(
                .init(
                    turnID: "turn",
                    blockID: "markdown",
                    baseRevision: 0,
                    nextRevision: 1,
                    operation: .appendMarkdown(", world")
                )
            )
        )
        let completed = builder.event(
            .turnUpdated(
                .init(
                    id: "turn",
                    role: .assistant,
                    blocks: [
                        .init(
                            id: "markdown",
                            kind: .markdown,
                            content: .markdown(.init(markdown: "Hello, world", isFinal: true)),
                            state: .succeeded,
                            revision: 2,
                            createdAt: date
                        )
                    ],
                    state: .completed,
                    createdAt: date,
                    completedAt: date
                )
            )
        )
        let runtime = MockAgentRuntime(
            scenario: .init(
                events: [insert, delta, completed].map {
                    .init(event: $0, delayNanoseconds: 1_000_000)
                })
        )
        let store = AgentConversationStore(snapshot: .empty(conversationID: "conversation"))
        let session = AgentChatSession(
            adapter: runtime,
            configuration: .init(conversationID: "conversation"),
            store: store
        )
        try await session.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.snapshot.turns.count, 1)
        XCTAssertEqual(store.snapshot.turns[0].state, .completed)
        guard case .markdown(let markdown) = store.snapshot.turns[0].blocks[0].content else {
            return XCTFail("Expected Markdown")
        }
        XCTAssertEqual(markdown.markdown, "Hello, world")

        try await session.send(.interrupt(.init(conversationID: "conversation")))
        let commands = await runtime.receivedCommands()
        XCTAssertEqual(commands, [.interrupt(.init(conversationID: "conversation"))])
        await session.stop()
        await session.stop()
    }

    func testMockConnectionAllowsOnlyOneEventConsumerAndCloseIsIdempotent() async {
        let connection = MockAgentRuntimeConnection(
            scenario: .init(events: []),
            capabilities: []
        )
        _ = connection.makeEventStream()
        let second = connection.makeEventStream()
        do {
            for try await _ in second {}
            XCTFail("Expected a single-consumer failure")
        } catch {
            XCTAssertEqual(error as? MockRuntimeError, .eventStreamAlreadyConsumed)
        }
        await connection.close()
        await connection.close()
    }

    func testSubmittedMessageProducesThinkingToolsAndStreamingMarkdown() async throws {
        let conversationID: AgentConversationID = "interactive"
        let runtime = MockAgentRuntime(scenario: .init(events: []))
        let store = AgentConversationStore(snapshot: .empty(conversationID: conversationID))
        let session = AgentChatSession(
            adapter: runtime,
            configuration: .init(conversationID: conversationID),
            store: store
        )
        try await session.start()

        try await session.send(
            .submit(.init(conversationID: conversationID, text: "Show every state"))
        )
        for _ in 0..<100 {
            if store.snapshot.turns.count == 2,
                store.snapshot.turns.last?.role == .assistant,
                store.snapshot.turns.last?.state == .completed
            {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(store.snapshot.turns.map(\.role), [.user, .assistant])
        let assistant = try XCTUnwrap(store.snapshot.turns.last)
        XCTAssertEqual(assistant.state, .completed)
        XCTAssertEqual(
            assistant.blocks.map(\.kind),
            [.activity, .fileSearch, .command, .fileOperation, .markdown]
        )
        guard case .markdown(let markdown) = assistant.blocks.last?.content else {
            return XCTFail("Expected final Markdown")
        }
        XCTAssertTrue(markdown.isFinal)
        XCTAssertTrue(markdown.markdown.contains("| 阶段 | 展示结果 |"))
        await session.stop()
    }

    func testStreamFailureRetainsSnapshotAndMarksStoreOffline() async throws {
        let conversationID: AgentConversationID = "disconnect"
        let snapshot = AgentConversationSnapshot(
            id: conversationID,
            turns: [
                .init(
                    id: "retained-turn",
                    role: .assistant,
                    blocks: [],
                    state: .completed,
                    createdAt: Date(timeIntervalSince1970: 0)
                )
            ],
            state: .connected
        )
        let store = AgentConversationStore(snapshot: .empty(conversationID: conversationID))
        let session = AgentChatSession(
            adapter: FailingAdapter(snapshot: snapshot),
            configuration: .init(conversationID: conversationID),
            store: store
        )
        try await session.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(store.snapshot.turns.map(\.id), ["retained-turn"])
        guard case .offline = store.snapshot.state else {
            return XCTFail("Expected retained offline state")
        }
        await session.stop()
    }

    func testNormalStreamCompletionAlsoMarksStoreOffline() async throws {
        let conversationID: AgentConversationID = "finished"
        let snapshot = AgentConversationSnapshot(id: conversationID, state: .connected)
        let store = AgentConversationStore(snapshot: .empty(conversationID: conversationID))
        let session = AgentChatSession(
            adapter: FinishingAdapter(snapshot: snapshot),
            configuration: .init(conversationID: conversationID),
            store: store
        )

        try await session.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        guard case .offline = store.snapshot.state else {
            return XCTFail("Expected a normally completed connection to become offline")
        }
        await session.stop()
    }
}

private struct FinishingAdapter: AgentRuntimeAdapter {
    let snapshot: AgentConversationSnapshot

    func connect(configuration: AgentRuntimeConfiguration) async throws
        -> any AgentRuntimeConnection
    {
        FinishingConnection(snapshot: snapshot)
    }
}

private struct FinishingConnection: AgentRuntimeConnection {
    let snapshot: AgentConversationSnapshot
    var capabilities: AgentRuntimeCapabilities { [] }

    func makeEventStream() -> AsyncThrowingStream<AgentRuntimeEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .init(
                    id: "snapshot",
                    sequence: 1,
                    conversationID: snapshot.id,
                    timestamp: Date(timeIntervalSince1970: 0),
                    payload: .snapshot(snapshot)
                )
            )
            continuation.finish()
        }
    }

    func send(_ command: AgentRuntimeCommand) async throws {}
    func close() async {}
}

private struct FailingAdapter: AgentRuntimeAdapter {
    let snapshot: AgentConversationSnapshot

    func connect(configuration: AgentRuntimeConfiguration) async throws
        -> any AgentRuntimeConnection
    {
        FailingConnection(snapshot: snapshot)
    }
}

private struct FailingConnection: AgentRuntimeConnection {
    let snapshot: AgentConversationSnapshot
    var capabilities: AgentRuntimeCapabilities { [] }

    func makeEventStream() -> AsyncThrowingStream<AgentRuntimeEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .init(
                    id: "snapshot",
                    sequence: 1,
                    conversationID: snapshot.id,
                    timestamp: Date(timeIntervalSince1970: 0),
                    payload: .snapshot(snapshot)
                )
            )
            continuation.finish(throwing: TestConnectionError.disconnected)
        }
    }

    func send(_ command: AgentRuntimeCommand) async throws {}
    func close() async {}
}

private enum TestConnectionError: Error { case disconnected }
