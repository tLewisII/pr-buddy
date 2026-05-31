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
        options: Options,
        message: String
    ) {
        let rows = tableRows(for: pullRequests)
        let widths = columnWidths(headers: headers, rows: rows)
        let visibleRows = max(1, terminalHeight() - 8)
        let endIndex = min(rows.count, topIndex + visibleRows)
        let repoText = options.repo ?? "current repository"
        let shownRange = rows.isEmpty ? "0 of 0" : "\(topIndex + 1)-\(endIndex) of \(rows.count)"

        var lines = [
            "pr-buddy  \(repoText)",
            "Showing \(shownRange).  arrows/j/k move  enter/v view  c checkout  o open  r refresh  q quit",
            message.isEmpty ? " " : message,
            "",
            "  " + renderRow(headers, widths: widths),
            "  " + widths.map { String(repeating: "-", count: $0) }.joined(separator: "  ")
        ]

        if rows.isEmpty {
            lines.append("  No pull requests matched the current filters.")
            drawListLines(lines)
            return
        }

        for index in topIndex..<endIndex {
            let marker = index == selectedIndex ? ">" : " "
            let rendered = "\(marker) " + renderRow(rows[index], widths: widths)

            if index == selectedIndex {
                lines.append("\u{001B}[7m\(rendered)\u{001B}[0m")
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
        headers.indices.map { column in
            let contentWidth = ([headers[column]] + rows.map { $0[column] })
                .map(\.count)
                .max() ?? headers[column].count

            return min(maximumWidths[column], max(headers[column].count, contentWidth))
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
                default:
                    return paddedText
                }
            }
            .joined(separator: "  ")
    }

    private func colorized(_ value: String, color: String) -> String {
        color + value + defaultForegroundColor
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
