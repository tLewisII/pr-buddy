import Foundation

enum InteractiveSession {
    static func run(
        initialPullRequests: [PullRequest],
        initialAttentionPullRequests: [PullRequest],
        options: Options
    ) throws {
        let eventReader = try TerminalEventReader()
        let terminalSession = try TerminalSession()
        let renderer = TUIRenderer()
        defer {
            terminalSession.restore()
            eventReader.close()
        }

        var state = State(
            basePullRequests: initialPullRequests,
            attentionPullRequests: initialAttentionPullRequests
        )
        var options = options
        var terminalSize = TerminalSize.current()
        var forceRedraw = true

        while true {
            state.keepSelectionsVisible(
                visibleRows: renderer.visibleListRows(terminalHeight: terminalSize.rows)
            )
            draw(
                state: state,
                renderer: renderer,
                options: options,
                terminalSize: terminalSize,
                forceRedraw: forceRedraw
            )
            forceRedraw = false

            switch eventReader.nextEvent() {
            case .resize(let size):
                terminalSize = size
                renderer.invalidateScreen()
                forceRedraw = true
            case .interrupt, .endOfInput:
                return
            case .key(.up):
                state.moveUp()
            case .key(.down):
                state.moveDown()
            case .key(.left):
                state.moveLeft()
            case .key(.right):
                state.moveRight()
            case .key(.enter):
                if state.focus == .updatedHeader {
                    state.sortByNextUpdatedOrder()
                } else if state.focus == .filesHeader {
                    state.sortByNextFileOrder()
                } else if state.focus == .reviewHeader {
                    state.sortByNextReviewOrder()
                } else if try dispatch(
                    .open,
                    state: &state,
                    renderer: renderer,
                    eventReader: eventReader,
                    terminalSize: &terminalSize,
                    options: &options
                ) {
                    return
                }
            case .key(.tab):
                if try dispatch(
                    .toggleView,
                    state: &state,
                    renderer: renderer,
                    eventReader: eventReader,
                    terminalSize: &terminalSize,
                    options: &options
                ) {
                    return
                }
            case .key(.character(let character)):
                if try handleCharacter(
                    character,
                    state: &state,
                    renderer: renderer,
                    eventReader: eventReader,
                    terminalSize: &terminalSize,
                    options: &options
                ) {
                    return
                }
            case .key(.interrupt):
                return
            case .key(.escape), .key(.backspace), .key(.clear):
                continue
            case .key(.unknown):
                state.message = helpMessage
            }
        }
    }

    static let helpMessage = "Use / for commands, arrows/h/j/k/l to move, tab to switch views, enter to open, c to checkout, r to refresh, q to quit."

    static func action(forShortcut character: Character) -> InteractiveAction? {
        switch String(character).lowercased() {
        case "c":
            return .checkout
        case "r":
            return .refresh
        case "q":
            return .quit
        default:
            return nil
        }
    }

    private static func handleCharacter(
        _ character: Character,
        state: inout State,
        renderer: TUIRenderer,
        eventReader: TerminalEventReader,
        terminalSize: inout TerminalSize,
        options: inout Options
    ) throws -> Bool {
        switch String(character).lowercased() {
        case "h":
            state.moveLeft()
        case "j":
            state.moveDown()
        case "k":
            state.moveUp()
        case "l":
            state.moveRight()
        case "/":
            return try editSlashCommand(
                state: &state,
                renderer: renderer,
                eventReader: eventReader,
                terminalSize: &terminalSize,
                options: &options
            )
        default:
            guard let action = action(forShortcut: character) else {
                state.message = helpMessage
                return false
            }

            return try dispatch(
                action,
                state: &state,
                renderer: renderer,
                eventReader: eventReader,
                terminalSize: &terminalSize,
                options: &options
            )
        }

        return false
    }

    private static func editSlashCommand(
        state: inout State,
        renderer: TUIRenderer,
        eventReader: TerminalEventReader,
        terminalSize: inout TerminalSize,
        options: inout Options
    ) throws -> Bool {
        var commandState = SlashCommandState()

        while true {
            let visibleCommandRows = renderer.visibleCommandRows(
                terminalHeight: terminalSize.rows,
                commandCount: max(1, commandState.matchingCommands.count)
            )
            commandState.keepSelectionVisible(visibleRows: visibleCommandRows)
            state.keepSelectionsVisible(
                visibleRows: renderer.visibleListRows(
                    terminalHeight: terminalSize.rows,
                    reservedBottomRows: visibleCommandRows
                )
            )
            draw(
                state: state,
                renderer: renderer,
                options: options,
                terminalSize: terminalSize,
                message: "",
                inputBar: "/\(commandState.query)_  arrows select  tab complete  enter run  esc cancel",
                commandPopup: commandState.popup
            )

            switch eventReader.nextEvent() {
            case .resize(let size):
                terminalSize = size
                renderer.invalidateScreen()
            case .interrupt, .endOfInput, .key(.interrupt):
                return true
            case .key(let key):
                switch commandState.handle(key) {
                case .continueEditing:
                    continue
                case .cancel:
                    return false
                case .execute(let action, let argument):
                    return try dispatch(
                        action,
                        argument: argument,
                        state: &state,
                        renderer: renderer,
                        eventReader: eventReader,
                        terminalSize: &terminalSize,
                        options: &options
                    )
                }
            }
        }
    }

