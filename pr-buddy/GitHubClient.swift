import Foundation

enum GitHubClient {
    static func fetchMainPullRequests(options: Options) throws -> [PullRequest] {
        try fetchPullRequests(arguments: pullRequestListArguments(options: options), options: options)
            .filter { PullRequestFilter.matches($0, options: options) }
    }

    static func fetchAttentionPullRequests(options: Options) throws -> [PullRequest] {
        try fetchPullRequests(arguments: attentionPullRequestListArguments(options: options), options: options)
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

    static func runPRCommand(_ arguments: [String], options: Options) throws -> CommandResult {
#if DEBUG
        if let debugJSONPath = options.debugJSONPath {
            return debugCommandResult(arguments: arguments, jsonPath: debugJSONPath)
        }
#endif

        let repoArguments = options.repo.flatMap { $0.isEmpty ? nil : ["--repo", $0] } ?? []
        let ghArguments = ["pr"] + arguments + repoArguments
        return try CommandRunner.run("gh", arguments: ghArguments)
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

    private static func fetchPullRequests(arguments: [String], options: Options) throws -> [PullRequest] {
#if DEBUG
        if let debugJSONPath = options.debugJSONPath {
            return try loadPullRequests(fromJSONFile: debugJSONPath)
        }
#endif

        let result = try CommandRunner.run("gh", arguments: arguments)

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
}

enum CommandRunner {
    static func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        let uniqueIdentifier = UUID().uuidString
        let stdoutURL = temporaryDirectory.appendingPathComponent("pr-buddy-\(uniqueIdentifier)-stdout")
        let stderrURL = temporaryDirectory.appendingPathComponent("pr-buddy-\(uniqueIdentifier)-stderr")

        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? fileManager.removeItem(at: stdoutURL)
            try? fileManager.removeItem(at: stderrURL)
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw AppError.commandFailed("Could not run `\(executable)`: \(error.localizedDescription)")
        }

        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdoutData: stdoutData,
            stderrData: stderrData
        )
    }
}
