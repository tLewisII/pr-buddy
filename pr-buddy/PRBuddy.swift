//
//  main.swift
//  pr-buddy
//
//  Created by Terry Lewis II on 5/25/26.
//

import ArgumentParser
import Darwin

struct PRBuddy {
    static func main() {
        PRBuddyCommand.main()
    }

    static func run(options: Options) throws {
        let pullRequests = try GitHubClient.fetchMainPullRequests(options: options)

        if isatty(STDIN_FILENO) != 0 {
            let attentionPullRequests = try GitHubClient.fetchAttentionPullRequests(options: options)
            try InteractiveSession.run(
                initialPullRequests: pullRequests,
                initialAttentionPullRequests: attentionPullRequests,
                options: options
            )
        } else if pullRequests.isEmpty {
            print("No pull requests matched the current filters.")
        } else {
            TUIRenderer().printTable(pullRequests)
        }
    }

    static func parseOptions(_ arguments: [String]) throws -> Options {
        try PRBuddyCommand.parse(arguments).parsedOptions()
    }
}

private struct PRBuddyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr-buddy",
        abstract: "Fetch pull requests with `gh pr list` and open an interactive PR picker when run in a terminal.",
        discussion: """
        Interactive keys:
          /              Filter PRs by text or fields.
          arrows, j/k    Move selection.
          tab            Toggle main and involves:@me views.
          enter          Open selected PR in the browser.
          c              Checkout selected PR.
          r              Refresh PRs.
          q              Quit.

        Interactive filter fields:
          ctrl-u          Clear the active filter.
          status:draft    Match status or review decision.
          label:bug,ui    Require labels.
          files:2..8      Match changed-file count or range.
          reviews:1..     Match review count or range.
        """
    )

    @Option(name: [.customLong("repo"), .customShort("R")], help: "GitHub repository to query. Defaults to the current repo.")
    var repo: String?

    @Option(name: [.customLong("search"), .customShort("s")], help: "Pass a GitHub search query to `gh pr list --search`.")
    var search: String?

    @Option(name: [.customLong("label"), .customShort("l")], help: "Require a label. May be repeated or comma-separated.")
    var labels: [String] = []

    @Option(name: .customLong("status"), help: "Match open, closed, merged, draft, ready, approved, changes_requested, or review_required. May be repeated or comma-separated.")
    var statuses: [String] = []

    @Option(name: .customLong("min-files"), help: "Minimum changed files.")
    var minChangedFiles: Int?

    @Option(name: .customLong("max-files"), help: "Maximum changed files.")
    var maxChangedFiles: Int?

    @Option(name: .customLong("changed-files"), help: "Changed files count or range, e.g. 3, 2..8, ..5, or 10..")
    var changedFiles: String?

    @Option(name: .customLong("reviews"), help: "Review count or range, e.g. 3, 2..8, ..5, or 10..")
    var reviews: String?

    @Option(name: .customLong("limit"), help: "Maximum PRs to fetch before local filters.")
    var limit = 50

#if DEBUG
    @Option(name: .customLong("debug-json"), help: "DEBUG only: read pull request JSON from a local file instead of running `gh pr list`.")
    var debugJSONPath: String?
#endif

    mutating func validate() throws {
        _ = try parsedOptions()
    }

    func run() throws {
        try PRBuddy.run(options: parsedOptions())
    }

    func parsedOptions() throws -> Options {
        var options = Options()
        options.repo = repo
        options.search = search
        options.labels = OptionsParser.splitCSV(labels)
        options.statuses = OptionsParser.splitCSV(statuses)
        options.minChangedFiles = minChangedFiles
        options.maxChangedFiles = maxChangedFiles
        options.limit = limit
#if DEBUG
        options.debugJSONPath = debugJSONPath
#endif

        if let changedFiles {
            try OptionsParser.applyChangedFilesRange(changedFiles, to: &options)
        }

        if let reviews {
            try OptionsParser.applyReviewsRange(reviews, to: &options)
        }

        try OptionsParser.validate(options)
        return options
    }
}

extension PRBuddy {
    static func validateOptions(_ options: Options) throws {
        try OptionsParser.validate(options)
    }

    static func pullRequestListArguments(options: Options) -> [String] {
        GitHubClient.pullRequestListArguments(options: options)
    }

    static func attentionPullRequestListArguments(options: Options) -> [String] {
        GitHubClient.attentionPullRequestListArguments(options: options)
    }

    static func matchesFilters(_ pullRequest: PullRequest, options: Options) -> Bool {
        PullRequestFilter.matches(pullRequest, options: options)
    }

    static func statusTokens(for pullRequest: PullRequest) -> [String] {
        PullRequestFilter.statusTokens(for: pullRequest)
    }

    static func normalized(_ value: String) -> String {
        PullRequestFilter.normalized(value)
    }

    static func sortedPullRequests(
        _ pullRequests: [PullRequest],
        fileSortOrder: FileSortOrder,
        updatedSortOrder: UpdatedSortOrder = .none,
        reviewSortOrder: ReviewSortOrder = .none
    ) -> [PullRequest] {
        PullRequestFilter.sorted(
            pullRequests,
            fileSortOrder: fileSortOrder,
            updatedSortOrder: updatedSortOrder,
            reviewSortOrder: reviewSortOrder
        )
    }

#if DEBUG
    static func debugCommandResult(arguments: [String], jsonPath: String) -> CommandResult {
        GitHubClient.debugCommandResult(arguments: arguments, jsonPath: jsonPath)
    }
#endif
}

#if !TESTING
public enum PRBuddyApp {
    public static func main() {
        PRBuddy.main()
    }
}
#endif