    private static func dispatch(
        _ action: InteractiveAction,
        argument: String? = nil,
        state: inout State,
        renderer: TUIRenderer,
        eventReader: TerminalEventReader,
        terminalSize: inout TerminalSize,
        options: inout Options
    ) throws -> Bool {
        switch action {
        case .filter:
            return editTextFilter(
                state: &state,
                renderer: renderer,
                eventReader: eventReader,
                terminalSize: &terminalSize,
                options: options
            )
        case .search:
            if let argument {
                return try applySearchQueryAndRefresh(
                    argument,
                    state: &state,
                    renderer: renderer,
                    terminalSize: terminalSize,
                    options: &options
                )
            }

            return try editSearchQuery(
                state: &state,
                renderer: renderer,
                eventReader: eventReader,
                terminalSize: &terminalSize,
                options: &options
            )
        case .help:
            state.message = helpMessage
            return false
        case .checkout:
            return try checkoutSelectedPullRequest(
                state: &state,
                renderer: renderer,
                eventReader: eventReader,
                terminalSize: &terminalSize,
                options: options
            )
        case .open:
            try openSelectedPullRequest(state: &state, options: options)
            return false
        case .refresh:
            try refreshPullRequests(
                state: &state,
                renderer: renderer,
                terminalSize: terminalSize,
                options: options
            )
            return false
        case .showMain:
            state.showMainView()
            return false
        case .showAttention:
            state.showAttentionView()
            return false
        case .toggleView:
            state.toggleView()
            return false
        case .quit:
            return true
        }
    }

