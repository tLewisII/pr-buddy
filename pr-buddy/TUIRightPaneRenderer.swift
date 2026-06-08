//
//  TUIRightPaneRenderer.swift
//  pr-buddy
//
//  Created by Terry Lewis II on 5/31/26.
//

import Foundation

final class TUIRightPaneRenderer {
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
        "involves:@me (\(count))"
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

}
