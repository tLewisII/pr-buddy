import Darwin
import Foundation

struct TerminalSize: Equatable {
    let columns: Int
    let rows: Int

    static func current(outputFileDescriptor: Int32 = STDOUT_FILENO) -> TerminalSize {
        var size = winsize()

        guard ioctl(outputFileDescriptor, TIOCGWINSZ, &size) == 0 else {
            return TerminalSize(columns: 120, rows: 24)
        }

        return TerminalSize(
            columns: size.ws_col > 0 ? Int(size.ws_col) : 120,
            rows: size.ws_row > 0 ? Int(size.ws_row) : 24
        )
    }
}

enum TerminalKey: Equatable {
    case up
    case down
    case left
    case right
    case enter
    case tab
    case escape
    case backspace
    case clear
    case interrupt
    case character(Character)
    case unknown
}

enum TerminalEvent: Equatable {
    case key(TerminalKey)
    case resize(TerminalSize)
    case interrupt
    case endOfInput
}

struct TerminalInputDecoder {
    private var buffer: [UInt8] = []

    var hasPendingEscape: Bool {
        buffer.first == 27
    }

    mutating func feed(_ bytes: [UInt8]) -> [TerminalKey] {
        buffer.append(contentsOf: bytes)

        var keys: [TerminalKey] = []
        while let key = decodeNext() {
            keys.append(key)
        }
        return keys
    }

    mutating func flushPendingEscape() -> TerminalKey? {
        guard buffer.first == 27 else {
            return nil
        }

        buffer.removeFirst()
        return .escape
    }

    private mutating func decodeNext() -> TerminalKey? {
        guard let first = buffer.first else {
            return nil
        }

        if first == 27 {
            return decodeEscapeSequence()
        }

        if let key = controlKey(for: first) {
            buffer.removeFirst()
            return key
        }

        guard first >= 32 else {
            buffer.removeFirst()
            return .unknown
        }

        let length = utf8SequenceLength(for: first)
        guard length > 0 else {
            buffer.removeFirst()
            return .unknown
        }

        guard buffer.count >= length else {
            return nil
        }

        let bytes = Array(buffer.prefix(length))
        guard
            let value = String(bytes: bytes, encoding: .utf8),
            value.count == 1,
            let character = value.first
        else {
            buffer.removeFirst()
            return .unknown
        }

        buffer.removeFirst(length)
        return .character(character)
    }

    private mutating func decodeEscapeSequence() -> TerminalKey? {
        guard buffer.count >= 2 else {
            return nil
        }

        guard buffer[1] == 91 else {
            buffer.removeFirst()
            return .escape
        }

        guard buffer.count >= 3 else {
            return nil
        }

        switch buffer[2] {
        case 65:
            buffer.removeFirst(3)
            return .up
        case 66:
            buffer.removeFirst(3)
            return .down
        case 67:
            buffer.removeFirst(3)
            return .right
        case 68:
            buffer.removeFirst(3)
            return .left
        default:
            guard let finalIndex = buffer[2...].firstIndex(where: { (0x40...0x7E).contains($0) }) else {
                return nil
            }

            buffer.removeFirst(finalIndex + 1)
            return .unknown
        }
    }

    private func controlKey(for byte: UInt8) -> TerminalKey? {
        switch byte {
        case 3:
            return .interrupt
        case 8, 127:
            return .backspace
        case 9:
            return .tab
        case 10, 13:
            return .enter
        case 21:
            return .clear
        default:
            return nil
        }
    }

    private func utf8SequenceLength(for firstByte: UInt8) -> Int {
        if firstByte < 0x80 {
            return 1
        } else if firstByte & 0xE0 == 0xC0 {
            return 2
        } else if firstByte & 0xF0 == 0xE0 {
            return 3
        } else if firstByte & 0xF8 == 0xF0 {
            return 4
        }

        return 0
    }
}

final class TerminalSession {
    private let original: termios
    private let inputFileDescriptor: Int32
    private let outputFileDescriptor: Int32
    private var isRestored = false

    init(
        inputFileDescriptor: Int32 = STDIN_FILENO,
        outputFileDescriptor: Int32 = STDOUT_FILENO
    ) throws {
        var settings = termios()

        guard tcgetattr(inputFileDescriptor, &settings) == 0 else {
            throw AppError.commandFailed("Could not read terminal settings.")
        }

        original = settings
        self.inputFileDescriptor = inputFileDescriptor
        self.outputFileDescriptor = outputFileDescriptor

        settings.c_lflag &= ~tcflag_t(ECHO | ICANON)
        settings.c_iflag &= ~tcflag_t(ICRNL | IXON)
        settings.c_cc.16 = 1
        settings.c_cc.17 = 0

        guard tcsetattr(inputFileDescriptor, TCSANOW, &settings) == 0 else {
            throw AppError.commandFailed("Could not enable interactive terminal mode.")
        }

        writeTerminal("\u{001B}[?1049h\u{001B}[?25l", to: outputFileDescriptor)
    }

