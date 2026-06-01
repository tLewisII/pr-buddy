enum PullRequestFilter {
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

    static func sorted(_ pullRequests: [PullRequest], fileSortOrder: FileSortOrder) -> [PullRequest] {
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
}
