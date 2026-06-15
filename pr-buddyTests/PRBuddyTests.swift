import Foundation
import XCTest
@testable import pr_buddy

final class PRBuddyTests: XCTestCase {
    func testParseOptionsAcceptsRepoSearchLabelsStatusAndFileRange() throws {
        let options = try PRBuddy.parseOptions([
            "--repo", "owner/project",
            "--search", "review-requested:@me",
            "--label", "bug,needs review",
            "--status", "draft,approved",
            "--changed-files", "2..8",
            "--reviews", "1..3",
            "--limit", "25"
        ])

        XCTAssertEqual(options.repo, "owner/project")
        XCTAssertEqual(options.search, "review-requested:@me")
        XCTAssertEqual(options.labels, ["bug", "needs review"])
        XCTAssertEqual(options.statuses, ["draft", "approved"])
        XCTAssertEqual(options.minChangedFiles, 2)
        XCTAssertEqual(options.maxChangedFiles, 8)
        XCTAssertEqual(options.minReviews, 1)
        XCTAssertEqual(options.maxReviews, 3)
        XCTAssertEqual(options.limit, 25)
    }

    func testParseOptionsDefaultsSearchToOpenPullRequests() throws {
        let options = try PRBuddy.parseOptions([])

        XCTAssertEqual(options.search, Options.defaultSearch)
    }

#if DEBUG
    func testParseOptionsAcceptsDebugJSONPathInDebugBuilds() throws {
        let options = try PRBuddy.parseOptions(["--debug-json", "fixtures/all-options-prs.json"])

        XCTAssertEqual(options.debugJSONPath, "fixtures/all-options-prs.json")
    }

    func testParseOptionsRejectsEmptyDebugJSONPath() {
        XCTAssertThrowsError(try PRBuddy.parseOptions(["--debug-json", "   "])) { error in
            XCTAssertTrue(String(describing: error).contains("--debug-json cannot be empty"))
        }
    }

    func testDebugCommandResultSkipsGhCommand() {
        let result = PRBuddy.debugCommandResult(
            arguments: ["view", "101"],
            jsonPath: "fixtures/all-options-prs.json"
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("DEBUG fixture mode is enabled."))
        XCTAssertTrue(result.stdout.contains("gh pr view 101"))
        XCTAssertTrue(result.stdout.contains("fixtures/all-options-prs.json"))
        XCTAssertTrue(result.stderr.isEmpty)
    }
#endif

    func testParseOptionsRejectsInvalidFileRange() {
        XCTAssertThrowsError(try PRBuddy.parseOptions(["--min-files", "10", "--max-files", "2"])) { error in
            XCTAssertTrue(String(describing: error).contains("--min-files cannot be greater than --max-files"))
        }
    }

    func testParseOptionsRejectsInvalidChangedFilesRanges() {
        let invalidRanges = [
            ("2...8", "uses two dots"),
            ("2..x", "expects a number"),
            ("1..2..3", "expects a number or range")
        ]

        for (range, expectedMessage) in invalidRanges {
            XCTAssertThrowsError(try PRBuddy.parseOptions(["--changed-files", range])) { error in
                XCTAssertTrue(
                    String(describing: error).contains(expectedMessage),
                    "Expected \(range) to fail with \(expectedMessage), got \(error)"
                )
            }
        }
    }

    func testParseOptionsRejectsInvalidReviewRanges() {
        let invalidRanges = [
            ("2...8", "uses two dots"),
            ("2..x", "expects a number"),
            ("1..2..3", "expects a number or range")
        ]

        for (range, expectedMessage) in invalidRanges {
            XCTAssertThrowsError(try PRBuddy.parseOptions(["--reviews", range])) { error in
                XCTAssertTrue(
                    String(describing: error).contains(expectedMessage),
                    "Expected \(range) to fail with \(expectedMessage), got \(error)"
                )
            }
        }
    }

    func testParseOptionsSupportsExactChangedFileCount() throws {
        let options = try PRBuddy.parseOptions(["--changed-files", "3"])

        XCTAssertEqual(options.minChangedFiles, 3)
        XCTAssertEqual(options.maxChangedFiles, 3)
    }

    func testParseOptionsSupportsExactReviewCount() throws {
        let options = try PRBuddy.parseOptions(["--reviews", "3"])

        XCTAssertEqual(options.minReviews, 3)
        XCTAssertEqual(options.maxReviews, 3)
    }

    func testParseOptionsSupportsOpenEndedChangedFileRanges() throws {
        let maxOnly = try PRBuddy.parseOptions(["--changed-files", "..5"])
        XCTAssertNil(maxOnly.minChangedFiles)
        XCTAssertEqual(maxOnly.maxChangedFiles, 5)

        let minOnly = try PRBuddy.parseOptions(["--changed-files", "10.."])
        XCTAssertEqual(minOnly.minChangedFiles, 10)
        XCTAssertNil(minOnly.maxChangedFiles)
    }

    func testParseOptionsSupportsOpenEndedReviewRanges() throws {
        let maxOnly = try PRBuddy.parseOptions(["--reviews", "..5"])
        XCTAssertNil(maxOnly.minReviews)
        XCTAssertEqual(maxOnly.maxReviews, 5)

        let minOnly = try PRBuddy.parseOptions(["--reviews", "10.."])
        XCTAssertEqual(minOnly.minReviews, 10)
        XCTAssertNil(minOnly.maxReviews)
    }

    func testParseOptionsRejectsInvalidLimitAndEmptyRepo() {
        XCTAssertThrowsError(try PRBuddy.parseOptions(["--limit", "0"])) { error in
            XCTAssertTrue(String(describing: error).contains("--limit must be greater than zero"))
        }

        XCTAssertThrowsError(try PRBuddy.parseOptions(["--repo", "   "])) { error in
            XCTAssertTrue(String(describing: error).contains("--repo cannot be empty"))
        }
    }

    func testPullRequestListArgumentsIncludesGhFilters() {
        var options = Options()
        options.repo = "owner/project"
        options.search = "review-requested:@me"
        options.labels = ["bug", "needs review"]
        options.limit = 25

        XCTAssertEqual(PRBuddy.pullRequestListArguments(options: options), [
            "pr",
            "list",
            "--state",
            "all",
            "--limit",
            "25",
            "--json",
            "number,title,author,headRefName,baseRefName,state,isDraft,reviewDecision,changedFiles,additions,deletions,labels,reviews,updatedAt,url",
            "--repo",
            "owner/project",
            "--search",
            "review-requested:@me",
            "--label",
            "bug",
            "--label",
            "needs review"
        ])
    }

