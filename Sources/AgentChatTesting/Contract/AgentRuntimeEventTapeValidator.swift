import AgentChatCore
import Foundation

/// One deterministic runtime-contract problem found in a captured event tape.
public struct AgentRuntimeContractIssue: Hashable, Sendable {
    /// Machine-readable issue code.
    public var code: String
    /// Event index containing the problem.
    public var eventIndex: Int
    /// User-readable explanation suitable for a test failure.
    public var message: String

    /// Creates a contract issue.
    public init(code: String, eventIndex: Int, message: String) {
        self.code = code
        self.eventIndex = eventIndex
        self.message = message
    }
}

/// Result of validating a runtime event tape before UI replay.
public struct AgentRuntimeContractReport: Hashable, Sendable {
    /// Number of validated envelopes.
    public var eventCount: Int
    /// Deterministic contract violations.
    public var issues: [AgentRuntimeContractIssue]

    /// Whether the tape satisfies the strict connection contract.
    public var isValid: Bool { issues.isEmpty }

    /// Creates a contract report.
    public init(eventCount: Int, issues: [AgentRuntimeContractIssue]) {
        self.eventCount = eventCount
        self.issues = issues
    }
}

/// Validates the transport-independent invariants expected from one runtime connection.
public enum AgentRuntimeEventTapeValidator {
    /// Validates stable IDs, one conversation, strictly increasing sequences, and block revisions.
    public static func validate(
        _ events: [AgentRuntimeEvent],
        expectedConversationID: AgentConversationID? = nil
    ) -> AgentRuntimeContractReport {
        var issues: [AgentRuntimeContractIssue] = []
        var eventIDs: Set<AgentEventID> = []
        var previousSequence: Int64?
        var conversationID = expectedConversationID ?? events.first?.conversationID
        var blockRevisions: [AgentBlockID: Int64] = [:]

        for (index, event) in events.enumerated() {
            if !eventIDs.insert(event.id).inserted {
                issues.append(
                    .init(
                        code: "event.duplicate-id",
                        eventIndex: index,
                        message:
                            "Event id \(event.id.rawValue) is duplicated in one connection tape."
                    )
                )
            }
            if let previousSequence, event.sequence <= previousSequence {
                issues.append(
                    .init(
                        code: "event.non-monotonic-sequence",
                        eventIndex: index,
                        message:
                            "Sequence \(event.sequence) must be greater than \(previousSequence)."
                    )
                )
            }
            previousSequence = event.sequence
            if let conversationID, event.conversationID != conversationID {
                issues.append(
                    .init(
                        code: "event.wrong-conversation",
                        eventIndex: index,
                        message:
                            "Event belongs to \(event.conversationID.rawValue), expected \(conversationID.rawValue)."
                    )
                )
            } else if conversationID == nil {
                conversationID = event.conversationID
            }

            switch event.payload {
            case .snapshot(let snapshot):
                blockRevisions.removeAll(keepingCapacity: true)
                for block in snapshot.turns.flatMap(\.blocks) {
                    if blockRevisions[block.id] != nil {
                        issues.append(
                            .init(
                                code: "snapshot.duplicate-block-id",
                                eventIndex: index,
                                message:
                                    "Snapshot contains duplicate block id \(block.id.rawValue)."
                            )
                        )
                    } else {
                        blockRevisions[block.id] = block.revision
                    }
                }
            case .turnInserted(let turn):
                for block in turn.blocks {
                    if blockRevisions[block.id] != nil {
                        issues.append(
                            .init(
                                code: "block.duplicate-insert",
                                eventIndex: index,
                                message: "Block \(block.id.rawValue) was inserted more than once."
                            )
                        )
                    }
                    blockRevisions[block.id] = block.revision
                }
            case .turnUpdated(let turn):
                for block in turn.blocks {
                    blockRevisions[block.id] = max(
                        blockRevisions[block.id] ?? block.revision,
                        block.revision
                    )
                }
            case .blockInserted(_, let block), .approvalRequested(_, let block):
                if blockRevisions[block.id] != nil {
                    issues.append(
                        .init(
                            code: "block.duplicate-insert",
                            eventIndex: index,
                            message: "Block \(block.id.rawValue) was inserted more than once."
                        )
                    )
                }
                blockRevisions[block.id] = block.revision
            case .blockReplaced(_, let block):
                validateReplacement(
                    block,
                    at: index,
                    revisions: &blockRevisions,
                    issues: &issues
                )
            case .blockDelta(let delta):
                if delta.nextRevision <= (delta.baseRevision ?? -1) {
                    issues.append(
                        .init(
                            code: "block.invalid-delta-revision",
                            eventIndex: index,
                            message: "Delta next revision must be greater than its base revision."
                        )
                    )
                }
                if let current = blockRevisions[delta.blockID] {
                    if let base = delta.baseRevision, base != current {
                        issues.append(
                            .init(
                                code: "block.delta-base-mismatch",
                                eventIndex: index,
                                message:
                                    "Delta base \(base) does not match current revision \(current)."
                            )
                        )
                    }
                    if delta.nextRevision <= current {
                        issues.append(
                            .init(
                                code: "block.stale-delta",
                                eventIndex: index,
                                message:
                                    "Delta revision \(delta.nextRevision) is not newer than \(current)."
                            )
                        )
                    }
                } else {
                    issues.append(
                        .init(
                            code: "block.delta-before-insert",
                            eventIndex: index,
                            message: "Delta targets unknown block \(delta.blockID.rawValue)."
                        )
                    )
                }
                blockRevisions[delta.blockID] = delta.nextRevision
            case .blockRemoved(_, let blockID):
                blockRevisions[blockID] = nil
            case .turnRemoved, .approvalResolved, .historyPage, .conversationStateChanged,
                .recoverableError, .terminalError:
                break
            }
        }

        return .init(eventCount: events.count, issues: issues)
    }

    private static func validateReplacement(
        _ block: AgentBlock,
        at eventIndex: Int,
        revisions: inout [AgentBlockID: Int64],
        issues: inout [AgentRuntimeContractIssue]
    ) {
        if let current = revisions[block.id], block.revision <= current {
            issues.append(
                .init(
                    code: "block.stale-replacement",
                    eventIndex: eventIndex,
                    message: "Replacement revision \(block.revision) is not newer than \(current)."
                )
            )
        }
        revisions[block.id] = block.revision
    }
}
