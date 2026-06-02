enum InteractiveSession {
    static func run(
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

        var state = State(
            basePullRequests: initialPullRequests,
            attentionPullRequests: initialAttentionPullRequests,
            showMyPRs: options.showMyPRs
        )

        renderer.hideCursor()

        while true {
            state.keepSelectionsVisible(visibleRows: renderer.visibleListRows())
            renderer.drawPullRequestList(
                pullRequests: state.pullRequests,
                selectedIndex: state.selectedIndex,
                topIndex: state.topIndex,
                isUpdatedHeaderSelected: state.focus == .updatedHeader,
                isFilesHeaderSelected: state.focus == .filesHeader,
                isReviewHeaderSelected: state.focus == .reviewHeader,
                isMainPaneSelected: state.focus == .mainRow,
                updatedSortOrder: state.updatedSortOrder,
                fileSortOrder: state.fileSortOrder,
                reviewSortOrder: state.reviewSortOrder,
                attentionPullRequests: state.attentionPullRequests,
                attentionSelectedIndex: state.attentionSelectedIndex,
                attentionTopIndex: state.attentionTopIndex,
                isAttentionPaneSelected: state.focus == .attentionRow,
                options: options,
                message: state.message
            )

            switch readKey() {
            case .up, .k:
                state.moveUp()
            case .down, .j:
                state.moveDown()
            case .left, .h:
                state.moveLeft(showMyPRs: options.showMyPRs)
            case .right, .l:
                state.moveRight(showMyPRs: options.showMyPRs)
            case .enter:
                if try handleEnter(state: &state, renderer: renderer, options: options) {
                    continue
                }
            case .v:
                try viewSelectedPullRequest(state: &state, renderer: renderer, options: options)
            case .c:
                try checkoutSelectedPullRequest(state: &state, renderer: renderer, options: options)
            case .o:
                try openSelectedPullRequest(state: &state, options: options)
            case .r:
                try state.refresh(options: options)
            case .q:
                return
            case .unknown:
                state.message = "Use arrows/h/j/k/l to move panes and rows, enter/v view, c checkout, o open, r refresh, q quit."
            }
        }
    }

    private static func handleEnter(state: inout State, renderer: TUIRenderer, options: Options) throws -> Bool {
        if state.focus == .updatedHeader {
            state.sortByNextUpdatedOrder()
            return true
        } else if state.focus == .filesHeader {
            state.sortByNextFileOrder()
            return true
        } else if state.focus == .reviewHeader {
            state.sortByNextReviewOrder()
            return true
        }

        try viewSelectedPullRequest(state: &state, renderer: renderer, options: options)
        return false
    }

    private static func viewSelectedPullRequest(state: inout State, renderer: TUIRenderer, options: Options) throws {
        guard !state.focus.isSortableHeader else {
            state.message = "Press enter on the Updated, Files, or Review header to change sorting."
            return
        }

        guard let selectedPullRequest = state.selectedPullRequest else {
            state.message = "No pull requests to view."
            return
        }

        renderer.drawCommandResult(
            title: "PR #\(selectedPullRequest.number)",
            result: try GitHubClient.runPRCommand(["view", String(selectedPullRequest.number)], options: options)
        )
        _ = readKey()
        state.message = "Returned from details."
    }

    private static func checkoutSelectedPullRequest(state: inout State, renderer: TUIRenderer, options: Options) throws {
        guard !state.focus.isSortableHeader else {
            state.message = "Move to a pull request before checking out."
            return
        }

        guard let selectedPullRequest = state.selectedPullRequest else {
            state.message = "No pull requests to checkout."
            return
        }

        renderer.drawCommandResult(
            title: "Checkout #\(selectedPullRequest.number)",
            result: try GitHubClient.runPRCommand(["checkout", String(selectedPullRequest.number)], options: options)
        )
        _ = readKey()
        state.message = "Checkout command finished."
    }

    private static func openSelectedPullRequest(state: inout State, options: Options) throws {
        guard !state.focus.isSortableHeader else {
            state.message = "Move to a pull request before opening it."
            return
        }

        guard let selectedPullRequest = state.selectedPullRequest else {
            state.message = "No pull requests to open."
            return
        }

        let result = try GitHubClient.runPRCommand(["view", String(selectedPullRequest.number), "--web"], options: options)
        state.message = result.exitCode == 0 ? "Opened #\(selectedPullRequest.number) in browser." : result.stderr
    }
}

