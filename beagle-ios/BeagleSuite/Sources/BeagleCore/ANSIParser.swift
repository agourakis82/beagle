//
//  ANSIParser.swift
//  BeagleCore
//
//  Stateful ANSI escape sequence parser for terminal output.
//  Converts raw text with embedded escape codes into structured tokens.
//  Handles split sequences across WebSocket message boundaries.
//
//  Works at Unicode scalar level to avoid Swift's grapheme clustering
//  (CR+LF is one Character in Swift, but terminals treat them separately).
//

import Foundation

// MARK: - Token types

public enum ANSIToken: Sendable, Equatable {
    case text(String)
    case sgr([SGRParam])
    case cursorMove(CursorAction)
    case eraseLine(EraseMode)
    case eraseDisplay(EraseMode)
    case carriageReturn
    case newline
    case bell
    case backspace
    case tab
}

public enum SGRParam: Sendable, Equatable {
    case reset
    case bold
    case dim
    case italic
    case underline
    case blink
    case reverse
    case hidden
    case strikethrough
    case boldOff
    case dimOff
    case italicOff
    case underlineOff
    case blinkOff
    case reverseOff
    case hiddenOff
    case strikethroughOff
    case foreground(ANSIColor)
    case background(ANSIColor)
    case defaultForeground
    case defaultBackground
}

public enum ANSIColor: Sendable, Equatable {
    case standard(UInt8)     // 0-7
    case bright(UInt8)       // 0-7 (maps to 8-15)
    case palette(UInt8)      // 0-255
    case rgb(UInt8, UInt8, UInt8)
}

public enum CursorAction: Sendable, Equatable {
    case up(Int)
    case down(Int)
    case forward(Int)
    case backward(Int)
    case position(row: Int, col: Int)
    case column(Int)
    case saveCursor
    case restoreCursor
}

public enum EraseMode: Sendable, Equatable {
    case toEnd        // 0 — from cursor to end
    case toBeginning  // 1 — from beginning to cursor
    case all          // 2 — entire line/display
}

// MARK: - Parser

/// Stateful ANSI parser that buffers incomplete escape sequences across calls.
public struct ANSIParser: Sendable {

    /// Pending scalars from an incomplete escape sequence.
    private var pending: [Unicode.Scalar] = []

    public init() {}

    /// Parse raw terminal text into structured tokens.
    /// Call repeatedly with successive chunks — incomplete sequences are buffered.
    public mutating func parse(_ input: String) -> [ANSIToken] {
        var tokens: [ANSIToken] = []
        let scalars = pending + Array(input.unicodeScalars)
        pending = []

        var textAccum: [Unicode.Scalar] = []
        var i = 0

        func flushText() {
            if !textAccum.isEmpty {
                tokens.append(.text(String(String.UnicodeScalarView(textAccum))))
                textAccum = []
            }
        }

        while i < scalars.count {
            let s = scalars[i]

            switch s.value {
            case 0x1B:  // ESC
                flushText()

                let remaining = scalars.count - i
                if remaining < 2 {
                    pending = Array(scalars[i...])
                    return tokens
                }

                let next = scalars[i + 1]
                if next == "[" {
                    // CSI sequence: ESC [ params command
                    if let (token, endIdx) = parseCSI(scalars: scalars, from: i + 2) {
                        tokens.append(token)
                        i = endIdx
                        continue
                    } else {
                        pending = Array(scalars[i...])
                        return tokens
                    }
                } else if next == "]" {
                    // OSC — skip until ST (ESC \ or BEL)
                    if let endIdx = skipOSC(scalars: scalars, from: i + 2) {
                        i = endIdx
                        continue
                    } else {
                        pending = Array(scalars[i...])
                        return tokens
                    }
                } else if next == "(" || next == ")" {
                    // Character set designation — skip 3 scalars total
                    if i + 3 <= scalars.count {
                        i += 3
                        continue
                    } else {
                        pending = Array(scalars[i...])
                        return tokens
                    }
                } else if next == "7" {
                    tokens.append(.cursorMove(.saveCursor))
                    i += 2; continue
                } else if next == "8" {
                    tokens.append(.cursorMove(.restoreCursor))
                    i += 2; continue
                } else {
                    // Unknown ESC sequence — skip ESC + next
                    i += 2; continue
                }

            case 0x0D:  // CR
                flushText()
                tokens.append(.carriageReturn)
                i += 1

            case 0x0A:  // LF
                flushText()
                tokens.append(.newline)
                i += 1

            case 0x07:  // BEL
                flushText()
                tokens.append(.bell)
                i += 1

            case 0x08:  // BS
                flushText()
                tokens.append(.backspace)
                i += 1

            case 0x09:  // TAB
                flushText()
                tokens.append(.tab)
                i += 1

            default:
                textAccum.append(s)
                i += 1
            }
        }

        flushText()
        return tokens
    }

    /// Reset parser state (e.g., on reconnect).
    public mutating func reset() {
        pending = []
    }

    // MARK: - CSI parsing

