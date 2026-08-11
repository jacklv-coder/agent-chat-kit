import Foundation

/// A deterministic playback controller for scripted runtime scenarios.
///
/// A single controller can be shared by the Demo's controls and a `MockAgentRuntime`.
/// A rate of zero emits events immediately; a paused controller only emits when stepped.
public actor AgentScenarioPlaybackController {
    /// A read-only playback status value for debug UIs and test assertions.
    public struct State: Hashable, Sendable {
        /// Whether automatic playback is paused.
        public var isPaused: Bool
        /// Playback speed. Zero means instant playback.
        public var rate: Double
        /// Events released by this controller.
        public var emittedEventCount: Int
        /// Explicit single-step permits waiting to be consumed.
        public var pendingStepCount: Int

        /// Creates a playback state value.
        public init(
            isPaused: Bool,
            rate: Double,
            emittedEventCount: Int,
            pendingStepCount: Int
        ) {
            self.isPaused = isPaused
            self.rate = rate
            self.emittedEventCount = emittedEventCount
            self.pendingStepCount = pendingStepCount
        }
    }

    private var isPaused: Bool
    private var rate: Double
    private var emittedEventCount = 0
    private var pendingStepCount = 0

    /// Creates a playback controller.
    public init(isPaused: Bool = false, rate: Double = 1) {
        self.isPaused = isPaused
        self.rate = Self.normalized(rate)
    }

    /// Pauses automatic event emission.
    public func pause() { isPaused = true }

    /// Resumes automatic event emission and clears unused step permits.
    public func resume() {
        isPaused = false
        pendingStepCount = 0
    }

    /// Releases one event while paused.
    public func step() {
        isPaused = true
        pendingStepCount += 1
    }

    /// Changes the delay multiplier. Zero switches to instant playback.
    public func setRate(_ rate: Double) { self.rate = Self.normalized(rate) }

    /// Returns the latest playback state.
    public func state() -> State {
        .init(
            isPaused: isPaused,
            rate: rate,
            emittedEventCount: emittedEventCount,
            pendingStepCount: pendingStepCount
        )
    }

    /// Resets counters and applies a new initial mode before a new connection is created.
    public func reset(isPaused: Bool = false, rate: Double = 1) {
        self.isPaused = isPaused
        self.rate = Self.normalized(rate)
        emittedEventCount = 0
        pendingStepCount = 0
    }

    func waitBeforeEmission(delayNanoseconds: UInt64) async throws {
        var isSingleStep = false
        while isPaused {
            if pendingStepCount > 0 {
                pendingStepCount -= 1
                isSingleStep = true
                break
            }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        if !isSingleStep, rate > 0, delayNanoseconds > 0 {
            let scaled = min(
                Double(Int64.max),
                Double(delayNanoseconds) / rate
            )
            try await Task.sleep(nanoseconds: UInt64(scaled))
        }
        try Task.checkCancellation()
        emittedEventCount += 1
    }

    private static func normalized(_ rate: Double) -> Double {
        guard rate.isFinite else { return 1 }
        return min(20, max(0, rate))
    }
}
