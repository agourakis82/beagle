//
//  TerminalColorPalette.swift
//  BeagleCore
//
//  256-color lookup table for ANSI terminal rendering.
//  Standard 16 colors are mapped to BeagleTheme semantic values.
//  The 216-color cube and 24-shade grayscale ramp follow xterm convention.
//

import SwiftUI

// MARK: - Color components

public struct TerminalRGB: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    public init(r255: Int, g255: Int, b255: Int) {
        self.r = Double(r255) / 255.0
        self.g = Double(g255) / 255.0
        self.b = Double(b255) / 255.0
    }

    public var color: Color {
        Color(red: r, green: g, blue: b)
    }
}

// MARK: - Palette

public struct TerminalColorPalette: Sendable {

    /// 256-entry lookup table.
    private let table: [TerminalRGB]

    public init(table: [TerminalRGB]) {
        precondition(table.count == 256)
        self.table = table
    }

    public subscript(index: UInt8) -> TerminalRGB {
        table[Int(index)]
    }

    /// Resolve an ANSIColor to concrete RGB.
    public func resolve(_ color: ANSIColor) -> TerminalRGB {
        switch color {
        case .standard(let idx):
            return table[Int(idx)]
        case .bright(let idx):
            return table[Int(min(idx, 7)) + 8]
        case .palette(let idx):
            return table[Int(idx)]
        case .rgb(let r, let g, let b):
            return TerminalRGB(Double(r) / 255.0, Double(g) / 255.0, Double(b) / 255.0)
        }
    }

    // MARK: - Beagle Dark palette

    /// Default palette using BeagleTheme semantic colors for the standard 16.
    public static let beagleDark: TerminalColorPalette = {
        var entries = [TerminalRGB](repeating: TerminalRGB(0, 0, 0), count: 256)

        // Standard 16 colors mapped to BeagleTheme
        // 0: Black     → surface0 (5, 10, 18)
        entries[0]  = TerminalRGB(r255: 5,   g255: 10,  b255: 18)
        // 1: Red       → stateError (hue 0, sat 0.84, bri 0.95) ≈ (242, 39, 39)
        entries[1]  = TerminalRGB(r255: 242, g255: 39,  b255: 39)
        // 2: Green     → truthObserved (hue 165, sat 0.60, bri 0.90) ≈ (92, 230, 196)
        entries[2]  = TerminalRGB(r255: 92,  g255: 230, b255: 196)
        // 3: Yellow    → postureWarm (hue 42, sat 0.88, bri 1.00) ≈ (255, 197, 31)
        entries[3]  = TerminalRGB(r255: 255, g255: 197, b255: 31)
        // 4: Blue      → truthRemembered (hue 214, sat 0.70, bri 1.00) ≈ (77, 148, 255)
        entries[4]  = TerminalRGB(r255: 77,  g255: 148, b255: 255)
        // 5: Magenta   → purple/violet tone
        entries[5]  = TerminalRGB(r255: 178, g255: 102, b255: 230)
        // 6: Cyan      → textData (200, 230, 255) at full opacity
        entries[6]  = TerminalRGB(r255: 200, g255: 230, b255: 255)
        // 7: White     → textPrimary (white 94%)
        entries[7]  = TerminalRGB(r255: 240, g255: 240, b255: 240)

        // Bright variants (8-15) — increased luminance
        // 8: Bright Black (gray)
        entries[8]  = TerminalRGB(r255: 90,  g255: 100, b255: 115)
        // 9: Bright Red
        entries[9]  = TerminalRGB(r255: 255, g255: 85,  b255: 85)
        // 10: Bright Green
        entries[10] = TerminalRGB(r255: 130, g255: 255, b255: 210)
        // 11: Bright Yellow
        entries[11] = TerminalRGB(r255: 255, g255: 220, b255: 100)
        // 12: Bright Blue
        entries[12] = TerminalRGB(r255: 120, g255: 180, b255: 255)
        // 13: Bright Magenta
        entries[13] = TerminalRGB(r255: 210, g255: 150, b255: 255)
        // 14: Bright Cyan
        entries[14] = TerminalRGB(r255: 220, g255: 240, b255: 255)
        // 15: Bright White
        entries[15] = TerminalRGB(r255: 255, g255: 255, b255: 255)

        // 216-color cube (indices 16-231)
        // Each axis has 6 levels: 0, 95, 135, 175, 215, 255
        let cubeValues: [Int] = [0, 95, 135, 175, 215, 255]
        for ri in 0..<6 {
            for gi in 0..<6 {
                for bi in 0..<6 {
                    let idx = 16 + ri * 36 + gi * 6 + bi
                    entries[idx] = TerminalRGB(r255: cubeValues[ri], g255: cubeValues[gi], b255: cubeValues[bi])
                }
            }
        }

        // 24-shade grayscale ramp (indices 232-255)
        // Values: 8, 18, 28, ..., 238
        for i in 0..<24 {
            let v = 8 + i * 10
            entries[232 + i] = TerminalRGB(r255: v, g255: v, b255: v)
        }

        return TerminalColorPalette(table: entries)
    }()
}

// MARK: - Default foreground/background

extension TerminalColorPalette {
    /// Default foreground for terminal text.
    public var defaultForeground: TerminalRGB {
        // textData: cool cyan tint
        TerminalRGB(r255: 200, g255: 230, b255: 255)
    }

    /// Default foreground for stderr text.
    public var stderrForeground: TerminalRGB {
        // stateError
        table[1]
    }

    /// Default background (transparent — rendered by the view's background).
    public var defaultBackground: TerminalRGB? {
        nil  // Use view background
    }
}
