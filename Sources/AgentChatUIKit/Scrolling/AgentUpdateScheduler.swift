import AgentChatCore
import UIKit

enum AgentCollectionUpdateKind: Hashable {
    case structural
    case sizeAffecting
    case contentOnly
}

enum AgentImmediateFlushReason: Hashable {
    case criticalState
    case foregroundReconciliation
    case explicitHostRequest
}

struct AgentScheduledUpdate {
    var requiresStructuralReconciliation = false
    var sizeAffectingBlockIDs: Set<AgentBlockID> = []
    var contentOnlyBlockIDs: Set<AgentBlockID> = []
    var includesCriticalState = false
    var patches: [AgentPresentationPatch] = []
}

@MainActor
final class AgentUpdateScheduler {
    private let coalescingNanoseconds: UInt64
    private let classify: (AgentPresentationPatch) -> AgentCollectionUpdateKind
    private let flush: (AgentScheduledUpdate) -> Void
    private var pending = AgentScheduledUpdate()
    private var scheduledTask: Task<Void, Never>?
    private var isActive = true
    private var isCancelled = false

    init(
        coalescingMilliseconds: Int = 50,
        classify: @escaping (AgentPresentationPatch) -> AgentCollectionUpdateKind,
        flush: @escaping (AgentScheduledUpdate) -> Void
    ) {
        let milliseconds = min(80, max(33, coalescingMilliseconds))
        self.coalescingNanoseconds = UInt64(milliseconds) * 1_000_000
        self.classify = classify
        self.flush = flush
    }

    func enqueue(_ patch: AgentPresentationPatch) {
        guard !isCancelled else { return }
        pending.patches.append(patch)
        switch classify(patch) {
        case .structural:
            pending.requiresStructuralReconciliation = true
        case .sizeAffecting:
            if case .reconfigureBlock(let blockID) = patch {
                pending.sizeAffectingBlockIDs.insert(blockID)
            }
        case .contentOnly:
            if case .reconfigureBlock(let blockID) = patch {
                pending.contentOnlyBlockIDs.insert(blockID)
            }
        }

        if isCritical(patch) {
            pending.includesCriticalState = true
            flushImmediately(reason: .criticalState)
        } else {
            scheduleIfNeeded()
        }
    }

    func flushImmediately(reason: AgentImmediateFlushReason) {
        guard isActive, !isCancelled, !pending.patches.isEmpty else { return }
        scheduledTask?.cancel()
        scheduledTask = nil
        let update = pending
        pending = AgentScheduledUpdate()
        flush(update)
    }

    func setActive(_ active: Bool) {
        guard !isCancelled else { return }
        isActive = active
        if active {
            flushImmediately(reason: .foregroundReconciliation)
        } else {
            scheduledTask?.cancel()
            scheduledTask = nil
        }
    }

    func cancelPendingUpdates() {
        isCancelled = true
        scheduledTask?.cancel()
        scheduledTask = nil
        pending = AgentScheduledUpdate()
    }

    private func scheduleIfNeeded() {
        guard isActive, scheduledTask == nil else { return }
        scheduledTask = Task { [weak self, coalescingNanoseconds] in
            try? await Task.sleep(nanoseconds: coalescingNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.scheduledTask = nil
            self.flushImmediately(reason: .explicitHostRequest)
        }
    }

    private func isCritical(_ patch: AgentPresentationPatch) -> Bool {
        switch patch {
        case .conversationStateChanged, .notice, .reconfigureTurn: true
        default: false
        }
    }
}
