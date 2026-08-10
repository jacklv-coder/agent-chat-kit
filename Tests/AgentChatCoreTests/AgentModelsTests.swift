import XCTest

@testable import AgentChatCore

final class AgentModelsTests: XCTestCase {
    func testStrongIdentifiersAndJSONRoundTrip() throws {
        let id: AgentConversationID = "conversation"
        XCTAssertEqual(id.rawValue, "conversation")

        let value: JSONValue = .object([
            "null": .null,
            "bool": .bool(true),
            "number": .number(42.5),
            "string": .string("你好 👋"),
            "array": .array([.number(1), .string("two")]),
        ])
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["bool"] as? Bool, true)
    }

    func testSnapshotCodableRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 123)
        let block = AgentBlock(
            id: "block",
            kind: .markdown,
            content: .markdown(.init(markdown: "**Hello**", isFinal: true)),
            state: .succeeded,
            revision: 2,
            createdAt: date
        )
        let snapshot = AgentConversationSnapshot(
            id: "conversation",
            title: "Demo",
            turns: [
                .init(
                    id: "turn",
                    role: .assistant,
                    blocks: [block],
                    state: .completed,
                    createdAt: date,
                    completedAt: date
                )
            ],
            state: .connected,
            earlierHistoryCursor: "cursor",
            hasEarlierHistory: true,
            metadata: ["count": .number(1)]
        )

        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(
            try JSONDecoder().decode(AgentConversationSnapshot.self, from: data), snapshot)
    }

    func testTextBufferIsChunkedSanitizedAndBounded() {
        var buffer = AgentTextBuffer(maximumUTF8Count: 12, maximumLineCount: 2)
        buffer.append("hello\u{001B}]0;injected\u{0007}\n")
        buffer.append("\u{001B}[31mworld\u{001B}[0m\nthird")
        XCTAssertEqual(buffer.chunks.count, 2)
        XCTAssertEqual(buffer.text, "hello\nworld\n")
        XCTAssertTrue(buffer.wasTruncated)
        XCTAssertFalse(buffer.text.contains("injected"))
        XCTAssertFalse(buffer.text.contains("\u{001B}"))
    }

    func testKindContentCompatibility() {
        let date = Date(timeIntervalSince1970: 0)
        let valid = AgentBlock(
            id: "valid",
            kind: .markdown,
            content: .markdown(.init(markdown: "ok", isFinal: true)),
            createdAt: date
        )
        let invalid = AgentBlock(
            id: "invalid",
            kind: .command,
            content: .markdown(.init(markdown: "safe fallback", isFinal: true)),
            createdAt: date
        )
        let custom = AgentBlock(
            id: "custom",
            kind: "company.tool",
            content: .custom(
                .init(kind: "company.tool", payload: .null, fallbackTitle: "Company tool")
            ),
            createdAt: date
        )
        XCTAssertTrue(valid.hasCompatibleKindAndContent)
        XCTAssertFalse(invalid.hasCompatibleKindAndContent)
        XCTAssertTrue(custom.hasCompatibleKindAndContent)
        let unknownWithBuiltInContent = AgentBlock(
            id: "unknown-mismatch",
            kind: "company.tool",
            content: .markdown(.init(markdown: "mismatch", isFinal: true)),
            createdAt: date
        )
        XCTAssertFalse(unknownWithBuiltInContent.hasCompatibleKindAndContent)
    }
}
