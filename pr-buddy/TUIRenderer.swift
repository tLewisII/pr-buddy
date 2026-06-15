//
//  TUIRenderer.swift
//  pr-buddy
//
//  Created by Terry Lewis II on 5/30/26.
//

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
    private let maximumWidths = [9, 18, 8, 18, 36, 72, 32]
    private let now: () -> Date
    private let updatedAtParser = ISO8601DateFormatter()
    private let updatedComponentsFormatter = DateComponentsFormatter()
    private let screenWriter: ScreenWriter

    init(
        now: @escaping () -> Date = Date.init,
        screenWriter: ScreenWriter = ScreenWriter()
    ) {
        self.now = now
        self.screenWriter = screenWriter
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
        inputBar: String? = nil,
        commandPopup: SlashCommandPopup? = nil,
        terminalSize: TerminalSize? = nil,
        forceRedraw: Bool = false
    ) {
        let terminalSize = terminalSize ?? .current()
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
            commandPopup: commandPopup,
            terminalWidth: terminalSize.columns,
            terminalHeight: terminalSize.rows
        )

        screenWriter.draw(
            TerminalFrame(lines: lines, size: terminalSize),
            force: forceRedraw
        )
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
        commandPopup: SlashCommandPopup? = nil,
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
            commandPopup: commandPopup,
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
        commandPopup: SlashCommandPopup?,
        terminalWidth: Int,
        terminalHeight: Int
    ) -> [String] {
        let activePullRequests = isAttentionViewSelected ? attentionPullRequests : pullRequests
        let rows = tableRows(for: activePullRequests)
        let headers = headers(
            updatedSortOrder: updatedSortOrder,
            fileSortOrder: fileSortOrder,
            reviewSortOrder: reviewSortOrder
        )
        let activeSelectedIndex = isAttentionViewSelected ? attentionSelectedIndex : selectedIndex
        let activeTopIndex = isAttentionViewSelected ? attentionTopIndex : topIndex
        let visiblePopupRows = commandPopup.map {
            visibleCommandRows(
                terminalHeight: terminalHeight,
                commandCount: max(1, $0.commands.count)
            )
        } ?? 0
        let visibleRows = visibleListRows(
            terminalHeight: terminalHeight,
            reservedBottomRows: visiblePopupRows
        )
        let endIndex = min(rows.count, activeTopIndex + visibleRows)
        let repoText = options.repo ?? "current repository"
        let shownRange = rows.isEmpty ? "0 of 0" : "\(activeTopIndex + 1)-\(endIndex) of \(rows.count)"

        let lines = mainPullRequestListLines(
            rows: rows,
            headers: headers,
            selectedIndex: activeSelectedIndex,
            topIndex: activeTopIndex,
            visibleRows: visibleRows,
            isUpdatedHeaderSelected: isUpdatedHeaderSelected,
            isFilesHeaderSelected: isFilesHeaderSelected,
            isReviewHeaderSelected: isReviewHeaderSelected,
            isListSelected: isMainViewSelected || isAttentionViewSelected,
            repoText: repoText,
            shownRange: shownRange,
            message: message,
            terminalWidth: terminalWidth
        )

        return bottomAnchored(
            lines,
            inputBar: inputBar,
            commandPopup: commandPopup,
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
        isListSelected: Bool,
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
            "Showing \(shownRange)  tab switch  / commands  arrows/jk  enter web  c checkout  r refresh  q",
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
            let isSelectedRow = !isUpdatedHeaderSelected && !isFilesHeaderSelected && !isReviewHeaderSelected && isListSelected && index == selectedIndex
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

    func drawCommandResult(title: String, result: CommandResult) {
        clearScreen()
        var output = [title, String(repeating: "-", count: title.count)]

        if !result.stdout.isEmpty {
            output.append(result.stdout)
        }

        if !result.stderr.isEmpty {
            output.append(result.stderr)
        }

        if result.stdout.isEmpty && result.stderr.isEmpty {
            output.append("Command completed with no output.")
        }

        output.append("")
        output.append("Press any key to return to the PR list.")
        writeTerminal(output.joined(separator: "\n"))
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

    func visibleListRows(terminalHeight: Int, reservedBottomRows: Int = 0) -> Int {
        max(1, terminalHeight - 8 - max(0, reservedBottomRows))
    }

    func visibleCommandRows(terminalHeight: Int, commandCount: Int) -> Int {
        min(max(0, commandCount), max(0, terminalHeight - 8))
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

    private func clippedLine(_ line: String, to terminalWidth: Int) -> String {
        TUIFormat.clipped(line, to: max(1, terminalWidth))
    }

    private func bottomAnchored(
        _ lines: [String],
        inputBar: String?,
        commandPopup: SlashCommandPopup?,
        terminalWidth: Int,
        terminalHeight: Int
    ) -> [String] {
        guard let inputBar else {
            return lines
        }

        guard terminalHeight > 0 else {
            return []
        }

        let popupLines = commandPopup.map {
            renderCommandPopup(
                $0,
                visibleRows: visibleCommandRows(
                    terminalHeight: terminalHeight,
                    commandCount: max(1, $0.commands.count)
                ),
                terminalWidth: terminalWidth
            )
        } ?? []
        let contentHeight = max(0, terminalHeight - popupLines.count - 1)
        var anchoredLines = Array(lines.prefix(contentHeight))
        anchoredLines.append(contentsOf: repeatElement("", count: max(0, contentHeight - anchoredLines.count)))
        anchoredLines.append(contentsOf: popupLines)
        anchoredLines.append(clippedLine(inputBar, to: terminalWidth))
        return anchoredLines
    }

    func renderCommandPopup(
        _ popup: SlashCommandPopup,
        visibleRows: Int,
        terminalWidth: Int
    ) -> [String] {
        guard visibleRows > 0 else {
            return []
        }

        guard !popup.commands.isEmpty else {
            return [clippedLine("  No matching commands", to: terminalWidth)]
        }

        let selectedIndex = min(max(popup.selectedIndex, 0), popup.commands.count - 1)
        let maximumTopIndex = max(0, popup.commands.count - visibleRows)
        let topIndex = min(max(popup.topIndex, 0), maximumTopIndex)
        let endIndex = min(popup.commands.count, topIndex + visibleRows)
        let commandWidth = popup.commands.map { $0.name.count + 1 }.max() ?? 1

        return (topIndex..<endIndex).map { index in
            let command = popup.commands[index]
            let name = TUIFormat.padded("/\(command.name)", to: commandWidth)
            let line = clippedLine("  \(name)  \(command.description)", to: terminalWidth)
            return index == selectedIndex ? TUIFormat.inverted(line) : line
        }
    }

    func clearScreen() {
        screenWriter.clearScreen()
    }

    func invalidateScreen() {
        screenWriter.invalidate()
    }

}
