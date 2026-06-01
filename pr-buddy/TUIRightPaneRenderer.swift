//
//  TUIRightPaneRenderer.swift
//  pr-buddy
//
//  Created by Terry Lewis II on 5/31/26.
//

import Foundation

final class TUIRightPaneRenderer {
    private let metadataColor = "\u{001B}[38;2;89;99;110m"
    private let openStatusColor = "\u{001B}[38;2;31;136;61m"
    private let closedStatusColor = "\u{001B}[38;2;207;34;46m"
    private let mergedStatusColor = "\u{001B}[38;2;130;80;223m"
    private let mergeQueueStatusColor = "\u{001B}[38;2;183;137;46m"
    private let defaultForegroundColor = "\u{001B}[39m"

    func paneWidth(for terminalWidth: Int) -> Int {
        min(max(36, terminalWidth / 3), max(36, terminalWidth - 34))
    }

    func tableRows(for pullRequests: [PullRequest]) -> [[String]] {
        pullRequests.map { pullRequest in
            [
                pullRequest.title,
                pullRequest.statusSummary
            ]
        }
    }

    func columnWidths(rows: [[String]]) -> [Int] {
        columnWidths(rows: rows, availableWidth: 36)
    }

    func columnWidths(rows: [[String]], availableWidth: Int) -> [Int] {
        let headers = ["Title", "Status"]
        return headers.indices.map { column in
            let contentWidth = ([headers[column]] + rows.map { $0[column] })
                .map(\.count)
                .max() ?? headers[column].count

            let maximumWidth = column == 0 ? max(16, availableWidth - 10) : 8
            return min(maximumWidth, max(headers[column].count, contentWidth))
        }
    }

    func title(count: Int) -> String {
        "My PRs (\(count))"
    }

    func header(widths: [Int]) -> String {
        renderCells(["Title", "Status"], widths: widths)
    }

    func row(_ row: [String], widths: [Int], isSelected: Bool) -> String {
        let rendered = "  " + renderCells(row, widths: widths)

        guard isSelected else {
            return rendered
        }

        return "\u{001B}[7m>\(rendered.dropFirst())\u{001B}[0m"
    }

    func line(
        rows: [[String]],
        widths: [Int],
        index: Int,
        selectedIndex: Int,
        isPaneSelected: Bool,
        visibleRows: Int,
        paneWidth: Int
    ) -> String {
        if index < rows.count {
            return row(
                rows[index],
                widths: widths,
                isSelected: isPaneSelected && index == selectedIndex
            )
        }

        guard rows.isEmpty else {
            return ""
        }

        if index == centeredRowIndex(in: visibleRows) {
            return centeredText("No Open PRs", width: paneWidth)
        }

        if index == centeredRowIndex(in: visibleRows) + 1 {
            return centeredText("that involve you today", width: paneWidth)
        }

        return ""
    }

    private func renderCells(_ row: [String], widths: [Int]) -> String {
        row.enumerated()
            .map { column, value in
                let text = truncate(value, to: widths[column])
                let paddedText = text.padding(toLength: widths[column], withPad: " ", startingAt: 0)

                if column == 1 {
                    return colorizedStatus(paddedText)
                }

                return paddedText
            }
            .joined(separator: "  ")
    }

    private func colorizedStatus(_ value: String) -> String {
        let normalizedStatus = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()

        switch normalizedStatus {
        case "open":
            return colorized(value, color: openStatusColor)
        case "closed":
            return colorized(value, color: closedStatusColor)
        case "merged":
            return colorized(value, color: mergedStatusColor)
        case "draft":
            return colorized(value, color: metadataColor)
        case "merge queue", "mergequeue", "queued":
            return colorized(value, color: mergeQueueStatusColor)
        default:
            return value
        }
    }

    private func colorized(_ value: String, color: String) -> String {
        color + value + defaultForegroundColor
    }

    private func truncate(_ value: String, to width: Int) -> String {
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

    private func centeredRowIndex(in visibleRows: Int) -> Int {
        max(0, visibleRows / 2)
    }

    private func centeredText(_ text: String, width: Int) -> String {
        let visibleTextLength = visibleLength(text)

        guard width > visibleTextLength else {
            return text
        }

        let leadingPadding = (width - visibleTextLength) / 2
        return String(repeating: " ", count: leadingPadding) + text
    }

    private func visibleLength(_ value: String) -> Int {
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
