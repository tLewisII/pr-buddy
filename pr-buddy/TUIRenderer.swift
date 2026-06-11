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
        case updated
        case files
        case status
        case review
        case labels
        case title
        case author
        case unknown

        init(index: Int) {
            if index == 0 {
                self = .updated
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

    private let headers = ["Updated  ", "Files", "Status", "Review  ", "Labels", "Title", "Author"]
    private let attentionHeaders = ["Title", "Status"]
    private let maximumWidths = [9, 18, 8, 18, 24, 72, 24]
    private let now: () -> Date
    private let updatedAtParser = ISO8601DateFormatter()
    private let updatedComponentsFormatter = DateComponentsFormatter()
    private var previousListLineCount = 0

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        updatedComponentsFormatter.maximumUnitCount = 1
        updatedComponentsFormatter.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute]
        updatedComponentsFormatter.unitsStyle = .full
    }

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
        isUpdatedHeaderSelected: Bool,
        isFilesHeaderSelected: Bool,
        isReviewHeaderSelected: Bool,
        isMainViewSelected: Bool,
        updatedSortOrder: UpdatedSortOrder,
        fileSortOrder: FileSortOrder,
        reviewSortOrder: ReviewSortOrder,
        attentionPullRequests: [PullRequest],
        attentionSelectedIndex: Int,
        attentionTopIndex: Int,
        isAttentionViewSelected: Bool,
        options: Options,
        message: String,
        inputBar: String? = nil
    ) {
        let lines = renderPullRequestListLines(
            pullRequests: pullRequests,
            selectedIndex: selectedIndex,
            topIndex: topIndex,
            isUpdatedHeaderSelected: isUpdatedHeaderSelected,
            isFilesHeaderSelected: isFilesHeaderSelected,
            isReviewHeaderSelected: isReviewHeaderSelected,
            isMainViewSelected: isMainViewSelected,
            updatedSortOrder: updatedSortOrder,
            fileSortOrder: fileSortOrder,
            reviewSortOrder: reviewSortOrder,
            attentionPullRequests: attentionPullRequests,
            attentionSelectedIndex: attentionSelectedIndex,
            attentionTopIndex: attentionTopIndex,
            isAttentionViewSelected: isAttentionViewSelected,
            options: options,
            message: message,
            inputBar: inputBar,
            terminalWidth: terminalWidth(),
            terminalHeight: terminalHeight()
        )

        drawListLines(lines)
    }

    func renderPullRequestList(
        pullRequests: [PullRequest],
        selectedIndex: Int,
        topIndex: Int,
        isUpdatedHeaderSelected: Bool,
        isFilesHeaderSelected: Bool,
        isReviewHeaderSelected: Bool,
        isMainViewSelected: Bool,
        updatedSortOrder: UpdatedSortOrder,
        fileSortOrder: FileSortOrder,
        reviewSortOrder: ReviewSortOrder,
        attentionPullRequests: [PullRequest],
        attentionSelectedIndex: Int,
        attentionTopIndex: Int,
        isAttentionViewSelected: Bool,
        options: Options,
        message: String,
        inputBar: String? = nil,
        terminalWidth: Int = 120,
        terminalHeight: Int = 24
    ) -> String {
        renderPullRequestListLines(
            pullRequests: pullRequests,
            selectedIndex: selectedIndex,
            topIndex: topIndex,
            isUpdatedHeaderSelected: isUpdatedHeaderSelected,
            isFilesHeaderSelected: isFilesHeaderSelected,
            isReviewHeaderSelected: isReviewHeaderSelected,
            isMainViewSelected: isMainViewSelected,
            updatedSortOrder: updatedSortOrder,
            fileSortOrder: fileSortOrder,
            reviewSortOrder: reviewSortOrder,
            attentionPullRequests: attentionPullRequests,
            attentionSelectedIndex: attentionSelectedIndex,
            attentionTopIndex: attentionTopIndex,
            isAttentionViewSelected: isAttentionViewSelected,
            options: options,
            message: message,
            inputBar: inputBar,
            terminalWidth: terminalWidth,
            terminalHeight: terminalHeight
        ).joined(separator: "\n")
    }

    private func renderPullRequestListLines(
        pullRequests: [PullRequest],
        selectedIndex: Int,
        topIndex: Int,
        isUpdatedHeaderSelected: Bool,
        isFilesHeaderSelected: Bool,
        isReviewHeaderSelected: Bool,
        isMainViewSelected: Bool,
        updatedSortOrder: UpdatedSortOrder,
        fileSortOrder: FileSortOrder,
        reviewSortOrder: ReviewSortOrder,
        attentionPullRequests: [PullRequest],
        attentionSelectedIndex: Int,
        attentionTopIndex: Int,
        isAttentionViewSelected: Bool,
        options: Options,
        message: String,
        inputBar: String?,
        terminalWidth: Int,
        terminalHeight: Int
    ) -> [String] {
        let rows = tableRows(for: pullRequests)
        let headers = headers(
            updatedSortOrder: updatedSortOrder,
            fileSortOrder: fileSortOrder,
            reviewSortOrder: reviewSortOrder
        )
        let visibleRows = visibleListRows(terminalHeight: terminalHeight)
        let endIndex = min(rows.count, topIndex + visibleRows)
        let repoText = options.repo ?? "current repository"
        let shownRange = rows.isEmpty ? "0 of 0" : "\(topIndex + 1)-\(endIndex) of \(rows.count)"

        let lines: [String]

        if isAttentionViewSelected {
            lines = attentionPullRequestListLines(
                pullRequests: attentionPullRequests,
                selectedIndex: attentionSelectedIndex,
                topIndex: attentionTopIndex,
                visibleRows: visibleRows,
                repoText: repoText,
                message: message,
                terminalWidth: terminalWidth
            )
        } else {
            lines = mainPullRequestListLines(
                rows: rows,
                headers: headers,
                selectedIndex: selectedIndex,
                topIndex: topIndex,
                visibleRows: visibleRows,
                isUpdatedHeaderSelected: isUpdatedHeaderSelected,
                isFilesHeaderSelected: isFilesHeaderSelected,
                isReviewHeaderSelected: isReviewHeaderSelected,
                isMainViewSelected: isMainViewSelected,
                repoText: repoText,
                shownRange: shownRange,
                message: message,
                terminalWidth: terminalWidth
            )
        }

        return bottomAnchored(
            lines,
            inputBar: inputBar,
            terminalWidth: terminalWidth,
            terminalHeight: terminalHeight
        )
    }

    private func mainPullRequestListLines(
        rows: [[String]],
        headers: [String],
        selectedIndex: Int,
        topIndex: Int,
        visibleRows: Int,
        isUpdatedHeaderSelected: Bool,
        isFilesHeaderSelected: Bool,
        isReviewHeaderSelected: Bool,
        isMainViewSelected: Bool,
        repoText: String,
        shownRange: String,
        message: String,
        terminalWidth: Int
    ) -> [String] {
        let widths = mainViewColumnWidths(
            headers: headers,
            rows: rows,
            availableWidth: terminalWidth
        )

        var lines = [
            "pr-buddy  \(repoText)",
            "Showing \(shownRange)  tab switch  / filter  arrows/jk  enter/v view  c checkout  o web  r refresh  q",
            message.isEmpty ? " " : message,
            "",
            "  " + renderHeaderRow(
                headers,
                widths: widths,
                isUpdatedHeaderSelected: isUpdatedHeaderSelected,
                isFilesHeaderSelected: isFilesHeaderSelected,
                isReviewHeaderSelected: isReviewHeaderSelected
            ),
            "  " + widths.map { String(repeating: "-", count: $0) }.joined(separator: "  ")
        ]

        if rows.isEmpty {
            lines.append("  No pull requests matched the current filters.")
            return lines.map { clippedLine($0, to: terminalWidth) }
        }

        for index in topIndex..<min(rows.count, topIndex + visibleRows) {
            let isSelectedRow = !isUpdatedHeaderSelected && !isFilesHeaderSelected && !isReviewHeaderSelected && isMainViewSelected && index == selectedIndex
            let marker = isSelectedRow ? ">" : " "
            let rendered = "\(marker) " + renderRow(rows[index], widths: widths)

            if isSelectedRow {
                lines.append(TUIFormat.inverted(rendered))
            } else {
                lines.append(rendered)
            }
        }

        return lines.map { clippedLine($0, to: terminalWidth) }
    }

    private func attentionPullRequestListLines(
        pullRequests: [PullRequest],
        selectedIndex: Int,
        topIndex: Int,
        visibleRows: Int,
        repoText: String,
        message: String,
        terminalWidth: Int
    ) -> [String] {
        let rows = attentionTableRows(for: pullRequests)
        let widths = attentionColumnWidths(rows: rows, availableWidth: max(20, terminalWidth - 2))
        let endIndex = min(rows.count, topIndex + visibleRows)
        let shownRange = rows.isEmpty ? "0 of 0" : "\(topIndex + 1)-\(endIndex) of \(rows.count)"

        var lines = [
            "pr-buddy  \(repoText)",
            "involves:@me \(shownRange)  tab main  / filter  arrows/jk  view enter/v  checkout c  open o  refresh r  q",
            message.isEmpty ? " " : message,
            "",
            "  involves:@me (\(rows.count))",
            "  " + renderAttentionCells(attentionHeaders, widths: widths)
        ]

        if rows.isEmpty {
            lines.append("  No open pull requests involve you.")
            return lines.map { clippedLine($0, to: terminalWidth) }
        }

        for index in topIndex..<min(rows.count, topIndex + visibleRows) {
            let rendered = "  " + renderAttentionCells(rows[index], widths: widths)

            if index == selectedIndex {
                lines.append(TUIFormat.inverted(">\(rendered.dropFirst())"))
            } else {
                lines.append(rendered)
            }
        }

        return lines.map { clippedLine($0, to: terminalWidth) }
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
                updatedSummary(for: pullRequest),
                fileSummary(for: pullRequest),
                pullRequest.statusSummary,
                pullRequest.reviewSummary,
                pullRequest.labelSummary.isEmpty ? "-" : pullRequest.labelSummary,
                pullRequest.title,
                pullRequest.author?.login ?? "-"
            ]
        }
    }

    func updatedSummary(for pullRequest: PullRequest) -> String {
        guard
            let updatedAt = pullRequest.updatedAt,
            let updatedDate = updatedAtParser.date(from: updatedAt)
        else {
            return "-"
        }

        let elapsedTime = max(0, now().timeIntervalSince(updatedDate))

        guard elapsedTime >= 60 else {
            return "now"
        }

        guard let components = updatedComponentsFormatter.string(from: elapsedTime)?.split(separator: " ").first else {
            return "-"
        }

        let value = String(components)

        if elapsedTime >= 365 * 24 * 60 * 60 {
            return "\(value)y"
        } else if elapsedTime >= 30 * 24 * 60 * 60 {
            return "\(value)mo"
        } else if elapsedTime >= 7 * 24 * 60 * 60 {
            return "\(value)w"
        } else if elapsedTime >= 24 * 60 * 60 {
            return "\(value)d"
        } else if elapsedTime >= 60 * 60 {
            return "\(value)h"
        }

        return "\(value)m"
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
        TUIFormat.columnWidths(headers: headers, rows: rows, maximumWidths: maximumWidths)
    }

    func renderRow(_ row: [String], widths: [Int]) -> String {
        row.enumerated()
            .map { column, value in
                let text = truncate(value, to: widths[column])
                let paddedText = TUIFormat.padded(text, to: widths[column])

                switch TableColumn(index: column) {
                case .updated, .author:
                    return TUIFormat.colorized(paddedText, color: TUIFormat.Color.metadata)
                case .files:
                    return colorizedFileSummary(paddedText)
                case .status:
                    return colorizedStatus(paddedText)
                case .review:
                    return colorizedReviewSummary(paddedText)
                case .labels, .title, .unknown:
                    return paddedText
                }
            }
            .joined(separator: "  ")
    }

    func headers(
        updatedSortOrder: UpdatedSortOrder,
        fileSortOrder: FileSortOrder,
        reviewSortOrder: ReviewSortOrder
    ) -> [String] {
        var headers = self.headers

        switch updatedSortOrder {
        case .none:
            headers[0] = "Updated  "
        case .ascending:
            headers[0] = "Updated ^"
        case .descending:
            headers[0] = "Updated v"
        }

        switch fileSortOrder {
        case .none:
            headers[1] = "Files"
        case .ascending:
            headers[1] = "Files ^"
        case .descending:
            headers[1] = "Files v"
        }

        switch reviewSortOrder {
        case .none:
            headers[3] = "Review  "
        case .ascending:
            headers[3] = "Review ^"
        case .descending:
            headers[3] = "Review v"
        }

        return headers
    }

    func renderHeaderRow(
        _ row: [String],
        widths: [Int],
        isUpdatedHeaderSelected: Bool,
        isFilesHeaderSelected: Bool,
        isReviewHeaderSelected: Bool
    ) -> String {
        row.enumerated()
            .map { column, value in
                let text = truncate(value, to: widths[column])
                let paddedText = TUIFormat.padded(text, to: widths[column])

                if column == 0, isUpdatedHeaderSelected {
                    return TUIFormat.inverted(paddedText)
                }

                if column == 1, isFilesHeaderSelected {
                    return TUIFormat.inverted(paddedText)
                }

                if column == 3, isReviewHeaderSelected {
                    return TUIFormat.inverted(paddedText)
                }

                return paddedText
            }
            .joined(separator: "  ")
    }

    func colorizedStatus(_ value: String) -> String {
        TUIFormat.colorizedStatus(value)
    }

    func colorizedReviewSummary(_ value: String) -> String {
        value.map { character in
            switch character {
            case "✓":
                return TUIFormat.colorized(String(character), color: TUIFormat.Color.openStatus)
            case "✕":
                return TUIFormat.colorized(String(character), color: TUIFormat.Color.closedStatus)
            case "🗨", "🗨︎":
                return TUIFormat.colorized(String(character), color: TUIFormat.Color.metadata)
            default:
                return String(character)
            }
        }
        .joined()
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
        visibleListRows(terminalHeight: terminalHeight())
    }

    private func visibleListRows(terminalHeight: Int) -> Int {
        max(1, terminalHeight - 8)
    }

    private func mainViewColumnWidths(
        headers: [String],
        rows: [[String]],
        availableWidth: Int
    ) -> [Int] {
        let minimumWidths = [9, 5, 4, 8, 6, 5, 6]
        let separatorWidth = (headers.count - 1) * 2 + 2
        var responsiveMaximumWidths = maximumWidths
        responsiveMaximumWidths[5] = max(
            responsiveMaximumWidths[5],
            availableWidth - separatorWidth
        )
        var widths = columnWidths(
            headers: headers,
            rows: rows,
            maximumWidths: responsiveMaximumWidths
        )
        var overflow = widths.reduce(0, +) + separatorWidth - availableWidth

        for column in [5, 4, 6, 3, 1, 2, 0] where overflow > 0 {
            let minimumWidth = min(widths[column], minimumWidths[column])
            let shrinkAmount = min(overflow, widths[column] - minimumWidth)
            widths[column] -= shrinkAmount
            overflow -= shrinkAmount
        }

        return widths
    }

    private func attentionColumnWidths(rows: [[String]], availableWidth: Int) -> [Int] {
        let maximumWidths = [max(16, availableWidth - 10), 8]
        return columnWidths(headers: attentionHeaders, rows: rows, maximumWidths: maximumWidths)
    }

    private func renderAttentionCells(_ row: [String], widths: [Int]) -> String {
        row.enumerated()
            .map { column, value in
                let text = truncate(value, to: widths[column])
                let paddedText = TUIFormat.padded(text, to: widths[column])
                return column == 1 ? colorizedStatus(paddedText) : paddedText
            }
            .joined(separator: "  ")
    }

    private func clippedLine(_ line: String, to terminalWidth: Int) -> String {
        TUIFormat.clipped(line, to: max(1, terminalWidth))
    }

    private func bottomAnchored(
        _ lines: [String],
        inputBar: String?,
        terminalWidth: Int,
        terminalHeight: Int
    ) -> [String] {
        guard let inputBar else {
            return lines
        }

        let contentHeight = max(0, terminalHeight - 1)
        var anchoredLines = Array(lines.prefix(contentHeight))
        anchoredLines.append(contentsOf: repeatElement("", count: max(0, contentHeight - anchoredLines.count)))
        anchoredLines.append(clippedLine(inputBar, to: terminalWidth))
        return anchoredLines
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
