//
//  main.swift
//  pr-buddy
//
//  Created by Terry Lewis II on 5/25/26.
//

import Darwin
import Foundation
import ArgumentParser

struct PRBuddy {
    static func main() {
        PRBuddyCommand.main()
    }

    static func run(options: Options) throws {
        let arguments = pullRequestListArguments(options: options)
        let pullRequests = try fetchPullRequests(arguments: arguments, options: options)
            .filter { matchesFilters($0, options: options) }

        if isatty(STDIN_FILENO) != 0 {
            let attentionPullRequests = options.showMyPRs
                ? try fetchPullRequests(arguments: attentionPullRequestListArguments(options: options), options: options)
                : []
            try runInteractiveTUI(
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
          arrows, j/k    Move selection.
          enter, v       View selected PR details.
          c              Checkout selected PR.
          o              Open selected PR in the browser.
          r              Refresh PRs.
          q              Quit.
          --show-my-prs   Show a right pane with PRs that involve you.
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

    @Flag(name: .customLong("show-my-prs"), help: "Show a right pane with open PRs that involve you.")
    var showMyPRs = false

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
        options.labels = labels.flatMap(PRBuddy.splitCSV)
        options.statuses = statuses.flatMap(PRBuddy.splitCSV)
        options.minChangedFiles = minChangedFiles
        options.maxChangedFiles = maxChangedFiles
        options.limit = limit
        options.showMyPRs = showMyPRs
#if DEBUG
        options.debugJSONPath = debugJSONPath
#endif

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

#if DEBUG
        if let debugJSONPath = options.debugJSONPath,
           debugJSONPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError("--debug-json cannot be empty.")
        }
#endif
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

    static func attentionPullRequestListArguments(options: Options) -> [String] {
        var attentionOptions = Options()
        attentionOptions.repo = options.repo
        attentionOptions.search = "is:pr is:open involves:@me"
        attentionOptions.limit = options.limit

        return pullRequestListArguments(options: attentionOptions)
    }

    private static func fetchPullRequests(arguments: [String], options: Options) throws -> [PullRequest] {
#if DEBUG
        if let debugJSONPath = options.debugJSONPath {
            return try loadPullRequests(fromJSONFile: debugJSONPath)
        }
#endif

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

#if DEBUG
    private static func loadPullRequests(fromJSONFile path: String) throws -> [PullRequest] {
        let url = URL(fileURLWithPath: path)

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([PullRequest].self, from: data)
        } catch {
            throw AppError.decodingFailed("Could not parse `\(path)`: \(error)")
        }
    }
#endif

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

    static func sortedPullRequests(_ pullRequests: [PullRequest], fileSortOrder: FileSortOrder) -> [PullRequest] {
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

    private static func runInteractiveTUI(
        initialPullRequests: [PullRequest],
        initialAttentionPullRequests: [PullRequest],
        options: Options
    ) throws {
        let terminalMode = try RawTerminalMode()
        let renderer = TUIRenderer()
        defer {
            terminalMode.restore()
            renderer.showCursor()
            renderer.clearScreen()
        }

        var basePullRequests = initialPullRequests
        var fileSortOrder = FileSortOrder.none
        var pullRequests = sortedPullRequests(basePullRequests, fileSortOrder: fileSortOrder)
        var attentionPullRequests = initialAttentionPullRequests
        var focus = options.showMyPRs && pullRequests.isEmpty && !attentionPullRequests.isEmpty ? InteractiveFocus.attentionRow : InteractiveFocus.mainRow
        var selectedIndex = 0
        var attentionSelectedIndex = 0
        var topIndex = 0
        var attentionTopIndex = 0
        var message = fetchedMessage(
            pullRequests: pullRequests,
            attentionPullRequests: attentionPullRequests,
            showMyPRs: options.showMyPRs
        )

        renderer.hideCursor()

        while true {
            keepSelectionVisible(
                pullRequests: pullRequests,
                selectedIndex: &selectedIndex,
                topIndex: &topIndex,
                visibleRows: renderer.visibleListRows()
            )
            if options.showMyPRs {
                keepSelectionVisible(
                    pullRequests: attentionPullRequests,
                    selectedIndex: &attentionSelectedIndex,
                    topIndex: &attentionTopIndex,
                    visibleRows: renderer.visibleListRows()
                )
            }

            renderer.drawPullRequestList(
                pullRequests: pullRequests,
                selectedIndex: selectedIndex,
                topIndex: topIndex,
                isFilesHeaderSelected: focus == .filesHeader,
                isMainPaneSelected: focus == .mainRow,
                fileSortOrder: fileSortOrder,
                attentionPullRequests: attentionPullRequests,
                attentionSelectedIndex: attentionSelectedIndex,
                attentionTopIndex: attentionTopIndex,
                isAttentionPaneSelected: focus == .attentionRow,
                options: options,
                message: message
            )

            let key = readKey()

            switch key {
            case .up, .k:
                if focus == .filesHeader {
                    message = ""
                } else if focus == .attentionRow {
                    attentionSelectedIndex = max(0, attentionSelectedIndex - 1)
                    message = ""
                } else if selectedIndex == 0 {
                    focus = .filesHeader
                    message = ""
                } else {
                    selectedIndex -= 1
                    message = ""
                }
            case .down, .j:
                if focus == .filesHeader {
                    if !pullRequests.isEmpty {
                        focus = .mainRow
                    }
                } else if focus == .attentionRow {
                    attentionSelectedIndex = min(max(0, attentionPullRequests.count - 1), attentionSelectedIndex + 1)
                } else {
                    selectedIndex = min(max(0, pullRequests.count - 1), selectedIndex + 1)
                }
                message = ""
            case .left, .h:
                if options.showMyPRs && focus == .attentionRow {
                    if pullRequests.isEmpty {
                        focus = .filesHeader
                    } else {
                        focus = .mainRow
                    }
                }
                message = ""
            case .right, .l:
                if options.showMyPRs && !attentionPullRequests.isEmpty {
                    focus = .attentionRow
                }
                message = ""
            case .enter:
                if focus == .filesHeader {
                    fileSortOrder = fileSortOrder.next
                    pullRequests = sortedPullRequests(basePullRequests, fileSortOrder: fileSortOrder)
                    selectedIndex = 0
                    topIndex = 0
                    message = "Sorted by files: \(fileSortOrder.description)."
                    continue
                }

                guard let selectedPullRequest = selectedPullRequest(
                    focus: focus,
                    pullRequests: pullRequests,
                    selectedIndex: selectedIndex,
                    attentionPullRequests: attentionPullRequests,
                    attentionSelectedIndex: attentionSelectedIndex
                ) else {
                    message = "No pull requests to view."
                    continue
                }

                renderer.drawCommandResult(
                    title: "PR #\(selectedPullRequest.number)",
                    result: try runPRCommand(["view", String(selectedPullRequest.number)], options: options)
                )
                _ = readKey()
                message = "Returned from details."
            case .v:
                guard focus != .filesHeader else {
                    message = "Press enter on the Files header to change file-count sorting."
                    continue
                }

                guard let selectedPullRequest = selectedPullRequest(
                    focus: focus,
                    pullRequests: pullRequests,
                    selectedIndex: selectedIndex,
                    attentionPullRequests: attentionPullRequests,
                    attentionSelectedIndex: attentionSelectedIndex
                ) else {
                    message = "No pull requests to view."
                    continue
                }

                renderer.drawCommandResult(
                    title: "PR #\(selectedPullRequest.number)",
                    result: try runPRCommand(["view", String(selectedPullRequest.number)], options: options)
                )
                _ = readKey()
                message = "Returned from details."
            case .c:
                guard focus != .filesHeader else {
                    message = "Move to a pull request before checking out."
                    continue
                }

                guard let selectedPullRequest = selectedPullRequest(
                    focus: focus,
                    pullRequests: pullRequests,
                    selectedIndex: selectedIndex,
                    attentionPullRequests: attentionPullRequests,
                    attentionSelectedIndex: attentionSelectedIndex
                ) else {
                    message = "No pull requests to checkout."
                    continue
                }

                renderer.drawCommandResult(
                    title: "Checkout #\(selectedPullRequest.number)",
                    result: try runPRCommand(["checkout", String(selectedPullRequest.number)], options: options)
                )
                _ = readKey()
                message = "Checkout command finished."
            case .o:
                guard focus != .filesHeader else {
                    message = "Move to a pull request before opening it."
                    continue
                }

                guard let selectedPullRequest = selectedPullRequest(
                    focus: focus,
                    pullRequests: pullRequests,
                    selectedIndex: selectedIndex,
                    attentionPullRequests: attentionPullRequests,
                    attentionSelectedIndex: attentionSelectedIndex
                ) else {
                    message = "No pull requests to open."
                    continue
                }

                let result = try runPRCommand(["view", String(selectedPullRequest.number), "--web"], options: options)
                message = result.exitCode == 0 ? "Opened #\(selectedPullRequest.number) in browser." : result.stderr
            case .r:
                let arguments = pullRequestListArguments(options: options)
                let selectedPRNumber = pullRequests.indices.contains(selectedIndex) ? pullRequests[selectedIndex].number : nil
                let selectedAttentionPRNumber = options.showMyPRs && attentionPullRequests.indices.contains(attentionSelectedIndex) ? attentionPullRequests[attentionSelectedIndex].number : nil

                basePullRequests = try fetchPullRequests(arguments: arguments, options: options)
                    .filter { matchesFilters($0, options: options) }
                pullRequests = sortedPullRequests(basePullRequests, fileSortOrder: fileSortOrder)
                attentionPullRequests = options.showMyPRs
                    ? try fetchPullRequests(arguments: attentionPullRequestListArguments(options: options), options: options)
                    : []

                if let selectedPRNumber,
                   let updatedIndex = pullRequests.firstIndex(where: { $0.number == selectedPRNumber }) {
                    selectedIndex = updatedIndex
                } else {
                    selectedIndex = min(selectedIndex, max(0, pullRequests.count - 1))
                }

                if let selectedAttentionPRNumber,
                   let updatedAttentionIndex = attentionPullRequests.firstIndex(where: { $0.number == selectedAttentionPRNumber }) {
                    attentionSelectedIndex = updatedAttentionIndex
                } else {
                    attentionSelectedIndex = min(attentionSelectedIndex, max(0, attentionPullRequests.count - 1))
                }

                if options.showMyPRs && focus == .mainRow && pullRequests.isEmpty && !attentionPullRequests.isEmpty {
                    focus = .attentionRow
                } else if options.showMyPRs && focus == .attentionRow && attentionPullRequests.isEmpty && !pullRequests.isEmpty {
                    focus = .mainRow
                } else if pullRequests.isEmpty && (!options.showMyPRs || attentionPullRequests.isEmpty) {
                    focus = .filesHeader
                }

                message = fetchedMessage(
                    pullRequests: pullRequests,
                    attentionPullRequests: attentionPullRequests,
                    showMyPRs: options.showMyPRs
                )
            case .q:
                return
            case .unknown:
                message = "Use arrows/h/j/k/l to move panes and rows, enter/v view, c checkout, o open, r refresh, q quit."
            }
        }
    }

    private static func keepSelectionVisible(
        pullRequests: [PullRequest],
        selectedIndex: inout Int,
        topIndex: inout Int,
        visibleRows: Int
    ) {
        if pullRequests.isEmpty {
            selectedIndex = 0
            topIndex = 0
            return
        }

        selectedIndex = min(max(selectedIndex, 0), pullRequests.count - 1)

        if selectedIndex < topIndex {
            topIndex = selectedIndex
        } else if selectedIndex >= topIndex + visibleRows {
            topIndex = selectedIndex - visibleRows + 1
        }
    }

    private static func selectedPullRequest(
        focus: InteractiveFocus,
        pullRequests: [PullRequest],
        selectedIndex: Int,
        attentionPullRequests: [PullRequest],
        attentionSelectedIndex: Int
    ) -> PullRequest? {
        if focus == .attentionRow {
            guard attentionPullRequests.indices.contains(attentionSelectedIndex) else {
                return nil
            }

            return attentionPullRequests[attentionSelectedIndex]
        }

        guard pullRequests.indices.contains(selectedIndex) else {
            return nil
        }

        return pullRequests[selectedIndex]
    }

    private static func fetchedMessage(
        pullRequests: [PullRequest],
        attentionPullRequests: [PullRequest],
        showMyPRs: Bool
    ) -> String {
        let pullRequestText = "Fetched \(pullRequests.count) pull request\(pullRequests.count == 1 ? "" : "s")"

        guard showMyPRs else {
            return pullRequestText + "."
        }

        return pullRequestText + " and \(attentionPullRequests.count) attention item\(attentionPullRequests.count == 1 ? "" : "s")."
    }

#if DEBUG
    static func debugCommandResult(arguments: [String], jsonPath: String) -> CommandResult {
        let command = (["gh", "pr"] + arguments).joined(separator: " ")
        let stdout = """
        DEBUG fixture mode is enabled.

        Skipped command:
        \(command)

        Pull request list data is being read from:
        \(jsonPath)
        """

        return CommandResult(
            exitCode: 0,
            stdoutData: Data(stdout.utf8),
            stderrData: Data()
        )
    }
#endif

    private static func runPRCommand(_ arguments: [String], options: Options) throws -> CommandResult {
#if DEBUG
        if let debugJSONPath = options.debugJSONPath {
            return debugCommandResult(arguments: arguments, jsonPath: debugJSONPath)
        }
#endif

        let repoArguments = options.repo.flatMap { $0.isEmpty ? nil : ["--repo", $0] } ?? []
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
        } else if sequence == [91, 67] {
            return .right
        } else if sequence == [91, 68] {
            return .left
        } else {
            return .unknown
        }
    case 99, 67:
        return .c
    case 104, 72:
        return .h
    case 106, 74:
        return .j
    case 107, 75:
        return .k
    case 108, 76:
        return .l
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
