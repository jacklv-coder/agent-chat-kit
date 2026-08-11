import Foundation

/// A portable, versioned scenario fixture shared by demos and automated tests.
public struct AgentScenarioDocument: Hashable, Codable, Sendable {
    /// The current JSON schema version.
    public static let currentSchemaVersion = 1

    /// The encoded fixture schema version.
    public var schemaVersion: Int
    /// A stable identifier used by launch arguments and reports.
    public var id: String
    /// A user-visible scenario title.
    public var title: String
    /// A short explanation of the behavior under test.
    public var summary: String
    /// Searchable categories such as `streaming`, `composer`, or `tool`.
    public var tags: [String]
    /// The deterministic runtime event tape.
    public var scenario: AgentScenario

    /// Creates a portable scenario fixture.
    public init(
        schemaVersion: Int = AgentScenarioDocument.currentSchemaVersion,
        id: String,
        title: String,
        summary: String = "",
        tags: [String] = [],
        scenario: AgentScenario
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.summary = summary
        self.tags = tags
        self.scenario = scenario
    }

    /// Encodes the fixture as stable JSON suitable for source control or clipboard replay.
    public func encodedJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Decodes and validates a fixture document.
    public static func decodeJSON(_ data: Data) throws -> AgentScenarioDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let document = try decoder.decode(Self.self, from: data)
        guard document.schemaVersion == currentSchemaVersion else {
            throw AgentScenarioDocumentError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return document
    }
}

/// Errors produced while loading portable scenario fixtures.
public enum AgentScenarioDocumentError: Error, Hashable, Sendable {
    /// The fixture was written for an unsupported schema.
    case unsupportedSchemaVersion(Int)
}