    func testPullRequestListArgumentsIncludesDefaultSearch() {
        let options = Options()

        XCTAssertEqual(PRBuddy.pullRequestListArguments(options: options), [
            "pr",
            "list",
            "--state",
            "all",
            "--limit",
            "50",
            "--json",
            "number,title,author,headRefName,baseRefName,state,isDraft,reviewDecision,changedFiles,additions,deletions,labels,reviews,updatedAt,url",
            "--search",
            Options.defaultSearch
        ])
    }

    func testAttentionPullRequestListArgumentsUsesCurrentRepoAndMeSearchOnly() {
        var options = Options()
        options.repo = "owner/project"
        options.search = "author:someone"
        options.labels = ["bug"]
        options.limit = 25

        XCTAssertEqual(PRBuddy.attentionPullRequestListArguments(options: options), [
            "pr",
            "list",
            "--state",
            "all",
            "--limit",
            "25",
            "--json",
            "number,title,author,headRefName,baseRefName,state,isDraft,reviewDecision,changedFiles,additions,deletions,labels,reviews,updatedAt,url",
            "--repo",
            "owner/project",
            "--search",
            "is:pr is:open involves:@me"
        ])
    }

    func testMatchesFiltersRequiresAllLabelsAndAcceptsMatchingStatus() {
        let pullRequest = makePullRequest(
            isDraft: true,
            reviewDecision: "APPROVED",
            changedFiles: 4,
            labels: ["bug", "needs review"],
            reviews: 2
        )

        var options = Options()
        options.labels = ["BUG", "needs-review"]
        options.statuses = ["approved"]
        options.minChangedFiles = 2
        options.maxChangedFiles = 5
        options.minReviews = 1
        options.maxReviews = 3

        XCTAssertTrue(PRBuddy.matchesFilters(pullRequest, options: options))
    }

    func testMatchesFiltersRejectsPullRequestOutsideChangedFileRange() {
        let pullRequest = makePullRequest(changedFiles: 12)
        var options = Options()
        options.maxChangedFiles = 5

        XCTAssertFalse(PRBuddy.matchesFilters(pullRequest, options: options))
    }

    func testMatchesFiltersRejectsPullRequestBelowChangedFileRange() {
        let pullRequest = makePullRequest(changedFiles: 1)
        var options = Options()
        options.minChangedFiles = 2

        XCTAssertFalse(PRBuddy.matchesFilters(pullRequest, options: options))
    }

    func testMatchesFiltersTreatsMissingChangedFilesAsZero() {
        let pullRequest = makePullRequest(changedFiles: nil)

        var minOptions = Options()
        minOptions.minChangedFiles = 1
        XCTAssertFalse(PRBuddy.matchesFilters(pullRequest, options: minOptions))

        var maxOptions = Options()
        maxOptions.maxChangedFiles = 5
        XCTAssertTrue(PRBuddy.matchesFilters(pullRequest, options: maxOptions))
    }

    func testMatchesFiltersRejectsPullRequestOutsideReviewRange() {
        let pullRequest = makePullRequest(reviews: 4)
        var options = Options()
        options.maxReviews = 3

        XCTAssertFalse(PRBuddy.matchesFilters(pullRequest, options: options))
    }

    func testMatchesFiltersRejectsPullRequestBelowReviewRange() {
        let pullRequest = makePullRequest(reviews: 1)
        var options = Options()
        options.minReviews = 2

        XCTAssertFalse(PRBuddy.matchesFilters(pullRequest, options: options))
    }

    func testMatchesFiltersTreatsMissingReviewsAsZero() {
        let pullRequest = makePullRequest(reviews: nil)

        var minOptions = Options()
        minOptions.minReviews = 1
        XCTAssertFalse(PRBuddy.matchesFilters(pullRequest, options: minOptions))

        var maxOptions = Options()
        maxOptions.maxReviews = 0
        XCTAssertTrue(PRBuddy.matchesFilters(pullRequest, options: maxOptions))
    }

    func testTextFilterMatchesNumberTitleAuthorBranchAndLabels() {
        let pullRequest = makePullRequest(
            number: 142,
            title: "Improve checkout flow",
            author: PullRequest.Author(login: "alexandria"),
            headRefName: "feature/quick-filter",
            labels: ["needs review", "cli"]
        )

        XCTAssertTrue(PullRequestFilter.matchesTextQuery(pullRequest, query: "#142"))
        XCTAssertTrue(PullRequestFilter.matchesTextQuery(pullRequest, query: "checkout alex"))
        XCTAssertTrue(PullRequestFilter.matchesTextQuery(pullRequest, query: "quick filter"))
        XCTAssertTrue(PullRequestFilter.matchesTextQuery(pullRequest, query: "needs-review cli"))
        XCTAssertFalse(PullRequestFilter.matchesTextQuery(pullRequest, query: "checkout web"))
    }

    func testTextFilterSupportsStatusLabelFileAndReviewFields() {
        let pullRequest = makePullRequest(
            state: "OPEN",
            isDraft: true,
            changedFiles: 7,
            labels: ["bug", "needs review"],
            reviews: 3
        )

        XCTAssertTrue(PullRequestFilter.matchesTextQuery(pullRequest, query: "status:draft"))
        XCTAssertTrue(PullRequestFilter.matchesTextQuery(pullRequest, query: "status:open,draft"))
        XCTAssertTrue(PullRequestFilter.matchesTextQuery(pullRequest, query: "label:bug,needs-review"))
        XCTAssertTrue(PullRequestFilter.matchesTextQuery(pullRequest, query: "files:2..8 reviews:3.."))
        XCTAssertFalse(PullRequestFilter.matchesTextQuery(pullRequest, query: "status:merged"))
        XCTAssertFalse(PullRequestFilter.matchesTextQuery(pullRequest, query: "label:ui"))
        XCTAssertFalse(PullRequestFilter.matchesTextQuery(pullRequest, query: "files:8.."))
        XCTAssertFalse(PullRequestFilter.matchesTextQuery(pullRequest, query: "reviews:..2"))
        XCTAssertFalse(PullRequestFilter.matchesTextQuery(pullRequest, query: "files:invalid"))
    }

