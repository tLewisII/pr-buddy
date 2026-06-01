import Darwin

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

    switch byte {
    case 10, 13:
        return .enter
    case 27:
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
    case 99, 67:
        return .c
    case 104, 72:
        return .h
    case 106, 74:
        return .j
    case 107, 75:
        return .k
    case 108, 76:
        return .l
    case 111, 79:
        return .o
    case 113, 81:
        return .q
    case 114, 82:
        return .r
    case 118, 86:
        return .v
    default:
        return .unknown
    }
}
