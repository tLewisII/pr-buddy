import Foundation

enum TUIFormat {
    private enum DisplayStatus {
        case open
        case closed
        case merged
        case draft
        case mergeQueue
        case unknown

        init(normalizedStatus: String) {
            if normalizedStatus == "open" {
                self = .open
            } else if normalizedStatus == "closed" {
                self = .closed
            } else if normalizedStatus == "merged" {
                self = .merged
            } else if normalizedStatus == "draft" {
                self = .draft
            } else if normalizedStatus == "merge queue" || normalizedStatus == "mergequeue" || normalizedStatus == "queued" {
                self = .mergeQueue
            } else {
                self = .unknown
            }
        }
    }

    enum Color {
        static let additions = "\u{001B}[38;2;26;127;55m"
        static let deletions = "\u{001B}[38;2;209;36;47m"
        static let metadata = "\u{001B}[38;2;89;99;110m"
        static let openStatus = "\u{001B}[38;2;31;136;61m"
        static let closedStatus = "\u{001B}[38;2;207;34;46m"
        static let mergedStatus = "\u{001B}[38;2;130;80;223m"
        static let mergeQueueStatus = "\u{001B}[38;2;183;137;46m"
        static let defaultForeground = "\u{001B}[39m"
        static let inverse = "\u{001B}[7m"
        static let reset = "\u{001B}[0m"
    }

    static func columnWidths(headers: [String], rows: [[String]], maximumWidths: [Int]) -> [Int] {
        headers.indices.map { column in
            let contentWidth = ([headers[column]] + rows.map { $0[column] })
                .map(visibleLength)
                .max() ?? visibleLength(headers[column])

            return min(maximumWidths[column], max(visibleLength(headers[column]), contentWidth))
        }
    }

    static func colorizedStatus(_ value: String) -> String {
        let normalizedStatus = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()

        switch DisplayStatus(normalizedStatus: normalizedStatus) {
        case .open:
            return colorized(value, color: Color.openStatus)
        case .closed:
            return colorized(value, color: Color.closedStatus)
        case .merged:
            return colorized(value, color: Color.mergedStatus)
        case .draft:
            return colorized(value, color: Color.metadata)
        case .mergeQueue:
            return colorized(value, color: Color.mergeQueueStatus)
        case .unknown:
            return value
        }
    }

    static func colorized(_ value: String, color: String) -> String {
        color + value + Color.defaultForeground
    }

    static func inverted(_ value: String) -> String {
        Color.inverse + value + Color.reset
    }

    static func truncate(_ value: String, to width: Int) -> String {
        guard visibleLength(value) > width else {
            return value
        }

        guard width > 1 else {
            return prefix(value, fitting: width)
        }

        guard width > 3 else {
            return prefix(value, fitting: width)
        }

        return prefix(value, fitting: width - 3) + "..."
    }

    static func clipped(_ value: String, to width: Int) -> String {
        guard visibleLength(value) > width else {
            return value
        }

        var output = ""
        var visibleCount = 0
        var index = value.startIndex

        while index < value.endIndex && visibleCount < width {
            let character = value[index]

            if character == "\u{001B}" {
                let sequenceStart = index
                value.formIndex(after: &index)

                while index < value.endIndex {
                    let sequenceCharacter = value[index]
                    value.formIndex(after: &index)

                    if sequenceCharacter.isLetter {
                        break
                    }
                }

                output += value[sequenceStart..<index]
                continue
            }

            let characterWidth = displayWidth(of: character)

            guard visibleCount + characterWidth <= width else {
                break
            }

            output.append(character)
            visibleCount += characterWidth
            value.formIndex(after: &index)
        }

        return output + Color.reset
    }

    static func padded(_ value: String, to width: Int) -> String {
        let visibleValueLength = visibleLength(value)

        guard visibleValueLength < width else {
            return value
        }

        return value + String(repeating: " ", count: width - visibleValueLength)
    }

    static func centeredText(_ text: String, width: Int) -> String {
        let visibleTextLength = visibleLength(text)

        guard width > visibleTextLength else {
            return text
        }

        let leadingPadding = (width - visibleTextLength) / 2
        return String(repeating: " ", count: leadingPadding) + text
    }

    static func visibleLength(_ value: String) -> Int {
        var count = 0
        var isEscapeSequence = false

        for character in value {
            if character == "\u{001B}" {
                isEscapeSequence = true
                continue
            }

            if isEscapeSequence {
                if character.isLetter {
                    isEscapeSequence = false
                }

                continue
            }

            count += displayWidth(of: character)
        }

        return count
    }

    private static func prefix(_ value: String, fitting width: Int) -> String {
        var output = ""
        var visibleCount = 0

        for character in value {
            let characterWidth = displayWidth(of: character)

            guard visibleCount + characterWidth <= width else {
                break
            }

            output.append(character)
            visibleCount += characterWidth
        }

        return output
    }

    private static func displayWidth(of character: Character) -> Int {
        if character.unicodeScalars.contains(where: { $0.value == 0xFE0E }) {
            return 1
        }

        return character.unicodeScalars.map(displayWidth(of:)).max() ?? 0
    }

    private static func displayWidth(of scalar: Unicode.Scalar) -> Int {
        if scalar.properties.generalCategory == .nonspacingMark
            || scalar.properties.generalCategory == .enclosingMark
            || scalar.value == 0xFE0E
            || scalar.value == 0xFE0F {
            return 0
        }

        if isWideScalar(scalar) {
            return 2
        }

        return 1
    }

    private static func isWideScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,
             0x2329...0x232A,
             0x2E80...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x1F000...0x1FAFF,
             0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}