    func testInteractiveTextFilterAppliesToBothViewsAndCanBeCleared() {
        var state = InteractiveSession.State(
            basePullRequests: [
                makePullRequest(number: 1, title: "Fix checkout flow"),
                makePullRequest(number: 2, title: "Update release notes")
            ],
            attentionPullRequests: [
                makePullRequest(number: 3, title: "Review checkout errors"),
                makePullRequest(number: 4, title: "Document parser behavior")
            ]
        )

        state.applyTextFilter("checkout")

        XCTAssertEqual(state.pullRequests.map(\.number), [1])
        XCTAssertEqual(state.attentionPullRequests.map(\.number), [3])
        XCTAssertEqual(state.textFilter, "checkout")
        XCTAssertTrue(state.displayMessage.contains("1 match"))

        state.message = ""
        XCTAssertTrue(state.displayMessage.contains("Filter: checkout"))

        state.applyTextFilter("  ")

        XCTAssertEqual(state.pullRequests.map(\.number), [1, 2])
        XCTAssertEqual(state.attentionPullRequests.map(\.number), [3, 4])
        XCTAssertEqual(state.textFilter, "")
    }

    func testInteractiveSessionTogglesBetweenFullScreenViews() {
        var state = InteractiveSession.State(
            basePullRequests: [makePullRequest(number: 1)],
            attentionPullRequests: [makePullRequest(number: 2)]
        )

        XCTAssertEqual(state.focus, .mainRow)
        XCTAssertEqual(state.selectedPullRequest?.number, 1)

        state.toggleView()

        XCTAssertEqual(state.focus, .attentionRow)
        XCTAssertEqual(state.selectedPullRequest?.number, 2)

        state.toggleView()

        XCTAssertEqual(state.focus, .mainRow)
        XCTAssertEqual(state.selectedPullRequest?.number, 1)
    }

    func testFilteringKeepsAttentionViewSelectedWhenItBecomesEmpty() {
        var state = InteractiveSession.State(
            basePullRequests: [makePullRequest(number: 1, title: "Main match")],
            attentionPullRequests: [makePullRequest(number: 2, title: "Attention item")]
        )
        state.toggleView()

        state.applyTextFilter("Main match")

        XCTAssertEqual(state.focus, .attentionRow)
        XCTAssertTrue(state.attentionPullRequests.isEmpty)
    }

    func testSlashCommandRegistryPreservesPresentationOrderForEmptyQuery() {
        XCTAssertEqual(
            SlashCommandRegistry.filtered(by: "").map(\.name),
            ["filter", "checkout", "open", "refresh", "main", "attention", "quit"]
        )
    }

    func testSlashCommandRegistryMatchesCaseInsensitivePrefixesAndExactNames() {
        XCTAssertEqual(SlashCommandRegistry.filtered(by: "R").map(\.name), ["refresh"])
        XCTAssertEqual(SlashCommandRegistry.filtered(by: "ATTen").map(\.name), ["attention"])
        XCTAssertEqual(SlashCommandRegistry.exactMatch(for: "/OPEN")?.action, .open)
        XCTAssertNil(SlashCommandRegistry.exactMatch(for: "unknown"))
    }

    func testSlashCommandSelectionWrapsClampsAndResetsAfterQueryChanges() {
        var state = SlashCommandState(selectedIndex: 99, topIndex: 99)

        XCTAssertEqual(state.selectedIndex, SlashCommandRegistry.commands.count - 1)
        state.moveDown()
        XCTAssertEqual(state.selectedIndex, 0)
        state.moveUp()
        XCTAssertEqual(state.selectedIndex, SlashCommandRegistry.commands.count - 1)

        state.keepSelectionVisible(visibleRows: 2)
        XCTAssertEqual(state.topIndex, SlashCommandRegistry.commands.count - 2)

        state.append("m")
        XCTAssertEqual(state.matchingCommands.map(\.name), ["main"])
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertEqual(state.topIndex, 0)
    }

    func testSlashCommandTabCompletesWithoutExecuting() {
        var state = SlashCommandState(query: "ch")

        XCTAssertEqual(state.handle(.tab), .continueEditing)
        XCTAssertEqual(state.query, "checkout")
        XCTAssertEqual(state.commandForExecution?.action, .checkout)
    }

    func testSlashCommandEnterDispatchesEveryRegisteredAction() {
        for command in SlashCommandRegistry.commands {
            var state = SlashCommandState(query: command.name)

            XCTAssertEqual(state.handle(.enter), .execute(command.action))
        }
    }

    func testSlashCommandCancelClearAndNoMatchBehavior() {
        var emptyState = SlashCommandState()
        XCTAssertEqual(emptyState.handle(.escape), .cancel)
        XCTAssertEqual(emptyState.handle(.backspace), .cancel)

        var populatedState = SlashCommandState(query: "open")
        XCTAssertEqual(populatedState.handle(.clear), .continueEditing)
        XCTAssertEqual(populatedState.query, "")

        var unmatchedState = SlashCommandState(query: "zzz")
        XCTAssertTrue(unmatchedState.matchingCommands.isEmpty)
        XCTAssertEqual(unmatchedState.handle(.enter), .continueEditing)
        XCTAssertNil(unmatchedState.commandForExecution)
    }

    func testSlashCommandsAndRetainedShortcutsUseTheSameActions() {
        XCTAssertEqual(InteractiveSession.action(forShortcut: "c"), SlashCommandRegistry.exactMatch(for: "checkout")?.action)
        XCTAssertEqual(InteractiveSession.action(forShortcut: "r"), SlashCommandRegistry.exactMatch(for: "refresh")?.action)
        XCTAssertEqual(InteractiveSession.action(forShortcut: "q"), SlashCommandRegistry.exactMatch(for: "quit")?.action)
        XCTAssertNil(InteractiveSession.action(forShortcut: "o"))
        XCTAssertNil(InteractiveSession.action(forShortcut: "v"))
    }

    func testSlashCommandViewActionsUseExistingViewState() {
        var state = InteractiveSession.State(
            basePullRequests: [makePullRequest(number: 1)],
            attentionPullRequests: [makePullRequest(number: 2)]
        )

        state.showAttentionView()
        XCTAssertEqual(state.focus, .attentionRow)
        XCTAssertEqual(state.selectedPullRequest?.number, 2)

        state.showMainView()
        XCTAssertEqual(state.focus, .mainRow)
        XCTAssertEqual(state.selectedPullRequest?.number, 1)
    }

    func testTerminalInputDecoderHandlesControlAndCharacterKeys() {
        var decoder = TerminalInputDecoder()

        XCTAssertEqual(
            decoder.feed([21, 99, 67, 120]),
            [.clear, .character("c"), .character("C"), .character("x")]
        )
    }

    func testTerminalInputDecoderHandlesSplitArrowSequence() {
        var decoder = TerminalInputDecoder()

        XCTAssertEqual(decoder.feed([27]), [])
        XCTAssertEqual(decoder.feed([91]), [])
        XCTAssertEqual(decoder.feed([65]), [.up])
    }

