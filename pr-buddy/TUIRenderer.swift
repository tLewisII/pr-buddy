//
//  TUIRenderer.swift
//  pr-buddy
//
//  Created by Terry Lewis II on 5/30/26.
//

import Darwin
import Foundation

final class TUIRenderer {
    private let headers = ["PR", "Files", "Status", "Review", "Labels", "Title", "Author"]
    private let maximumWidths = [6, 18, 8, 18, 24, 72, 24]
    private let additionsColor = "\u{001B}[38;2;26;127;55m"
    private let deletionsColor = "\u{001B}[38;2;209;36;47m"
    private let metadataColor = "\u{001B}[38;2;89;99;110m"
    private let openStatusColor = "\u{001B}[38;2;31;136;61m"
    private let closedStatusColor = "\u{001B}[38;2;207;34;46m"
    private let mergedStatusColor = "\u{001B}[38;2;130;80;223m"
    private let mergeQueueStatusColor = "\u{001B}[38;2;183;137;46m"
    private let defaultForegroundColor = "\u{001B}[39m"
    private var previousListLineCount = 0

    func printTable(_ pullRequests: [PullRequest]) {
        let rows = tableRows(for: pullRequests)
        let widths = columnWidths(headers: headers, rows: rows)

        print(renderRow(headers, widths: widths))
        print(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))

