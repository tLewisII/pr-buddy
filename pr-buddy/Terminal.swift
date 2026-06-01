import Darwin

private enum TerminalByte {
    case enter
    case escape
    case c
    case h
    case j
    case k
    case l
    case o
    case q
    case r
    case v
    case unknown

    init(_ byte: UInt8) {
        if byte == 10 || byte == 13 {
            self = .enter
        } else if byte == 27 {
            self = .escape
        } else if byte == 99 || byte == 67 {
            self = .c
        } else if byte == 104 || byte == 72 {
            self = .h
        } else if byte == 106 || byte == 74 {
            self = .j
        } else if byte == 107 || byte == 75 {
            self = .k
        } else if byte == 108 || byte == 76 {
            self = .l
        } else if byte == 111 || byte == 79 {
            self = .o
        } else if byte == 113 || byte == 81 {
            self = .q
        } else if byte == 114 || byte == 82 {
            self = .r
        } else if byte == 118 || byte == 86 {
            self = .v
        } else {
            self = .unknown
        }
    }
}

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

    switch TerminalByte(byte) {
    case .enter:
        return .enter
    case .escape:
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
    case .c:
        return .c
    case .h:
        return .h
    case .j:
        return .j
    case .k:
        return .k
    case .l:
        return .l
    case .o:
        return .o
    case .q:
        return .q
    case .r:
        return .r
    case .v:
        return .v
    case .unknown:
        return .unknown
    }
}
