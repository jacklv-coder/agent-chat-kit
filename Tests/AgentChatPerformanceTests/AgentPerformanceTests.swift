import AgentChatCore
import AgentChatMarkdown
import XCTest

final class AgentPerformanceTests: XCTestCase {
    func testConstructsLongConversationFixture() {
        measure {
            let date = Date(timeIntervalSince1970: 0)
            let turns = (0..<2_000).map { turnIndex in
                AgentTurn(
                    id: .init(rawValue: "turn-\(turnIndex)"),
                    role: .assistant,
                    blocks: (0..<3).map { blockIndex in
                        AgentBlock(
                            id: .init(rawValue: "block-\(turnIndex)-\(blockIndex)"),
                            kind: .markdown,
                            content: .markdown(
                                .init(markdown: "Content \(turnIndex)", isFinal: true)),
                            state: .succeeded,
                            createdAt: date
                        )
                    },
                    state: .completed,
                    createdAt: date
                )
            }
            XCTAssertEqual(turns.flatMap(\.blocks).count, 6_000)
        }
    }

    func testLargeDiffUsesBoundedInlineResult() async {
        let lines = (0..<5_000).map { "+line \($0)" }.joined(separator: "\n")
        let diff = "--- a/file\n+++ b/file\n@@ -1,0 +1,5000 @@\n\(lines)"
        let result = await AgentUnifiedDiffParser().parse(diff)
        XCTAssertTrue(result.wasTruncated)
        XCTAssertLessThanOrEqual(result.files.first?.additions ?? 0, 1_000)
    }
}