    func testTerminalInputDecoderFlushesStandaloneEscape() {
        var decoder = TerminalInputDecoder()

        XCTAssertEqual(decoder.feed([27]), [])
        XCTAssertEqual(decoder.flushPendingEscape(), .escape)
    }

    func testTerminalInputDecoderHandlesSplitUTF8Character() {
        var decoder = TerminalInputDecoder()
        let bytes = Array("é".utf8)

        XCTAssertEqual(decoder.feed([bytes[0]]), [])
        XCTAssertEqual(decoder.feed([bytes[1]]), [.character("é")])
    }

    func testScreenWriterSkipsUnchangedFrame() {
        let frame = TerminalFrame(
            lines: ["one", "two"],
            size: TerminalSize(columns: 80, rows: 24)
        )

        XCTAssertEqual(ScreenWriter.update(previous: frame, current: frame), "")
    }

    func testScreenWriterUpdatesOnlyChangedRows() {
        let size = TerminalSize(columns: 80, rows: 24)
        let previous = TerminalFrame(lines: ["one", "two"], size: size)
        let current = TerminalFrame(lines: ["one", "changed"], size: size)

        XCTAssertEqual(
            ScreenWriter.update(previous: previous, current: current),
            "\u{001B}[2;1H\u{001B}[2Kchanged"
        )
    }

    func testScreenWriterClearsRowsWhenFrameShrinks() {
        let size = TerminalSize(columns: 80, rows: 24)
        let previous = TerminalFrame(lines: ["one", "two"], size: size)
        let current = TerminalFrame(lines: ["one"], size: size)

        XCTAssertEqual(
            ScreenWriter.update(previous: previous, current: current),
            "\u{001B}[2;1H\u{001B}[2K"
        )
    }

    func testScreenWriterFullyRedrawsAfterResize() {
        let previous = TerminalFrame(
            lines: ["same"],
            size: TerminalSize(columns: 80, rows: 24)
        )
        let current = TerminalFrame(
            lines: ["same"],
            size: TerminalSize(columns: 100, rows: 30)
        )

        XCTAssertEqual(
            ScreenWriter.update(previous: previous, current: current),
            "\u{001B}[2J\u{001B}[1;1H\u{001B}[2Ksame"
        )
    }

    func testMatchesFiltersRejectsMissingLabel() {
        let pullRequest = makePullRequest(labels: ["bug"])
        var options = Options()
        options.labels = ["bug", "frontend"]

        XCTAssertFalse(PRBuddy.matchesFilters(pullRequest, options: options))
    }

    func testMatchesFiltersAcceptsStateDraftReadyAndReviewStatuses() {
        let draftApproved = makePullRequest(
            state: "OPEN",
            isDraft: true,
            reviewDecision: "APPROVED"
        )

        var draftOptions = Options()
        draftOptions.statuses = ["draft"]
        XCTAssertTrue(PRBuddy.matchesFilters(draftApproved, options: draftOptions))

        var approvedOptions = Options()
        approvedOptions.statuses = ["approved"]
        XCTAssertTrue(PRBuddy.matchesFilters(draftApproved, options: approvedOptions))

        let readyMergedChangesRequested = makePullRequest(
            state: "MERGED",
            isDraft: false,
            reviewDecision: "CHANGES_REQUESTED"
        )

        var readyOptions = Options()
        readyOptions.statuses = ["ready"]
        XCTAssertTrue(PRBuddy.matchesFilters(readyMergedChangesRequested, options: readyOptions))

        var mergedOptions = Options()
        mergedOptions.statuses = ["merged"]
        XCTAssertTrue(PRBuddy.matchesFilters(readyMergedChangesRequested, options: mergedOptions))

        var changesRequestedOptions = Options()
        changesRequestedOptions.statuses = ["changes-requested"]
        XCTAssertTrue(PRBuddy.matchesFilters(readyMergedChangesRequested, options: changesRequestedOptions))
    }

    func testMatchesFiltersRejectsUnmatchedStatus() {
        let pullRequest = makePullRequest(
            state: "OPEN",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED"
        )

        var options = Options()
        options.statuses = ["approved"]

        XCTAssertFalse(PRBuddy.matchesFilters(pullRequest, options: options))
    }

    func testStatusTokensNormalizeStateAndReviewDecision() {
        let pullRequest = makePullRequest(
            state: "CLOSED",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED"
        )

        XCTAssertEqual(PRBuddy.statusTokens(for: pullRequest), ["closed", "ready", "reviewrequired"])
    }

    func testSortedPullRequestsSortsChangedFilesInMemoryAndPreservesTies() {
        let pullRequests = [
            makePullRequest(number: 1, changedFiles: 3),
            makePullRequest(number: 2, changedFiles: nil),
            makePullRequest(number: 3, changedFiles: 8),
            makePullRequest(number: 4, changedFiles: 3)
        ]

        XCTAssertEqual(
            PRBuddy.sortedPullRequests(pullRequests, fileSortOrder: .none).map(\.number),
            [1, 2, 3, 4]
        )
        XCTAssertEqual(
            PRBuddy.sortedPullRequests(pullRequests, fileSortOrder: .ascending).map(\.number),
            [2, 1, 4, 3]
        )
        XCTAssertEqual(
            PRBuddy.sortedPullRequests(pullRequests, fileSortOrder: .descending).map(\.number),
            [3, 1, 4, 2]
        )
    }

    func testSortedPullRequestsSortsUpdatedAtInMemoryAndPreservesTies() {
        let pullRequests = [
            makePullRequest(number: 1, updatedAt: "2026-05-31T12:00:00Z"),
            makePullRequest(number: 2, updatedAt: nil),
            makePullRequest(number: 3, updatedAt: "2026-06-01T12:00:00Z"),
            makePullRequest(number: 4, updatedAt: "2026-05-31T12:00:00Z")
        ]

        XCTAssertEqual(
            PRBuddy.sortedPullRequests(pullRequests, fileSortOrder: .none, updatedSortOrder: .none).map(\.number),
            [1, 2, 3, 4]
        )
        XCTAssertEqual(
            PRBuddy.sortedPullRequests(pullRequests, fileSortOrder: .none, updatedSortOrder: .ascending).map(\.number),
            [2, 1, 4, 3]
        )
        XCTAssertEqual(
            PRBuddy.sortedPullRequests(pullRequests, fileSortOrder: .none, updatedSortOrder: .descending).map(\.number),
            [3, 1, 4, 2]
        )
    }

