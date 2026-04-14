//
//  AttributedStringBuilder.swift
//  BeagleCore
//
//  Converts TerminalRow cells to AttributedString for SwiftUI rendering.
//  Run-length encodes: adjacent cells with identical attributes are merged
//  into a single attributed run for performance.
//

import Foundation
import SwiftUI

// MARK: - Attributed terminal line

/// A pre-built attributed string for a single terminal row.
public struct AttributedTerminalLine: Identifiable, Sendable {
    public let id: UInt64
    public let content: AttributedString
    public let isStderr: Bool
    public let lineNumber: UInt64
}

// MARK: - Builder

public struct AttributedStringBuilder: Sendable {

    private let palette: TerminalColorPalette
    private let fontSize: CGFloat

    public init(palette: TerminalColorPalette = .beagleDark, fontSize: CGFloat = 13) {
        self.palette = palette
        self.fontSize = fontSize
    }

    /// Convert a TerminalRow to an AttributedString.
    public func build(from row: TerminalRow) -> AttributedString {
        let cells = row.cells
        guard !cells.isEmpty else { return AttributedString("") }

        // Find the last non-space cell to avoid trailing blanks
        var lastNonBlank = cells.count - 1
        while lastNonBlank >= 0 && cells[lastNonBlank].character == " " && cells[lastNonBlank].attributes == .default {
            lastNonBlank -= 1
        }

        if lastNonBlank < 0 {
            return AttributedString("")
        }

        let activeCells = cells[0...lastNonBlank]

        // Run-length encode: merge adjacent cells with same attributes
        var result = AttributedString()
        var runStart = activeCells.startIndex
        var runAttrs = activeCells[runStart].attributes

        for i in activeCells.indices {
            if activeCells[i].attributes != runAttrs {
                // End current run
                let text = String(activeCells[runStart..<i].map { $0.character })
                result.append(styledRun(text, attrs: runAttrs, isStderr: row.isStderr))
                runStart = i
                runAttrs = activeCells[i].attributes
            }
        }

        // Final run
        let lastText = String(activeCells[runStart...].map { $0.character })
        result.append(styledRun(lastText, attrs: runAttrs, isStderr: row.isStderr))

        return result
    }

    /// Build an AttributedTerminalLine from a row with its index.
    public func buildLine(from row: TerminalRow, lineNumber: UInt64) -> AttributedTerminalLine {
        AttributedTerminalLine(
            id: row.id,
            content: build(from: row),
            isStderr: row.isStderr,
            lineNumber: lineNumber
        )
    }

    // MARK: - Private

    private func styledRun(_ text: String, attrs: CellAttributes, isStderr: Bool) -> AttributedString {
        var str = AttributedString(text)

        // Font — monospaced, with weight/style variants
        let size = fontSize
        if attrs.bold && attrs.italic {
            str.font = .system(size: size, weight: .bold, design: .monospaced).italic()
        } else if attrs.bold {
            str.font = .system(size: size, weight: .bold, design: .monospaced)
        } else if attrs.italic {
            str.font = .system(size: size, weight: .regular, design: .monospaced).italic()
        } else if attrs.dim {
            str.font = .system(size: size, weight: .light, design: .monospaced)
        } else {
            str.font = .system(size: size, weight: .regular, design: .monospaced)
        }

        // Foreground color
        let effectiveFG: Color
        let effectiveBG: Color?

        if attrs.reverse {
            // Swap foreground and background
            effectiveFG = resolveBackground(attrs) ?? Color(red: 5/255, green: 10/255, blue: 18/255)
            effectiveBG = resolveForeground(attrs, isStderr: isStderr)
        } else {
            effectiveFG = resolveForeground(attrs, isStderr: isStderr)
            effectiveBG = resolveBackground(attrs)
        }

        str.foregroundColor = attrs.dim ? effectiveFG.opacity(0.5) : effectiveFG
        if attrs.hidden {
            str.foregroundColor = .clear
        }

        if let bg = effectiveBG {
            str.backgroundColor = bg
        }

        // Decorations
        if attrs.underline {
            str.underlineStyle = .single
        }
        if attrs.strikethrough {
            str.strikethroughStyle = .single
        }

        return str
    }

    private func resolveForeground(_ attrs: CellAttributes, isStderr: Bool) -> Color {
        if let fg = attrs.foreground {
            return palette.resolve(fg).color
        }
        // Default foreground
        if isStderr {
            return palette.stderrForeground.color
        }
        return palette.defaultForeground.color
    }

    private func resolveBackground(_ attrs: CellAttributes) -> Color? {
        guard let bg = attrs.background else { return nil }
        return palette.resolve(bg).color
    }
}

// MARK: - Line cache

/// Cache for AttributedString results, keyed on row ID.
/// Invalidated when a row's isDirty flag is set.
@MainActor
public final class AttributedLineCache {

    private var cache: [UInt64: AttributedString] = [:]
    private let builder: AttributedStringBuilder

    public init(palette: TerminalColorPalette = .beagleDark) {
        self.builder = AttributedStringBuilder(palette: palette)
    }

    /// Get or build the attributed string for a row.
    public func attributedString(for row: TerminalRow) -> AttributedString {
        if !row.isDirty, let cached = cache[row.id] {
            return cached
        }
        let result = builder.build(from: row)
        cache[row.id] = result
        return result
    }

    /// Build a full AttributedTerminalLine.
    public func attributedLine(for row: TerminalRow, lineNumber: UInt64) -> AttributedTerminalLine {
        AttributedTerminalLine(
            id: row.id,
            content: attributedString(for: row),
            isStderr: row.isStderr,
            lineNumber: lineNumber
        )
    }

    /// Remove cached entries for rows no longer in the grid.
    public func prune(validIds: Set<UInt64>) {
        cache = cache.filter { validIds.contains($0.key) }
    }

    /// Clear the entire cache.
    public func invalidateAll() {
        cache.removeAll()
    }
}
