import AgentChatCore
import Foundation

/// The bounded result of parsing a unified diff.
public struct AgentUnifiedDiffParseResult: Hashable, Codable, Sendable {
    /// Parsed file changes.
    public var files: [AgentDiffFile]
    /// Safe text fallback when no structured file could be parsed.
    public var rawFallback: String?
    /// Whether parsing stopped at configured inline limits.
    public var wasTruncated: Bool
    /// Creates a parse result.
    public init(files: [AgentDiffFile], rawFallback: String?, wasTruncated: Bool) {
        self.files = files
        self.rawFallback = rawFallback
        self.wasTruncated = wasTruncated
    }
}

/// Parses unified diffs away from the main actor with bounded inline output.
public actor AgentUnifiedDiffParser {
    private let maximumLines: Int
    private let maximumUTF8Count: Int

    /// Creates a bounded parser.
    public init(maximumLines: Int = 1_000, maximumUTF8Count: Int = 150_000) {
        self.maximumLines = max(1, maximumLines)
        self.maximumUTF8Count = max(1, maximumUTF8Count)
    }

    /// Parses multi-file, rename, binary, hunk, and no-newline markers.
    public func parse(_ source: String) -> AgentUnifiedDiffParseResult {
        let bounded = boundedSource(source)
        let lines = bounded.text.split(separator: "\n", omittingEmptySubsequences: false).map(
            String.init)
        var files: [AgentDiffFile] = []
        var currentFile: AgentDiffFile?
        var currentHunk: AgentDiffHunk?
        var oldLine = 0
        var newLine = 0

        func cleanPath(_ value: String) -> String? {
            let token = value.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? value
            guard token != "/dev/null" else { return nil }
            if token.hasPrefix("a/") || token.hasPrefix("b/") {
                return String(token.dropFirst(2))
            }
            return token.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        func flushHunk() {
            guard let hunk = currentHunk else { return }
            if currentFile == nil { currentFile = AgentDiffFile() }
            currentFile?.hunks.append(hunk)
            currentHunk = nil
        }

        func flushFile() {
            flushHunk()
            if let file = currentFile { files.append(file) }
            currentFile = nil
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flushFile()
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                currentFile = AgentDiffFile(
                    oldPath: parts.count > 2 ? cleanPath(String(parts[2])) : nil,
                    newPath: parts.count > 3 ? cleanPath(String(parts[3])) : nil
                )
                continue
            }
            if line.hasPrefix("--- ") {
                flushHunk()
                if currentFile == nil { currentFile = AgentDiffFile() }
                currentFile?.oldPath = cleanPath(String(line.dropFirst(4)))
                continue
            }
            if line.hasPrefix("+++ ") {
                if currentFile == nil { currentFile = AgentDiffFile() }
                currentFile?.newPath = cleanPath(String(line.dropFirst(4)))
                continue
            }
            if line.hasPrefix("rename from ") {
                if currentFile == nil { currentFile = AgentDiffFile() }
                currentFile?.oldPath = String(line.dropFirst("rename from ".count))
                continue
            }
            if line.hasPrefix("rename to ") {
                if currentFile == nil { currentFile = AgentDiffFile() }
                currentFile?.newPath = String(line.dropFirst("rename to ".count))
                continue
            }
            if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
                if currentFile == nil { currentFile = AgentDiffFile() }
                currentFile?.isBinary = true
                continue
            }
            if line.hasPrefix("@@"), let range = parseHunkRange(line) {
                flushHunk()
                oldLine = range.oldStart
                newLine = range.newStart
                currentHunk = AgentDiffHunk(header: line, lines: [])
                continue
            }
            guard currentHunk != nil else { continue }
            if line.hasPrefix("+") {
                currentHunk?.lines.append(
                    .init(kind: .addition, text: String(line.dropFirst()), newLine: newLine)
                )
                newLine += 1
            } else if line.hasPrefix("-") {
                currentHunk?.lines.append(
                    .init(kind: .deletion, text: String(line.dropFirst()), oldLine: oldLine)
                )
                oldLine += 1
            } else if line.hasPrefix("\\ No newline at end of file") {
                currentHunk?.lines.append(.init(kind: .marker, text: line))
            } else {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                currentHunk?.lines.append(
                    .init(kind: .context, text: text, oldLine: oldLine, newLine: newLine)
                )
                oldLine += 1
                newLine += 1
            }
        }
        flushFile()

        return .init(
            files: files,
            rawFallback: files.isEmpty ? bounded.text : nil,
            wasTruncated: bounded.truncated
        )
    }

    private func boundedSource(_ source: String) -> (text: String, truncated: Bool) {
        var text = ""
        var bytes = 0
        var lines = 0
        for character in source {
            let byteCount = String(character).utf8.count
            let addedLine = character == "\n" ? 1 : 0
            guard bytes + byteCount <= maximumUTF8Count, lines + addedLine <= maximumLines else {
                return (text, true)
            }
            text.append(character)
            bytes += byteCount
            lines += addedLine
        }
        return (text, false)
    }

    private func parseHunkRange(_ line: String) -> (oldStart: Int, newStart: Int)? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3,
            parts[1].hasPrefix("-"),
            parts[2].hasPrefix("+")
        else { return nil }
        func start(_ part: Substring) -> Int? {
            Int(part.dropFirst().split(separator: ",", maxSplits: 1)[0])
        }
        guard let oldStart = start(parts[1]), let newStart = start(parts[2]) else { return nil }
        return (oldStart, newStart)
    }
}
