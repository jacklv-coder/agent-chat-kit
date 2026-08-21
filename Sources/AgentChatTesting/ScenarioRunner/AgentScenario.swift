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
    /// Earlier-history pages keyed by the cursor that requests each page.
    public var historyPages: [String: AgentHistoryPage]

    /// Creates a scenario from a result-builder body.
    public init(@AgentScenarioBuilder _ content: () -> [AgentScenarioEvent]) {
        self.events = content()
        self.historyPages = [:]
    }

    /// Creates a scenario from prebuilt events.
    public init(
        events: [AgentScenarioEvent],
        historyPages: [String: AgentHistoryPage] = [:]
    ) {
        self.events = events
        self.historyPages = historyPages
    }

    /// Returns the deterministic page configured for an earlier-history request.
    public func historyPage(for cursor: AgentHistoryCursor?) -> AgentHistoryPage? {
        historyPages[cursor?.rawValue ?? ""]
    }

    private enum CodingKeys: String, CodingKey {
        case events
        case historyPages
    }

    /// Decodes older event-only fixtures with an empty history-page map.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decode([AgentScenarioEvent].self, forKey: .events)
        historyPages =
            try container.decodeIfPresent([String: AgentHistoryPage].self, forKey: .historyPages)
            ?? [:]
    }

    /// Encodes the event tape and any deterministic history responses.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        if !historyPages.isEmpty {
            try container.encode(historyPages, forKey: .historyPages)
        }
    }
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
