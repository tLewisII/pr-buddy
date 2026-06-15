import Foundation

enum InteractiveAction: Equatable {
    case filter
    case checkout
    case open
    case refresh
    case showMain
    case showAttention
    case toggleView
    case quit
}

struct SlashCommand: Equatable {
    let name: String
    let description: String
    let action: InteractiveAction
}

enum SlashCommandRegistry {
    static let commands = [
        SlashCommand(name: "filter", description: "Filter pull requests by text", action: .filter),
        SlashCommand(name: "checkout", description: "Check out the selected pull request", action: .checkout),
        SlashCommand(name: "open", description: "Open the selected pull request in a browser", action: .open),
        SlashCommand(name: "refresh", description: "Refresh pull requests", action: .refresh),
        SlashCommand(name: "main", description: "Switch to the main pull request view", action: .showMain),
        SlashCommand(name: "attention", description: "Switch to the involves:@me view", action: .showAttention),
        SlashCommand(name: "quit", description: "Exit pr-buddy", action: .quit)
    ]

    static func filtered(by query: String) -> [SlashCommand] {
        guard !query.isEmpty else {
            return commands
        }

        let normalizedQuery = normalized(query)
        return commands.filter { $0.name.lowercased().hasPrefix(normalizedQuery) }
    }

    static func exactMatch(for query: String) -> SlashCommand? {
        let normalizedQuery = normalized(query)
        return commands.first { $0.name.lowercased() == normalizedQuery }
    }

    private static func normalized(_ query: String) -> String {
        var normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedQuery.first == "/" {
            normalizedQuery.removeFirst()
        }
        return normalizedQuery.lowercased()
    }
}

enum SlashCommandTransition: Equatable {
    case continueEditing
    case cancel
    case execute(InteractiveAction)
}

struct SlashCommandState: Equatable {
    private(set) var query: String
    private(set) var selectedIndex: Int
    private(set) var topIndex: Int

    init(query: String = "", selectedIndex: Int = 0, topIndex: Int = 0) {
        self.query = query
        self.selectedIndex = selectedIndex
        self.topIndex = topIndex
        clampSelection()
    }

    var matchingCommands: [SlashCommand] {
        SlashCommandRegistry.filtered(by: query)
    }

    var selectedCommand: SlashCommand? {
        let commands = matchingCommands
        guard commands.indices.contains(selectedIndex) else {
            return nil
        }

        return commands[selectedIndex]
    }

    var commandForExecution: SlashCommand? {
        SlashCommandRegistry.exactMatch(for: query) ?? selectedCommand
    }

    var popup: SlashCommandPopup {
        SlashCommandPopup(
            commands: matchingCommands,
            selectedIndex: selectedIndex,
            topIndex: topIndex
        )
    }

    mutating func append(_ character: Character) {
        query.append(character)
        resetSelection()
    }

    @discardableResult
    mutating func backspace() -> Bool {
        guard !query.isEmpty else {
            return false
        }

        query.removeLast()
        resetSelection()
        return true
    }

    mutating func clear() {
        query = ""
        resetSelection()
    }

    mutating func moveUp() {
        let count = matchingCommands.count
        guard count > 0 else {
            return
        }

        selectedIndex = selectedIndex == 0 ? count - 1 : selectedIndex - 1
    }

    mutating func moveDown() {
        let count = matchingCommands.count
        guard count > 0 else {
            return
        }

        selectedIndex = (selectedIndex + 1) % count
    }

    @discardableResult
    mutating func completeSelectedCommand() -> Bool {
        guard let selectedCommand else {
            return false
        }

        query = selectedCommand.name
        resetSelection()
        return true
    }

    mutating func keepSelectionVisible(visibleRows: Int) {
        clampSelection()
        guard !matchingCommands.isEmpty else {
            topIndex = 0
            return
        }

        guard visibleRows > 0 else {
            topIndex = selectedIndex
            return
        }

        if selectedIndex < topIndex {
            topIndex = selectedIndex
        } else if selectedIndex >= topIndex + visibleRows {
            topIndex = selectedIndex - visibleRows + 1
        }

        topIndex = min(topIndex, max(0, matchingCommands.count - visibleRows))
    }

    mutating func handle(_ key: TerminalKey) -> SlashCommandTransition {
        switch key {
        case .character(let character):
            append(character)
        case .up:
            moveUp()
        case .down:
            moveDown()
        case .tab:
            completeSelectedCommand()
        case .enter:
            guard let command = commandForExecution else {
                return .continueEditing
            }
            return .execute(command.action)
        case .backspace:
            return backspace() ? .continueEditing : .cancel
        case .clear:
            clear()
        case .escape:
            return .cancel
        case .left, .right, .interrupt, .unknown:
            break
        }

        return .continueEditing
    }

    private mutating func resetSelection() {
        selectedIndex = 0
        topIndex = 0
        clampSelection()
    }

    private mutating func clampSelection() {
        let count = matchingCommands.count
        selectedIndex = count == 0 ? 0 : min(max(selectedIndex, 0), count - 1)
        topIndex = count == 0 ? 0 : min(max(topIndex, 0), count - 1)
    }
}

struct SlashCommandPopup: Equatable {
    let commands: [SlashCommand]
    let selectedIndex: Int
    let topIndex: Int
}