    func restore() {
        guard !isRestored else {
            return
        }

        isRestored = true
        var settings = original
        tcsetattr(inputFileDescriptor, TCSANOW, &settings)
        writeTerminal("\u{001B}[?25h\u{001B}[?1049l", to: outputFileDescriptor)
    }

    deinit {
        restore()
    }
}

nonisolated(unsafe) private var terminalSignalWriteFileDescriptor: Int32 = -1

private func forwardTerminalSignal(_ signalNumber: Int32) {
    guard terminalSignalWriteFileDescriptor >= 0 else {
        return
    }

    var byte = UInt8(truncatingIfNeeded: signalNumber)
    withUnsafeBytes(of: &byte) { bytes in
        _ = Darwin.write(terminalSignalWriteFileDescriptor, bytes.baseAddress, bytes.count)
    }
}

final class TerminalEventReader {
    private let inputFileDescriptor: Int32
    private let signalReadFileDescriptor: Int32
    private let signalWriteFileDescriptor: Int32
    private var decoder = TerminalInputDecoder()
    private var queuedEvents: [TerminalEvent] = []
    private var previousSignalHandlers: [Int32: sig_t] = [:]
    private var isClosed = false

    init(inputFileDescriptor: Int32 = STDIN_FILENO) throws {
        self.inputFileDescriptor = inputFileDescriptor

        var descriptors = [Int32](repeating: 0, count: 2)
        guard pipe(&descriptors) == 0 else {
            throw AppError.commandFailed("Could not create the terminal event pipe.")
        }

        signalReadFileDescriptor = descriptors[0]
        signalWriteFileDescriptor = descriptors[1]
        terminalSignalWriteFileDescriptor = signalWriteFileDescriptor

        for descriptor in descriptors {
            let flags = fcntl(descriptor, F_GETFL)
            if flags >= 0 {
                _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
            }
        }

        for signalNumber in [SIGWINCH, SIGINT, SIGTERM] {
            previousSignalHandlers[signalNumber] = Darwin.signal(signalNumber, forwardTerminalSignal)
        }
    }

    func nextEvent() -> TerminalEvent {
        if !queuedEvents.isEmpty {
            return queuedEvents.removeFirst()
        }

        while true {
            var descriptors = [
                pollfd(fd: inputFileDescriptor, events: Int16(POLLIN), revents: 0),
                pollfd(fd: signalReadFileDescriptor, events: Int16(POLLIN), revents: 0)
            ]
            let timeout: Int32 = decoder.hasPendingEscape ? 30 : -1
            let result = Darwin.poll(&descriptors, nfds_t(descriptors.count), timeout)

            if result == 0, let key = decoder.flushPendingEscape() {
                return .key(key)
            }

            if result < 0 {
                if errno == EINTR {
                    continue
                }
                return .endOfInput
            }

            if descriptors[1].revents & Int16(POLLIN) != 0, let event = readSignalEvent() {
                return event
            }

            if descriptors[1].revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
                return .endOfInput
            }

            if descriptors[0].revents & Int16(POLLIN) != 0 {
                var bytes = [UInt8](repeating: 0, count: 256)
                let count = Darwin.read(inputFileDescriptor, &bytes, bytes.count)

                if count == 0 {
                    return .endOfInput
                }

                if count < 0 {
                    if errno == EAGAIN || errno == EINTR {
                        continue
                    }
                    return .endOfInput
                }

                let keys = decoder.feed(Array(bytes.prefix(count)))
                queuedEvents.append(contentsOf: keys.map(event(for:)))

                if !queuedEvents.isEmpty {
                    return queuedEvents.removeFirst()
                }
            }

            if descriptors[0].revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
                return .endOfInput
            }
        }
    }

    func close() {
        guard !isClosed else {
            return
        }

        isClosed = true
        terminalSignalWriteFileDescriptor = -1

        for (signalNumber, handler) in previousSignalHandlers {
            Darwin.signal(signalNumber, handler)
        }

        Darwin.close(signalReadFileDescriptor)
        Darwin.close(signalWriteFileDescriptor)
    }

    deinit {
        close()
    }

    private func event(for key: TerminalKey) -> TerminalEvent {
        key == .interrupt ? .interrupt : .key(key)
    }

    private func readSignalEvent() -> TerminalEvent? {
        var bytes = [UInt8](repeating: 0, count: 32)
        let count = Darwin.read(signalReadFileDescriptor, &bytes, bytes.count)

        guard count > 0 else {
            return nil
        }

        let signals = bytes.prefix(count).map(Int32.init)
        if signals.contains(SIGINT) || signals.contains(SIGTERM) {
            return .interrupt
        }

        if signals.contains(SIGWINCH) {
            return .resize(TerminalSize.current())
        }

        return nil
    }
}

func writeTerminal(_ value: String, to fileDescriptor: Int32 = STDOUT_FILENO) {
    let bytes = Array(value.utf8)
    var written = 0

    while written < bytes.count {
        let count = bytes.withUnsafeBytes { buffer in
            Darwin.write(
                fileDescriptor,
                buffer.baseAddress?.advanced(by: written),
                bytes.count - written
            )
        }

        if count < 0, errno == EINTR {
            continue
        }

        guard count > 0 else {
            return
        }

        written += count
    }
}
