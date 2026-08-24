import AgentChatCore
import AgentChatMarkdown
import XCTest

@testable import AgentChatUIKit

final class AgentPerformanceTests: XCTestCase {
    func testConstructsLongConversationFixture() {
        measure {
            let date = Date(timeIntervalSince1970: 0)
            let turns = (0..<2_000).map { turnIndex in
                AgentTurn(
                    id: .init(rawValue: "turn-\(turnIndex)"),
                    role: .assistant,
                    blocks: (0..<3).map { blockIndex in
                        let kind: AgentBlockKind
                        let content: AgentBlockContent
                        switch blockIndex {
                        case 0:
                            kind = .markdown
                            content = .markdown(
                                .init(markdown: "# Turn \(turnIndex)\n\nContent", isFinal: true)
                            )
                        case 1:
                            kind = .tool
                            content = .tool(
                                .init(
                                    toolName: "fixture.tool",
                                    title: "Tool \(turnIndex)",
                                    summary: "Completed"
                                )
                            )
                        default:
                            kind = .command
                            content = .command(
                                .init(command: "printf \(turnIndex)", output: .init())
                            )
                        }
                        return AgentBlock(
                            id: .init(rawValue: "block-\(turnIndex)-\(blockIndex)"),
                            kind: kind,
                            content: content,
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

    @MainActor
    func testSustainedStreamingScenarioCoalescesTenMinutesOfTargetedDeltas() {
        let deltaCount = 10 * 60 * 30
        var flushCount = 0
        var receivedPatchCount = 0
        let scheduler = AgentUpdateScheduler(coalescingMilliseconds: 50) { update in
            flushCount += 1
            receivedPatchCount += update.patches.count
            XCTAssertEqual(update.reconfiguredBlockIDs, ["streaming-block"])
        }

        for _ in 0..<deltaCount {
            scheduler.enqueue(.reconfigureBlock("streaming-block"))
        }
        scheduler.flushImmediately()

        XCTAssertEqual(flushCount, 1)
        XCTAssertEqual(receivedPatchCount, deltaCount)
    }

    func testOneMegabyteCommandOutputRemainsBounded() {
        let rawOutput = String(repeating: "0123456789abcdef\n", count: 65_536)
        XCTAssertGreaterThan(rawOutput.utf8.count, 1_000_000)
        var buffer = AgentTextBuffer()

        buffer.append(rawOutput)

        XCTAssertTrue(buffer.wasTruncated)
        XCTAssertLessThanOrEqual(buffer.utf8Count, 200_000)
        XCTAssertLessThanOrEqual(buffer.lineCount, 2_000)
    }

    func testLargeDiffUsesBoundedInlineResult() async {
        let lines = (0..<5_000).map { "+line \($0)" }.joined(separator: "\n")
        let diff = "--- a/file\n+++ b/file\n@@ -1,0 +1,5000 @@\n\(lines)"
        let result = await AgentUnifiedDiffParser().parse(diff)
        XCTAssertTrue(result.wasTruncated)
        XCTAssertLessThanOrEqual(result.files.first?.additions ?? 0, 1_000)
    }
}
