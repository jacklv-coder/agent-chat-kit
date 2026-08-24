import CoreGraphics
import Foundation

/// Pure decision rules for conversation auto-follow and manual reading protection.
enum AgentScrollPolicy {
    /// Streaming gets a looser threshold so small incremental height changes do not flap state.
    static let streamingThresholdMultiplier: CGFloat = 2
    /// Automatic follow remains paused briefly after the user releases the list.
    static let userInteractionCooldown: TimeInterval = 0.25

    static func bottomThreshold(
        followingThreshold: CGFloat,
        isStreaming: Bool
    ) -> CGFloat {
        let base = max(0, followingThreshold)
        return isStreaming ? base * streamingThresholdMultiplier : base
    }

    static func isNearBottom(
        distanceFromBottom: CGFloat,
        followingThreshold: CGFloat,
        isStreaming: Bool
    ) -> Bool {
        distanceFromBottom
            <= bottomThreshold(
                followingThreshold: followingThreshold,
                isStreaming: isStreaming
            )
    }

    static func cooldownDeadline(after date: Date = Date()) -> Date {
        date.addingTimeInterval(userInteractionCooldown)
    }

    static func isAutomaticFollowPaused(
        isUserInteracting: Bool,
        cooldownUntil: Date?,
        now: Date = Date()
    ) -> Bool {
        if isUserInteracting { return true }
        guard let cooldownUntil else { return false }
        return now < cooldownUntil
    }
}
