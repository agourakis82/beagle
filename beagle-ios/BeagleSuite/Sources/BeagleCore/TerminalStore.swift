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

    /// The last non-zero exit observed from the terminal stream.
    public private(set) var lastExitCode: Int?
    public private(set) var lastExitDetail: String?

    /// Typed Workbench stream state. Raw terminal rendering remains separate.
    public private(set) var workbenchEvents: [WorkbenchLiveEvent] = []
    public private(set) var liveBlocks: [TerminalBlockLiveState] = []
    public private(set) var agentStates: [String: AgentRunState] = [:]
    public private(set) var approvalRequests: [String: ApprovalRequest] = [:]
    public private(set) var latestMemoryStatus: WorkbenchMemoryStatus?

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
        clearLastExit()

        let stream = Task {
            await client.connectAgent(slug: slug, kind: kind)
        }

        streamTask = Task { [weak self] in
            guard let self else { return }
            let messages = await stream.value
            for await message in messages {
                let newState = await client.state
                self.connectionState = newState

                switch message {
                case .data(let text):
                    self.processRawOutput(text, isStderr: false)
                case .stderr(let text):
                    self.processRawOutput(text, isStderr: true)
                case .ready(let slug):
                    self.appendStatusLine("● connected to \(slug)", isStderr: false)
                case .workbenchEvent(let event):
                    self.processWorkbenchEvent(event)
                case .exit(let code, let detail):
                    self.recordExit(code: code, detail: detail, fallback: "■ process exited (\(code))")
                    self.connectionState = .disconnected
                }
            }

            // Stream ended
            if self.connectionState.isConnected {
                self.connectionState = .disconnected
            }
        }
    }

    /// Connect to a workspace terminal WebSocket.
    public func connectTerminal(slug: String, sessionId: String = "") {
        disconnect()
        connectionState = .connecting
        parser.reset()
        clearLastExit()

        let stream = Task {
            await client.connectTerminal(slug: slug, sessionId: sessionId)
        }

        streamTask = Task { [weak self] in
            guard let self else { return }
            let messages = await stream.value
            for await message in messages {
                let newState = await client.state
                self.connectionState = newState

                switch message {
                case .data(let text):
                    self.processRawOutput(text, isStderr: false)
                case .stderr(let text):
                    self.processRawOutput(text, isStderr: true)
                case .ready(let slug):
                    self.appendStatusLine("● terminal ready: \(slug)", isStderr: false)
                case .workbenchEvent(let event):
                    self.processWorkbenchEvent(event)
                case .exit(let code, let detail):
                    self.recordExit(code: code, detail: detail, fallback: "■ terminal exited (\(code))")
                    self.connectionState = .disconnected
                }
            }

            if self.connectionState.isConnected {
                self.connectionState = .disconnected
            }
        }
    }

    /// Connect to a Beagle Notebook Terminal pane.
    public func connectWorkspacePane(slug: String, sessionId: String, paneId: String) {
        disconnect()
        connectionState = .connecting
        parser.reset()
        clearLastExit()

        let stream = Task {
            await client.connectWorkspacePane(slug: slug, sessionId: sessionId, paneId: paneId)
        }

        streamTask = Task { [weak self] in
            guard let self else { return }
            let messages = await stream.value
            for await message in messages {
                let newState = await client.state
                self.connectionState = newState

                switch message {
                case .data(let text):
                    self.processRawOutput(text, isStderr: false)
                case .stderr(let text):
                    self.processRawOutput(text, isStderr: true)
                case .ready(let slug):
                    self.appendStatusLine("● workbench ready: \(slug)", isStderr: false)
                case .workbenchEvent(let event):
                    self.processWorkbenchEvent(event)
                case .exit(let code, let detail):
                    self.recordExit(code: code, detail: detail, fallback: "■ workbench exited (\(code))")
                    self.connectionState = .disconnected
                }
            }

            if self.connectionState.isConnected {
                self.connectionState = .disconnected
            }
        }
    }

    // MARK: - Send

    public func sendInput(_ text: String) {
        Task { await client.sendInput(text) }
    }

    public func sendPaste(_ text: String) {
        Task { await client.sendPaste(text) }
    }

    public func sendSignal(_ signal: String = "SIGINT") {
        Task { await client.sendSignal(signal) }
    }

    public func sendFocus() {
        Task { await client.sendFocus() }
    }

    public func stopProcess() {
        Task { await client.stopProcess() }
    }

    public func startProcess(_ command: String) {
        Task { await client.startProcess(command) }
    }

    public func approve(_ text: String = "y\n") {
        Task { await client.approve(text) }
    }

    public func attachBlockToMemory(blockId: String) {
        Task { await client.attachBlockToMemory(blockId: blockId) }
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

    public var hasAbnormalExit: Bool {
        guard let lastExitCode else { return false }
        return lastExitCode != 0
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

    /// Token counter for Live Activity updates.
    public private(set) var totalTokens = 0
    private var lastActivityUpdate: Date = .distantPast

    /// Callback for Live Activity updates (set by the view layer).
    /// Parameters: (status: String, tokens: Int, snippet: String)
    public var onActivityUpdate: ((String, Int, String) -> Void)?

    private func processRawOutput(_ text: String, isStderr: Bool) {
        let tokens = parser.parse(text)
        guard !tokens.isEmpty else { return }
        grid.processTokens(tokens, isStderr: isStderr)
        rebuildAttributedLines()

        // Update Live Activity with terminal output (throttled to every 2s)
        totalTokens += text.count
        if Date.now.timeIntervalSince(lastActivityUpdate) > 2 {
            lastActivityUpdate = .now
            let snippet = String((lastLine?.text ?? "").prefix(60))
            onActivityUpdate?("active", totalTokens, snippet)
        }
    }

    /// Write a plain-text diagnostic line into the terminal buffer.
    /// Used by AgentSessionView to show pod spawn status before the WebSocket connects.
    public func appendDiagnosticLine(_ text: String) {
        appendStatusLine(text, isStderr: false)
    }

    private func clearLastExit() {
        lastExitCode = nil
        lastExitDetail = nil
        workbenchEvents.removeAll()
        liveBlocks.removeAll()
        agentStates.removeAll()
        approvalRequests.removeAll()
        latestMemoryStatus = nil
    }

    private func recordExit(code: Int, detail: String?, fallback: String) {
        let message = detail ?? fallback
        appendStatusLine(message, isStderr: code != 0)
        if code != 0 {
            lastExitCode = code
            lastExitDetail = message
        }
    }

    private func appendStatusLine(_ text: String, isStderr: Bool) {
        // Status lines are plain text (no ANSI parsing needed)
        let tokens: [ANSIToken] = [.text(text), .newline]
        grid.processTokens(tokens, isStderr: isStderr)
        rebuildAttributedLines()
    }

    private func processWorkbenchEvent(_ event: WorkbenchLiveEvent) {
        workbenchEvents.append(event)
        if workbenchEvents.count > 240 {
            workbenchEvents.removeFirst(workbenchEvents.count - 240)
        }

        switch event.type {
        case "block_started":
            guard let blockId = event.blockId else { return }
            upsertLiveBlock(
                TerminalBlockLiveState(
                    id: blockId,
                    sessionId: event.sessionId,
                    paneId: event.paneId,
                    kind: event.kind ?? "command",
                    title: event.title ?? event.command ?? "Command",
                    command: event.command ?? "",
                    outputPreview: "",
                    status: "running",
                    privacyClass: event.privacyClass ?? "sensitive",
                    memoryStatus: "not_saved",
                    updatedAt: event.at
                )
            )
        case "block_output":
            guard let blockId = event.blockId else { return }
            updateLiveBlock(blockId) { block in
                let appended = [block.outputPreview, event.data ?? ""]
                    .filter { !$0.isEmpty }
                    .joined()
                block.outputPreview = String(appended.suffix(800))
                block.updatedAt = event.at
            }
        case "block_finished":
            guard let blockId = event.blockId else { return }
            updateLiveBlock(blockId) { block in
                block.status = event.status ?? "finished"
                block.exitCode = event.exitCode
                block.durationMs = event.durationMs
                block.privacyClass = event.privacyClass ?? block.privacyClass
                block.updatedAt = event.finishedAt ?? event.at
            }
        case "memory_imported":
            let status = event.status ?? "unknown"
            latestMemoryStatus = WorkbenchMemoryStatus(
                blockId: event.blockId,
                status: status,
                privacyClass: status == "blocked" ? "restricted_local_only" : nil,
                reason: event.reason,
                error: event.error,
                memoryEventId: event.memoryEventId,
                auditEventId: event.auditEventId,
                updatedAt: event.at,
                sourceModel: event.sourceModel,
                bridgeVersion: event.bridgeVersion
            )
            if let blockId = event.blockId {
                updateLiveBlock(blockId) { block in
                    block.memoryStatus = status
                    block.memoryEventId = event.memoryEventId
                    block.auditEventId = event.auditEventId
                    block.updatedAt = event.at
                }
            }
        case "secret_redacted":
            if let blockId = event.blockId {
                updateLiveBlock(blockId) { block in
                    block.privacyClass = "restricted_local_only"
                    block.memoryStatus = "blocked"
                    block.updatedAt = event.at
                }
            }
        case "agent_state":
            guard let paneId = event.paneId else { return }
            agentStates[paneId] = AgentRunState(
                kind: "agent",
                state: event.state ?? "active",
                summary: event.event ?? event.state ?? "",
                branch: "",
                commit: "",
                changedFiles: []
            )
        case "approval_requested":
            let id = event.blockId ?? event.paneId ?? event.at ?? UUID().uuidString
            approvalRequests[id] = ApprovalRequest(
                id: id,
                title: event.status == "approved" ? "Approval sent" : "Approval requested",
                detail: event.reason ?? event.data ?? "",
                requestedBy: event.sourceModel ?? "workspace-agent",
                status: event.status ?? "pending",
                createdAt: event.at ?? ""
            )
        default:
            break
        }
    }

    private func upsertLiveBlock(_ block: TerminalBlockLiveState) {
        if let index = liveBlocks.firstIndex(where: { $0.id == block.id }) {
            liveBlocks[index] = block
        } else {
            liveBlocks.insert(block, at: 0)
        }
        if liveBlocks.count > 80 {
            liveBlocks.removeLast(liveBlocks.count - 80)
        }
    }

    private func updateLiveBlock(_ blockId: String, mutate: (inout TerminalBlockLiveState) -> Void) {
        guard let index = liveBlocks.firstIndex(where: { $0.id == blockId }) else { return }
        var block = liveBlocks[index]
        mutate(&block)
        liveBlocks[index] = block
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
