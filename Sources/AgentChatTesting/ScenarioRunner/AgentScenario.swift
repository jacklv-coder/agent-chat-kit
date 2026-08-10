import AgentChatCore
import Foundation

/// One delayed event in an offline mock scenario.
public struct AgentScenarioEvent: Hashable, Codable, Sendable {
    /// The event to emit.
    public var event: AgentRuntimeEvent
    /// Delay before emission in nanoseconds.
    public var delayNanoseconds: UInt64
    /// Creates a scenario event.
    public init(event: AgentRuntimeEvent, delayNanoseconds: UInt64 = 0) {
        self.event = event
        self.delayNanoseconds = delayNanoseconds
    }
}

/// An offline, deterministic runtime scenario.
public struct AgentScenario: Hashable, Codable, Sendable {
    /// Ordered scripted events.
    public var events: [AgentScenarioEvent]
    /// Creates a scenario from a result-builder body.
    public init(@AgentScenarioBuilder _ content: () -> [AgentScenarioEvent]) {
        self.events = content()
    }
    /// Creates a scenario from prebuilt events.
    public init(events: [AgentScenarioEvent]) { self.events = events }
}

/// Builds arrays of scripted scenario events.
@resultBuilder
public enum AgentScenarioBuilder {
    /// Builds a block.
    public static func buildBlock(_ components: AgentScenarioEvent...) -> [AgentScenarioEvent] {
        components
    }
    /// Builds an array expression.
    public static func buildArray(_ components: [[AgentScenarioEvent]]) -> [AgentScenarioEvent] {
        components.flatMap { $0 }
    }
    /// Builds an optional expression.
    public static func buildOptional(_ component: [AgentScenarioEvent]?) -> [AgentScenarioEvent] {
        component ?? []
    }
    /// Builds the first conditional branch.
    public static func buildEither(first component: [AgentScenarioEvent]) -> [AgentScenarioEvent] {
        component
    }
    /// Builds the second conditional branch.
    public static func buildEither(second component: [AgentScenarioEvent]) -> [AgentScenarioEvent] {
        component
    }
    /// Converts an expression.
    public static func buildExpression(_ expression: AgentScenarioEvent) -> [AgentScenarioEvent] {
        [expression]
    }
}