    /// Parse CSI sequence starting after `ESC[`. Returns token and index past the command byte.
    private func parseCSI(scalars: [Unicode.Scalar], from start: Int) -> (ANSIToken, Int)? {
        var idx = start
        var params: [Int] = []
        var currentParam: Int? = nil
        var isExtended = false

        // Check for private mode prefix
        if idx < scalars.count && scalars[idx] == "?" {
            isExtended = true
            idx += 1
        }

        while idx < scalars.count {
            let v = scalars[idx].value

            if v >= 0x30 && v <= 0x39 {
                // Digit
                let digit = Int(v - 0x30)
                currentParam = (currentParam ?? 0) * 10 + digit
                idx += 1
            } else if v == 0x3B {  // ";"
                params.append(currentParam ?? 0)
                currentParam = nil
                idx += 1
            } else if v == 0x3A {  // ":" — colon sub-params (38:2:R:G:B)
                params.append(currentParam ?? 0)
                currentParam = nil
                idx += 1
            } else if v >= 0x40 && v <= 0x7E {
                // Command byte
                if let p = currentParam { params.append(p) }
                let token = buildCSIToken(command: scalars[idx], params: params, isExtended: isExtended)
                return (token, idx + 1)
            } else if v >= 0x20 && v <= 0x2F {
                // Intermediate byte — skip
                idx += 1
            } else {
                // Unexpected — treat as end of CSI
                break
            }
        }

        return nil  // Incomplete
    }

    private func buildCSIToken(command: Unicode.Scalar, params: [Int], isExtended: Bool) -> ANSIToken {
        switch command {
        case "m":
            return .sgr(parseSGRParams(params))

        case "A": return .cursorMove(.up(params.first ?? 1))
        case "B": return .cursorMove(.down(params.first ?? 1))
        case "C": return .cursorMove(.forward(params.first ?? 1))
        case "D": return .cursorMove(.backward(params.first ?? 1))
        case "H", "f":
            let row = params.count > 0 ? params[0] : 1
            let col = params.count > 1 ? params[1] : 1
            return .cursorMove(.position(row: row, col: col))
        case "G": return .cursorMove(.column(params.first ?? 1))
        case "s": return .cursorMove(.saveCursor)
        case "u": return .cursorMove(.restoreCursor)

        case "J": return .eraseDisplay(eraseMode(params.first ?? 0))
        case "K": return .eraseLine(eraseMode(params.first ?? 0))

        default:
            return .text("")
        }
    }

    private func eraseMode(_ param: Int) -> EraseMode {
        switch param {
        case 1:  return .toBeginning
        case 2:  return .all
        default: return .toEnd
        }
    }

    // MARK: - SGR parameter parsing

    private func parseSGRParams(_ raw: [Int]) -> [SGRParam] {
        if raw.isEmpty { return [.reset] }

        var result: [SGRParam] = []
        var i = 0

        while i < raw.count {
            let code = raw[i]

            switch code {
            case 0:  result.append(.reset)
            case 1:  result.append(.bold)
            case 2:  result.append(.dim)
            case 3:  result.append(.italic)
            case 4:  result.append(.underline)
            case 5, 6: result.append(.blink)
            case 7:  result.append(.reverse)
            case 8:  result.append(.hidden)
            case 9:  result.append(.strikethrough)

            case 21: result.append(.boldOff)
            case 22: result.append(.dimOff)
            case 23: result.append(.italicOff)
            case 24: result.append(.underlineOff)
            case 25: result.append(.blinkOff)
            case 27: result.append(.reverseOff)
            case 28: result.append(.hiddenOff)
            case 29: result.append(.strikethroughOff)

            case 30...37:
                result.append(.foreground(.standard(UInt8(code - 30))))

            case 38:
                if let (color, advance) = parseExtendedColor(raw, from: i + 1) {
                    result.append(.foreground(color))
                    i += advance
                }

            case 39:
                result.append(.defaultForeground)

            case 40...47:
                result.append(.background(.standard(UInt8(code - 40))))

            case 48:
                if let (color, advance) = parseExtendedColor(raw, from: i + 1) {
                    result.append(.background(color))
                    i += advance
                }

            case 49:
                result.append(.defaultBackground)

            case 90...97:
                result.append(.foreground(.bright(UInt8(code - 90))))

            case 100...107:
                result.append(.background(.bright(UInt8(code - 100))))

            default:
                break
            }

            i += 1
        }

        return result
    }

    /// Parse 256-color (5;N) or truecolor (2;R;G;B) after code 38/48.
    private func parseExtendedColor(_ params: [Int], from start: Int) -> (ANSIColor, Int)? {
        guard start < params.count else { return nil }

        switch params[start] {
        case 5:
            guard start + 1 < params.count else { return nil }
            return (.palette(UInt8(clamping: params[start + 1])), 2)

        case 2:
            guard start + 3 < params.count else { return nil }
            let r = UInt8(clamping: params[start + 1])
            let g = UInt8(clamping: params[start + 2])
            let b = UInt8(clamping: params[start + 3])
            return (.rgb(r, g, b), 4)

        default:
            return nil
        }
    }

    // MARK: - OSC skipping

    /// Skip OSC sequence (ESC ] ... BEL or ESC ] ... ESC \).
    private func skipOSC(scalars: [Unicode.Scalar], from start: Int) -> Int? {
        var idx = start
        while idx < scalars.count {
            let v = scalars[idx].value
            if v == 0x07 {
                return idx + 1
            }
            if v == 0x1B && idx + 1 < scalars.count && scalars[idx + 1] == "\\" {
                return idx + 2
            }
            idx += 1
        }
        return nil
    }
}
