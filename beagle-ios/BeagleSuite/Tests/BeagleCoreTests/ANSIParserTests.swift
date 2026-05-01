//
//  ANSIParserTests.swift
//  BeagleCoreTests
//
//  Tests for the ANSI escape sequence parser.
//

import Testing
@testable import BeagleCore

@Suite("ANSIParser")
struct ANSIParserTests {

    // MARK: - Plain text

    @Test func plainText() {
        var parser = ANSIParser()
        let tokens = parser.parse("hello world")
        #expect(tokens == [.text("hello world")])
    }

    @Test func emptyInput() {
        var parser = ANSIParser()
        let tokens = parser.parse("")
        #expect(tokens.isEmpty)
    }

    @Test func newlinesAndCR() {
        var parser = ANSIParser()
        let tokens = parser.parse("a\r\nb")
        #expect(tokens == [.text("a"), .carriageReturn, .newline, .text("b")])
    }

    @Test func tabAndBell() {
        var parser = ANSIParser()
        let tokens = parser.parse("x\ty\u{07}z")
        #expect(tokens == [.text("x"), .tab, .text("y"), .bell, .text("z")])
    }

    @Test func backspace() {
        var parser = ANSIParser()
        let tokens = parser.parse("ab\u{08}c")
        #expect(tokens == [.text("ab"), .backspace, .text("c")])
    }

    // MARK: - Basic SGR

    @Test func sgrReset() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[0m")
        #expect(tokens == [.sgr([.reset])])
    }

    @Test func sgrEmptyReset() {
        var parser = ANSIParser()
        // ESC[m with no params is implicit reset
        let tokens = parser.parse("\u{1B}[m")
        #expect(tokens == [.sgr([.reset])])
    }

    @Test func sgrBold() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[1mhello\u{1B}[0m")
        #expect(tokens == [.sgr([.bold]), .text("hello"), .sgr([.reset])])
    }

    @Test func sgrMultipleParams() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[1;3;4m")
        #expect(tokens == [.sgr([.bold, .italic, .underline])])
    }

    @Test func sgrDim() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[2m")
        #expect(tokens == [.sgr([.dim])])
    }

    @Test func sgrStrikethrough() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[9m")
        #expect(tokens == [.sgr([.strikethrough])])
    }

    @Test func sgrReverse() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[7m")
        #expect(tokens == [.sgr([.reverse])])
    }

    // MARK: - Standard colors

    @Test func foregroundStandard() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[31m")  // Red
        #expect(tokens == [.sgr([.foreground(.standard(1))])])
    }

    @Test func backgroundStandard() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[44m")  // Blue bg
        #expect(tokens == [.sgr([.background(.standard(4))])])
    }

    @Test func brightForeground() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[92m")  // Bright green
        #expect(tokens == [.sgr([.foreground(.bright(2))])])
    }

    @Test func brightBackground() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[105m")  // Bright magenta bg
        #expect(tokens == [.sgr([.background(.bright(5))])])
    }

    @Test func defaultForeground() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[39m")
        #expect(tokens == [.sgr([.defaultForeground])])
    }

    @Test func defaultBackground() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[49m")
        #expect(tokens == [.sgr([.defaultBackground])])
    }

    // MARK: - 256-color

    @Test func foreground256() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[38;5;196m")  // Palette index 196
        #expect(tokens == [.sgr([.foreground(.palette(196))])])
    }

    @Test func background256() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[48;5;22m")
        #expect(tokens == [.sgr([.background(.palette(22))])])
    }

    // MARK: - Truecolor (24-bit)

    @Test func foregroundTruecolor() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[38;2;255;100;50m")
        #expect(tokens == [.sgr([.foreground(.rgb(255, 100, 50))])])
    }

    @Test func backgroundTruecolor() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[48;2;10;20;30m")
        #expect(tokens == [.sgr([.background(.rgb(10, 20, 30))])])
    }

    @Test func truecolorWithColon() {
        var parser = ANSIParser()
        // Some terminals use colon separator: 38:2:R:G:B
        let tokens = parser.parse("\u{1B}[38:2:128:64:32m")
        #expect(tokens == [.sgr([.foreground(.rgb(128, 64, 32))])])
    }

    // MARK: - Combined SGR + text

    @Test func coloredText() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[1;31mERROR\u{1B}[0m: something failed")
        #expect(tokens == [
            .sgr([.bold, .foreground(.standard(1))]),
            .text("ERROR"),
            .sgr([.reset]),
            .text(": something failed")
        ])
    }

    // MARK: - Cursor movement

    @Test func cursorUp() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[3A")
        #expect(tokens == [.cursorMove(.up(3))])
    }

    @Test func cursorDown() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[B")  // Default 1
        #expect(tokens == [.cursorMove(.down(1))])
    }

    @Test func cursorForward() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[5C")
        #expect(tokens == [.cursorMove(.forward(5))])
    }

    @Test func cursorBackward() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[2D")
        #expect(tokens == [.cursorMove(.backward(2))])
    }

    @Test func cursorPosition() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[10;20H")
        #expect(tokens == [.cursorMove(.position(row: 10, col: 20))])
    }

    @Test func cursorColumn() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[15G")
        #expect(tokens == [.cursorMove(.column(15))])
    }

