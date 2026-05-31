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

    func testTableRowsFormatsMissingOptionalValues() {
        let pullRequest = makePullRequest(
            author: nil,
            headRefName: nil,
            baseRefName: nil,
            reviewDecision: nil,
            changedFiles: nil,
            additions: nil,
            deletions: nil,
            labels: []
        )

        let rows = TUIRenderer().tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][0], "#42")
        XCTAssertEqual(rows[0][1], "-")
        XCTAssertEqual(rows[0][3], "-")
        XCTAssertEqual(rows[0][4], "-")
        XCTAssertEqual(rows[0][6], "-")
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

    func testTruncateUsesAsciiEllipsisAndKeepsRequestedWidth() {
        let renderer = TUIRenderer()

        XCTAssertEqual(renderer.truncate("abcdef", to: 5), "ab...")
        XCTAssertEqual(renderer.truncate("abcdef", to: 3), "abc")
        XCTAssertEqual(renderer.truncate("abc", to: 5), "abc")
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
            reviews: reviews.map { Array(repeating: PullRequest.Review(), count: $0) },
            updatedAt: updatedAt,
            url: url
        )
    }
}
