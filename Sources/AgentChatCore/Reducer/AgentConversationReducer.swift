import Foundation

/// Deterministically merges runtime events into a conversation snapshot.
public actor AgentConversationReducer {
    private let configuration: AgentReducerConfiguration
    private var snapshot: AgentConversationSnapshot
    private var rememberedEventIDs: BoundedEventIDLRU
    private var expectedSequence: Int64?
    private var bufferedEvents: [Int64: AgentRuntimeEvent] = [:]
    private var gapDetectedAt: Date?

    /// Creates a reducer with an initial UI snapshot.
    public init(
        snapshot: AgentConversationSnapshot,
        configuration: AgentReducerConfiguration = .init()
    ) {
        self.snapshot = Self.normalizedSnapshot(snapshot).snapshot
        self.configuration = configuration
        self.rememberedEventIDs = BoundedEventIDLRU(
            capacity: configuration.rememberedEventIDCapacity
        )
    }

    /// Consumes one event and drains any newly contiguous buffered events.
    public func consume(_ event: AgentRuntimeEvent) -> AgentReductionResult {
        var output = AgentReductionResult(snapshot: snapshot)

        guard event.conversationID == snapshot.id else {
            appendNotice(
                .init(
                    code: "event.wrong-conversation",
                    message: "Ignored an event for a different conversation."
                ),
                to: &output
            )
            output.snapshot = snapshot
            return output
        }

        guard rememberedEventIDs.insert(event.id) else {
            output.snapshot = snapshot
            return output
        }

        if case .snapshot = event.payload {
            apply(event, to: &output)
            expectedSequence = event.sequence + 1
            bufferedEvents = bufferedEvents.filter { $0.key > event.sequence }
            gapDetectedAt = nil
            drainBufferedEvents(to: &output)
            output.snapshot = snapshot
            return output
        }

        if expectedSequence == nil {
            expectedSequence = event.sequence
        }

        guard let expectedSequence else {
            output.snapshot = snapshot
            return output
        }

        if event.sequence < expectedSequence {
            appendNotice(
                .init(code: "event.stale-sequence", message: "Ignored a stale runtime event."),
                to: &output
            )
        } else if event.sequence == expectedSequence {
            apply(event, to: &output)
            self.expectedSequence = expectedSequence + 1
            gapDetectedAt = nil
            drainBufferedEvents(to: &output)
        } else {
            buffer(event, output: &output)
        }

        output.snapshot = snapshot
        return output
    }

    /// Replaces state directly, clearing ordering state that cannot survive a new baseline.
    public func replaceSnapshot(_ replacement: AgentConversationSnapshot) -> AgentReductionResult {
        guard replacement.id == snapshot.id else {
            let notice = AgentRuntimeNotice(
                code: "snapshot.wrong-conversation",
                message: "Ignored a snapshot for a different conversation."
            )
            return .init(snapshot: snapshot, patches: [.notice(notice)], notices: [notice])
        }
        let normalized = Self.normalizedSnapshot(replacement)
        snapshot = normalized.snapshot
        expectedSequence = nil
        bufferedEvents.removeAll(keepingCapacity: true)
        gapDetectedAt = nil
        var output = AgentReductionResult(snapshot: snapshot, patches: [.replaceAll])
        appendStableIDNotices(
            duplicateTurnIDs: normalized.hadDuplicateTurnIDs,
            duplicateBlockIDs: normalized.hadDuplicateBlockIDs,
            to: &output
        )
        return output
    }

    private func buffer(_ event: AgentRuntimeEvent, output: inout AgentReductionResult) {
        if let current = bufferedEvents[event.sequence] {
            let winner = current.id.rawValue <= event.id.rawValue ? current : event
            bufferedEvents[event.sequence] = winner
            appendNotice(
                .init(
                    code: "event.sequence-collision",
                    message: "Multiple runtime events used the same sequence number."
                ),
                to: &output
            )
        } else {
            if bufferedEvents.count == configuration.outOfOrderEventCapacity,
                let largest = bufferedEvents.keys.max()
            {
                if event.sequence < largest {
                    bufferedEvents.removeValue(forKey: largest)
                    bufferedEvents[event.sequence] = event
                }
                output.requiresSnapshot = true
                appendNotice(
                    .init(
                        code: "event.out-of-order-capacity",
                        message: "Runtime events exceeded the ordering buffer; resynchronizing."
                    ),
                    to: &output
                )
            } else {
                bufferedEvents[event.sequence] = event
            }
        }

        if let gapDetectedAt {
            if event.timestamp.timeIntervalSince(gapDetectedAt)
                >= configuration.sequenceGapTimeout
            {
                output.requiresSnapshot = true
            }
        } else {
            gapDetectedAt = event.timestamp
        }
    }

    private func drainBufferedEvents(to output: inout AgentReductionResult) {
        while let sequence = expectedSequence,
            let next = bufferedEvents.removeValue(forKey: sequence)
        {
            apply(next, to: &output)
            expectedSequence = sequence + 1
        }
        gapDetectedAt = bufferedEvents.isEmpty ? nil : gapDetectedAt
    }

    private func apply(_ event: AgentRuntimeEvent, to output: inout AgentReductionResult) {
        switch event.payload {
        case .snapshot(let replacement):
            guard replacement.id == snapshot.id else {
                appendNotice(
                    .init(
                        code: "snapshot.wrong-conversation",
                        message: "Ignored a snapshot for a different conversation."
                    ),
                    to: &output
                )
                return
            }
            let normalized = Self.normalizedSnapshot(replacement)
            snapshot = normalized.snapshot
            output.patches.append(.replaceAll)
            appendStableIDNotices(
                duplicateTurnIDs: normalized.hadDuplicateTurnIDs,
                duplicateBlockIDs: normalized.hadDuplicateBlockIDs,
                to: &output
            )

        case .conversationStateChanged(let state):
            snapshot.state = state
            output.patches.append(.conversationStateChanged)

        case .turnInserted(let turn):
            guard snapshot.turns.contains(where: { $0.id == turn.id }) == false else {
                appendStableIDNotices(
                    duplicateTurnIDs: true,
                    duplicateBlockIDs: false,
                    to: &output
                )
                return
            }
            var reservedBlockIDs = Set(snapshot.turns.flatMap { $0.blocks.map(\.id) })
            let normalized = Self.normalizedTurn(turn, reserving: &reservedBlockIDs)
            snapshot.turns.append(normalized.turn)
            output.patches.append(.insertTurn(turn.id, index: snapshot.turns.count - 1))
            appendStableIDNotices(
                duplicateTurnIDs: false,
                duplicateBlockIDs: normalized.hadDuplicateBlockIDs,
                to: &output
            )
            validate(blocks: normalized.turn.blocks, output: &output)

        case .turnUpdated(let turn):
            guard let index = snapshot.turns.firstIndex(where: { $0.id == turn.id }) else {
                var reservedBlockIDs = Set(snapshot.turns.flatMap { $0.blocks.map(\.id) })
                let normalized = Self.normalizedTurn(turn, reserving: &reservedBlockIDs)
                snapshot.turns.append(normalized.turn)
                output.patches.append(.insertTurn(turn.id, index: snapshot.turns.count - 1))
                appendStableIDNotices(
                    duplicateTurnIDs: false,
                    duplicateBlockIDs: normalized.hadDuplicateBlockIDs,
                    to: &output
                )
                validate(blocks: normalized.turn.blocks, output: &output)
                return
            }
            var reservedBlockIDs = Set(
                snapshot.turns.enumerated().filter { $0.offset != index }.flatMap {
                    $0.element.blocks.map(\.id)
                }
            )
            let normalized = Self.normalizedTurn(turn, reserving: &reservedBlockIDs)
            let previous = snapshot.turns[index]
            snapshot.turns[index] = normalized.turn
            let previousBlockIDs = previous.blocks.map(\.id)
            let updatedBlockIDs = normalized.turn.blocks.map(\.id)
            if previousBlockIDs == updatedBlockIDs {
                output.patches.append(.reconfigureTurn(turn.id))
                let previousBlocks = Dictionary(
                    uniqueKeysWithValues: previous.blocks.map { ($0.id, $0) })
                for block in normalized.turn.blocks where previousBlocks[block.id] != block {
                    output.patches.append(.reconfigureBlock(block.id))
                }
            } else {
                output.patches.append(.replaceAll)
            }
            appendStableIDNotices(
                duplicateTurnIDs: false,
                duplicateBlockIDs: normalized.hadDuplicateBlockIDs,
                to: &output
            )
            validate(blocks: normalized.turn.blocks, output: &output)

        case .turnRemoved(let turnID):
            guard let index = snapshot.turns.firstIndex(where: { $0.id == turnID }) else { return }
            snapshot.turns.remove(at: index)
            output.patches.append(.deleteTurn(turnID))

        case .blockInserted(let turnID, let block),
            .approvalRequested(let turnID, let block):
            insert(block, into: turnID, output: &output)

        case .blockReplaced(let turnID, let block):
            replace(block, in: turnID, output: &output)

        case .blockDelta(let delta):
            apply(delta, at: event.timestamp, output: &output)

        case .blockRemoved(let turnID, let blockID):
            guard let turnIndex = snapshot.turns.firstIndex(where: { $0.id == turnID }),
                let blockIndex = snapshot.turns[turnIndex].blocks.firstIndex(where: {
                    $0.id == blockID
                })
            else { return }
            snapshot.turns[turnIndex].blocks.remove(at: blockIndex)
            output.patches.append(.deleteBlock(turnID: turnID, blockID: blockID))

        case .approvalResolved(let resolution):
            resolveApproval(resolution, output: &output)

        case .historyPage(let page):
            var seenTurnIDs = Set(snapshot.turns.map(\.id))
            var reservedBlockIDs = Set(snapshot.turns.flatMap { $0.blocks.map(\.id) })
            var prepended: [AgentTurn] = []
            var hadDuplicateTurnIDs = false
            var hadDuplicateBlockIDs = false
            for turn in page.turns {
                guard seenTurnIDs.insert(turn.id).inserted else {
                    hadDuplicateTurnIDs = true
                    continue
                }
                let normalized = Self.normalizedTurn(turn, reserving: &reservedBlockIDs)
                hadDuplicateBlockIDs = hadDuplicateBlockIDs || normalized.hadDuplicateBlockIDs
                prepended.append(normalized.turn)
            }
            snapshot.turns.insert(contentsOf: prepended, at: 0)
            snapshot.earlierHistoryCursor = page.earlierCursor
            snapshot.hasEarlierHistory = page.hasEarlierHistory
            if !prepended.isEmpty {
                output.patches.append(.prependTurns(prepended.map(\.id)))
                validate(blocks: prepended.flatMap(\.blocks), output: &output)
            }
            appendStableIDNotices(
                duplicateTurnIDs: hadDuplicateTurnIDs,
                duplicateBlockIDs: hadDuplicateBlockIDs,
                to: &output
            )

        case .recoverableError(let notice):
            appendNotice(notice, to: &output)

        case .terminalError(let failure):
            snapshot.state = .failed(failure)
            output.patches.append(.conversationStateChanged)
        }
    }

    private func insert(
        _ block: AgentBlock,
        into turnID: AgentTurnID,
        output: inout AgentReductionResult
    ) {
        guard let turnIndex = snapshot.turns.firstIndex(where: { $0.id == turnID }) else {
            appendNotice(
                .init(code: "block.missing-turn", message: "Ignored a block for an unknown turn."),
                to: &output
            )
            return
        }
        if snapshot.turns.enumerated().contains(where: { index, turn in
            index != turnIndex && turn.blocks.contains(where: { $0.id == block.id })
        }) {
            appendStableIDNotices(
                duplicateTurnIDs: false,
                duplicateBlockIDs: true,
                to: &output
            )
            return
        }
        if let blockIndex = snapshot.turns[turnIndex].blocks.firstIndex(where: { $0.id == block.id }
        ) {
            if block.revision > snapshot.turns[turnIndex].blocks[blockIndex].revision {
                snapshot.turns[turnIndex].blocks[blockIndex] = block
                output.patches.append(.reconfigureBlock(block.id))
            }
        } else {
            snapshot.turns[turnIndex].blocks.append(block)
            output.patches.append(
                .insertBlock(
                    turnID: turnID,
                    blockID: block.id,
                    index: snapshot.turns[turnIndex].blocks.count - 1
                )
            )
        }
        validate(blocks: [block], output: &output)
    }

    private func replace(
        _ block: AgentBlock,
        in turnID: AgentTurnID,
        output: inout AgentReductionResult
    ) {
        guard let turnIndex = snapshot.turns.firstIndex(where: { $0.id == turnID }) else {
            appendNotice(
                .init(code: "block.missing-turn", message: "Ignored a block for an unknown turn."),
                to: &output
            )
            return
        }
        guard
            let blockIndex = snapshot.turns[turnIndex].blocks.firstIndex(where: {
                $0.id == block.id
            })
        else {
            insert(block, into: turnID, output: &output)
            return
        }
        guard block.revision > snapshot.turns[turnIndex].blocks[blockIndex].revision else { return }
        snapshot.turns[turnIndex].blocks[blockIndex] = block
        output.patches.append(.reconfigureBlock(block.id))
        validate(blocks: [block], output: &output)
    }

    private func apply(
        _ delta: AgentBlockDelta,
        at timestamp: Date,
        output: inout AgentReductionResult
    ) {
        guard let turnIndex = snapshot.turns.firstIndex(where: { $0.id == delta.turnID }),
            let blockIndex = snapshot.turns[turnIndex].blocks.firstIndex(where: {
                $0.id == delta.blockID
            })
        else {
            appendNotice(
                .init(
                    code: "delta.missing-block", message: "Ignored an update for an unknown block."),
                to: &output
            )
            return
        }

        var block = snapshot.turns[turnIndex].blocks[blockIndex]
        guard delta.nextRevision > block.revision else { return }
        if let baseRevision = delta.baseRevision, baseRevision != block.revision {
            appendNotice(
                .init(
                    code: "delta.revision-conflict",
                    message: "Ignored an update based on a stale block revision."
                ),
                to: &output
            )
            return
        }

        switch delta.operation {
        case .appendMarkdown(let text):
            guard case .markdown(var markdown) = block.content else {
                appendDeltaTypeNotice(to: &output)
                return
            }
            markdown.markdown.append(text)
            block.content = .markdown(markdown)

        case .appendCommandOutput(let text):
            guard case .command(var command) = block.content else {
                appendDeltaTypeNotice(to: &output)
                return
            }
            command.output.append(text)
            block.content = .command(command)

        case .replaceContent(let content):
            let candidate = AgentBlock(
                id: block.id,
                kind: block.kind,
                content: content,
                state: block.state,
                revision: delta.nextRevision,
                createdAt: block.createdAt,
                updatedAt: timestamp,
                metadata: block.metadata
            )
            guard candidate.hasCompatibleKindAndContent else {
                appendDeltaTypeNotice(to: &output)
                return
            }
            block.content = content

        case .setState(let state):
            block.state = state

        case .setProgress(let progress):
            block.state = .running(progress: progress.map { min(1, max(0, $0)) })

        case .mergeMetadata(let metadata):
            block.metadata.merge(metadata) { _, new in new }
        }

        block.revision = delta.nextRevision
        block.updatedAt = timestamp
        snapshot.turns[turnIndex].blocks[blockIndex] = block
        output.patches.append(.reconfigureBlock(block.id))
    }

    private func resolveApproval(
        _ resolution: AgentApprovalResolution,
        output: inout AgentReductionResult
    ) {
        for turnIndex in snapshot.turns.indices {
            for blockIndex in snapshot.turns[turnIndex].blocks.indices {
                var block = snapshot.turns[turnIndex].blocks[blockIndex]
                guard case .approval(var approval) = block.content,
                    approval.approvalID == resolution.approvalID
                else { continue }
                guard approval.resolution == nil else { return }
                guard approval.choices.contains(where: { $0.id == resolution.choiceID }) else {
                    appendNotice(
                        .init(
                            code: "approval.unknown-choice",
                            message: "Ignored an unknown approval choice."
                        ),
                        to: &output
                    )
                    return
                }
                approval.resolution = resolution
                block.content = .approval(approval)
                block.state = .succeeded
                block.revision += 1
                block.updatedAt = resolution.resolvedAt
                snapshot.turns[turnIndex].blocks[blockIndex] = block
                output.patches.append(.reconfigureBlock(block.id))
                return
            }
        }
        appendNotice(
            .init(
                code: "approval.missing",
                message: "Ignored a resolution for an unknown approval request."
            ),
            to: &output
        )
    }

    private func validate(blocks: [AgentBlock], output: inout AgentReductionResult) {
        for block in blocks where !block.hasCompatibleKindAndContent {
            appendNotice(
                .init(
                    code: "block.kind-content-mismatch",
                    message: "A block had mismatched content and will use a safe fallback renderer."
                ),
                to: &output
            )
        }
    }

    private static func normalizedSnapshot(
        _ candidate: AgentConversationSnapshot
    ) -> (
        snapshot: AgentConversationSnapshot,
        hadDuplicateTurnIDs: Bool,
        hadDuplicateBlockIDs: Bool
    ) {
        var result = candidate
        var seenTurnIDs: Set<AgentTurnID> = []
        var seenBlockIDs: Set<AgentBlockID> = []
        var turns: [AgentTurn] = []
        var hadDuplicateTurnIDs = false
        var hadDuplicateBlockIDs = false

        for turn in candidate.turns {
            guard seenTurnIDs.insert(turn.id).inserted else {
                hadDuplicateTurnIDs = true
                continue
            }
            let normalized = normalizedTurn(turn, reserving: &seenBlockIDs)
            hadDuplicateBlockIDs = hadDuplicateBlockIDs || normalized.hadDuplicateBlockIDs
            turns.append(normalized.turn)
        }
        result.turns = turns
        return (result, hadDuplicateTurnIDs, hadDuplicateBlockIDs)
    }

    private static func normalizedTurn(
        _ candidate: AgentTurn,
        reserving blockIDs: inout Set<AgentBlockID>
    ) -> (turn: AgentTurn, hadDuplicateBlockIDs: Bool) {
        var result = candidate
        var hadDuplicateBlockIDs = false
        result.blocks = candidate.blocks.filter { block in
            let inserted = blockIDs.insert(block.id).inserted
            hadDuplicateBlockIDs = hadDuplicateBlockIDs || !inserted
            return inserted
        }
        return (result, hadDuplicateBlockIDs)
    }

    private func appendStableIDNotices(
        duplicateTurnIDs: Bool,
        duplicateBlockIDs: Bool,
        to output: inout AgentReductionResult
    ) {
        if duplicateTurnIDs {
            appendNotice(
                .init(
                    code: "snapshot.duplicate-turn-id",
                    message: "Ignored conversation content with a duplicate turn identifier."
                ),
                to: &output
            )
        }
        if duplicateBlockIDs {
            appendNotice(
                .init(
                    code: "snapshot.duplicate-block-id",
                    message: "Ignored conversation content with a duplicate block identifier."
                ),
                to: &output
            )
        }
    }

    private func appendDeltaTypeNotice(to output: inout AgentReductionResult) {
        appendNotice(
            .init(
                code: "delta.type-mismatch",
                message: "Ignored an update that did not match the target block type."
            ),
            to: &output
        )
    }

    private func appendNotice(
        _ notice: AgentRuntimeNotice,
        to output: inout AgentReductionResult
    ) {
        output.notices.append(notice)
        output.patches.append(.notice(notice))
    }
}

private struct BoundedEventIDLRU: Sendable {
    private let capacity: Int
    private var ordered: [AgentEventID] = []
    private var members: Set<AgentEventID> = []

    init(capacity: Int) {
        self.capacity = capacity
        ordered.reserveCapacity(capacity)
    }

    mutating func insert(_ id: AgentEventID) -> Bool {
        if members.contains(id) {
            if let index = ordered.firstIndex(of: id) {
                ordered.remove(at: index)
                ordered.append(id)
            }
            return false
        }
        members.insert(id)
        ordered.append(id)
        if ordered.count > capacity {
            members.remove(ordered.removeFirst())
        }
        return true
    }
}
