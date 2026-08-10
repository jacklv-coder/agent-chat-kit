import Foundation

/// Main-actor state published to presentation layers without importing UIKit.
@MainActor
public final class AgentConversationStore {
    /// The latest conversation snapshot.
    public private(set) var snapshot: AgentConversationSnapshot

    private var patchContinuations: [UUID: AsyncStream<AgentPresentationPatch>.Continuation] = [:]

    /// Creates a store with its initial snapshot.
    public init(snapshot: AgentConversationSnapshot) {
        self.snapshot = snapshot
    }

    /// Creates an independent stream of stable-ID presentation patches.
    public func makePatchStream() -> AsyncStream<AgentPresentationPatch> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(2_048)) { continuation in
            patchContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.patchContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Atomically installs a reduction result and publishes its ordered patches.
    public func apply(_ result: AgentReductionResult) {
        guard result.snapshot.id == snapshot.id else { return }
        snapshot = result.snapshot
        for patch in result.patches {
            for continuation in patchContinuations.values {
                continuation.yield(patch)
            }
        }
    }
}
