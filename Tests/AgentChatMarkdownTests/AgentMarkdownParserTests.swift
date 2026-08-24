import AgentChatCore
import XCTest

@testable import AgentChatMarkdown

final class AgentMarkdownParserTests: XCTestCase {
    func testParsesGFMAndPortableRenderDocument() async {
        let source = """
            # Heading **strong**

            - [x] done
            - [ ] todo

            > quote

            | Name | Value |
            | --- | ---: |
            | 中文 | `42` |

            ```swift
            let value = 42
            ```
            """
        let document = await AgentMarkdownParser().parse(source)
        XCTAssertTrue(document.blocks.contains { if case .heading = $0 { true } else { false } })
        XCTAssertTrue(
            document.blocks.contains { if case .unorderedList = $0 { true } else { false } })
        XCTAssertTrue(document.blocks.contains { if case .blockQuote = $0 { true } else { false } })
        XCTAssertTrue(document.blocks.contains { if case .table = $0 { true } else { false } })
        XCTAssertTrue(document.blocks.contains { if case .codeBlock = $0 { true } else { false } })
    }

    func testIncompleteMarkdownAndHTMLHaveSafeFallbacks() async {
        let parser = AgentMarkdownParser()
        let incomplete = await parser.parse("```swift\nlet value = **未完成 👋")
        XCTAssertFalse(incomplete.blocks.isEmpty)
        let html = await parser.parse("<script>alert('no')</script>")
        XCTAssertTrue(
            html.blocks.contains { block in
                if case .unsupported(let raw) = block { return raw.contains("script") }
                return false
            })
    }

    func testImageLinkAndRTLContent() async {
        let document = await AgentMarkdownParser().parse(
            "![alt](https://example.com/image.png) [رابط](https://example.com) 😀"
        )
        XCTAssertFalse(document.blocks.isEmpty)
    }

    func testDocumentCacheIsBoundedAndInvalidatesByBlock() async {
        let cache = AgentMarkdownDocumentCache(capacity: 2)
        let document = AgentMarkdownRenderDocument(blocks: [.paragraph([.text("one")])])
        let first = key("one", revision: 1)
        let second = key("two", revision: 1)
        let third = key("three", revision: 1)
        await cache.insert(document, for: first)
        await cache.insert(document, for: second)
        await cache.insert(document, for: third)
        let evicted = await cache.document(for: first)
        XCTAssertNil(evicted)
        await cache.remove(blockIDs: ["two"])
        let removed = await cache.document(for: second)
        XCTAssertNil(removed)
    }

    func testUnifiedDiffParserHandlesMultipleFilesRenameBinaryAndMarker() async {
        let source = """
            diff --git a/old.swift b/new.swift
            similarity index 90%
            rename from old.swift
            rename to new.swift
            --- a/old.swift
            +++ b/new.swift
            @@ -1,2 +1,2 @@
             context
            -old
            +new
            \\ No newline at end of file
            diff --git a/image.png b/image.png
            Binary files a/image.png and b/image.png differ
            """
        let result = await AgentUnifiedDiffParser().parse(source)
        XCTAssertEqual(result.files.count, 2)
        XCTAssertEqual(result.files[0].oldPath, "old.swift")
        XCTAssertEqual(result.files[0].newPath, "new.swift")
        XCTAssertEqual(result.files[0].additions, 1)
        XCTAssertEqual(result.files[0].deletions, 1)
        XCTAssertTrue(result.files[1].isBinary)
    }

    func testUnifiedDiffParserBoundsInlineContent() async {
        let parser = AgentUnifiedDiffParser(maximumLines: 3, maximumUTF8Count: 1_000)
        let result = await parser.parse("--- a/a\n+++ b/a\n@@ -1 +1 @@\n-old\n+new\n")
        XCTAssertTrue(result.wasTruncated)
    }

    func testUnifiedDiffCacheIsBoundedAndExplicitlyInvalidated() async {
        let parser = AgentUnifiedDiffParser(cacheCapacity: 1)
        let firstKey = AgentUnifiedDiffCacheKey(identifier: "first", revision: 1)
        let secondKey = AgentUnifiedDiffCacheKey(identifier: "second", revision: 1)
        let first = await parser.parse(
            "--- a/a\n+++ b/a\n@@ -1 +1 @@\n-old\n+first\n",
            cacheKey: firstKey
        )
        let cached = await parser.parse(
            "--- a/a\n+++ b/a\n@@ -1 +1 @@\n-old\n+changed\n",
            cacheKey: firstKey
        )
        XCTAssertEqual(first, cached)

        _ = await parser.parse(
            "--- a/b\n+++ b/b\n@@ -1 +1 @@\n-old\n+second\n",
            cacheKey: secondKey
        )
        let reparsed = await parser.parse(
            "--- a/a\n+++ b/a\n@@ -1 +1 @@\n-old\n+changed\n",
            cacheKey: firstKey
        )
        XCTAssertNotEqual(first, reparsed)
        await parser.removeCachedResults(identifiers: ["first"])
        await parser.removeAllCachedResults()
    }

    private func key(_ id: AgentBlockID, revision: Int64) -> AgentMarkdownCacheKey {
        .init(
            blockID: id,
            revision: revision,
            width: 320,
            contentSizeCategory: "large",
            themeVersion: 1
        )
    }

    func testStreamingParseDebouncesIntermediateContentAndCancelsStaleWork() async throws {
        let parser = AgentMarkdownParser()
        let clock = ContinuousClock()
        let started = clock.now
        _ = try await parser.parseStreaming(
            "A streaming **fragment",
            isFinal: false,
            debounceMilliseconds: 40
        )
        XCTAssertGreaterThanOrEqual(started.duration(to: clock.now), .milliseconds(35))

        let stale = Task {
            try await parser.parseStreaming(
                "A stale fragment",
                isFinal: false,
                debounceMilliseconds: 80
            )
        }
        stale.cancel()
        do {
            _ = try await stale.value
            XCTFail("Expected stale streaming parse to be cancelled")
        } catch is CancellationError {
            // Expected: a reused cell must not apply stale Markdown.
        }
    }

    func testFinalStreamingParseSkipsDebounce() async throws {
        let parser = AgentMarkdownParser()
        let clock = ContinuousClock()
        let started = clock.now
        let document = try await parser.parseStreaming(
            "Final **content**",
            isFinal: true,
            debounceMilliseconds: 80
        )
        XCTAssertFalse(document.blocks.isEmpty)
        XCTAssertLessThan(started.duration(to: clock.now), .milliseconds(60))
    }
}