extension InteractiveSession {
    struct State {
        var basePullRequests: [PullRequest]
        var fileSortOrder = FileSortOrder.none
        var updatedSortOrder = UpdatedSortOrder.none
        var reviewSortOrder = ReviewSortOrder.none
        var pullRequests: [PullRequest]
        var attentionPullRequests: [PullRequest]
        var focus: InteractiveFocus
        var selectedIndex = 0
        var attentionSelectedIndex = 0
        var topIndex = 0
        var attentionTopIndex = 0
        var message: String
        private let showMyPRs: Bool

        init(
            basePullRequests: [PullRequest],
            attentionPullRequests: [PullRequest],
            showMyPRs: Bool
        ) {
            self.basePullRequests = basePullRequests
            self.pullRequests = PullRequestFilter.sorted(
                basePullRequests,
                fileSortOrder: .none,
                updatedSortOrder: .none,
                reviewSortOrder: .none
            )
            self.attentionPullRequests = attentionPullRequests
            self.focus = showMyPRs && basePullRequests.isEmpty && !attentionPullRequests.isEmpty ? .attentionRow : .mainRow
            self.message = Self.fetchedMessage(
                pullRequests: basePullRequests,
                attentionPullRequests: attentionPullRequests,
                showMyPRs: showMyPRs
            )
            self.showMyPRs = showMyPRs
        }

