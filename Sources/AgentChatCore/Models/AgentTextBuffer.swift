import Foundation

/// A bounded, chunked buffer for incremental command output.
public struct AgentTextBuffer: Hashable, Codable, Sendable {
    /// The retained output chunks.
    public private(set) var chunks: [String]
    /// The number of retained UTF-8 bytes.
    public private(set) var utf8Count: Int
    /// The number of retained line breaks.
    public private(set) var lineCount: Int
    /// Whether content was discarded after reaching a configured limit.
    public private(set) var wasTruncated: Bool
    /// The maximum retained UTF-8 byte count.
    public let maximumUTF8Count: Int
    /// The maximum retained line count.
    public let maximumLineCount: Int

    /// Creates an empty bounded buffer.
    public init(maximumUTF8Count: Int = 200_000, maximumLineCount: Int = 2_000) {
        self.chunks = []
        self.utf8Count = 0
        self.lineCount = 0
        self.wasTruncated = false
        self.maximumUTF8Count = max(0, maximumUTF8Count)
        self.maximumLineCount = max(0, maximumLineCount)
    }

    /// The retained output as a single string, assembled only on demand.
    public var text: String { chunks.joined() }

    /// Appends sanitized terminal text without repeated whole-buffer concatenation.
    public mutating func append(_ rawText: String) {
        guard !wasTruncated else { return }
        let sanitized = Self.sanitizeTerminalText(rawText)
        guard !sanitized.isEmpty else { return }

        let remainingBytes = maximumUTF8Count - utf8Count
        let remainingLines = maximumLineCount - lineCount
        guard remainingBytes > 0, remainingLines >= 0 else {
            wasTruncated = true
            return
        }

        var retained = ""
        retained.reserveCapacity(min(sanitized.utf8.count, remainingBytes))
        var retainedBytes = 0
        var retainedLines = 0
        var truncated = false

        for character in sanitized {
            let byteCount = String(character).utf8.count
            let addedLines = character == "\n" ? 1 : 0
            if retainedBytes + byteCount > remainingBytes
                || retainedLines + addedLines > remainingLines
            {
                truncated = true
                break
            }
            retained.append(character)
            retainedBytes += byteCount
            retainedLines += addedLines
        }

        if !retained.isEmpty {
            chunks.append(retained)
            utf8Count += retainedBytes
            lineCount += retainedLines
        }
        wasTruncated = truncated || retained.count < sanitized.count
    }

    /// Removes terminal controls, OSC sequences, CSI sequences, and non-text control characters.
    public static func sanitizeTerminalText(_ input: String) -> String {
        enum EscapeState { case text, escape, controlSequence, operatingSystemCommand }
        var state = EscapeState.text
        var result = String.UnicodeScalarView()

        for scalar in input.unicodeScalars {
            switch state {
            case .text:
                if scalar.value == 0x1B {
                    state = .escape
                } else if scalar == "\n" || scalar == "\r" || scalar == "\t"
                    || scalar.value >= 0x20
                {
                    result.append(scalar)
                }
            case .escape:
                if scalar == "[" {
                    state = .controlSequence
                } else if scalar == "]" {
                    state = .operatingSystemCommand
                } else {
                    state = .text
                }
            case .controlSequence:
                if (0x40...0x7E).contains(scalar.value) {
                    state = .text
                }
            case .operatingSystemCommand:
                if scalar.value == 0x07 {
                    state = .text
                } else if scalar.value == 0x1B {
                    state = .escape
                }
            }
        }
        return String(result)
    }
}
