import Foundation

enum PullRequestFilter {
    static func matchesTextQuery(_ pullRequest: PullRequest, query: String) -> Bool {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !terms.isEmpty else {
            return true
        }

        let searchableValues = [
            String(pullRequest.number),
            pullRequest.title,
            pullRequest.author?.login ?? "",
            pullRequest.headRefName ?? "",
            pullRequest.baseRefName ?? "",
            pullRequest.statusSummary,
            pullRequest.reviewDecision ?? ""
        ] + pullRequest.labels.map(\.name)
        let searchableText = searchableValues.map(normalized).joined(separator: " ")

        return terms.allSatisfy { term in
            matchesInteractiveTerm(term, pullRequest: pullRequest, searchableText: searchableText)
        }
    }

    private static func matchesInteractiveTerm(
        _ term: String,
        pullRequest: PullRequest,
        searchableText: String
    ) -> Bool {
        let parts = term.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)

        guard parts.count == 2 else {
            return searchableText.contains(normalized(term))
        }

        let field = normalized(String(parts[0]))
        let value = String(parts[1])

        switch field {
        case "status":
            let requestedStatuses = csvValues(value)
            let availableStatuses = Set(statusTokens(for: pullRequest))
            return !requestedStatuses.isEmpty && !requestedStatuses.isDisjoint(with: availableStatuses)
        case "label":
            let requestedLabels = csvValues(value)
            let availableLabels = Set(pullRequest.labels.map { normalized($0.name) })
            return !requestedLabels.isEmpty && requestedLabels.isSubset(of: availableLabels)
        case "files":
            return countRange(value)?.contains(pullRequest.changedFiles ?? 0) == true
        case "reviews":
            return countRange(value)?.contains(pullRequest.reviewCount) == true
        default:
            return searchableText.contains(normalized(term))
        }
    }

    private static func csvValues(_ value: String) -> Set<String> {
        Set(
            value.split(separator: ",")
                .map { normalized(String($0)) }
                .filter { !$0.isEmpty }
        )
    }

    private static func countRange(_ value: String) -> CountRange? {
        let parts = value.components(separatedBy: "..")

        guard parts.count <= 2 else {
            return nil
        }

        if parts.count == 1 {
            guard let count = nonnegativeInt(parts[0]) else {
                return nil
            }

            return CountRange(min: count, max: count)
        }

        let min = parts[0].isEmpty ? nil : nonnegativeInt(parts[0])
        let max = parts[1].isEmpty ? nil : nonnegativeInt(parts[1])

        guard (parts[0].isEmpty || min != nil), (parts[1].isEmpty || max != nil), min != nil || max != nil else {
            return nil
        }

        if let min, let max, min > max {
            return nil
        }

        return CountRange(min: min, max: max)
    }

    private static func nonnegativeInt(_ value: String) -> Int? {
        guard let integer = Int(value), integer >= 0 else {
            return nil
        }

        return integer
    }

    static func matches(_ pullRequest: PullRequest, options: Options) -> Bool {
        if !options.changedFilesRange.contains(pullRequest.changedFiles ?? 0) {
            return false
        }

        if !options.reviewsRange.contains(pullRequest.reviewCount) {
            return false
        }

        if !options.labels.isEmpty {
            let pullRequestLabels = Set(pullRequest.labels.map { normalized($0.name) })
            let requiredLabels = options.labels.map(normalized)

            guard requiredLabels.allSatisfy({ pullRequestLabels.contains($0) }) else {
                return false
            }
        }

        if !options.statuses.isEmpty {
            let requestedStatuses = Set(options.statuses.map(normalized))
            let availableStatuses = Set(statusTokens(for: pullRequest))

            guard !requestedStatuses.isDisjoint(with: availableStatuses) else {
                return false
            }
        }

        return true
    }

    static func statusTokens(for pullRequest: PullRequest) -> [String] {
        var statuses = [
            normalized(pullRequest.state),
            pullRequest.isDraft ? "draft" : "ready"
        ]

        if let reviewDecision = pullRequest.reviewDecision {
            statuses.append(normalized(reviewDecision))
        }

        return statuses
    }

    static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    static func sorted(
        _ pullRequests: [PullRequest],
        fileSortOrder: FileSortOrder,
        updatedSortOrder: UpdatedSortOrder = .none,
        reviewSortOrder: ReviewSortOrder = .none
    ) -> [PullRequest] {
        if updatedSortOrder != .none {
            return sortedByUpdatedAt(pullRequests, updatedSortOrder: updatedSortOrder)
        }

        if reviewSortOrder != .none {
            return sortedByReviews(pullRequests, reviewSortOrder: reviewSortOrder)
        }

        guard fileSortOrder != .none else {
            return pullRequests
        }

        return pullRequests.enumerated()
            .sorted { lhs, rhs in
                let leftFiles = lhs.element.changedFiles ?? 0
                let rightFiles = rhs.element.changedFiles ?? 0

                if leftFiles == rightFiles {
                    return lhs.offset < rhs.offset
                }

                switch fileSortOrder {
                case .ascending:
                    return leftFiles < rightFiles
                case .descending:
                    return leftFiles > rightFiles
                case .none:
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private static func sortedByReviews(
        _ pullRequests: [PullRequest],
        reviewSortOrder: ReviewSortOrder
    ) -> [PullRequest] {
        pullRequests.enumerated()
            .sorted { lhs, rhs in
                let leftReviews = lhs.element.approvalCount
                let rightReviews = rhs.element.approvalCount

                if leftReviews == rightReviews {
                    return lhs.offset < rhs.offset
                }

                switch reviewSortOrder {
                case .ascending:
                    return leftReviews < rightReviews
                case .descending:
                    return leftReviews > rightReviews
                case .none:
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private static func sortedByUpdatedAt(
        _ pullRequests: [PullRequest],
        updatedSortOrder: UpdatedSortOrder
    ) -> [PullRequest] {
        pullRequests.enumerated()
            .sorted { lhs, rhs in
                let leftDate = updatedDate(for: lhs.element)
                let rightDate = updatedDate(for: rhs.element)

                if leftDate == rightDate {
                    return lhs.offset < rhs.offset
                }

                switch updatedSortOrder {
                case .ascending:
                    return leftDate < rightDate
                case .descending:
                    return leftDate > rightDate
                case .none:
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private static func updatedDate(for pullRequest: PullRequest) -> Date {
        guard
            let updatedAt = pullRequest.updatedAt,
            let date = ISO8601DateFormatter().date(from: updatedAt)
        else {
            return .distantPast
        }

        return date
    }
}
