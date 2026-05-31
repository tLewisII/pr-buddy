//
//  main.swift
//  pr-buddy
//
//  Created by Terry Lewis II on 5/25/26.
//

import Darwin
import Foundation
import ArgumentParser

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
}

struct PullRequest: Decodable {
    struct Author: Decodable {
        let login: String?
    }

    struct Label: Decodable {
        let name: String
    }

    struct Review: Decodable {}

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
        guard let reviewDecision else {
            return "-"
        }

        return reviewDecision
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }

    var labelSummary: String {
        labels.map(\.name).joined(separator: ", ")
    }

    var reviewCount: Int {
        reviews?.count ?? 0
    }
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

struct PRBuddy {
    static func main() {
        PRBuddyCommand.main()
    }

    static func run(options: Options) throws {
        let arguments = pullRequestListArguments(options: options)
        let pullRequests = try fetchPullRequests(arguments: arguments)
            .filter { matchesFilters($0, options: options) }

        if pullRequests.isEmpty {
            print("No pull requests matched the current filters.")
            return
        }

        if isatty(STDIN_FILENO) != 0 {
            try runInteractiveTUI(initialPullRequests: pullRequests, options: options)
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
          arrows, j/k    Move selection.
          enter, v       View selected PR details.
          c              Checkout selected PR.
          o              Open selected PR in the browser.
          r              Refresh PRs.
          q              Quit.
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
        options.labels = labels.flatMap(PRBuddy.splitCSV)
        options.statuses = statuses.flatMap(PRBuddy.splitCSV)
        options.minChangedFiles = minChangedFiles
        options.maxChangedFiles = maxChangedFiles
        options.limit = limit

        if let changedFiles {
            try PRBuddy.parseChangedFilesRange(changedFiles, into: &options)
        }

        if let reviews {
            try PRBuddy.parseReviewsRange(reviews, into: &options)
        }

        try PRBuddy.validateOptions(options)
        return options
    }
}

extension PRBuddy {
    static func validateOptions(_ options: Options) throws {
        if let minChangedFiles = options.minChangedFiles,
           let maxChangedFiles = options.maxChangedFiles,
           minChangedFiles > maxChangedFiles {
            throw ValidationError("--min-files cannot be greater than --max-files.")
        }

        if let minReviews = options.minReviews,
           let maxReviews = options.maxReviews,
           minReviews > maxReviews {
            throw ValidationError("--reviews minimum cannot be greater than maximum.")
        }

        if options.limit < 1 {
            throw ValidationError("--limit must be greater than zero.")
        }

        if let repo = options.repo, repo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError("--repo cannot be empty.")
        }
    }

