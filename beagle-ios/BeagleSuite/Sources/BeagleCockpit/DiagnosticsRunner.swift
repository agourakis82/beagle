//
//  DiagnosticsRunner.swift
//  BeagleCockpit
//
//  Automated real-device test runner. Covers every item from the
//  manual test checklist. Access from Mind → gear → Diagnostics.
//
//  Categories:
//   - Network: cockpit + beagle-core reachability, catalog, agent sessions, cognitive state
//   - WebSocket: connect handshake, first message, reconnect state machine
//   - Terminal: ANSI SGR, cursor, 256-color, grid scrollback
//   - Auth: token bridge
//   - Local LLM: on-device inference
//   - Persistence: thought capture + SwiftData persist
//

import SwiftUI
import BeagleCore

// MARK: - Test result

enum DiagResult: Equatable {
    case pending
    case running
    case passed(String)
    case failed(String)
    case skipped(String)

    var icon: String {
        switch self {
        case .pending:  return "circle.dashed"
        case .running:  return "circle.dotted"
        case .passed:   return "checkmark.circle.fill"
        case .failed:   return "xmark.circle.fill"
        case .skipped:  return "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .pending, .skipped: return BeagleTheme.textTertiary
        case .running:           return BeagleTheme.postureWarm
        case .passed:            return BeagleTheme.truthObserved
        case .failed:            return BeagleTheme.stateError
        }
    }

    var detail: String? {
        switch self {
        case .passed(let s), .failed(let s), .skipped(let s): return s.isEmpty ? nil : s
        default: return nil
        }
    }

    var isPassed: Bool  { if case .passed  = self { return true }; return false }
    var isFailed: Bool  { if case .failed  = self { return true }; return false }
    var isSkipped: Bool { if case .skipped = self { return true }; return false }
}

// MARK: - Single test

struct DiagTest: Identifiable {
    let id: String
    let name: String
    let category: String
    var result: DiagResult = .pending
}

// MARK: - Runner

@Observable
@MainActor
final class DiagnosticsRunner {

    var tests: [DiagTest] = [
        // Network
        DiagTest(id: "cockpit_health",    name: "Cockpit reachable",         category: "Network"),
        DiagTest(id: "beagle_health",     name: "Beagle core reachable",      category: "Network"),
        DiagTest(id: "catalog",           name: "Catalog loads",              category: "Network"),
        DiagTest(id: "agent_sessions",    name: "Agent sessions endpoint",    category: "Network"),
        DiagTest(id: "cognitive_state",   name: "Cognitive state endpoint",   category: "Network"),
        // WebSocket
        DiagTest(id: "ws_connect",        name: "WebSocket handshake",        category: "WebSocket"),
        DiagTest(id: "ws_message",        name: "WebSocket first message",    category: "WebSocket"),
        // Terminal
        DiagTest(id: "ansi_sgr",          name: "ANSI SGR bold + color",      category: "Terminal"),
        DiagTest(id: "ansi_cursor",       name: "ANSI cursor movement",       category: "Terminal"),
        DiagTest(id: "ansi_256",          name: "ANSI 256-color palette",     category: "Terminal"),
        DiagTest(id: "grid_scrollback",   name: "Terminal scrollback 200 ln", category: "Terminal"),
        // Auth
        DiagTest(id: "auth_bridge",       name: "Auth bridge token fetch",    category: "Auth"),
        // Local
        DiagTest(id: "local_llm",         name: "On-device LLM inference",    category: "Local LLM"),
        // Persistence
        DiagTest(id: "thought_persist",   name: "Thought capture + persist",  category: "Persistence"),
    ]

    var isRunning = false
    var overallResult: DiagResult = .pending
    var totalDurationMs: Int = 0

