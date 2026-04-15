//
//  TerminalGrid.swift
//  BeagleCore
//
//  2D character buffer for terminal emulation.
//  Handles cursor positioning, line wrapping, scrollback, and SGR state.
//  Replaces the flat [TerminalLine] model with a proper terminal grid.
//

import Foundation
import Observation

// MARK: - Cell model

/// Visual attributes for a single terminal cell.
public struct CellAttributes: Sendable, Equatable {
    public var foreground: ANSIColor?      // nil = default
    public var background: ANSIColor?      // nil = default (transparent)
    public var bold: Bool = false
    public var dim: Bool = false
    public var italic: Bool = false
    public var underline: Bool = false
    public var strikethrough: Bool = false
    public var reverse: Bool = false
    public var hidden: Bool = false

    public static let `default` = CellAttributes()

    /// Apply an SGR parameter, returning a new attributes value.
    public mutating func apply(_ param: SGRParam) {
        switch param {
        case .reset:
            self = .default
        case .bold:           bold = true
        case .dim:            dim = true
        case .italic:         italic = true
        case .underline:      underline = true
        case .blink:          break  // Ignored
        case .reverse:        reverse = true
        case .hidden:         hidden = true
        case .strikethrough:  strikethrough = true
        case .boldOff:        bold = false
        case .dimOff:         dim = false
        case .italicOff:      italic = false
        case .underlineOff:   underline = false
        case .blinkOff:       break
        case .reverseOff:     reverse = false
        case .hiddenOff:      hidden = false
        case .strikethroughOff: strikethrough = false
        case .foreground(let c):    foreground = c
        case .background(let c):    background = c
        case .defaultForeground:    foreground = nil
        case .defaultBackground:    background = nil
        }
    }
}

/// A single character cell in the terminal grid.
public struct TerminalCell: Sendable, Equatable {
    public var character: Character
    public var attributes: CellAttributes

    public static let blank = TerminalCell(character: " ", attributes: .default)
}

// MARK: - Row model

/// A single row in the terminal grid.
public struct TerminalRow: Sendable, Identifiable {
    public let id: UInt64
    public var cells: [TerminalCell]
    public var isStderr: Bool
    public internal(set) var isDirty: Bool

    public init(id: UInt64, cols: Int, isStderr: Bool = false) {
        self.id = id
        self.cells = Array(repeating: .blank, count: cols)
        self.isStderr = isStderr
        self.isDirty = true
    }

    /// The text content of this row (trailing spaces trimmed).
    public var text: String {
        var lastNonSpace = cells.count - 1
        while lastNonSpace >= 0 && cells[lastNonSpace].character == " " {
            lastNonSpace -= 1
        }
        guard lastNonSpace >= 0 else { return "" }
        return String(cells[0...lastNonSpace].map { $0.character })
    }

    /// Whether the row has any non-space content.
    public var isEmpty: Bool {
        cells.allSatisfy { $0.character == " " }
    }
}

// MARK: - Grid

/// Observable 2D terminal grid with cursor tracking and scrollback.
@Observable
@MainActor
public final class TerminalGrid {

    // MARK: - Public state

    /// All rows including scrollback. Newest rows are at the end.
    public private(set) var rows: [TerminalRow] = []

    /// Cursor position (0-based).
    public private(set) var cursorRow: Int = 0
    public private(set) var cursorCol: Int = 0

    /// Terminal width in columns.
    public private(set) var cols: Int

    /// Monotonic revision counter — increments on every mutation.
    /// Views observe this instead of the row array for efficient change detection.
    public private(set) var revision: UInt64 = 0

    /// Total number of rows including scrollback.
    public var lineCount: Int { rows.count }

    // MARK: - Config

    public let scrollbackLimit: Int

    // MARK: - Private state

    private var currentAttributes = CellAttributes.default
    private var rowIdCounter: UInt64 = 0
    private var savedCursorRow: Int = 0
    private var savedCursorCol: Int = 0

    // MARK: - Init

    public init(cols: Int = 120, scrollbackLimit: Int = 5000) {
        self.cols = cols
        self.scrollbackLimit = scrollbackLimit
        // Start with one empty row
        appendNewRow(isStderr: false)
        cursorRow = 0
    }

    // MARK: - Process tokens

    /// Process parsed ANSI tokens into the grid.
    public func processTokens(_ tokens: [ANSIToken], isStderr: Bool) {
        for token in tokens {
            switch token {
            case .text(let str):
                writeText(str, isStderr: isStderr)

            case .sgr(let params):
                for param in params {
                    currentAttributes.apply(param)
                }

            case .carriageReturn:
                cursorCol = 0

            case .newline:
                advanceLine(isStderr: isStderr)

            case .tab:
                // Advance to next tab stop (every 8 columns)
                let nextTab = ((cursorCol / 8) + 1) * 8
                cursorCol = min(nextTab, cols - 1)

            case .backspace:
                if cursorCol > 0 { cursorCol -= 1 }

            case .cursorMove(let action):
                applyCursorMove(action)

            case .eraseLine(let mode):
                eraseInLine(mode)

            case .eraseDisplay(let mode):
                eraseInDisplay(mode, isStderr: isStderr)

            case .bell:
                break  // No-op for now

            }
        }

        trimScrollback()
        if !tokens.isEmpty {
            revision += 1
        }
    }

