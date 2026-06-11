import Foundation

struct TerminalFrame: Equatable {
    let lines: [String]
    let size: TerminalSize
}

final class ScreenWriter {
    private var previousFrame: TerminalFrame?
    private let output: (String) -> Void

    init(output: @escaping (String) -> Void = { writeTerminal($0) }) {
        self.output = output
    }

    func draw(_ frame: TerminalFrame, force: Bool = false) {
        let update = Self.update(previous: previousFrame, current: frame, force: force)
        previousFrame = frame

        guard !update.isEmpty else {
            return
        }

        output(update)
    }

    func clearScreen() {
        previousFrame = nil
        output("\u{001B}[2J\u{001B}[H")
    }

    func invalidate() {
        previousFrame = nil
    }

    static func update(
        previous: TerminalFrame?,
        current: TerminalFrame,
        force: Bool = false
    ) -> String {
        let fullRedraw = force || previous == nil || previous?.size != current.size
        let previousLines = previous?.lines ?? []
        let lineCount = max(previousLines.count, current.lines.count)
        var output = fullRedraw ? "\u{001B}[2J" : ""

        for index in 0..<lineCount {
            let previousLine = previousLines.indices.contains(index) ? previousLines[index] : ""
            let currentLine = current.lines.indices.contains(index) ? current.lines[index] : ""

            guard fullRedraw || previousLine != currentLine else {
                continue
            }

            output += "\u{001B}[\(index + 1);1H\u{001B}[2K\(currentLine)"
        }

        return output
    }
}
