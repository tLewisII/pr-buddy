//
//  TUIRightPaneRenderer.swift
//  pr-buddy
//
//  Created by Terry Lewis II on 5/31/26.
//

import Foundation

final class TUIRightPaneRenderer {
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
        let maximumWidths = [max(16, availableWidth - 10), 8]
        return TUIFormat.columnWidths(headers: headers, rows: rows, maximumWidths: maximumWidths)
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

        return TUIFormat.inverted(">\(rendered.dropFirst())")
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
                let paddedText = TUIFormat.padded(text, to: widths[column])

                if column == 1 {
                    return TUIFormat.colorizedStatus(paddedText)
                }

                return paddedText
            }
            .joined(separator: "  ")
    }

    private func truncate(_ value: String, to width: Int) -> String {
        TUIFormat.truncate(value, to: width)
    }

    private func centeredRowIndex(in visibleRows: Int) -> Int {
        max(0, visibleRows / 2)
    }

    private func centeredText(_ text: String, width: Int) -> String {
        TUIFormat.centeredText(text, width: width)
    }
}
