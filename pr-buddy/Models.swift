//
//  Models.swift
//  pr-buddy
//
//  Created by Terry Lewis II on 5/31/26.
//

import Foundation

struct Options {
    var repo: String?
    var search: String?
    var labels: [String] = []
    var statuses: [String] = []
    var minChangedFiles: Int?
    var maxChangedFiles: Int?
    var minReviews: Int?
    var maxReviews: Int?
    var limit = 50
    var showMyPRs = false
#if DEBUG
    var debugJSONPath: String?
#endif
}

struct CountRange {
    let min: Int?
    let max: Int?

    func contains(_ value: Int) -> Bool {
        if let min, value < min {
            return false
        }

        if let max, value > max {
            return false
        }

        return true
    }

}

extension Options {
    var changedFilesRange: CountRange {
        CountRange(min: minChangedFiles, max: maxChangedFiles)
    }

    var reviewsRange: CountRange {
        CountRange(min: minReviews, max: maxReviews)
    }
}

struct PullRequest: Decodable {
    struct Author: Decodable {
        let login: String?
    }

    struct Label: Decodable {
        let name: String
    }

    struct Review: Decodable {
        let state: String?

        init(state: String? = nil) {
            self.state = state
        }
    }

    let number: Int
    let title: String
    let author: Author?
    let headRefName: String?
    let baseRefName: String?
    let state: String
    let isDraft: Bool
    let reviewDecision: String?
    let changedFiles: Int?
    let additions: Int?
    let deletions: Int?
    let labels: [Label]
    let reviews: [Review]?
    let updatedAt: String?
    let url: String

    var statusSummary: String {
        if isDraft {
            return "draft"
        }

        return state.lowercased()
    }

    var reviewSummary: String {
        guard reviewCount > 0 else {
            return "0"
        }

        let icons = reviewStatusIcons
        guard !icons.isEmpty else {
            return String(reviewCount)
        }

        return ([String(reviewCount)] + icons).joined(separator: " ")
    }

    var labelSummary: String {
        labels.map(\.name).joined(separator: ", ")
    }

    var reviewCount: Int {
        reviews?.count ?? 0
    }

    private var reviewStatusIcons: [String] {
        let reviewStates = reviews?.compactMap(\.state) ?? []
        let states = reviewStates.isEmpty ? fallbackReviewStates : reviewStates

        return states.compactMap { state in
            switch normalizedReviewState(state) {
            case "approved":
                return "✓"
            case "changes requested":
                return "✕"
            case "commented":
                return "🗨"
            default:
                return nil
            }
        }
    }

    private var fallbackReviewStates: [String] {
        guard let reviewDecision else {
            return []
        }

        return Array(repeating: reviewDecision, count: reviewCount)
    }

    private func normalizedReviewState(_ state: String) -> String {
        state
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }
}

enum FileSortOrder: Equatable {
    case none
    case ascending
    case descending

    var next: FileSortOrder {
        switch self {
        case .none:
            return .ascending
        case .ascending:
            return .descending
        case .descending:
            return .none
        }
    }

    var description: String {
        switch self {
        case .none:
            return "original order"
        case .ascending:
            return "fewest files first"
        case .descending:
            return "most files first"
        }
    }
}

enum InteractiveFocus {
    case filesHeader
    case mainRow
    case attentionRow
}

enum AppError: Error, CustomStringConvertible {
    case commandFailed(String)
    case decodingFailed(String)

    var description: String {
        switch self {
        case .commandFailed(let message), .decodingFailed(let message):
            return message
        }
    }
}

enum InputKey {
    case up
    case down
    case left
    case right
    case enter
    case h
    case j
    case k
    case l
    case v
    case c
    case o
    case r
    case q
    case unknown
}

struct CommandResult {
    let exitCode: Int32
    let stdoutData: Data
    let stderrData: Data

    var stdout: String {
        String(data: stdoutData, encoding: .utf8) ?? ""
    }

    var stderr: String {
        String(data: stderrData, encoding: .utf8) ?? ""
    }
}
