import XCTest

@testable import AgentChatCore

final class AgentConversationReducerTests: XCTestCase {
    private let conversationID: AgentConversationID = "conversation"
    private let epoch = Date(timeIntervalSince1970: 1_000)

    func testDuplicateEventIsIdempotent() async {
        let reducer = makeReducer()
        let event = makeEvent(sequence: 1, payload: .turnInserted(makeTurn()))
        let first = await reducer.consume(event)
        let duplicate = await reducer.consume(event)
        XCTAssertEqual(first.snapshot.turns.count, 1)
        XCTAssertEqual(duplicate.snapshot.turns.count, 1)
        XCTAssertTrue(duplicate.patches.isEmpty)
    }

    func testOutOfOrderEventsDrainInSequence() async {
        let reducer = makeReducer()
        _ = await reducer.consume(makeEvent(sequence: 1, payload: .turnInserted(makeTurn())))
        let third = makeEvent(
            sequence: 3,
            payload: .blockDelta(
                .init(
                    turnID: "turn",
                    blockID: "block",
                    baseRevision: 1,
                    nextRevision: 2,
                    operation: .appendMarkdown("B")
                )
            )
        )
        let buffered = await reducer.consume(third)
        XCTAssertEqual(markdown(in: buffered.snapshot), "")

        let second = makeEvent(
            sequence: 2,
            payload: .blockDelta(
                .init(
                    turnID: "turn",
                    blockID: "block",
                    baseRevision: 0,
                    nextRevision: 1,
                    operation: .appendMarkdown("A")
                )
            )
        )
        let drained = await reducer.consume(second)
        XCTAssertEqual(markdown(in: drained.snapshot), "AB")
        XCTAssertEqual(drained.patches.filter(isBlockReconfigure).count, 2)
    }

    func testSequenceGapRequestsSnapshotAfterTimeout() async {
        let reducer = makeReducer(configuration: .init(sequenceGapTimeout: 2))
        _ = await reducer.consume(makeEvent(sequence: 1, payload: .turnInserted(makeTurn())))
        _ = await reducer.consume(
            makeEvent(sequence: 3, seconds: 0, payload: .conversationStateChanged(.connected))
        )
        let result = await reducer.consume(
            makeEvent(sequence: 4, seconds: 3, payload: .conversationStateChanged(.connected))
        )
        XCTAssertTrue(result.requiresSnapshot)
    }

    func testSnapshotReestablishesOrderingBaseline() async {
        let reducer = makeReducer()
        _ = await reducer.consume(makeEvent(sequence: 1, payload: .turnInserted(makeTurn())))
        _ = await reducer.consume(
            makeEvent(sequence: 3, payload: .conversationStateChanged(.offline(message: nil)))
        )
        let replacement = AgentConversationSnapshot(
            id: conversationID,
            title: "Recovered",
            state: .connected
        )
        let result = await reducer.consume(
            makeEvent(sequence: 10, payload: .snapshot(replacement))
        )
        XCTAssertEqual(result.snapshot, replacement)
        let next = await reducer.consume(
            makeEvent(sequence: 11, payload: .conversationStateChanged(.idle))
        )
        XCTAssertEqual(next.snapshot.state, .idle)
    }

    func testRevisionConflictDoesNotOverwriteNewerBlock() async {
        let reducer = makeReducer()
        _ = await reducer.consume(makeEvent(sequence: 1, payload: .turnInserted(makeTurn())))
        _ = await reducer.consume(
            makeEvent(
                sequence: 2,
                payload: .blockDelta(
                    .init(
                        turnID: "turn",
                        blockID: "block",
                        baseRevision: 0,
                        nextRevision: 2,
                        operation: .appendMarkdown("new")
                    )
                )
            )
        )
        let stale = await reducer.consume(
            makeEvent(
                sequence: 3,
                payload: .blockDelta(
                    .init(
                        turnID: "turn",
                        blockID: "block",
                        baseRevision: 0,
                        nextRevision: 3,
                        operation: .appendMarkdown("stale")
                    )
                )
            )
        )
        XCTAssertEqual(markdown(in: stale.snapshot), "new")
        XCTAssertTrue(stale.notices.contains { $0.code == "delta.revision-conflict" })
    }

