//
//  TUIRenderer.swift
//  pr-buddy
//
//  Created by Terry Lewis II on 5/30/26.
//

import Darwin
import Foundation

final class TUIRenderer {
    private enum TableColumn {
        case number
        case files
        case status
        case review
        case labels
        case title
        case author
        case unknown

        init(index: Int) {
            if index == 0 {
                self = .number
            } else if index == 1 {
                self = .files
            } else if index == 2 {
                self = .status
            } else if index == 3 {
                self = .review
            } else if index == 4 {
                self = .labels
            } else if index == 5 {
                self = .title
            } else if index == 6 {
                self = .author
            } else {
                self = .unknown
            }
        }
    }

    private let rightPaneRenderer = TUIRightPaneRenderer()
    private let headers = ["PR", "Files", "Status", "Review", "Labels", "Title", "Author"]
    private let maximumWidths = [6, 18, 8, 18, 24, 72, 24]
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
        let visibleRows = visibleListRows()
        let endIndex = min(rows.count, topIndex + visibleRows)
        let repoText = options.repo ?? "current repository"
        let shownRange = rows.isEmpty ? "0 of 0" : "\(topIndex + 1)-\(endIndex) of \(rows.count)"

        guard options.showMyPRs else {
            drawSinglePanePullRequestList(
                rows: rows,
                headers: headers,
                selectedIndex: selectedIndex,
                topIndex: topIndex,
                visibleRows: visibleRows,
                isFilesHeaderSelected: isFilesHeaderSelected,
                repoText: repoText,
                shownRange: shownRange,
                message: message
            )
            return
        }

        let terminalWidth = terminalWidth()
        let attentionPaneWidth = rightPaneRenderer.paneWidth(for: terminalWidth)
        let leftPaneWidth = max(30, terminalWidth - attentionPaneWidth - 2)
        let widths = columnWidths(
            headers: headers,
            rows: rows,
            maximumWidths: mainPaneMaximumWidths(availableWidth: leftPaneWidth)
        )
        let attentionRows = rightPaneRenderer.tableRows(for: attentionPullRequests)
        let attentionWidths = rightPaneRenderer.columnWidths(rows: attentionRows, availableWidth: attentionPaneWidth)
        let attentionEndIndex = min(attentionRows.count, attentionTopIndex + visibleRows)
        let attentionShownRange = attentionRows.isEmpty ? "0 of 0" : "\(attentionTopIndex + 1)-\(attentionEndIndex) of \(attentionRows.count)"
        let attentionHeader = attentionRows.isEmpty ? "" : rightPaneRenderer.title(count: attentionRows.count)
        let attentionColumnHeader = attentionRows.isEmpty ? "" : rightPaneRenderer.header(widths: attentionWidths)

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
                left = isSelectedRow ? TUIFormat.inverted(rendered) : rendered
            } else if rows.isEmpty && offset == 0 {
                left = "  No pull requests matched the current filters."
            } else {
                left = ""
            }

            right = rightPaneRenderer.line(
                rows: attentionRows,
                widths: attentionWidths,
                index: attentionIndex,
                selectedIndex: attentionSelectedIndex,
                isPaneSelected: isAttentionPaneSelected,
                visibleRows: visibleRows,
                paneWidth: attentionPaneWidth
            )

            lines.append(joinPaneLines(left: left, right: right, leftWidth: leftPaneWidth))
        }

        drawListLines(lines)
    }

    private func drawSinglePanePullRequestList(
        rows: [[String]],
        headers: [String],
        selectedIndex: Int,
        topIndex: Int,
        visibleRows: Int,
        isFilesHeaderSelected: Bool,
        repoText: String,
        shownRange: String,
        message: String
    ) {
        let widths = columnWidths(headers: headers, rows: rows)

        var lines = [
            "pr-buddy  \(repoText)",
            "Showing \(shownRange).  arrows/j/k move  enter on Files sort  enter/v view  c checkout  o open  r refresh  q quit",
            message.isEmpty ? " " : message,
            "",
            "  " + renderHeaderRow(headers, widths: widths, isFilesHeaderSelected: isFilesHeaderSelected),
            "  " + widths.map { String(repeating: "-", count: $0) }.joined(separator: "  ")
        ]

        if rows.isEmpty {
            lines.append("  No pull requests matched the current filters.")
            drawListLines(lines)
            return
        }

        for index in topIndex..<min(rows.count, topIndex + visibleRows) {
            let isSelectedRow = !isFilesHeaderSelected && index == selectedIndex
            let marker = isSelectedRow ? ">" : " "
            let rendered = "\(marker) " + renderRow(rows[index], widths: widths)

            if isSelectedRow {
                lines.append(TUIFormat.inverted(rendered))
            } else {
                lines.append(rendered)
            }
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
        rightPaneRenderer.tableRows(for: pullRequests)
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
        TUIFormat.columnWidths(headers: headers, rows: rows, maximumWidths: maximumWidths)
    }

    func attentionColumnWidths(rows: [[String]]) -> [Int] {
        rightPaneRenderer.columnWidths(rows: rows, availableWidth: max(36, terminalWidth() / 3))
    }

    func renderRow(_ row: [String], widths: [Int]) -> String {
        row.enumerated()
            .map { column, value in
                let text = truncate(value, to: widths[column])
                let paddedText = text.padding(toLength: widths[column], withPad: " ", startingAt: 0)

                switch TableColumn(index: column) {
                case .number, .author:
                    return TUIFormat.colorized(paddedText, color: TUIFormat.Color.metadata)
                case .files:
                    return colorizedFileSummary(paddedText)
                case .status:
                    return colorizedStatus(paddedText)
                case .review, .labels, .title, .unknown:
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

                return TUIFormat.inverted(paddedText)
            }
            .joined(separator: "  ")
    }

    func renderAttentionHeader(widths: [Int]) -> String {
        rightPaneRenderer.header(widths: widths)
    }

    func renderAttentionRow(_ row: [String], widths: [Int], isSelected: Bool) -> String {
        rightPaneRenderer.row(row, widths: widths, isSelected: isSelected)
    }

    func colorizedStatus(_ value: String) -> String {
        TUIFormat.colorizedStatus(value)
    }

    func colorizedFileSummary(_ value: String) -> String {
        value
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { token -> String in
                let text = String(token)

                if isSignedNumber(text, prefix: "+") {
                    return TUIFormat.colorized(text, color: TUIFormat.Color.additions)
                }

                if isSignedNumber(text, prefix: "-") {
                    return TUIFormat.colorized(text, color: TUIFormat.Color.deletions)
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
        TUIFormat.truncate(value, to: width)
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

    private func joinPaneLines(left: String, right: String, leftWidth: Int) -> String {
        let clippedLeft = TUIFormat.clipped(left, to: leftWidth)
        return clippedLeft + String(repeating: " ", count: max(1, leftWidth - TUIFormat.visibleLength(clippedLeft) + 1)) + right
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