    fileprivate static func splitCSV(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseInt(_ value: String, option: String) throws -> Int {
        guard let integer = Int(value) else {
            throw ValidationError("\(option) expects a number.")
        }

        return integer
    }

    fileprivate static func parseChangedFilesRange(_ value: String, into options: inout Options) throws {
        let range = try parseIntRange(value, option: "--changed-files")
        options.minChangedFiles = range.min
        options.maxChangedFiles = range.max
    }

    fileprivate static func parseReviewsRange(_ value: String, into options: inout Options) throws {
        let range = try parseIntRange(value, option: "--reviews")
        options.minReviews = range.min
        options.maxReviews = range.max
    }

    private static func parseIntRange(_ value: String, option: String) throws -> (min: Int?, max: Int?) {
        if value.contains("...") {
            throw ValidationError("\(option) uses two dots, for example 2..8.")
        }

        let parts = value.components(separatedBy: "..")

        switch parts.count {
        case 1:
            let count = try parseInt(parts[0], option: option)
            return (count, count)
        case 2:
            var min: Int?
            var max: Int?

            if !parts[0].isEmpty {
                min = try parseInt(parts[0], option: option)
            }

            if !parts[1].isEmpty {
                max = try parseInt(parts[1], option: option)
            }

            return (min, max)
        default:
            throw ValidationError("\(option) expects a number or range, for example 3, 2..8, ..5, or 10..")
        }
    }

    static func pullRequestListArguments(options: Options) -> [String] {
        let baseArguments = [
            "pr",
            "list",
            "--state",
            "all",
            "--limit",
            String(options.limit),
            "--json",
            "number,title,author,headRefName,baseRefName,state,isDraft,reviewDecision,changedFiles,additions,deletions,labels,reviews,updatedAt,url"
        ]

        let repoArguments = options.repo.flatMap { $0.isEmpty ? nil : ["--repo", $0] } ?? []
        let searchArguments = options.search.map { $0.isEmpty ? [] : ["--search", $0] } ?? []
        let labelArguments = options.labels.flatMap { ["--label", $0] }

        return baseArguments + repoArguments + searchArguments + labelArguments
    }

    private static func fetchPullRequests(arguments: [String]) throws -> [PullRequest] {
        let result = try runCommand("gh", arguments: arguments)

        guard result.exitCode == 0 else {
            throw AppError.commandFailed(result.stderr.isEmpty ? "gh pr list failed." : result.stderr)
        }

        do {
            return try JSONDecoder().decode([PullRequest].self, from: result.stdoutData)
        } catch {
            throw AppError.decodingFailed("Could not parse `gh pr list` output: \(error)")
        }
    }

    static func matchesFilters(_ pullRequest: PullRequest, options: Options) -> Bool {
        if let minChangedFiles = options.minChangedFiles,
           (pullRequest.changedFiles ?? 0) < minChangedFiles {
            return false
        }

        if let maxChangedFiles = options.maxChangedFiles,
           (pullRequest.changedFiles ?? 0) > maxChangedFiles {
            return false
        }

        if let minReviews = options.minReviews,
           pullRequest.reviewCount < minReviews {
            return false
        }

        if let maxReviews = options.maxReviews,
           pullRequest.reviewCount > maxReviews {
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

    private static func runInteractiveTUI(initialPullRequests: [PullRequest], options: Options) throws {
        let terminalMode = try RawTerminalMode()
        let renderer = TUIRenderer()
        defer {
            terminalMode.restore()
            renderer.showCursor()
            renderer.clearScreen()
        }

        var pullRequests = initialPullRequests
        var selectedIndex = 0
        var topIndex = 0
        var message = "Fetched \(pullRequests.count) pull request\(pullRequests.count == 1 ? "" : "s")."

        renderer.hideCursor()

        while true {
            if pullRequests.isEmpty {
                selectedIndex = 0
                topIndex = 0
            } else {
                selectedIndex = min(max(selectedIndex, 0), pullRequests.count - 1)
                let visibleRows = max(1, renderer.terminalHeight() - 8)

                if selectedIndex < topIndex {
                    topIndex = selectedIndex
                } else if selectedIndex >= topIndex + visibleRows {
                    topIndex = selectedIndex - visibleRows + 1
                }
            }

            renderer.drawPullRequestList(
                pullRequests: pullRequests,
                selectedIndex: selectedIndex,
                topIndex: topIndex,
                options: options,
                message: message
            )

            switch readKey() {
            case .up, .k:
                selectedIndex = max(0, selectedIndex - 1)
                message = ""
            case .down, .j:
                selectedIndex = min(max(0, pullRequests.count - 1), selectedIndex + 1)
                message = ""
            case .enter, .v:
                guard !pullRequests.isEmpty else {
                    message = "No pull requests to view."
                    continue
                }

                renderer.drawCommandResult(
                    title: "PR #\(pullRequests[selectedIndex].number)",
                    result: try runPRCommand(["view", String(pullRequests[selectedIndex].number)], repo: options.repo)
                )
                _ = readKey()
                message = "Returned from details."
            case .c:
                guard !pullRequests.isEmpty else {
                    message = "No pull requests to checkout."
                    continue
                }

                renderer.drawCommandResult(
                    title: "Checkout #\(pullRequests[selectedIndex].number)",
                    result: try runPRCommand(["checkout", String(pullRequests[selectedIndex].number)], repo: options.repo)
                )
                _ = readKey()
                message = "Checkout command finished."
            case .o:
                guard !pullRequests.isEmpty else {
                    message = "No pull requests to open."
                    continue
                }

                let result = try runPRCommand(["view", String(pullRequests[selectedIndex].number), "--web"], repo: options.repo)
                message = result.exitCode == 0 ? "Opened #\(pullRequests[selectedIndex].number) in browser." : result.stderr
            case .r:
                let arguments = pullRequestListArguments(options: options)
                pullRequests = try fetchPullRequests(arguments: arguments)
                    .filter { matchesFilters($0, options: options) }
                selectedIndex = min(selectedIndex, max(0, pullRequests.count - 1))
                message = "Refreshed \(pullRequests.count) pull request\(pullRequests.count == 1 ? "" : "s")."
            case .q:
                return
            case .unknown:
                message = "Use arrows/j/k to move, enter/v to view, c to checkout, o to open, r to refresh, q to quit."
            }
        }
    }

    private static func runPRCommand(_ arguments: [String], repo: String?) throws -> CommandResult {
        let repoArguments = repo.flatMap { $0.isEmpty ? nil : ["--repo", $0] } ?? []
        let ghArguments = ["pr"] + arguments + repoArguments
        return try runCommand("gh", arguments: ghArguments)
    }

    private static func runCommand(_ executable: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw AppError.commandFailed("Could not run `\(executable)`: \(error.localizedDescription)")
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdoutData: stdoutData,
            stderrData: stderrData
        )
    }

}

#if !TESTING
public enum PRBuddyApp {
    public static func main() {
        PRBuddy.main()
    }
}
#endif

enum InputKey {
    case up
    case down
    case enter
    case j
    case k
    case v
    case c
    case o
    case r
    case q
    case unknown
}

final class RawTerminalMode {
    private let original: termios

    init() throws {
        var settings = termios()

        guard tcgetattr(STDIN_FILENO, &settings) == 0 else {
            throw AppError.commandFailed("Could not read terminal settings.")
        }

        original = settings
        settings.c_lflag &= ~tcflag_t(ECHO | ICANON)
        settings.c_iflag &= ~tcflag_t(ICRNL | IXON)

        guard tcsetattr(STDIN_FILENO, TCSANOW, &settings) == 0 else {
            throw AppError.commandFailed("Could not enable interactive terminal mode.")
        }
    }

    func restore() {
        var settings = original
        tcsetattr(STDIN_FILENO, TCSANOW, &settings)
    }
}

func readKey() -> InputKey {
    var byte: UInt8 = 0

    guard read(STDIN_FILENO, &byte, 1) == 1 else {
        return .unknown
    }

    switch byte {
    case 10, 13:
        return .enter
    case 27:
        var sequence = [UInt8](repeating: 0, count: 2)

        guard read(STDIN_FILENO, &sequence, 2) == 2 else {
            return .unknown
        }

        if sequence == [91, 65] {
            return .up
        } else if sequence == [91, 66] {
            return .down
        } else {
            return .unknown
        }
    case 99, 67:
        return .c
    case 106, 74:
        return .j
    case 107, 75:
        return .k
    case 111, 79:
        return .o
    case 113, 81:
        return .q
    case 114, 82:
        return .r
    case 118, 86:
        return .v
    default:
        return .unknown
    }
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