        var selectedPullRequest: PullRequest? {
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

        mutating func keepSelectionsVisible(visibleRows: Int) {
            Self.keepSelectionVisible(
                pullRequests: pullRequests,
                selectedIndex: &selectedIndex,
                topIndex: &topIndex,
                visibleRows: visibleRows
            )

            if showMyPRs {
                Self.keepSelectionVisible(
                    pullRequests: attentionPullRequests,
                    selectedIndex: &attentionSelectedIndex,
                    topIndex: &attentionTopIndex,
                    visibleRows: visibleRows
                )
            }
        }

        mutating func moveUp() {
            if focus.isSortableHeader {
                message = ""
            } else if focus == .attentionRow {
                attentionSelectedIndex = max(0, attentionSelectedIndex - 1)
                message = ""
            } else if selectedIndex == 0 {
                focus = .updatedHeader
                message = ""
            } else {
                selectedIndex -= 1
                message = ""
            }
        }

        mutating func moveDown() {
            if focus.isSortableHeader {
                if !pullRequests.isEmpty {
                    focus = .mainRow
                }
            } else if focus == .attentionRow {
                attentionSelectedIndex = min(max(0, attentionPullRequests.count - 1), attentionSelectedIndex + 1)
            } else {
                selectedIndex = min(max(0, pullRequests.count - 1), selectedIndex + 1)
            }
            message = ""
        }

        mutating func moveLeft(showMyPRs: Bool) {
            if focus == .reviewHeader {
                focus = .filesHeader
            } else if focus == .filesHeader {
                focus = .updatedHeader
            } else if showMyPRs && focus == .attentionRow {
                focus = pullRequests.isEmpty ? .reviewHeader : .mainRow
            }
            message = ""
        }

        mutating func moveRight(showMyPRs: Bool) {
            if focus == .updatedHeader {
                focus = .filesHeader
            } else if focus == .filesHeader {
                focus = .reviewHeader
            } else if showMyPRs && !attentionPullRequests.isEmpty {
                focus = .attentionRow
            }
            message = ""
        }

        mutating func sortByNextUpdatedOrder() {
            updatedSortOrder = updatedSortOrder.next
            fileSortOrder = .none
            reviewSortOrder = .none
            pullRequests = PullRequestFilter.sorted(
                basePullRequests,
                fileSortOrder: fileSortOrder,
                updatedSortOrder: updatedSortOrder,
                reviewSortOrder: reviewSortOrder
            )
            selectedIndex = 0
            topIndex = 0
            message = "Sorted by updated date: \(updatedSortOrder.description)."
        }

        mutating func sortByNextFileOrder() {
            fileSortOrder = fileSortOrder.next
            updatedSortOrder = .none
            reviewSortOrder = .none
            pullRequests = PullRequestFilter.sorted(
                basePullRequests,
                fileSortOrder: fileSortOrder,
                updatedSortOrder: updatedSortOrder,
                reviewSortOrder: reviewSortOrder
            )
            selectedIndex = 0
            topIndex = 0
            message = "Sorted by files: \(fileSortOrder.description)."
        }

        mutating func sortByNextReviewOrder() {
            reviewSortOrder = reviewSortOrder.next
            updatedSortOrder = .none
            fileSortOrder = .none
            pullRequests = PullRequestFilter.sorted(
                basePullRequests,
                fileSortOrder: fileSortOrder,
                updatedSortOrder: updatedSortOrder,
                reviewSortOrder: reviewSortOrder
            )
            selectedIndex = 0
            topIndex = 0
            message = "Sorted by reviews: \(reviewSortOrder.description)."
        }

        mutating func refresh(options: Options) throws {
            let selectedPRNumber = pullRequests.indices.contains(selectedIndex) ? pullRequests[selectedIndex].number : nil
            let selectedAttentionPRNumber = options.showMyPRs && attentionPullRequests.indices.contains(attentionSelectedIndex)
                ? attentionPullRequests[attentionSelectedIndex].number
                : nil

            basePullRequests = try GitHubClient.fetchMainPullRequests(options: options)
            pullRequests = PullRequestFilter.sorted(
                basePullRequests,
                fileSortOrder: fileSortOrder,
                updatedSortOrder: updatedSortOrder,
                reviewSortOrder: reviewSortOrder
            )
            attentionPullRequests = options.showMyPRs
                ? try GitHubClient.fetchAttentionPullRequests(options: options)
                : []

            selectedIndex = Self.updatedSelectionIndex(
                currentIndex: selectedIndex,
                selectedNumber: selectedPRNumber,
                pullRequests: pullRequests
            )
            attentionSelectedIndex = Self.updatedSelectionIndex(
                currentIndex: attentionSelectedIndex,
                selectedNumber: selectedAttentionPRNumber,
                pullRequests: attentionPullRequests
            )
            updateFocusAfterRefresh(showMyPRs: options.showMyPRs)
            message = Self.fetchedMessage(
                pullRequests: pullRequests,
                attentionPullRequests: attentionPullRequests,
                showMyPRs: options.showMyPRs
            )
        }

        private mutating func updateFocusAfterRefresh(showMyPRs: Bool) {
            if showMyPRs && focus == .mainRow && pullRequests.isEmpty && !attentionPullRequests.isEmpty {
                focus = .attentionRow
            } else if showMyPRs && focus == .attentionRow && attentionPullRequests.isEmpty && !pullRequests.isEmpty {
                focus = .mainRow
            } else if pullRequests.isEmpty && (!showMyPRs || attentionPullRequests.isEmpty) {
                focus = .updatedHeader
            }
        }

        private static func updatedSelectionIndex(
            currentIndex: Int,
            selectedNumber: Int?,
            pullRequests: [PullRequest]
        ) -> Int {
            if let selectedNumber,
               let updatedIndex = pullRequests.firstIndex(where: { $0.number == selectedNumber }) {
                return updatedIndex
            }

            return min(currentIndex, max(0, pullRequests.count - 1))
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
    }
}
