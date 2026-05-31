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
            "--limit", "25"
        ])

        XCTAssertEqual(options.repo, "owner/project")
        XCTAssertEqual(options.search, "review-requested:@me")
        XCTAssertEqual(options.labels, ["bug", "needs review"])
        XCTAssertEqual(options.statuses, ["draft", "approved"])
        XCTAssertEqual(options.minChangedFiles, 2)
        XCTAssertEqual(options.maxChangedFiles, 8)
        XCTAssertEqual(options.limit, 25)
    }

    func testParseOptionsRejectsInvalidFileRange() {
        XCTAssertThrowsError(try PRBuddy.parseOptions(["--min-files", "10", "--max-files", "2"])) { error in
            XCTAssertTrue(String(describing: error).contains("--min-files cannot be greater than --max-files"))
        }
    }

    func testParseOptionsSupportsOpenEndedChangedFileRanges() throws {
        let maxOnly = try PRBuddy.parseOptions(["--changed-files", "..5"])
        XCTAssertNil(maxOnly.minChangedFiles)
        XCTAssertEqual(maxOnly.maxChangedFiles, 5)

        let minOnly = try PRBuddy.parseOptions(["--changed-files", "10.."])
        XCTAssertEqual(minOnly.minChangedFiles, 10)
        XCTAssertNil(minOnly.maxChangedFiles)
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
            "number,title,author,headRefName,baseRefName,state,isDraft,reviewDecision,changedFiles,labels,updatedAt,url",
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
            labels: ["bug", "needs review"]
        )

        var options = Options()
        options.labels = ["BUG", "needs-review"]
        options.statuses = ["approved"]
        options.minChangedFiles = 2
        options.maxChangedFiles = 5

        XCTAssertTrue(PRBuddy.matchesFilters(pullRequest, options: options))
    }

    func testMatchesFiltersRejectsPullRequestOutsideChangedFileRange() {
        let pullRequest = makePullRequest(changedFiles: 12)
        var options = Options()
        options.maxChangedFiles = 5

        XCTAssertFalse(PRBuddy.matchesFilters(pullRequest, options: options))
    }

    func testMatchesFiltersRejectsMissingLabel() {
        let pullRequest = makePullRequest(labels: ["bug"])
        var options = Options()
        options.labels = ["bug", "frontend"]

        XCTAssertFalse(PRBuddy.matchesFilters(pullRequest, options: options))
    }

    func testTableRowsFormatsMissingOptionalValues() {
        let pullRequest = makePullRequest(
            author: nil,
            headRefName: nil,
            baseRefName: nil,
            reviewDecision: nil,
            changedFiles: nil,
            labels: []
        )

        let rows = TUIRenderer().tableRows(for: [pullRequest])

        XCTAssertEqual(rows[0][0], "1")
        XCTAssertEqual(rows[0][1], "#42")
        XCTAssertEqual(rows[0][2], "-")
        XCTAssertEqual(rows[0][4], "-")
        XCTAssertEqual(rows[0][5], "-")
        XCTAssertEqual(rows[0][7], "-")
    }

    func testTruncateUsesAsciiEllipsisAndKeepsRequestedWidth() {
        let renderer = TUIRenderer()

        XCTAssertEqual(renderer.truncate("abcdef", to: 5), "ab...")
        XCTAssertEqual(renderer.truncate("abcdef", to: 3), "abc")
        XCTAssertEqual(renderer.truncate("abc", to: 5), "abc")
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
        labels: [String] = ["enhancement"],
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
            labels: labels.map { PullRequest.Label(name: $0) },
            updatedAt: updatedAt,
            url: url
        )
    }
}
