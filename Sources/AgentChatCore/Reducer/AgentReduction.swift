import Foundation

/// Bounds and recovery policy for deterministic event reduction.
public struct AgentReducerConfiguration: Hashable, Codable, Sendable {
    /// The event-ID LRU capacity, always at least 4,096.
    public var rememberedEventIDCapacity: Int
    /// The out-of-order capacity, clamped to 1...512.
    public var outOfOrderEventCapacity: Int
    /// Runtime timestamp duration before a sequence gap requests a snapshot.
    public var sequenceGapTimeout: TimeInterval

    /// Creates reducer policy.
    public init(
        rememberedEventIDCapacity: Int = 4_096,
        outOfOrderEventCapacity: Int = 512,
        sequenceGapTimeout: TimeInterval = 2
    ) {
        self.rememberedEventIDCapacity = max(4_096, rememberedEventIDCapacity)
        self.outOfOrderEventCapacity = min(512, max(1, outOfOrderEventCapacity))
        self.sequenceGapTimeout = max(0, sequenceGapTimeout)
    }
}

/// A stable-ID presentation mutation independent of UIKit.
public enum AgentPresentationPatch: Hashable, Codable, Sendable {
    /// Reconciles the entire presentation after an authoritative snapshot.
    case replaceAll
    /// Inserts a turn section at an index.
    case insertTurn(AgentTurnID, index: Int)
    /// Reconfigures a turn's supplementary presentation.
    case reconfigureTurn(AgentTurnID)
    /// Deletes a turn section.
    case deleteTurn(AgentTurnID)
    /// Inserts a block item at an index in its turn.
    case insertBlock(turnID: AgentTurnID, blockID: AgentBlockID, index: Int)
    /// Reconfigures only a target block item.
    case reconfigureBlock(AgentBlockID)
    /// Deletes a target block item.
    case deleteBlock(turnID: AgentTurnID, blockID: AgentBlockID)
    /// Prepends earlier turn sections while preserving a stable-ID scroll anchor.
    case prependTurns([AgentTurnID])
    /// Updates connection-level UI.
    case conversationStateChanged
    /// Publishes a recoverable, user-safe notice.
    case notice(AgentRuntimeNotice)
}

/// The complete deterministic output of reducing one event and any newly contiguous buffered events.
public struct AgentReductionResult: Hashable, Codable, Sendable {
    /// The resulting authoritative UI snapshot.
    public var snapshot: AgentConversationSnapshot
    /// Ordered stable-ID presentation changes.
    public var patches: [AgentPresentationPatch]
    /// Recoverable notices produced while validating input.
    public var notices: [AgentRuntimeNotice]
    /// Whether the session should request an authoritative snapshot.
    public var requiresSnapshot: Bool

    /// Creates a reduction result.
    public init(
        snapshot: AgentConversationSnapshot,
        patches: [AgentPresentationPatch] = [],
        notices: [AgentRuntimeNotice] = [],
        requiresSnapshot: Bool = false
    ) {
        self.snapshot = snapshot
        self.patches = patches
        self.notices = notices
        self.requiresSnapshot = requiresSnapshot
    }
}