    func testSortedPullRequestsSortsApprovalCountInMemoryAndPreservesTies() {
        let pullRequests = [
            makePullRequest(number: 1, reviews: nil, reviewStates: ["APPROVED", "COMMENTED"]),
            makePullRequest(number: 2, reviews: nil, reviewStates: ["COMMENTED", "COMMENTED", "COMMENTED"]),
            makePullRequest(number: 3, reviews: nil, reviewStates: ["APPROVED", "APPROVED", "APPROVED"]),
            makePullRequest(number: 4, reviews: nil, reviewStates: ["APPROVED", "CHANGES_REQUESTED"])
        ]

        XCTAssertEqual(
            PRBuddy.sortedPullRequests(pullRequests, fileSortOrder: .none, reviewSortOrder: .none).map(\.number),
            [1, 2, 3, 4]
        )
        XCTAssertEqual(
            PRBuddy.sortedPullRequests(pullRequests, fileSortOrder: .none, reviewSortOrder: .ascending).map(\.number),
            [2, 1, 4, 3]
        )
        XCTAssertEqual(
            PRBuddy.sortedPullRequests(pullRequests, fileSortOrder: .none, reviewSortOrder: .descending).map(\.number),
            [3, 1, 4, 2]
        )
    }

    func testTableRowsFormatsMissingOptionalValues() {
        let pullRequest = makePullRequest(
            author: nil,
            headRefName: nil,
            baseRefName: nil,
            reviewDecision: nil,
            changedFiles: nil,
            additions: nil,
            deletions: nil,
            labels: [],
            reviews: nil
        )

        let rows = TUIRenderer(now: { Self.date("2026-06-01T12:00:00Z") }).tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][0], "1w")
        XCTAssertEqual(rows[0][1], "-")
        XCTAssertEqual(rows[0][3], "0")
        XCTAssertEqual(rows[0][4], "-")
        XCTAssertEqual(rows[0][6], "-")
    }

    func testTableRowsFormatsUpdatedAtAsCompactElapsedTime() {
        let pullRequest = makePullRequest(updatedAt: "2026-06-01T11:50:00Z")

        let rows = TUIRenderer(now: { Self.date("2026-06-01T12:00:00Z") }).tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][0], "10m")
    }

    func testTableRowsFormatsSubMinuteUpdatedAtAsNow() {
        let pullRequest = makePullRequest(updatedAt: "2026-06-01T11:59:30Z")

        let rows = TUIRenderer(now: { Self.date("2026-06-01T12:00:00Z") }).tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][0], "now")
    }

    func testTableRowsFormatsFutureUpdatedAtAsNow() {
        let pullRequest = makePullRequest(updatedAt: "2026-06-01T12:01:00Z")

        let rows = TUIRenderer(now: { Self.date("2026-06-01T12:00:00Z") }).tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][0], "now")
    }

    func testTableRowsFormatsMissingOrInvalidUpdatedAtAsPlaceholder() {
        let renderer = TUIRenderer(now: { Self.date("2026-06-01T12:00:00Z") })

        XCTAssertEqual(renderer.tableRows(for: [makePullRequest(updatedAt: nil)])[0][0], "-")
        XCTAssertEqual(renderer.tableRows(for: [makePullRequest(updatedAt: "not-a-date")])[0][0], "-")
    }

    func testTableRowsFormatsReviewCountAndStatusIcons() {
        let pullRequest = makePullRequest(
            reviewDecision: nil,
            reviews: nil,
            reviewStates: ["APPROVED", "CHANGES_REQUESTED", "COMMENTED"]
        )

        let rows = TUIRenderer().tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][3], "3 ✓ ✕ 🗨︎ 1")
    }

    func testTableRowsDoesNotInferApprovalIconsFromReviewDecision() {
        let pullRequest = makePullRequest(
            reviewDecision: "APPROVED",
            reviews: 3,
            reviewStates: nil
        )

        let rows = TUIRenderer().tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][3], "3")
    }

    func testTableRowsCollapsesMoreThanThreeApprovalIcons() {
        let pullRequest = makePullRequest(
            reviewDecision: nil,
            reviews: nil,
            reviewStates: ["APPROVED", "APPROVED", "APPROVED", "APPROVED"]
        )

        let rows = TUIRenderer().tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][3], "4 ✓ 4")
    }

    func testTableRowsShowsUpToThreeApprovalIcons() {
        let pullRequest = makePullRequest(
            reviewDecision: nil,
            reviews: nil,
            reviewStates: ["APPROVED", "APPROVED", "APPROVED"]
        )

        let rows = TUIRenderer().tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][3], "3 ✓ ✓ ✓")
    }

    func testTableRowsAlwaysCollapsesCommentIconsWithCount() {
        let pullRequest = makePullRequest(
            reviewDecision: nil,
            reviews: nil,
            reviewStates: ["COMMENTED", "COMMENTED", "COMMENTED"]
        )

        let rows = TUIRenderer().tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][3], "3 🗨︎ 3")
    }

    func testTableRowsFormatsChangedFileStats() {
        let pullRequest = makePullRequest(
            changedFiles: 3,
            additions: 120,
            deletions: 45
        )

        let rows = TUIRenderer().tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][1], "3 +120 -45")
    }

    func testHeadersShowFileSortState() {
        let renderer = TUIRenderer()

        XCTAssertEqual(renderer.headers(updatedSortOrder: .none, fileSortOrder: .none, reviewSortOrder: .none)[1], "Files")
        XCTAssertEqual(renderer.headers(updatedSortOrder: .none, fileSortOrder: .ascending, reviewSortOrder: .none)[1], "Files ^")
        XCTAssertEqual(renderer.headers(updatedSortOrder: .none, fileSortOrder: .descending, reviewSortOrder: .none)[1], "Files v")
    }

    func testHeadersShowUpdatedSortState() {
        let renderer = TUIRenderer()

        XCTAssertEqual(renderer.headers(updatedSortOrder: .none, fileSortOrder: .none, reviewSortOrder: .none)[0], "Updated  ")
        XCTAssertEqual(renderer.headers(updatedSortOrder: .ascending, fileSortOrder: .none, reviewSortOrder: .none)[0], "Updated ^")
        XCTAssertEqual(renderer.headers(updatedSortOrder: .descending, fileSortOrder: .none, reviewSortOrder: .none)[0], "Updated v")
    }

    func testHeadersShowReviewSortState() {
        let renderer = TUIRenderer()

        XCTAssertEqual(renderer.headers(updatedSortOrder: .none, fileSortOrder: .none, reviewSortOrder: .none)[3], "Review  ")
        XCTAssertEqual(renderer.headers(updatedSortOrder: .none, fileSortOrder: .none, reviewSortOrder: .ascending)[3], "Review ^")
        XCTAssertEqual(renderer.headers(updatedSortOrder: .none, fileSortOrder: .none, reviewSortOrder: .descending)[3], "Review v")
    }

    func testUpdatedColumnWidthDoesNotChangeWhenSorting() {
        let renderer = TUIRenderer()
        let rows = renderer.tableRows(for: [makePullRequest()])
        let unsortedHeaders = renderer.headers(updatedSortOrder: .none, fileSortOrder: .none, reviewSortOrder: .none)
        let headers = renderer.headers(updatedSortOrder: .descending, fileSortOrder: .none, reviewSortOrder: .none)
        let unsortedWidths = renderer.columnWidths(headers: unsortedHeaders, rows: rows)
        let widths = renderer.columnWidths(headers: headers, rows: rows)
        let rendered = renderer.renderHeaderRow(
            headers,
            widths: widths,
            isUpdatedHeaderSelected: false,
            isFilesHeaderSelected: false,
            isReviewHeaderSelected: false
        )

        XCTAssertEqual(unsortedWidths[0], 9)
        XCTAssertEqual(widths[0], 9)
        XCTAssertTrue(rendered.contains("Updated v"))
        XCTAssertFalse(rendered.contains("Update..."))
    }

    func testReviewColumnWidthDoesNotChangeWhenSorting() {
        let renderer = TUIRenderer()
        let rows = renderer.tableRows(for: [makePullRequest(reviews: 1)])
        let unsortedHeaders = renderer.headers(updatedSortOrder: .none, fileSortOrder: .none, reviewSortOrder: .none)
        let headers = renderer.headers(updatedSortOrder: .none, fileSortOrder: .none, reviewSortOrder: .descending)
        let unsortedWidths = renderer.columnWidths(headers: unsortedHeaders, rows: rows)
        let widths = renderer.columnWidths(headers: headers, rows: rows)
        let rendered = renderer.renderHeaderRow(
            headers,
            widths: widths,
            isUpdatedHeaderSelected: false,
            isFilesHeaderSelected: false,
            isReviewHeaderSelected: false
        )

        XCTAssertEqual(unsortedWidths[3], 8)
        XCTAssertEqual(widths[3], 8)
        XCTAssertTrue(rendered.contains("Review v"))
        XCTAssertFalse(rendered.contains("Revie..."))
    }

    func testRenderHeaderRowHighlightsSelectedSortableHeaderOnly() {
        let renderer = TUIRenderer()
        let filesRendered = renderer.renderHeaderRow(
            ["Updated", "Files", "Status"],
            widths: [7, 5, 6],
            isUpdatedHeaderSelected: false,
            isFilesHeaderSelected: true,
            isReviewHeaderSelected: false
        )
        let updatedRendered = renderer.renderHeaderRow(
            ["Updated", "Files", "Status"],
            widths: [7, 5, 6],
            isUpdatedHeaderSelected: true,
            isFilesHeaderSelected: false,
            isReviewHeaderSelected: false
        )
        let reviewRendered = renderer.renderHeaderRow(
            ["Updated", "Files", "Status", "Review"],
            widths: [7, 5, 6, 6],
            isUpdatedHeaderSelected: false,
            isFilesHeaderSelected: false,
            isReviewHeaderSelected: true
        )

        XCTAssertTrue(filesRendered.contains("Updated"))
        XCTAssertTrue(filesRendered.contains("\u{001B}[7mFiles\u{001B}[0m"))
        XCTAssertTrue(filesRendered.contains("Status"))
        XCTAssertTrue(updatedRendered.contains("\u{001B}[7mUpdated\u{001B}[0m"))
        XCTAssertFalse(updatedRendered.contains("\u{001B}[7mFiles\u{001B}[0m"))
        XCTAssertTrue(reviewRendered.contains("\u{001B}[7mReview\u{001B}[0m"))
    }

    func testTruncateUsesAsciiEllipsisAndKeepsRequestedWidth() {
        let renderer = TUIRenderer()

        XCTAssertEqual(renderer.truncate("abcdef", to: 5), "ab...")
        XCTAssertEqual(renderer.truncate("abcdef", to: 3), "abc")
        XCTAssertEqual(renderer.truncate("abc", to: 5), "abc")
    }

    func testTerminalFormattingUsesDisplayWidthForCommentIcon() {
        XCTAssertEqual(TUIFormat.visibleLength("3 ✓ ✕ 🗨︎"), 7)
        XCTAssertEqual(TUIFormat.visibleLength(TUIFormat.padded("3 ✓ ✕ 🗨︎", to: 10)), 10)
        XCTAssertEqual(TUIFormat.truncate("ab🗨︎cde", to: 5), "ab...")
    }

    func testRenderRowKeepsColumnsAlignedAfterCommentIcon() {
        let renderer = TUIRenderer()
        let rendered = renderer.renderRow(
            ["#42", "3", "open", "1 🗨︎", "-", "Title", "terry"],
            widths: [3, 1, 4, 5, 1, 5, 5]
        )

        XCTAssertEqual(
            TUIFormat.visibleLength(rendered),
            3 + 1 + 4 + 5 + 1 + 5 + 5 + 6 * 2
        )
    }

    func testRenderRowColorsChangedFileStats() {
        let renderer = TUIRenderer()
        let rendered = renderer.renderRow(
            ["#42", "3 +120 -45", "open", "-", "-", "Title", "terry"],
            widths: [3, 10, 4, 1, 1, 5, 5]
        )

        XCTAssertTrue(rendered.contains("\u{001B}[38;2;89;99;110m#42\u{001B}[39m"))
        XCTAssertTrue(rendered.contains("\u{001B}[38;2;26;127;55m+120\u{001B}[39m"))
        XCTAssertTrue(rendered.contains("\u{001B}[38;2;209;36;47m-45\u{001B}[39m"))
        XCTAssertTrue(rendered.contains("\u{001B}[38;2;89;99;110mterry\u{001B}[39m"))
    }

    func testColorizedStatusUsesStatusColors() {
        let renderer = TUIRenderer()

        XCTAssertEqual(renderer.colorizedStatus("open"), "\u{001B}[38;2;31;136;61mopen\u{001B}[39m")
        XCTAssertEqual(renderer.colorizedStatus("closed"), "\u{001B}[38;2;207;34;46mclosed\u{001B}[39m")
        XCTAssertEqual(renderer.colorizedStatus("merged"), "\u{001B}[38;2;130;80;223mmerged\u{001B}[39m")
        XCTAssertEqual(renderer.colorizedStatus("draft"), "\u{001B}[38;2;89;99;110mdraft\u{001B}[39m")
        XCTAssertEqual(renderer.colorizedStatus("merge queue"), "\u{001B}[38;2;183;137;46mmerge queue\u{001B}[39m")
        XCTAssertEqual(renderer.colorizedStatus("merge_queue"), "\u{001B}[38;2;183;137;46mmerge_queue\u{001B}[39m")
    }

    func testColorizedReviewSummaryUsesReviewIconColors() {
        let renderer = TUIRenderer()

        XCTAssertEqual(
            renderer.colorizedReviewSummary("3 ✓ ✕ 🗨︎"),
            "3 \u{001B}[38;2;31;136;61m✓\u{001B}[39m \u{001B}[38;2;207;34;46m✕\u{001B}[39m \u{001B}[38;2;89;99;110m🗨︎\u{001B}[39m"
        )
    }

    func testMainPullRequestListMatchesSnapshot() throws {
        var options = Options()
        options.repo = "owner/project"

        let rendered = TUIRenderer(now: { Self.date("2026-06-01T12:00:00Z") }).renderPullRequestList(
            pullRequests: [
                makePullRequest(),
                makePullRequest(
                    number: 7,
                    title: "Ship snapshot renderer that truncates long titles",
                    author: PullRequest.Author(login: "alexandria"),
                    state: "OPEN",
                    isDraft: true,
                    reviewDecision: "APPROVED",
                    changedFiles: 12,
                    additions: 1200,
                    deletions: 50,
                    labels: ["bug", "needs review"],
                    reviews: 3
                )
            ],
            selectedIndex: 1,
            topIndex: 0,
            isUpdatedHeaderSelected: false,
            isFilesHeaderSelected: false,
            isReviewHeaderSelected: false,
            isMainViewSelected: true,
            updatedSortOrder: .none,
            fileSortOrder: .descending,
            reviewSortOrder: .none,
            attentionPullRequests: [],
            attentionSelectedIndex: 0,
            attentionTopIndex: 0,
            isAttentionViewSelected: false,
            options: options,
            message: "Sorted by most files first.",
            terminalWidth: 100,
            terminalHeight: 14
        )

        try assertSnapshot(rendered, named: "main-view-pr-list.txt")
    }

    func testMainPullRequestListFitsTerminalWidth() {
        var options = Options()
        options.repo = "owner/project-with-a-long-name"

        let terminalWidth = 72
        let rendered = TUIRenderer(now: { Self.date("2026-06-01T12:00:00Z") }).renderPullRequestList(
            pullRequests: [
                makePullRequest(
                    title: "A long pull request title that would otherwise exceed the terminal width",
                    author: PullRequest.Author(login: "long-author-name"),
                    labels: ["long-label", "another-long-label"]
                )
            ],
            selectedIndex: 0,
            topIndex: 0,
            isUpdatedHeaderSelected: false,
            isFilesHeaderSelected: false,
            isReviewHeaderSelected: false,
            isMainViewSelected: true,
            updatedSortOrder: .none,
            fileSortOrder: .none,
            reviewSortOrder: .none,
            attentionPullRequests: [],
            attentionSelectedIndex: 0,
            attentionTopIndex: 0,
            isAttentionViewSelected: false,
            options: options,
            message: "A status message that is intentionally longer than the terminal width so it must be clipped.",
            terminalWidth: terminalWidth,
            terminalHeight: 14
        )

        for line in rendered.split(separator: "\n", omittingEmptySubsequences: false) {
            XCTAssertLessThanOrEqual(TUIFormat.visibleLength(String(line)), terminalWidth)
        }
    }

    func testMainPullRequestListUsesAvailableWidthBeforeTruncatingColumns() {
        let title = "Add a wide integer fast path for addition and subtraction without truncating useful context"
        let pullRequest = makePullRequest(
            title: title,
            author: PullRequest.Author(login: "long-contributor-name"),
            changedFiles: 1234,
            additions: 56789,
            deletions: 43210,
            labels: ["awaiting review", "tests"]
        )
        let rendered = TUIRenderer(now: { Self.date("2026-06-01T12:00:00Z") }).renderPullRequestList(
            pullRequests: [pullRequest],
            selectedIndex: 0,
            topIndex: 0,
            isUpdatedHeaderSelected: false,
            isFilesHeaderSelected: false,
            isReviewHeaderSelected: false,
            isMainViewSelected: true,
            updatedSortOrder: .none,
            fileSortOrder: .none,
            reviewSortOrder: .none,
            attentionPullRequests: [],
            attentionSelectedIndex: 0,
            attentionTopIndex: 0,
            isAttentionViewSelected: false,
            options: Options(),
            message: "",
            terminalWidth: 213,
            terminalHeight: 14
        )

        XCTAssertTrue(rendered.contains("+56789"))
        XCTAssertTrue(rendered.contains("-43210"))
        XCTAssertTrue(rendered.contains("awaiting review, tests"))
        XCTAssertTrue(rendered.contains(title))
        XCTAssertTrue(rendered.contains("long-contributor-name"))
    }

    func testSearchInputBarIsAnchoredToBottomAndClippedToTerminalWidth() {
        let terminalWidth = 48
        let terminalHeight = 14
        let rendered = TUIRenderer(now: { Self.date("2026-06-01T12:00:00Z") }).renderPullRequestList(
            pullRequests: [makePullRequest()],
            selectedIndex: 0,
            topIndex: 0,
            isUpdatedHeaderSelected: false,
            isFilesHeaderSelected: false,
            isReviewHeaderSelected: false,
            isMainViewSelected: true,
            updatedSortOrder: .none,
            fileSortOrder: .none,
            reviewSortOrder: .none,
            attentionPullRequests: [],
            attentionSelectedIndex: 0,
            attentionTopIndex: 0,
            isAttentionViewSelected: false,
            options: Options(),
            message: "",
            inputBar: "Filter: needs-review_  enter apply  ctrl-u clear  esc cancel  backspace edit",
            terminalWidth: terminalWidth,
            terminalHeight: terminalHeight
        )
        let lines = rendered.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertEqual(lines.count, terminalHeight)
        XCTAssertEqual(lines.last, "Filter: needs-review_  enter apply  ctrl-u clear" + TUIFormat.Color.reset)
        XCTAssertTrue(lines[terminalHeight - 2].isEmpty)
        XCTAssertLessThanOrEqual(TUIFormat.visibleLength(lines.last ?? ""), terminalWidth)
    }

    func testSlashCommandPopupRendersSelectionAndNoMatchState() {
        let renderer = TUIRenderer()
        let commandLines = renderer.renderCommandPopup(
            SlashCommandState().popup,
            visibleRows: 3,
            terminalWidth: 48
        )
        let noMatchLines = renderer.renderCommandPopup(
            SlashCommandState(query: "zzz").popup,
            visibleRows: 3,
            terminalWidth: 48
        )

        XCTAssertEqual(commandLines.count, 3)
        XCTAssertTrue(commandLines[0].contains("\u{001B}[7m"))
        XCTAssertTrue(commandLines[0].contains("/filter"))
        XCTAssertEqual(noMatchLines, ["  No matching commands"])
    }

    func testSlashCommandPopupIsBottomAnchoredAndFitsConstrainedTerminals() {
        let terminalWidth = 32
        let terminalHeight = 10
        let commandState = SlashCommandState(query: "c")
        let renderer = TUIRenderer()
        let rendered = renderer.renderPullRequestList(
            pullRequests: [makePullRequest()],
            selectedIndex: 0,
            topIndex: 0,
            isUpdatedHeaderSelected: false,
            isFilesHeaderSelected: false,
            isReviewHeaderSelected: false,
            isMainViewSelected: true,
            updatedSortOrder: .none,
            fileSortOrder: .none,
            reviewSortOrder: .none,
            attentionPullRequests: [],
            attentionSelectedIndex: 0,
            attentionTopIndex: 0,
            isAttentionViewSelected: false,
            options: Options(),
            message: "",
            inputBar: "/c_  arrows select  tab complete",
            commandPopup: commandState.popup,
            terminalWidth: terminalWidth,
            terminalHeight: terminalHeight
        )
        let lines = rendered.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertEqual(lines.count, terminalHeight)
        XCTAssertTrue(lines[terminalHeight - 2].contains("/checkout"))
        XCTAssertTrue(lines.last?.contains("/c_") == true)
        for line in lines {
            XCTAssertLessThanOrEqual(TUIFormat.visibleLength(line), terminalWidth)
        }

        XCTAssertEqual(renderer.visibleCommandRows(terminalHeight: 7, commandCount: 7), 0)
    }

    func testAttentionPullRequestListMatchesFullScreenSnapshot() throws {
        var options = Options()
        options.repo = "owner/project"
        let rendered = TUIRenderer(now: { Self.date("2026-06-01T12:00:00Z") }).renderPullRequestList(
            pullRequests: [
                makePullRequest(number: 101, title: "Review dashboard keyboard navigation", labels: ["ui"]),
                makePullRequest(number: 102, title: "Fix stale checkout command", state: "MERGED", labels: ["cli"])
            ],
            selectedIndex: 0,
            topIndex: 0,
            isUpdatedHeaderSelected: false,
            isFilesHeaderSelected: false,
            isReviewHeaderSelected: false,
            isMainViewSelected: false,
            updatedSortOrder: .none,
            fileSortOrder: .none,
            reviewSortOrder: .none,
            attentionPullRequests: [
                makePullRequest(number: 201, title: "Update release notes", isDraft: true),
                makePullRequest(number: 202, title: "Tighten parser errors", reviewDecision: "APPROVED")
            ],
            attentionSelectedIndex: 1,
            attentionTopIndex: 0,
            isAttentionViewSelected: true,
            options: options,
            message: "",
            terminalWidth: 100,
            terminalHeight: 14
        )

        try assertSnapshot(rendered, named: "attention-pr-list.txt")
    }

    func testCommandRunnerDrainsLargeStdoutWithoutBlocking() throws {
        let result = try CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", "yes x | head -c 1048576"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr.count, 0)
        XCTAssertEqual(result.stdout.count, 1_048_576)
        XCTAssertTrue(result.stdout.hasPrefix("x\nx\n"))
    }

    private func assertSnapshot(
        _ actual: String,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let snapshotsURL = try snapshotURL(named: name)
        let expected = try String(contentsOf: snapshotsURL, encoding: .utf8)

        XCTAssertEqual(normalizedSnapshot(actual), normalizedSnapshot(expected), file: file, line: line)
    }

    private func snapshotURL(named name: String) throws -> URL {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle(for: PRBuddyTests.self)
#endif
        let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "__Snapshots__")
            ?? bundle.url(forResource: name, withExtension: nil)

        guard let url else {
            throw SnapshotError.missingSnapshot(name)
        }

        return url
    }

    private func normalizedSnapshot(_ snapshot: String) -> String {
        snapshot
            .replacingOccurrences(of: "\r\n", with: "\n")
            .strippingANSIEscapeSequences()
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingTrailingWhitespace() }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }

    private func makePullRequest(
        number: Int = 42,
        title: String = "Fix checkout flow",
        author: PullRequest.Author? = PullRequest.Author(login: "terry"),
        headRefName: String? = "feature",
        baseRefName: String? = "main",
        state: String = "OPEN",
        isDraft: Bool = false,
        reviewDecision: String? = "REVIEW_REQUIRED",
        changedFiles: Int? = 3,
        additions: Int? = 12,
        deletions: Int? = 4,
        labels: [String] = ["enhancement"],
        reviews: Int? = 1,
        reviewStates: [String]? = nil,
        updatedAt: String? = "2026-05-25T00:00:00Z",
        url: String = "https://github.com/owner/project/pull/42"
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: title,
            author: author,
            headRefName: headRefName,
            baseRefName: baseRefName,
            state: state,
            isDraft: isDraft,
            reviewDecision: reviewDecision,
            changedFiles: changedFiles,
            additions: additions,
            deletions: deletions,
            labels: labels.map { PullRequest.Label(name: $0) },
            reviews: reviewStates.map { $0.map { PullRequest.Review(state: $0) } }
                ?? reviews.map { Array(repeating: PullRequest.Review(), count: $0) },
            updatedAt: updatedAt,
            url: url
        )
    }

    private static func date(_ value: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            fatalError("Invalid test date: \(value)")
        }

        return date
    }
}

private enum SnapshotError: Error, CustomStringConvertible {
    case missingSnapshot(String)

    var description: String {
        switch self {
        case .missingSnapshot(let name):
            return "Missing snapshot fixture: \(name)"
        }
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var output = self

        while let last = output.last, last == " " || last == "\t" {
            output.removeLast()
        }

        return output
    }

    func strippingANSIEscapeSequences() -> String {
        var output = ""
        var index = startIndex

        while index < endIndex {
            if self[index] == "\u{001B}" {
                formIndex(after: &index)

                while index < endIndex {
                    let character = self[index]
                    formIndex(after: &index)

                    if character.isLetter {
                        break
                    }
                }

                continue
            }

            output.append(self[index])
            formIndex(after: &index)
        }

        return output
    }
}
