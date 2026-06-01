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
                .map(\.count)
                .max() ?? headers[column].count

            return min(maximumWidths[column], max(headers[column].count, contentWidth))
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
        guard value.count > width else {
            return value
        }

        guard width > 1 else {
            return String(value.prefix(width))
        }

        guard width > 3 else {
            return String(value.prefix(width))
        }

        return String(value.prefix(width - 3)) + "..."
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

            output.append(character)
            visibleCount += 1
            value.formIndex(after: &index)
        }

        return output + Color.reset
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

            count += 1
        }

        return count
    }
}