        for row in rows {
            print(renderRow(row, widths: widths))
        }
    }

    func drawPullRequestList(
        pullRequests: [PullRequest],
        selectedIndex: Int,
        topIndex: Int,
        isFilesHeaderSelected: Bool,
        isMainPaneSelected: Bool,
        fileSortOrder: FileSortOrder,
        attentionPullRequests: [PullRequest],
        attentionSelectedIndex: Int,
        attentionTopIndex: Int,
        isAttentionPaneSelected: Bool,
        options: Options,
        message: String
    ) {
        let rows = tableRows(for: pullRequests)
        let headers = headers(for: fileSortOrder)
        let terminalWidth = terminalWidth()
        let attentionPaneWidth = rightPaneWidth(for: terminalWidth)
        let leftPaneWidth = max(30, terminalWidth - attentionPaneWidth - 2)
        let widths = columnWidths(
            headers: headers,
            rows: rows,
            maximumWidths: mainPaneMaximumWidths(availableWidth: leftPaneWidth)
        )
        let visibleRows = visibleListRows()
        let endIndex = min(rows.count, topIndex + visibleRows)
        let attentionRows = attentionTableRows(for: attentionPullRequests)
        let attentionWidths = attentionColumnWidths(rows: attentionRows, availableWidth: attentionPaneWidth)
        let attentionEndIndex = min(attentionRows.count, attentionTopIndex + visibleRows)
        let repoText = options.repo ?? "current repository"
        let shownRange = rows.isEmpty ? "0 of 0" : "\(topIndex + 1)-\(endIndex) of \(rows.count)"
        let attentionShownRange = attentionRows.isEmpty ? "0 of 0" : "\(attentionTopIndex + 1)-\(attentionEndIndex) of \(attentionRows.count)"
        let attentionHeader = attentionRows.isEmpty ? "" : attentionTitle(count: attentionRows.count)
        let attentionColumnHeader = attentionRows.isEmpty ? "" : renderAttentionHeader(widths: attentionWidths)

        var lines = [
            "pr-buddy  \(repoText)",
            "Main \(shownRange).  My PRs \(attentionShownRange).  arrows/h/j/k/l move  enter/v view  c checkout  o open  r refresh  q quit",
            message.isEmpty ? " " : message,
            "",
            joinPaneLines(
                left: "  " + renderHeaderRow(headers, widths: widths, isFilesHeaderSelected: isFilesHeaderSelected),
                right: attentionHeader,
                leftWidth: leftPaneWidth
            ),
            joinPaneLines(
                left: "  " + widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "),
                right: attentionColumnHeader,
                leftWidth: leftPaneWidth
            )
        ]

        for offset in 0..<visibleRows {
            let mainIndex = topIndex + offset
            let attentionIndex = attentionTopIndex + offset
            let left: String
            let right: String

            if mainIndex < rows.count {
                let isSelectedRow = !isFilesHeaderSelected && isMainPaneSelected && mainIndex == selectedIndex
                let marker = isSelectedRow ? ">" : " "
                let rendered = "\(marker) " + renderRow(rows[mainIndex], widths: widths)
                left = isSelectedRow ? "\u{001B}[7m\(rendered)\u{001B}[0m" : rendered
            } else if rows.isEmpty && offset == 0 {
                left = "  No pull requests matched the current filters."
            } else {
                left = ""
            }

            if attentionIndex < attentionRows.count {
                right = renderAttentionRow(
                    attentionRows[attentionIndex],
                    widths: attentionWidths,
                    isSelected: isAttentionPaneSelected && attentionIndex == attentionSelectedIndex
                )
            } else if attentionRows.isEmpty && offset == centeredRowIndex(in: visibleRows) {
                right = centeredText("No Open PRs", width: attentionPaneWidth)
            } else if attentionRows.isEmpty && offset == centeredRowIndex(in: visibleRows) + 1 {
                right = centeredText("that involve you today", width: attentionPaneWidth)
            } else {
                right = ""
            }

            lines.append(joinPaneLines(left: left, right: right, leftWidth: leftPaneWidth))
        }

        drawListLines(lines)
    }

    func drawCommandResult(title: String, result: CommandResult) {
        clearScreen()
        previousListLineCount = 0
        print(title)
        print(String(repeating: "-", count: title.count))

        if !result.stdout.isEmpty {
            print(result.stdout)
        }

        if !result.stderr.isEmpty {
            print(result.stderr)
        }

        if result.stdout.isEmpty && result.stderr.isEmpty {
            print("Command completed with no output.")
        }

        print("")
        print("Press any key to return to the PR list.")
        fflush(stdout)
    }

    func tableRows(for pullRequests: [PullRequest]) -> [[String]] {
        pullRequests.map { pullRequest in
            [
                "#\(pullRequest.number)",
                fileSummary(for: pullRequest),
                pullRequest.statusSummary,
                pullRequest.reviewSummary,
                pullRequest.labelSummary.isEmpty ? "-" : pullRequest.labelSummary,
                pullRequest.title,
                pullRequest.author?.login ?? "-"
            ]
        }
    }

    func attentionTableRows(for pullRequests: [PullRequest]) -> [[String]] {
        pullRequests.map { pullRequest in
            [
                pullRequest.title,
                pullRequest.statusSummary
            ]
        }
    }

    func fileSummary(for pullRequest: PullRequest) -> String {
        guard let changedFiles = pullRequest.changedFiles else {
            return "-"
        }

        var parts = [String(changedFiles)]

        if let additions = pullRequest.additions {
            parts.append("+\(additions)")
        }

        if let deletions = pullRequest.deletions {
            parts.append("-\(deletions)")
        }

        return parts.joined(separator: " ")
    }

    func columnWidths(headers: [String], rows: [[String]]) -> [Int] {
        columnWidths(headers: headers, rows: rows, maximumWidths: maximumWidths)
    }

    private func columnWidths(headers: [String], rows: [[String]], maximumWidths: [Int]) -> [Int] {
        headers.indices.map { column in
            let contentWidth = ([headers[column]] + rows.map { $0[column] })
                .map(\.count)
                .max() ?? headers[column].count

            return min(maximumWidths[column], max(headers[column].count, contentWidth))
        }
    }

    func attentionColumnWidths(rows: [[String]]) -> [Int] {
        attentionColumnWidths(rows: rows, availableWidth: max(36, terminalWidth() / 3))
    }

    private func attentionColumnWidths(rows: [[String]], availableWidth: Int) -> [Int] {
        let headers = ["Title", "Status"]
        return headers.indices.map { column in
            let contentWidth = ([headers[column]] + rows.map { $0[column] })
                .map(\.count)
                .max() ?? headers[column].count

            let maximumWidth = column == 0 ? max(16, availableWidth - 10) : 8
            return min(maximumWidth, max(headers[column].count, contentWidth))
        }
    }

    func renderRow(_ row: [String], widths: [Int]) -> String {
        row.enumerated()
            .map { column, value in
                let text = truncate(value, to: widths[column])
                let paddedText = text.padding(toLength: widths[column], withPad: " ", startingAt: 0)

                switch column {
                case 0, 6:
                    return colorized(paddedText, color: metadataColor)
                case 1:
                    return colorizedFileSummary(paddedText)
                case 2:
                    return colorizedStatus(paddedText)
                default:
                    return paddedText
                }
            }
            .joined(separator: "  ")
    }

    func headers(for fileSortOrder: FileSortOrder) -> [String] {
        var headers = self.headers

        switch fileSortOrder {
        case .none:
            headers[1] = "Files"
        case .ascending:
            headers[1] = "Files ^"
        case .descending:
            headers[1] = "Files v"
        }

        return headers
    }

    func renderHeaderRow(_ row: [String], widths: [Int], isFilesHeaderSelected: Bool) -> String {
        row.enumerated()
            .map { column, value in
                let text = truncate(value, to: widths[column])
                let paddedText = text.padding(toLength: widths[column], withPad: " ", startingAt: 0)

                guard column == 1, isFilesHeaderSelected else {
                    return paddedText
                }

                return "\u{001B}[7m\(paddedText)\u{001B}[0m"
            }
            .joined(separator: "  ")
    }

    func renderAttentionHeader(widths: [Int]) -> String {
        renderAttentionCells(["Title", "Status"], widths: widths)
    }

    func renderAttentionRow(_ row: [String], widths: [Int], isSelected: Bool) -> String {
        let rendered = "  " + renderAttentionCells(row, widths: widths)

        guard isSelected else {
            return rendered
        }

        return "\u{001B}[7m>\(rendered.dropFirst())\u{001B}[0m"
    }

    private func renderAttentionCells(_ row: [String], widths: [Int]) -> String {
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

    private func colorized(_ value: String, color: String) -> String {
        color + value + defaultForegroundColor
    }

    func colorizedStatus(_ value: String) -> String {
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

    func colorizedFileSummary(_ value: String) -> String {
        value
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { token -> String in
                let text = String(token)

                if isSignedNumber(text, prefix: "+") {
                    return additionsColor + text + defaultForegroundColor
                }

                if isSignedNumber(text, prefix: "-") {
                    return deletionsColor + text + defaultForegroundColor
                }

                return text
            }
            .joined(separator: " ")
    }

    private func isSignedNumber(_ value: String, prefix: Character) -> Bool {
        guard value.first == prefix else {
            return false
        }

        return !value.dropFirst().isEmpty && value.dropFirst().allSatisfy(\.isNumber)
    }

    func truncate(_ value: String, to width: Int) -> String {
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

    func terminalHeight() -> Int {
        var size = winsize()

        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_row > 0 else {
            return 24
        }

        return Int(size.ws_row)
    }

    func terminalWidth() -> Int {
        var size = winsize()

        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 else {
            return 120
        }

        return Int(size.ws_col)
    }

    func visibleListRows() -> Int {
        max(1, terminalHeight() - 8)
    }

    private func attentionTitle(count: Int) -> String {
        "My PRs (\(count))"
    }

    private func rightPaneWidth(for terminalWidth: Int) -> Int {
        min(max(36, terminalWidth / 3), max(36, terminalWidth - 34))
    }

    private func mainPaneMaximumWidths(availableWidth: Int) -> [Int] {
        var widths = [6, 9, 8, 12, 12, 24, 12]
        let minimumWidths = [3, 5, 4, 6, 6, 5, 6]
        let separatorWidth = (widths.count - 1) * 2 + 2
        var overflow = widths.reduce(0, +) + separatorWidth - availableWidth

        for column in [5, 4, 6, 3, 1, 2, 0] where overflow > 0 {
            let shrinkAmount = min(overflow, widths[column] - minimumWidths[column])
            widths[column] -= shrinkAmount
            overflow -= shrinkAmount
        }

        if overflow < 0 {
            widths[5] += min(maximumWidths[5] - widths[5], abs(overflow))
        }

        return widths
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

    private func joinPaneLines(left: String, right: String, leftWidth: Int) -> String {
        let clippedLeft = clipped(left, to: leftWidth)
        return clippedLeft + String(repeating: " ", count: max(1, leftWidth - visibleLength(clippedLeft) + 1)) + right
    }

    private func clipped(_ value: String, to width: Int) -> String {
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

        return output + "\u{001B}[0m"
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

    private func drawListLines(_ lines: [String]) {
        if previousListLineCount == 0 {
            clearScreen()
        }

        let lineCount = max(lines.count, previousListLineCount)
        var output = "\u{001B}[H"

        for index in 0..<lineCount {
            output += "\u{001B}[2K"

            if index < lines.count {
                output += lines[index]
            }

            if index < lineCount - 1 {
                output += "\n"
            }
        }

        previousListLineCount = lines.count
        print(output, terminator: "")
        fflush(stdout)
    }

    func clearScreen() {
        previousListLineCount = 0
        print("\u{001B}[2J\u{001B}[H", terminator: "")
    }

    func moveCursorHome() {
        print("\u{001B}[H", terminator: "")
    }

    func clearToEndOfScreen() {
        print("\u{001B}[J", terminator: "")
    }

    func hideCursor() {
        print("\u{001B}[?25l", terminator: "")
    }

    func showCursor() {
        print("\u{001B}[?25h", terminator: "")
    }
}