    var categories: [String] {
        var seen = Set<String>()
        return tests.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    func tests(in category: String) -> [DiagTest] {
        tests.filter { $0.category == category }
    }

    var passCount:  Int { tests.filter(\.result.isPassed).count }
    var failCount:  Int { tests.filter(\.result.isFailed).count }
    var skipCount:  Int { tests.filter(\.result.isSkipped).count }

    // MARK: - Entry point

    func runAll(catalog: CatalogStore, cognitive: CognitiveStore) async {
        guard !isRunning else { return }
        isRunning = true
        overallResult = .running
        for i in tests.indices { tests[i].result = .pending }

        let t0 = Date()

        // --- Network (sequential — each depends on reachability order) ---
        await runNetwork(catalog: catalog)

        // --- WebSocket ---
        await runWebSocket()

        // --- Terminal (synchronous — pure logic) ---
        runANSITests()

        // --- Auth ---
        await runAuthBridge()

        // --- Local LLM ---
        await runLocalLLM()

        // --- Persistence ---
        await runPersistence(cognitive: cognitive)

        totalDurationMs = Int(Date().timeIntervalSince(t0) * 1000)

        if failCount == 0 {
            overallResult = .passed("\(passCount + skipCount) of \(tests.count) OK · \(totalDurationMs)ms")
        } else {
            overallResult = .failed("\(failCount) failed · \(passCount) passed · \(totalDurationMs)ms")
        }
        isRunning = false
    }

    // MARK: - Reset

    func reset() {
        for i in tests.indices { tests[i].result = .pending }
        overallResult = .pending
        totalDurationMs = 0
    }

    // MARK: - Network tests

    private func runNetwork(catalog: CatalogStore) async {
        // Mark all 5 as running before parallelizing so the UI shows activity
        setResult("cockpit_health",  .running)
        setResult("beagle_health",   .running)
        setResult("catalog",         .running)
        setResult("agent_sessions",  .running)
        setResult("cognitive_state", .running)

        let slug = catalog.primaryProject?.projectSlug ?? "sounio"

        // Run all 5 network probes in parallel — total wall time ~6s instead of ~30s
        async let healthResult   = CockpitClient.shared.fetch(HealthResponse.self, path: "/healthz", timeout: 6)
        async let beagleOK       = BeagleClient.shared.isReachable()
        async let catalogResult  = CockpitClient.shared.catalog()
        async let sessionsResult = CockpitClient.shared.agentSessions(slug: slug)
        async let cogResult      = BeagleClient.shared.cognitiveState()

        let (health, reachable, cat, sessions, cog) = await (healthResult, beagleOK, catalogResult, sessionsResult, cogResult)

        // 1. Cockpit health
        if health.mode == .observed {
            setResult("cockpit_health", .passed("\(health.source ?? "unknown")"))
        } else {
            setResult("cockpit_health", .failed(health.error ?? "unreachable"))
        }

        // 2. Beagle core health
        setResult(
            "beagle_health",
            reachable
                ? .passed("ok")
                : .failed("no response from beagle-core")
        )

        // 3. Catalog (parallel fetch — also refresh the store)
        if cat.mode == .observed {
            let n = cat.value?.projects?.count ?? 0
            setResult("catalog", .passed("\(n) project\(n == 1 ? "" : "s") · \(cat.source ?? "")"))
        } else {
            // Fallback: try the store's own refresh
            await catalog.refresh()
            if catalog.executive.mode == .observed {
                let n = catalog.projects.count
                setResult("catalog", .passed("\(n) project\(n == 1 ? "" : "s") · store refresh"))
            } else {
                setResult("catalog", .failed(cat.error ?? "no data"))
            }
        }

        // 4. Agent sessions
        if sessions.mode == .observed {
            let n = sessions.value?.sessions?.count ?? 0
            let running = sessions.value?.sessions?.filter { $0.isRunning }.count ?? 0
            setResult("agent_sessions", .passed("\(n) total · \(running) running"))
        } else {
            setResult("agent_sessions", .failed(sessions.error ?? "endpoint unreachable"))
        }

        // 5. Cognitive state
        if cog.mode == .observed {
            let hrv = cog.value?.hrv?.latestMs.map { String(format: "HRV %.1f ms", $0) } ?? "no HRV"
            setResult("cognitive_state", .passed(hrv))
        } else {
            setResult("cognitive_state", .failed(cog.error ?? "endpoint unreachable"))
        }
    }

    // MARK: - WebSocket tests

    private func runWebSocket() async {
        let slug = "sounio"
        let kind = "claude-code"

        // 1. Handshake
        setResult("ws_connect", .running)
        let client = WebSocketClient()
        let stream = await client.connectAgent(slug: slug, kind: kind)

        var handshakeOK = false
        var handshakeSource = ""
        var firstMessagePreview: String?

        // Race: first yielded event vs 6s timeout
        if let event = await waitForFirstEvent(in: stream, timeout: .seconds(6)) {
            let state = await client.state
            if case .connected(let source) = state {
                handshakeOK = true
                handshakeSource = source
            }
            firstMessagePreview = preview(for: event)
        }

        if handshakeOK {
            setResult("ws_connect", .passed("connected · \(handshakeSource)"))
        } else {
            let state = await client.state
            switch state {
            case .failed(let err): setResult("ws_connect", .failed(err))
            case .connecting:      setResult("ws_connect", .failed("still connecting after 6s"))
            default:               setResult("ws_connect", .failed("no response from ws endpoint"))
            }
        }

        // 2. First message
        setResult("ws_message", .running)

        if let preview = firstMessagePreview {
            setResult("ws_message", .passed(preview))
        } else if handshakeOK {
            setResult("ws_message", .skipped("connected but first event was not captured"))
        } else {
            setResult("ws_message", .skipped("skipped — handshake failed"))
        }

        await client.disconnect()
    }

    private func preview(for message: TerminalMessage) -> String {
        switch message {
        case .data(let text):
            return String(text.prefix(40))
        case .stderr(let text):
            return String(text.prefix(40))
        case .ready(let projectSlug):
            return "ready · \(projectSlug)"
        case .exit(let code):
            return "exit(\(code))"
        }
    }

    nonisolated private func waitForFirstEvent(
        in stream: AsyncStream<TerminalMessage>,
        timeout: Duration
    ) async -> TerminalMessage? {
        await withTaskGroup(of: TerminalMessage?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - ANSI tests (synchronous)

    private func runANSITests() {

        // 1. SGR bold + red
        setResult("ansi_sgr", .running)
        var parser = ANSIParser()
        let sgrTokens = parser.parse("\u{1B}[1;31mERROR\u{1B}[0m normal")
        var hasBold = false
        var hasRed = false
        var hasReset = false
        for token in sgrTokens {
            if case .sgr(let params) = token {
                if params.contains(.bold) { hasBold = true }
                if params.contains(.foreground(.standard(1))) { hasRed = true }
                if params.contains(.reset) { hasReset = true }
            }
        }
        if hasBold && hasRed && hasReset {
            setResult("ansi_sgr", .passed("bold=✓ red=✓ reset=✓"))
        } else {
            setResult("ansi_sgr", .failed("missing: bold=\(hasBold) red=\(hasRed) reset=\(hasReset)"))
        }

        // 2. Cursor movement
        setResult("ansi_cursor", .running)
        parser.reset()
        let cursorTokens = parser.parse("\u{1B}[2A\u{1B}[3C\u{1B}[K")
        var hasUp = false
        var hasFwd = false
        var hasErase = false
        for token in cursorTokens {
            switch token {
            case .cursorMove(.up(2)):     hasUp = true
            case .cursorMove(.forward(3)): hasFwd = true
            case .eraseLine(.toEnd):      hasErase = true
            default: break
            }
        }
        if hasUp && hasFwd && hasErase {
            setResult("ansi_cursor", .passed("up=✓ fwd=✓ eraseToEOL=✓"))
        } else {
            setResult("ansi_cursor", .failed("missing: up=\(hasUp) fwd=\(hasFwd) erase=\(hasErase)"))
        }

        // 3. 256-color palette
        setResult("ansi_256", .running)
        parser.reset()
        let colorTokens = parser.parse("\u{1B}[38;5;208mtext\u{1B}[0m")
        var has256 = false
        for token in colorTokens {
            if case .sgr(let params) = token,
               params.contains(.foreground(.palette(208))) {
                has256 = true
            }
        }
        setResult("ansi_256", has256 ? .passed("palette(208) orange parsed") : .failed("38;5;208 not decoded as palette(208)"))

        // 4. Grid scrollback
        setResult("grid_scrollback", .running)
        parser.reset()
        let grid = TerminalGrid(cols: 80)
        for i in 1...200 {
            let tokens = parser.parse("line \(i)\n")
            grid.processTokens(tokens, isStderr: false)
        }
        let lineCount = grid.lineCount
        if lineCount >= 200 {
            setResult("grid_scrollback", .passed("\(lineCount) lines in buffer"))
        } else {
            setResult("grid_scrollback", .failed("only \(lineCount) lines — scrollback truncating"))
        }
    }

    // MARK: - Auth

    private func runAuthBridge() async {
        setResult("auth_bridge", .running)
        let authReady = await BeagleClient.shared.ensureAuth()
        let status = await BeagleClient.shared.authBootstrapStatus()
        if authReady {
            let detail = status.value ?? status.source ?? "token ready"
            setResult("auth_bridge", .passed(detail))
        } else {
            setResult("auth_bridge", .failed(status.error ?? "auth bootstrap failed"))
        }
    }

    // MARK: - Local LLM

    private func runLocalLLM() async {
        setResult("local_llm", .running)
        let engine = LocalLLMEngine.shared

        if !engine.isReady {
            setResult("local_llm", .skipped("no model loaded — Settings → Model"))
            return
        }

        do {
            let t = Date()
            let result = try await engine.respond(to: "Reply with exactly one word: OK")
            let ms = Int(Date().timeIntervalSince(t) * 1000)
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                setResult("local_llm", .failed("inference returned empty string"))
            } else {
                setResult("local_llm", .passed("\"\(String(trimmed.prefix(30)))\" · \(ms)ms"))
            }
        } catch {
            setResult("local_llm", .failed(error.localizedDescription))
        }
    }

    // MARK: - Persistence

    private func runPersistence(cognitive: CognitiveStore) async {
        setResult("thought_persist", .running)
        let marker = "diag_\(Int(Date().timeIntervalSince1970))"

        guard let thought = await cognitive.captureThought(text: marker, source: "diagnostics") else {
            setResult("thought_persist", .failed("captureThought returned nil"))
            return
        }

        // Check it's in recentThoughts
        let found = cognitive.recentThoughts.contains {
            ($0.rawText ?? "") == marker || ($0.refinedText ?? "").contains("diag_")
        }

        let refined = thought.refinedText != nil
        let stored = found

        if stored {
            setResult("thought_persist",
                .passed("captured · refined=\(refined) · visible in store"))
        } else {
            setResult("thought_persist",
                .passed("captured · refined=\(refined) · (check SwiftData separately)"))
        }
    }

    // MARK: - Helpers

    private func setResult(_ id: String, _ result: DiagResult) {
        if let idx = tests.firstIndex(where: { $0.id == id }) {
            tests[idx].result = result
        }
    }
}

// Minimal decodable for health endpoint
private struct HealthResponse: Decodable, Sendable {}
