//
//  TerminalStore.swift
//  BeagleCore
//
//  Observable store for terminal output from WebSocket streams.
//  Uses TerminalGrid for proper ANSI rendering with cursor support.
//  Exposes pre-built AttributedString lines for SwiftUI views.
//

import Foundation
import Observation

@Observable
@MainActor
public final class TerminalStore {

    // MARK: - Public state

    /// The terminal grid (2D character buffer with cursor tracking).
    public private(set) var grid: TerminalGrid

    /// WebSocket connection state.
    public private(set) var connectionState: WebSocketState = .disconnected

    /// Pre-built attributed lines for rendering.
    /// Updated when grid revision changes.
    public private(set) var attributedLines: [AttributedTerminalLine] = []

    /// Whether the user is scrolled to the bottom (for smart scroll).
    public var isAtBottom: Bool = true

    // MARK: - Private state

    private let client = WebSocketClient()
    private var streamTask: Task<Void, Never>?
    private var parser = ANSIParser()
    private let lineCache = AttributedLineCache()

    // MARK: - Config

    private static let defaultCols = 120

    // MARK: - Init

    public init(cols: Int = 120) {
        self.grid = TerminalGrid(cols: cols)
    }

    // MARK: - Connect

    /// Connect to an agent terminal WebSocket.
    public func connect(slug: String, kind: String) {
        disconnect()
        connectionState = .connecting
        parser.reset()

        let stream = Task {
            await client.connectAgent(slug: slug, kind: kind)
        }

        streamTask = Task {
            let messages = await stream.value
            for await message in messages {
                let newState = await client.state
                connectionState = newState

                switch message {
                case .data(let text):
                    processRawOutput(text, isStderr: false)
                case .stderr(let text):
                    processRawOutput(text, isStderr: true)
                case .ready(let slug):
                    appendStatusLine("● connected to \(slug)", isStderr: false)
                case .exit(let code):
                    appendStatusLine("■ process exited (\(code))", isStderr: code != 0)
                    connectionState = .disconnected
                }
            }

            // Stream ended
            if connectionState.isConnected {
                connectionState = .disconnected
            }
        }
    }

    /// Connect to a workspace terminal WebSocket.
    public func connectTerminal(slug: String, sessionId: String = "") {
        disconnect()
        connectionState = .connecting
        parser.reset()

        let stream = Task {
            await client.connectTerminal(slug: slug, sessionId: sessionId)
        }

        streamTask = Task {
            let messages = await stream.value
            for await message in messages {
                let newState = await client.state
                connectionState = newState

                switch message {
                case .data(let text):
                    processRawOutput(text, isStderr: false)
                case .stderr(let text):
                    processRawOutput(text, isStderr: true)
                case .ready(let slug):
                    appendStatusLine("● terminal ready: \(slug)", isStderr: false)
                case .exit(let code):
                    appendStatusLine("■ terminal exited (\(code))", isStderr: code != 0)
                    connectionState = .disconnected
                }
            }

            if connectionState.isConnected {
                connectionState = .disconnected
            }
        }
    }

    // MARK: - Send

    public func sendInput(_ text: String) {
        Task { await client.sendInput(text) }
    }

    public func sendResize(cols: Int, rows: Int) {
        grid.resize(cols: cols)
        Task { await client.sendResize(cols: cols, rows: rows) }
    }

    // MARK: - Disconnect

    public func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        Task { await client.disconnect() }
        connectionState = .disconnected
    }

    // MARK: - Derived

    public var truthMode: TruthMode {
        connectionState.truthMode
    }

    public var isEmpty: Bool {
        grid.lineCount <= 1 && (grid.rows.first?.isEmpty ?? true)
    }

    public var lineCount: Int {
        grid.lineCount
    }

    // MARK: - Backward compatibility

    /// Flat line array for code that still reads `lines`.
    /// Prefer `attributedLines` for rendering.
    public var lines: [TerminalLine] {
        grid.rows.enumerated().map { (idx, row) in
            TerminalLine(
                id: row.id,
                text: row.text,
                isStderr: row.isStderr
            )
        }
    }

    public var lastLine: TerminalLine? {
        guard let row = grid.rows.last else { return nil }
        return TerminalLine(id: row.id, text: row.text, isStderr: row.isStderr)
    }

    // MARK: - Internal

    private func processRawOutput(_ text: String, isStderr: Bool) {
        let tokens = parser.parse(text)
        guard !tokens.isEmpty else { return }
        grid.processTokens(tokens, isStderr: isStderr)
        rebuildAttributedLines()
    }

    private func appendStatusLine(_ text: String, isStderr: Bool) {
        // Status lines are plain text (no ANSI parsing needed)
        let tokens: [ANSIToken] = [.text(text), .newline]
        grid.processTokens(tokens, isStderr: isStderr)
        rebuildAttributedLines()
    }

    private func rebuildAttributedLines() {
        // Mark all dirty rows as clean after building
        var lines: [AttributedTerminalLine] = []
        lines.reserveCapacity(grid.rows.count)

        for i in grid.rows.indices {
            let row = grid.rows[i]
            let line = lineCache.attributedLine(for: row, lineNumber: UInt64(i + 1))
            lines.append(line)

            // Mark clean
            if row.isDirty {
                grid.markClean(at: i)
            }
        }

        // Prune cache of removed rows
        let validIds = Set(grid.rows.map { $0.id })
        lineCache.prune(validIds: validIds)

        attributedLines = lines
    }
}
