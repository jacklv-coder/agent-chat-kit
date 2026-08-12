import AgentChatCore
import UIKit

struct AgentScheduledUpdate {
    var requiresStructuralReconciliation = false
    var reconfiguredBlockIDs: Set<AgentBlockID> = []
    var patches: [AgentPresentationPatch] = []
}

@MainActor
final class AgentUpdateScheduler {
    private let coalescingNanoseconds: UInt64
    private let flush: (AgentScheduledUpdate) -> Void
    private var pending = AgentScheduledUpdate()
    private var scheduledTask: Task<Void, Never>?
    private var isActive = true
    private var isCancelled = false

    init(
        coalescingMilliseconds: Int = 50,
        flush: @escaping (AgentScheduledUpdate) -> Void
    ) {
        let milliseconds = min(80, max(33, coalescingMilliseconds))
        self.coalescingNanoseconds = UInt64(milliseconds) * 1_000_000
        self.flush = flush
    }

    func enqueue(_ patch: AgentPresentationPatch) {
        guard !isCancelled else { return }
        pending.patches.append(patch)
        switch patch {
        case .replaceAll, .insertTurn, .deleteTurn, .insertBlock, .deleteBlock, .prependTurns:
            pending.requiresStructuralReconciliation = true
        case .reconfigureBlock(let blockID):
            pending.reconfiguredBlockIDs.insert(blockID)
        case .reconfigureTurn, .historyStateChanged, .conversationStateChanged, .notice:
            break
        }

        if isCritical(patch) {
            flushImmediately()
        } else {
            scheduleIfNeeded()
        }
    }

    func flushImmediately() {
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
            flushImmediately()
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
            self.flushImmediately()
        }
    }

    private func isCritical(_ patch: AgentPresentationPatch) -> Bool {
        switch patch {
        case .conversationStateChanged, .historyStateChanged, .notice, .reconfigureTurn: true
        default: false
        }
    }
}