    func testDeltaTypeMismatchPreservesBlock() async {
        let reducer = makeReducer()
        _ = await reducer.consume(makeEvent(sequence: 1, payload: .turnInserted(makeTurn())))
        let result = await reducer.consume(
            makeEvent(
                sequence: 2,
                payload: .blockDelta(
                    .init(
                        turnID: "turn",
                        blockID: "block",
                        nextRevision: 1,
                        operation: .appendCommandOutput("unsafe")
                    )
                )
            )
        )
        XCTAssertEqual(markdown(in: result.snapshot), "")
        XCTAssertTrue(result.notices.contains { $0.code == "delta.type-mismatch" })
    }

    func testApprovalResolutionIsOneShot() async {
        let reducer = makeReducer()
        var turn = makeTurn()
        let approval = ApprovalBlock(
            approvalID: "approval",
            title: "Proceed?",
            risk: .high,
            choices: [
                .init(id: "yes", title: "Allow", role: .approve),
                .init(id: "no", title: "Reject", role: .reject),
            ]
        )
        turn.blocks = [
            AgentBlock(
                id: "approval-block",
                kind: .approval,
                content: .approval(approval),
                state: .waitingForApproval,
                createdAt: epoch
            )
        ]
        _ = await reducer.consume(makeEvent(sequence: 1, payload: .turnInserted(turn)))
        let accepted = AgentApprovalResolution(
            approvalID: "approval",
            choiceID: "yes",
            resolvedAt: epoch
        )
        _ = await reducer.consume(makeEvent(sequence: 2, payload: .approvalResolved(accepted)))
        let rejected = AgentApprovalResolution(
            approvalID: "approval",
            choiceID: "no",
            resolvedAt: epoch.addingTimeInterval(1)
        )
        let second = await reducer.consume(
            makeEvent(sequence: 3, payload: .approvalResolved(rejected))
        )
        guard case .approval(let final) = second.snapshot.turns[0].blocks[0].content else {
            return XCTFail("Expected approval")
        }
        XCTAssertEqual(final.resolution, accepted)
    }

    func testHistoryPrependsUniqueTurnsAndDeleteIsIdempotent() async {
        let reducer = makeReducer()
        _ = await reducer.consume(
            makeEvent(sequence: 1, payload: .turnInserted(makeTurn(id: "new"))))
        let page = AgentHistoryPage(
            turns: [makeTurn(id: "old"), makeTurn(id: "new")],
            earlierCursor: "older",
            hasEarlierHistory: true
        )
        let history = await reducer.consume(makeEvent(sequence: 2, payload: .historyPage(page)))
        XCTAssertEqual(history.snapshot.turns.map(\.id), ["old", "new"])
        XCTAssertEqual(
            Array(history.patches.prefix(2)),
            [.prependTurns(["old"]), .historyStateChanged]
        )
        let deleted = await reducer.consume(
            makeEvent(
                sequence: 3,
                payload: .blockRemoved(turnID: "new", blockID: "missing")
            )
        )
        XCTAssertEqual(deleted.snapshot.turns.count, 2)
        XCTAssertTrue(deleted.patches.isEmpty)
    }

    func testEmptyHistoryPageStillPublishesHistoryStateChange() async {
        let reducer = makeReducer()
        let page = AgentHistoryPage(turns: [], hasEarlierHistory: false)

        let result = await reducer.consume(
            makeEvent(sequence: 1, payload: .historyPage(page))
        )

        XCTAssertEqual(result.patches, [.historyStateChanged])
        XCTAssertFalse(result.snapshot.hasEarlierHistory)
        XCTAssertNil(result.snapshot.earlierHistoryCursor)
    }

    func testDuplicateBlockIdentifierAcrossTurnsIsIgnored() async {
        let reducer = makeReducer()
        _ = await reducer.consume(
            makeEvent(sequence: 1, payload: .turnInserted(makeTurn(id: "first")))
        )

        let result = await reducer.consume(
            makeEvent(sequence: 2, payload: .turnInserted(makeTurn(id: "second")))
        )

        XCTAssertEqual(result.snapshot.turns.map { $0.blocks.count }, [1, 0])
        XCTAssertTrue(result.notices.contains { $0.code == "snapshot.duplicate-block-id" })
    }

