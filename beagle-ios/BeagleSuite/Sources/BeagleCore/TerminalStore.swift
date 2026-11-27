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

    /// Active OpenAI Agents API session ID (when connected via `connectOpenAIAgentSession`).
    public private(set) var openAIAgentSessionId: String? = nil
    public private(set) var isOpenAIAgentTurnActive: Bool = false

    // MARK: - Private state

    private let client = WebSocketClient()
    private var streamTask: Task<Void, Never>?
    private var parser = ANSIParser()
    private let lineCache = AttributedLineCache()
    private var isOpenAIAgentMode: Bool = false
    private var openAIAgentSlug: String = ""
    private var openAIAgentModel: String = OpenAIModelCatalog.defaultFlagshipModel
    private var openAIAgentInstructions: String = ""

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
        isOpenAIAgentMode = false
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
        isOpenAIAgentMode = false
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
        isOpenAIAgentMode = false
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

    // MARK: - OpenAI Agents API (`v1/agents/sessions`, `OpenAI-Beta: agents=v1`)

    public static func defaultOpenAIAgentInstructions(for slug: String) -> String {
        """
        Você é o agente autônomo do ecossistema Beagle operando em um sandbox gerenciado (`openai_hosted`) para o projeto `\(slug)` de Demetrios Chiuratto Agourakis.
        Use seu ambiente Linux/Python/shell hospedado para investigar, prototipar, analisar dados científicos/PBPK, inspecionar código, validar hipóteses e sintetizar resultados rigorosos em português do Brasil.
        Seja direto, técnico, conciso e transparente sobre comandos executados e artefatos gerados.
        """
    }

    /// Inicia ou retoma uma sessão nativa na OpenAI Agents API (`POST /v1/agents/sessions` + SSE),
    /// com suporte a steering em tempo real (`sendInput`), cancelamento (`stopProcess`) e histórico salvo (`/items`).
    public func connectOpenAIAgentSession(
        slug: String,
        model: String? = nil,
        instructions: String? = nil,
        initialPrompt: String? = nil,
        forceNewSession: Bool = false
    ) {
        disconnect()
        isOpenAIAgentMode = true
        openAIAgentSlug = slug
        let chosenModel = (model?.isEmpty == false) ? model! : DirectBrainCredentials.openAIModel
        openAIAgentModel = chosenModel
        openAIAgentInstructions = instructions ?? Self.defaultOpenAIAgentInstructions(for: slug)
        parser.reset()
        clearLastExit()

        let apiKey = DirectBrainCredentials.openAIKey
        guard !apiKey.isEmpty else {
            let msg = "Chave da API OpenAI não configurada. Abra Ajustes → Modelos & APIs para inserir sua sk-…"
            appendStatusLine("✗ \(msg)", isStderr: true)
            connectionState = .failed(msg)
            return
        }

        if forceNewSession {
            OpenAIAgentsSessionClient.saveSessionId(nil, forProject: slug)
        }

        connectionState = .connecting
        let savedId = forceNewSession ? nil : OpenAIAgentsSessionClient.savedSessionId(forProject: slug)
        let promptToSend: String = {
            let trimmed = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
            return "Prepare o workspace em nuvem para o projeto '\(slug)' e informe brevemente que está pronto para receber instruções."
        }()

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let existingId = savedId {
                    self.openAIAgentSessionId = existingId
                    self.connectionState = .connected(source: "openai-agents · \(chosenModel)")
                    self.appendStatusLine("● Sessão OpenAI Agents retomada: \(existingId) (\(chosenModel))", isStderr: false)

                    if let items = try? await OpenAIAgentsSessionClient.shared.listSavedItems(
                        apiKey: apiKey,
                        sessionId: existingId,
                        limit: 20
                    ), !items.isEmpty {
                        self.appendStatusLine("── Histórico salvo (\(items.count) itens) ──", isStderr: false)
                        for item in items.suffix(6) {
                            let prefix = item.role == "user" ? "❯ " : "◈ "
                            let snippet = item.text.replacingOccurrences(of: "\n", with: "\r\n")
                            self.processRawOutput("\(prefix)\(snippet)\r\n", isStderr: false)
                        }
                        self.appendStatusLine("────────────────────────────────────────", isStderr: false)
                    }

                    if let rawPrompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPrompt.isEmpty {
                        self.processRawOutput("\r\n❯ \(rawPrompt)\r\n", isStderr: false)
                        self.isOpenAIAgentTurnActive = true
                        try await OpenAIAgentsSessionClient.shared.sendInputMessage(
                            apiKey: apiKey,
                            sessionId: existingId,
                            text: rawPrompt
                        )
                    }

                    await self.listenToOpenAIAgentStream(apiKey: apiKey, sessionId: existingId)
                } else {
                    self.appendStatusLine("● Criando sessão OpenAI Agents (\(chosenModel) · openai_hosted)…", isStderr: false)
                    self.processRawOutput("❯ \(promptToSend)\r\n", isStderr: false)
                    self.isOpenAIAgentTurnActive = true

                    let created = try await OpenAIAgentsSessionClient.shared.createAndStreamSession(
                        apiKey: apiKey,
                        model: chosenModel,
                        instructions: self.openAIAgentInstructions,
                        initialInput: promptToSend,
                        onEvent: { [weak self] event in
                            await MainActor.run {
                                self?.handleOpenAIAgentEvent(event, slug: slug, model: chosenModel)
                            }
                        }
                    )
                    if !created.sessionId.isEmpty {
                        self.openAIAgentSessionId = created.sessionId
                        OpenAIAgentsSessionClient.saveSessionId(created.sessionId, forProject: slug)
                        await self.listenToOpenAIAgentStream(apiKey: apiKey, sessionId: created.sessionId)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self.isOpenAIAgentTurnActive = false
                let desc = error.localizedDescription
                self.appendStatusLine("✗ OpenAI Agents API: \(desc)", isStderr: true)
                self.connectionState = .failed(desc)
            }
        }
    }

    private func listenToOpenAIAgentStream(apiKey: String, sessionId: String) async {
        while !Task.isCancelled && isOpenAIAgentMode {
            do {
                _ = try await OpenAIAgentsSessionClient.shared.streamExistingSession(
                    apiKey: apiKey,
                    sessionId: sessionId,
                    stopOnTurnCompleted: false,
                    onEvent: { [weak self] event in
                        await MainActor.run {
                            guard let self else { return }
                            self.handleOpenAIAgentEvent(event, slug: self.openAIAgentSlug, model: self.openAIAgentModel)
                        }
                    }
                )
                // Brief pause before re-subscribing if SSE stream closed cleanly between turns
                try? await Task.sleep(for: .seconds(1))
            } catch is CancellationError {
                break
            } catch {
                if Task.isCancelled || !isOpenAIAgentMode { break }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func handleOpenAIAgentEvent(_ event: OpenAIAgentStreamEvent, slug: String, model: String) {
        switch event {
        case .sessionCreated(let sid):
            openAIAgentSessionId = sid
            OpenAIAgentsSessionClient.saveSessionId(sid, forProject: slug)
            connectionState = .connected(source: "openai-agents · \(model)")
            appendStatusLine("● Sessão ativa: \(sid) · sandbox hospedado conectado", isStderr: false)
        case .textDelta(_, let delta):
            isOpenAIAgentTurnActive = true
            let normalized = delta.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
            processRawOutput(normalized, isStderr: false)
        case .textDone:
            break
        case .statusLine(let line):
            appendStatusLine("  ↳ \(line)", isStderr: false)
        case .requiresAction(let detail):
            appendStatusLine("⚠ Ação requerida pelo agente: \(detail)", isStderr: true)
        case .turnCompleted:
            isOpenAIAgentTurnActive = false
            processRawOutput("\r\n", isStderr: false)
            appendStatusLine("✓ Turno concluído — envie nova tarefa ou redirecione durante a execução.", isStderr: false)
        }
    }

    public func resetOpenAIAgentSession(for slug: String) {
        OpenAIAgentsSessionClient.saveSessionId(nil, forProject: slug)
        openAIAgentSessionId = nil
        isOpenAIAgentTurnActive = false
        disconnect()
    }

    // MARK: - Send

    public func sendInput(_ text: String) {
        if isOpenAIAgentMode {
            sendOpenAIAgentUserMessage(text)
            return
        }
        Task { await client.sendInput(text) }
    }

    public func sendPaste(_ text: String) {
        if isOpenAIAgentMode {
            sendOpenAIAgentUserMessage(text)
            return
        }
        Task { await client.sendPaste(text) }
    }

    private func sendOpenAIAgentUserMessage(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let sessionId = openAIAgentSessionId, !sessionId.isEmpty else {
            connectOpenAIAgentSession(
                slug: openAIAgentSlug.isEmpty ? "sounio" : openAIAgentSlug,
                model: openAIAgentModel,
                instructions: openAIAgentInstructions,
                initialPrompt: trimmed,
                forceNewSession: true
            )
            return
        }

        if isOpenAIAgentTurnActive {
            appendStatusLine("↻ Redirecionando turno em andamento (steering c/ Idempotency-Key)…", isStderr: false)
        }
        processRawOutput("\r\n❯ \(trimmed)\r\n", isStderr: false)
        isOpenAIAgentTurnActive = true

        let apiKey = DirectBrainCredentials.openAIKey
        Task { @MainActor [weak self] in
            do {
                try await OpenAIAgentsSessionClient.shared.sendInputMessage(
                    apiKey: apiKey,
                    sessionId: sessionId,
                    text: trimmed
                )
            } catch {
                self?.isOpenAIAgentTurnActive = false
                self?.appendStatusLine("✗ Falha ao enviar mensagem ao agente: \(error.localizedDescription)", isStderr: true)
            }
        }
    }

    public func sendSignal(_ signal: String = "SIGINT") {
        if isOpenAIAgentMode {
            cancelOpenAIAgentTurn()
            return
        }
        Task { await client.sendSignal(signal) }
    }

    public func sendFocus() {
        guard !isOpenAIAgentMode else { return }
        Task { await client.sendFocus() }
    }

    public func stopProcess() {
        if isOpenAIAgentMode {
            cancelOpenAIAgentTurn()
            return
        }
        Task { await client.stopProcess() }
    }

    private func cancelOpenAIAgentTurn() {
        guard let sessionId = openAIAgentSessionId, !sessionId.isEmpty else { return }
        let apiKey = DirectBrainCredentials.openAIKey
        appendStatusLine("■ Enviando agent.session.input.cancel para interromper o turno atual…", isStderr: false)
        Task { @MainActor [weak self] in
            do {
                try await OpenAIAgentsSessionClient.shared.cancelActiveTurn(apiKey: apiKey, sessionId: sessionId)
                self?.isOpenAIAgentTurnActive = false
            } catch {
                self?.appendStatusLine("✗ Falha ao cancelar turno: \(error.localizedDescription)", isStderr: true)
            }
        }
    }

    public func startProcess(_ command: String) {
        if isOpenAIAgentMode {
            sendOpenAIAgentUserMessage(command)
            return
        }
        Task { await client.startProcess(command) }
    }

    public func approve(_ text: String = "y\n") {
        if isOpenAIAgentMode {
            sendOpenAIAgentUserMessage(text)
            return
        }
        Task { await client.approve(text) }
    }

    public func attachBlockToMemory(blockId: String) {
        guard !isOpenAIAgentMode else { return }
        Task { await client.attachBlockToMemory(blockId: blockId) }
    }

    public func sendResize(cols: Int, rows: Int) {
        grid.resize(cols: cols)
        guard !isOpenAIAgentMode else { return }
        Task { await client.sendResize(cols: cols, rows: rows) }
    }

    // MARK: - Disconnect

    public func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        isOpenAIAgentMode = false
        isOpenAIAgentTurnActive = false
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
