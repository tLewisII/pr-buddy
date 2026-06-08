import Darwin
import Foundation

private enum TerminalByte {
    case enter
    case tab
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
    case search
    case unknown

    init(_ byte: UInt8) {
        if byte == 10 || byte == 13 {
            self = .enter
        } else if byte == 9 {
            self = .tab
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
        } else if byte == 47 {
            self = .search
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
    case .tab:
        return .tab
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
    case .search:
        return .search
    case .unknown:
        return .unknown
    }
}

func readSearchInput() -> SearchInput {
    var byte: UInt8 = 0

    guard read(STDIN_FILENO, &byte, 1) == 1 else {
        return .unknown
    }

    if let controlInput = searchControlInput(for: byte) {
        return controlInput
    }

    guard byte >= 32 else {
        return .unknown
    }

    var bytes = [byte]
    let additionalByteCount: Int

    if byte < 0x80 {
        additionalByteCount = 0
    } else if byte & 0xE0 == 0xC0 {
        additionalByteCount = 1
    } else if byte & 0xF0 == 0xE0 {
        additionalByteCount = 2
    } else if byte & 0xF8 == 0xF0 {
        additionalByteCount = 3
    } else {
        return .unknown
    }

    for _ in 0..<additionalByteCount {
        var continuationByte: UInt8 = 0

        guard read(STDIN_FILENO, &continuationByte, 1) == 1 else {
            return .unknown
        }

        bytes.append(continuationByte)
    }

    guard let value = String(bytes: bytes, encoding: .utf8), let character = value.first else {
        return .unknown
    }

    return .character(character)
}

func searchControlInput(for byte: UInt8) -> SearchInput? {
    if byte == 10 || byte == 13 {
        return .submit
    }

    if byte == 27 {
        return .cancel
    }

    if byte == 8 || byte == 127 {
        return .backspace
    }

    if byte == 21 {
        return .clear
    }

    return nil
}