    static func applySearchQuery(_ query: String, to options: inout Options) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        options.search = trimmedQuery.isEmpty ? nil : trimmedQuery
    }

    private static func applySearchQueryAndRefresh(
        _ query: String,
        state: inout State,
        renderer: TUIRenderer,
        terminalSize: TerminalSize,
        options: inout Options
    ) throws -> Bool {
        applySearchQuery(query, to: &options)
        try refreshPullRequests(
            state: &state,
            renderer: renderer,
            terminalSize: terminalSize,
            options: options
        )
        state.message = "Search: \(options.search ?? "none"). \(state.message)"
        return false
    }

    private static func refreshPullRequests(
        state: inout State,
        renderer: TUIRenderer,
        terminalSize: TerminalSize,
        options: Options
    ) throws {
        draw(
            state: state,
            renderer: renderer,
            options: options,
            terminalSize: terminalSize,
            message: "",
            inputBar: "Refreshing pull requests..."
        )
        try state.refresh(options: options)
    }

    private static func editSearchQuery(
        state: inout State,
        renderer: TUIRenderer,
        eventReader: TerminalEventReader,
        terminalSize: inout TerminalSize,
        options: inout Options
    ) throws -> Bool {
        var query = options.search ?? ""

        while true {
            state.keepSelectionsVisible(
                visibleRows: renderer.visibleListRows(terminalHeight: terminalSize.rows)
            )
            draw(
                state: state,
                renderer: renderer,
                options: options,
                terminalSize: terminalSize,
                message: "",
                inputBar: "Search: \(query)_  enter reload  esc cancel  ctrl-u clear"
            )

            switch eventReader.nextEvent() {
            case .resize(let size):
                terminalSize = size
                renderer.invalidateScreen()
            case .interrupt, .endOfInput, .key(.interrupt):
                return true
            case .key(.character(let character)):
                query.append(character)
            case .key(.backspace):
                if !query.isEmpty {
                    query.removeLast()
                }
            case .key(.enter):
                return try applySearchQueryAndRefresh(
                    query,
                    state: &state,
                    renderer: renderer,
                    terminalSize: terminalSize,
                    options: &options
                )
            case .key(.escape):
                return false
            case .key(.clear):
                query = ""
            case .key:
                continue
            }
        }
    }

    private static func editTextFilter(
        state: inout State,
        renderer: TUIRenderer,
        eventReader: TerminalEventReader,
        terminalSize: inout TerminalSize,
        options: Options
    ) -> Bool {
        let originalQuery = state.textFilter
        var query = originalQuery

        while true {
            state.previewTextFilter(query)
            state.keepSelectionsVisible(
                visibleRows: renderer.visibleListRows(terminalHeight: terminalSize.rows)
            )
            draw(
                state: state,
                renderer: renderer,
                options: options,
                terminalSize: terminalSize,
                message: "",
                inputBar: "Filter: \(query)_  enter apply  esc clear"
            )

            switch eventReader.nextEvent() {
            case .resize(let size):
                terminalSize = size
                renderer.invalidateScreen()
            case .interrupt, .endOfInput, .key(.interrupt):
                return true
            case .key(.character(let character)):
                query.append(character)
            case .key(.backspace):
                if !query.isEmpty {
                    query.removeLast()
                }
            case .key(.enter):
                state.applyTextFilter(query)
                return false
            case .key(.escape):
                state.applyTextFilter("")
                return false
            case .key(.clear):
                query = ""
            case .key:
                continue
            }
        }
    }

    private static func checkoutSelectedPullRequest(
        state: inout State,
        renderer: TUIRenderer,
        eventReader: TerminalEventReader,
        terminalSize: inout TerminalSize,
        options: Options
    ) throws -> Bool {
        guard !state.focus.isSortableHeader else {
            state.message = "Move to a pull request before checking out."
            return false
        }

        guard let selectedPullRequest = state.selectedPullRequest else {
            state.message = "No pull requests to checkout."
            return false
        }

        renderer.drawCommandResult(
            title: "Checkout #\(selectedPullRequest.number)",
            result: try GitHubClient.runPRCommand(["checkout", String(selectedPullRequest.number)], options: options)
        )
        let shouldExit = waitForDismissal(
            eventReader: eventReader,
            renderer: renderer,
            terminalSize: &terminalSize
        )
        state.message = "Checkout command finished."
        return shouldExit
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

    private static func waitForDismissal(
        eventReader: TerminalEventReader,
        renderer: TUIRenderer,
        terminalSize: inout TerminalSize
    ) -> Bool {
        while true {
            switch eventReader.nextEvent() {
            case .resize(let size):
                terminalSize = size
            case .interrupt, .endOfInput, .key(.interrupt):
                return true
            case .key:
                renderer.invalidateScreen()
                return false
            }
        }
    }

    private static func draw(
        state: State,
        renderer: TUIRenderer,
        options: Options,
        terminalSize: TerminalSize,
        message: String? = nil,
        inputBar: String? = nil,
        commandPopup: SlashCommandPopup? = nil,
        forceRedraw: Bool = false
    ) {
        renderer.drawPullRequestList(
            pullRequests: state.pullRequests,
            selectedIndex: state.selectedIndex,
            topIndex: state.topIndex,
            isUpdatedHeaderSelected: state.focus == .updatedHeader,
            isFilesHeaderSelected: state.focus == .filesHeader,
            isReviewHeaderSelected: state.focus == .reviewHeader,
            isMainViewSelected: state.focus == .mainRow,
            updatedSortOrder: state.updatedSortOrder,
            fileSortOrder: state.fileSortOrder,
            reviewSortOrder: state.reviewSortOrder,
            attentionPullRequests: state.attentionPullRequests,
            attentionSelectedIndex: state.attentionSelectedIndex,
            attentionTopIndex: state.attentionTopIndex,
            isAttentionViewSelected: state.focus == .attentionRow,
            options: options,
            message: message ?? state.displayMessage,
            inputBar: inputBar,
            commandPopup: commandPopup,
            terminalSize: terminalSize,
            forceRedraw: forceRedraw
        )
    }
}

extension InteractiveSession {
    struct State {
        var basePullRequests: [PullRequest]
        var baseAttentionPullRequests: [PullRequest]
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
        var textFilter = ""
        init(
            basePullRequests: [PullRequest],
            attentionPullRequests: [PullRequest]
        ) {
            self.basePullRequests = basePullRequests
            self.baseAttentionPullRequests = attentionPullRequests
            self.pullRequests = PullRequestFilter.sorted(
                basePullRequests,
                fileSortOrder: .none,
                updatedSortOrder: .none,
                reviewSortOrder: .none
            )
            self.attentionPullRequests = attentionPullRequests
            self.focus = basePullRequests.isEmpty && !attentionPullRequests.isEmpty ? .attentionRow : .mainRow
            self.message = Self.fetchedMessage(
                pullRequests: basePullRequests,
                attentionPullRequests: attentionPullRequests
            )
        }

