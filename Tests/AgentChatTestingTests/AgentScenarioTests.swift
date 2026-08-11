import AgentChatCore
import XCTest

@testable import AgentChatTesting

final class AgentScenarioTests: XCTestCase {
    func testScenarioDocumentJSONRoundTrip() throws {
        let event = AgentRuntimeEvent(
            id: "event",
            sequence: 1,
            conversationID: "conversation",
            timestamp: Date(timeIntervalSince1970: 0.123_456),
            payload: .conversationStateChanged(.connected)
        )
        let document = AgentScenarioDocument(
            id: "basic-streaming",
            title: "Basic Streaming",
            summary: "A portable fixture",
            tags: ["streaming"],
            scenario: .init(events: [.init(event: event)])
        )

        let data = try document.encodedJSON()
        let decoded = try AgentScenarioDocument.decodeJSON(data)

        XCTAssertEqual(decoded, document)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("basic-streaming"))
    }

    func testScenarioDocumentRejectsUnknownSchema() throws {
        let document = AgentScenarioDocument(
            schemaVersion: 999,
            id: "future",
            title: "Future",
            scenario: .init(events: [])
        )
        let data = try document.encodedJSON()

        XCTAssertThrowsError(try AgentScenarioDocument.decodeJSON(data)) { error in
            XCTAssertEqual(
                error as? AgentScenarioDocumentError,
                .unsupportedSchemaVersion(999)
            )
        }
    }

    func testPausedPlaybackReleasesExactlyOneStep() async throws {
        let controller = AgentScenarioPlaybackController(isPaused: true)
        let release = Task {
            try await controller.waitForTest(delayNanoseconds: 5_000_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        var state = await controller.state()
        XCTAssertEqual(state.emittedEventCount, 0)

        await controller.step()
        try await release.value
        state = await controller.state()

        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(state.emittedEventCount, 1)
        XCTAssertEqual(state.pendingStepCount, 0)
    }

    func testInstantPlaybackSkipsScriptDelay() async throws {
        let controller = AgentScenarioPlaybackController(rate: 0)
        let start = ContinuousClock.now

        try await controller.waitForTest(delayNanoseconds: 5_000_000_000)

        let state = await controller.state()
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(200))
        XCTAssertEqual(state.emittedEventCount, 1)
    }

    func testRuntimeEventTapeValidatorAcceptsStrictRevisionFlow() {
        let date = Date(timeIntervalSince1970: 0)
        let block = AgentBlock(
            id: "markdown",
            kind: .markdown,
            content: .markdown(.init(markdown: "", isFinal: false)),
            state: .streaming,
            createdAt: date
        )
        let turn = AgentTurn(
            id: "assistant",
            role: .assistant,
            blocks: [block],
            state: .streaming,
            createdAt: date
        )
        let events = [
            AgentRuntimeEvent(
                id: "one",
                sequence: 1,
                conversationID: "conversation",
                timestamp: date,
                payload: .turnInserted(turn)
            ),
            AgentRuntimeEvent(
                id: "two",
                sequence: 2,
                conversationID: "conversation",
                timestamp: date,
                payload: .blockDelta(
                    .init(
                        turnID: "assistant",
                        blockID: "markdown",
                        baseRevision: 0,
                        nextRevision: 1,
                        operation: .appendMarkdown("Hello")
                    )
                )
            ),
        ]

        let report = AgentRuntimeEventTapeValidator.validate(events)

        XCTAssertTrue(report.isValid, report.issues.map(\.message).joined(separator: "\n"))
    }

    func testRuntimeEventTapeValidatorReportsTransportContractViolations() {
        let date = Date(timeIntervalSince1970: 0)
        let events = [
            AgentRuntimeEvent(
                id: "duplicate",
                sequence: 2,
                conversationID: "one",
                timestamp: date,
                payload: .conversationStateChanged(.connected)
            ),
            AgentRuntimeEvent(
                id: "duplicate",
                sequence: 1,
                conversationID: "two",
                timestamp: date,
                payload: .blockDelta(
                    .init(
                        turnID: "turn",
                        blockID: "missing",
                        baseRevision: 4,
                        nextRevision: 4,
                        operation: .appendMarkdown("stale")
                    )
                )
            ),
        ]

        let report = AgentRuntimeEventTapeValidator.validate(
            events,
            expectedConversationID: "one"
        )
        let codes = Set(report.issues.map(\.code))

        XCTAssertFalse(report.isValid)
        XCTAssertTrue(codes.contains("event.duplicate-id"))
        XCTAssertTrue(codes.contains("event.non-monotonic-sequence"))
        XCTAssertTrue(codes.contains("event.wrong-conversation"))
        XCTAssertTrue(codes.contains("block.invalid-delta-revision"))
        XCTAssertTrue(codes.contains("block.delta-before-insert"))
    }
}

extension AgentScenarioPlaybackController {
    fileprivate func waitForTest(delayNanoseconds: UInt64) async throws {
        try await waitBeforeEmission(delayNanoseconds: delayNanoseconds)
    }
}