    @Test func cursorSaveRestore() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}7\u{1B}8")
        #expect(tokens == [.cursorMove(.saveCursor), .cursorMove(.restoreCursor)])
    }

    @Test func cursorSaveRestoreCSI() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[s\u{1B}[u")
        #expect(tokens == [.cursorMove(.saveCursor), .cursorMove(.restoreCursor)])
    }

    // MARK: - Erase

    @Test func eraseLineToEnd() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[K")
        #expect(tokens == [.eraseLine(.toEnd)])
    }

    @Test func eraseLineAll() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[2K")
        #expect(tokens == [.eraseLine(.all)])
    }

    @Test func eraseDisplayAll() {
        var parser = ANSIParser()
        let tokens = parser.parse("\u{1B}[2J")
        #expect(tokens == [.eraseDisplay(.all)])
    }

    // MARK: - Split escape sequences across chunks

    @Test func splitEscapeAcrossChunks() {
        var parser = ANSIParser()

        // First chunk ends mid-escape: ESC
        let tokens1 = parser.parse("\u{1B}")
        #expect(tokens1.isEmpty, "Incomplete ESC should be buffered")

        // Second chunk completes: [31m
        let tokens2 = parser.parse("[31m")
        #expect(tokens2 == [.sgr([.foreground(.standard(1))])])
    }

    @Test func splitCSIParams() {
        var parser = ANSIParser()

        // Split in the middle of CSI params
        let tokens1 = parser.parse("\u{1B}[38;5")
        #expect(tokens1.isEmpty)

        let tokens2 = parser.parse(";196m")
        #expect(tokens2 == [.sgr([.foreground(.palette(196))])])
    }

    @Test func splitTextThenEscape() {
        var parser = ANSIParser()

        let tokens1 = parser.parse("hello\u{1B}")
        #expect(tokens1 == [.text("hello")])

        let tokens2 = parser.parse("[1mworld")
        #expect(tokens2 == [.sgr([.bold]), .text("world")])
    }

    // MARK: - Malformed sequences

    @Test func unknownCSICommand() {
        var parser = ANSIParser()
        // Unknown command 'z' — should not crash, produces empty text
        let tokens = parser.parse("\u{1B}[99zhello")
        #expect(tokens.count == 2)
        #expect(tokens.last == .text("hello"))
    }

    @Test func oscSkipped() {
        var parser = ANSIParser()
        // OSC with BEL terminator
        let tokens = parser.parse("\u{1B}]0;window title\u{07}hello")
        #expect(tokens == [.text("hello")])
    }

    @Test func oscWithSTTerminator() {
        var parser = ANSIParser()
        // OSC with ESC \ terminator
        let tokens = parser.parse("\u{1B}]8;;https://example.com\u{1B}\\link\u{1B}]8;;\u{1B}\\")
        #expect(tokens == [.text("link")])
    }

    // MARK: - Carriage return (progress bar pattern)

    @Test func carriageReturnOverwrite() {
        var parser = ANSIParser()
        let tokens = parser.parse("Progress: 50%\rProgress: 75%")
        #expect(tokens == [
            .text("Progress: 50%"),
            .carriageReturn,
            .text("Progress: 75%")
        ])
    }

    // MARK: - Color palette

    @Test func paletteStandardColors() {
        let palette = TerminalColorPalette.beagleDark
        // Red (index 1) should be stateError-like
        let red = palette[1]
        #expect(red.r > 0.9)
        #expect(red.g < 0.2)
    }

    @Test func paletteBrightColors() {
        let palette = TerminalColorPalette.beagleDark
        // Bright white (index 15) should be full white
        let white = palette[15]
        #expect(white.r == 1.0)
        #expect(white.g == 1.0)
        #expect(white.b == 1.0)
    }

    @Test func palette256Cube() {
        let palette = TerminalColorPalette.beagleDark
        // Index 16 = first cube entry (0,0,0) = black
        let black = palette[16]
        #expect(black.r == 0.0)
        #expect(black.g == 0.0)
        #expect(black.b == 0.0)

        // Index 231 = last cube entry (5,5,5) = white
        let white = palette[231]
        #expect(white.r == 1.0)
        #expect(white.g == 1.0)
        #expect(white.b == 1.0)
    }

    @Test func paletteGrayscale() {
        let palette = TerminalColorPalette.beagleDark
        // Index 232 = darkest gray (8/255)
        let dark = palette[232]
        #expect(dark.r > 0.03 && dark.r < 0.04)
        // Index 255 = lightest gray (238/255)
        let light = palette[255]
        #expect(light.r > 0.93 && light.r < 0.94)
    }

    @Test func resolveRGB() {
        let palette = TerminalColorPalette.beagleDark
        let rgb = palette.resolve(.rgb(128, 64, 32))
        #expect(abs(rgb.r - 128.0/255.0) < 0.001)
        #expect(abs(rgb.g - 64.0/255.0) < 0.001)
        #expect(abs(rgb.b - 32.0/255.0) < 0.001)
    }

    @Test func resolveBright() {
        let palette = TerminalColorPalette.beagleDark
        // .bright(2) should resolve to index 10 (bright green)
        let color = palette.resolve(.bright(2))
        #expect(color.g > 0.9)
    }
}