        var displayMessage: String {
            if !message.isEmpty {
                return message
            }

            guard !textFilter.isEmpty else {
                return ""
            }

            return "Filter: \(textFilter)  (\(pullRequests.count) match\(pullRequests.count == 1 ? "" : "es"))"
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

            Self.keepSelectionVisible(
                pullRequests: attentionPullRequests,
                selectedIndex: &attentionSelectedIndex,
                topIndex: &attentionTopIndex,
                visibleRows: visibleRows
            )
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

        mutating func moveLeft() {
            if focus == .reviewHeader {
                focus = .filesHeader
            } else if focus == .filesHeader {
                focus = .updatedHeader
            }
            message = ""
        }

        mutating func moveRight() {
            if focus == .updatedHeader {
                focus = .filesHeader
            } else if focus == .filesHeader {
                focus = .reviewHeader
            }
            message = ""
        }

        mutating func toggleView() {
            if focus == .attentionRow {
                showMainView()
            } else {
                showAttentionView()
            }
        }

        mutating func showMainView() {
            focus = pullRequests.isEmpty ? .updatedHeader : .mainRow
            message = "Showing main PRs."
        }

        mutating func showAttentionView() {
            focus = .attentionRow
            message = "Showing involves:@me PRs."
        }

        mutating func sortByNextUpdatedOrder() {
            updatedSortOrder = updatedSortOrder.next
            fileSortOrder = .none
            reviewSortOrder = .none
            updateFilteredPullRequests()
            selectedIndex = 0
            topIndex = 0
            message = "Sorted by updated date: \(updatedSortOrder.description)."
        }

        mutating func sortByNextFileOrder() {
            fileSortOrder = fileSortOrder.next
            updatedSortOrder = .none
            reviewSortOrder = .none
            updateFilteredPullRequests()
            selectedIndex = 0
            topIndex = 0
            message = "Sorted by files: \(fileSortOrder.description)."
        }

        mutating func sortByNextReviewOrder() {
            reviewSortOrder = reviewSortOrder.next
            updatedSortOrder = .none
            fileSortOrder = .none
            updateFilteredPullRequests()
            selectedIndex = 0
            topIndex = 0
            message = "Sorted by reviews: \(reviewSortOrder.description)."
        }

        mutating func refresh(options: Options) throws {
            let selectedPRNumber = pullRequests.indices.contains(selectedIndex) ? pullRequests[selectedIndex].number : nil
            let selectedAttentionPRNumber = attentionPullRequests.indices.contains(attentionSelectedIndex)
                ? attentionPullRequests[attentionSelectedIndex].number
                : nil

            basePullRequests = try GitHubClient.fetchMainPullRequests(options: options)
            baseAttentionPullRequests = try GitHubClient.fetchAttentionPullRequests(options: options)
            updateFilteredPullRequests()

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
            updateFocusAfterRefresh()
            message = Self.fetchedMessage(
                pullRequests: pullRequests,
                attentionPullRequests: attentionPullRequests
            )
        }

        mutating func previewTextFilter(_ query: String) {
            let isAttentionView = focus == .attentionRow
            textFilter = query
            updateFilteredPullRequests()
            selectedIndex = 0
            attentionSelectedIndex = 0
            topIndex = 0
            attentionTopIndex = 0

            if isAttentionView {
                focus = .attentionRow
            } else if !pullRequests.isEmpty {
                focus = .mainRow
            } else if !attentionPullRequests.isEmpty {
                focus = .attentionRow
            } else {
                focus = .updatedHeader
            }
        }

        mutating func applyTextFilter(_ query: String) {
            previewTextFilter(query.trimmingCharacters(in: .whitespacesAndNewlines))
            message = textFilter.isEmpty
                ? "Filter cleared."
                : "Filter: \(textFilter)  (\(pullRequests.count) match\(pullRequests.count == 1 ? "" : "es"))"
        }

        private mutating func updateFilteredPullRequests() {
            let filteredMain = basePullRequests.filter {
                PullRequestFilter.matchesTextQuery($0, query: textFilter)
            }
            pullRequests = PullRequestFilter.sorted(
                filteredMain,
                fileSortOrder: fileSortOrder,
                updatedSortOrder: updatedSortOrder,
                reviewSortOrder: reviewSortOrder
            )
            attentionPullRequests = baseAttentionPullRequests.filter {
                PullRequestFilter.matchesTextQuery($0, query: textFilter)
            }
        }

        private mutating func updateFocusAfterRefresh() {
            if focus != .attentionRow && pullRequests.isEmpty {
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
            attentionPullRequests: [PullRequest]
        ) -> String {
            let pullRequestText = "Fetched \(pullRequests.count) pull request\(pullRequests.count == 1 ? "" : "s")"
            return pullRequestText + " and \(attentionPullRequests.count) attention item\(attentionPullRequests.count == 1 ? "" : "s")."
        }
    }
}