    /// Resize the terminal grid.
    public func resize(cols: Int) {
        guard cols > 0, cols != self.cols else { return }
        self.cols = cols
        // Resize all existing rows
        for i in rows.indices {
            if rows[i].cells.count < cols {
                rows[i].cells.append(contentsOf: Array(repeating: .blank, count: cols - rows[i].cells.count))
            } else if rows[i].cells.count > cols {
                rows[i].cells = Array(rows[i].cells.prefix(cols))
            }
            rows[i].isDirty = true
        }
        cursorCol = min(cursorCol, cols - 1)
        savedCursorCol = min(savedCursorCol, cols - 1)
        revision += 1
    }

    /// Mark a row as clean (no longer dirty).
    public func markClean(at index: Int) {
        guard index < rows.count else { return }
        rows[index].isDirty = false
    }

    /// Clear all content and reset cursor.
    public func clear() {
        rows.removeAll()
        appendNewRow(isStderr: false)
        cursorRow = 0
        cursorCol = 0
        currentAttributes = .default
        revision += 1
    }

    // MARK: - Private: text writing

    private func writeText(_ text: String, isStderr: Bool) {
        for scalar in text.unicodeScalars {
            let ch = Character(scalar)

            // Ensure cursor row exists
            ensureCursorRow(isStderr: isStderr)

            // Line wrap
            if cursorCol >= cols {
                advanceLine(isStderr: isStderr)
            }

            // Write character
            let attrs = isStderr ? stderrAttributes() : currentAttributes
            rows[cursorRow].cells[cursorCol] = TerminalCell(character: ch, attributes: attrs)
            rows[cursorRow].isDirty = true
            if isStderr { rows[cursorRow].isStderr = true }
            cursorCol += 1
        }
    }

    private func stderrAttributes() -> CellAttributes {
        var attrs = currentAttributes
        if attrs.foreground == nil {
            // Default stderr to error color (standard red)
            attrs.foreground = .standard(1)
        }
        return attrs
    }

    // MARK: - Private: line management

    private func advanceLine(isStderr: Bool) {
        cursorRow += 1
        cursorCol = 0

        if cursorRow >= rows.count {
            appendNewRow(isStderr: isStderr)
        }
    }

    private func appendNewRow(isStderr: Bool) {
        rowIdCounter += 1
        let row = TerminalRow(id: rowIdCounter, cols: cols, isStderr: isStderr)
        rows.append(row)
    }

    private func ensureCursorRow(isStderr: Bool) {
        while cursorRow >= rows.count {
            appendNewRow(isStderr: isStderr)
        }
    }

    // MARK: - Private: cursor movement

    private func applyCursorMove(_ action: CursorAction) {
        switch action {
        case .up(let n):
            cursorRow = max(0, cursorRow - n)
        case .down(let n):
            cursorRow = min(rows.count - 1, cursorRow + n)
        case .forward(let n):
            cursorCol = min(cols - 1, cursorCol + n)
        case .backward(let n):
            cursorCol = max(0, cursorCol - n)
        case .position(let row, let col):
            // ANSI positions are 1-based
            cursorRow = max(0, row - 1)
            cursorCol = max(0, min(cols - 1, col - 1))
            ensureCursorRow(isStderr: false)
        case .column(let col):
            cursorCol = max(0, min(cols - 1, col - 1))
        case .saveCursor:
            savedCursorRow = cursorRow
            savedCursorCol = cursorCol
        case .restoreCursor:
            cursorRow = savedCursorRow
            cursorCol = savedCursorCol
        }
    }

    // MARK: - Private: erase operations

    private func eraseInLine(_ mode: EraseMode) {
        guard cursorRow < rows.count else { return }

        switch mode {
        case .toEnd:
            for c in cursorCol..<cols {
                rows[cursorRow].cells[c] = .blank
            }
        case .toBeginning:
            for c in 0...min(cursorCol, cols - 1) {
                rows[cursorRow].cells[c] = .blank
            }
        case .all:
            for c in 0..<cols {
                rows[cursorRow].cells[c] = .blank
            }
        }
        rows[cursorRow].isDirty = true
    }

    private func eraseInDisplay(_ mode: EraseMode, isStderr: Bool) {
        switch mode {
        case .toEnd:
            eraseInLine(.toEnd)
            // Clear all rows below cursor
            if cursorRow + 1 < rows.count {
                rows.removeSubrange((cursorRow + 1)...)
            }
        case .toBeginning:
            eraseInLine(.toBeginning)
            // Clear all rows above cursor
            for r in 0..<cursorRow {
                for c in 0..<cols {
                    rows[r].cells[c] = .blank
                }
                rows[r].isDirty = true
            }
        case .all:
            rows.removeAll()
            appendNewRow(isStderr: isStderr)
            cursorRow = 0
            cursorCol = 0
        }
    }

    // MARK: - Private: scrollback management

    private func trimScrollback() {
        if rows.count > scrollbackLimit {
            let excess = rows.count - scrollbackLimit
            rows.removeFirst(excess)
            cursorRow = max(0, cursorRow - excess)
        }
    }
}