    func testSnapshotNormalizesDuplicateTurnAndBlockIdentifiers() async {
        let reducer = makeReducer()
        let replacement = AgentConversationSnapshot(
            id: conversationID,
            turns: [
                makeTurn(id: "first"),
                makeTurn(id: "first"),
                makeTurn(id: "second"),
            ]
        )

        let result = await reducer.consume(
            makeEvent(sequence: 1, payload: .snapshot(replacement))
        )

        XCTAssertEqual(result.snapshot.turns.map(\.id), ["first", "second"])
        XCTAssertEqual(result.snapshot.turns.map { $0.blocks.count }, [1, 0])
        XCTAssertTrue(result.notices.contains { $0.code == "snapshot.duplicate-turn-id" })
        XCTAssertTrue(result.notices.contains { $0.code == "snapshot.duplicate-block-id" })
    }

    func testTurnUpdateEmitsStructuralPatchWhenBlockIdentifiersChange() async {
        let reducer = makeReducer()
        _ = await reducer.consume(makeEvent(sequence: 1, payload: .turnInserted(makeTurn())))
        var replacement = makeTurn()
        replacement.blocks.append(
            AgentBlock(
                id: "second-block",
                kind: .markdown,
                content: .markdown(.init(markdown: "done", isFinal: true)),
                state: .succeeded,
                createdAt: epoch
            )
        )

        let result = await reducer.consume(
            makeEvent(sequence: 2, payload: .turnUpdated(replacement))
        )

        XCTAssertEqual(result.snapshot.turns[0].blocks.count, 2)
        XCTAssertTrue(result.patches.contains(.replaceAll))
    }

    func testReductionIsDeterministic() async {
        let first = makeReducer()
        let second = makeReducer()
        let events = [
            makeEvent(sequence: 1, payload: .turnInserted(makeTurn())),
            makeEvent(
                sequence: 2,
                payload: .blockDelta(
                    .init(
                        turnID: "turn",
                        blockID: "block",
                        nextRevision: 1,
                        operation: .appendMarkdown("same")
                    )
                )
            ),
            makeEvent(sequence: 3, payload: .conversationStateChanged(.connected)),
        ]
        var firstResult: AgentReductionResult?
        var secondResult: AgentReductionResult?
        for event in events {
            firstResult = await first.consume(event)
            secondResult = await second.consume(event)
        }
        XCTAssertEqual(firstResult, secondResult)
    }

    private func makeReducer(
        configuration: AgentReducerConfiguration = .init()
    ) -> AgentConversationReducer {
        AgentConversationReducer(
            snapshot: .empty(conversationID: conversationID),
            configuration: configuration
        )
    }

    private func makeTurn(id: AgentTurnID = "turn") -> AgentTurn {
        .init(
            id: id,
            role: .assistant,
            blocks: [
                AgentBlock(
                    id: "block",
                    kind: .markdown,
                    content: .markdown(.init(markdown: "", isFinal: false)),
                    state: .streaming,
                    createdAt: epoch
                )
            ],
            state: .streaming,
            createdAt: epoch
        )
    }

    private func makeEvent(
        sequence: Int64,
        seconds: TimeInterval = 0,
        payload: AgentRuntimeEventPayload
    ) -> AgentRuntimeEvent {
        .init(
            id: .init(rawValue: "event-\(sequence)-\(seconds)"),
            sequence: sequence,
            conversationID: conversationID,
            timestamp: epoch.addingTimeInterval(seconds),
            payload: payload
        )
    }

    private func markdown(in snapshot: AgentConversationSnapshot) -> String? {
        guard case .markdown(let value) = snapshot.turns.first?.blocks.first?.content else {
            return nil
        }
        return value.markdown
    }

    private func isBlockReconfigure(_ patch: AgentPresentationPatch) -> Bool {
        if case .reconfigureBlock = patch { return true }
        return false
    }
}
