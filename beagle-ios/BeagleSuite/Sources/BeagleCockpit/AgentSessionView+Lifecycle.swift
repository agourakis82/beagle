//
//  AgentSessionView+Lifecycle.swift
//  BeagleCockpit
//
//  Session lifecycle actions, polling, reconnection, and terminal diagnostics.
//

import SwiftUI
import BeagleCore

extension AgentSessionView {

    // MARK: - Actions

    /// Connect to (or deploy) an agent session.
    ///
    /// Flow:
    ///  1. Fetch sessions list from cockpit
    ///  2a. Session running → connect WebSocket immediately
    ///  2b. Session exists but paused → resume it, then poll until ready
    ///  2c. No session → deploy via startAgentSession, then poll until ready
    ///  3. Error reaching cockpit → show actionable message
    func spawnSession() async {
        if selectedKind == .openAIAgent {
            guard DirectBrainCredentials.hasOpenAI else {
                sessionState = .error("Chave OpenAI ausente. Abra Ajustes → Cérebro · MoE · Voz para configurar sua sk-…")
                return
            }
            let activeModel = DirectBrainCredentials.openAIModel
            let sessionLabel = OpenAIAgentsSessionClient.savedSessionId(forProject: currentSlug)
                ?? "openai-hosted · \(activeModel)"
            sessionState = .running(podName: sessionLabel)
            terminal.connectOpenAIAgentSession(
                slug: currentSlug,
                model: activeModel,
                initialPrompt: pinnedLaneQuestions[currentSlug]
            )
            LiveActivityManager.shared.startAgentActivity(
                slug: currentSlug,
                kind: selectedKind.rawValue,
                sessionId: sessionLabel
            )
            persistShellObjective()
            return
        }

        sessionState = .pending(message: "Checking session state...")

        // Fetch real sessions from cockpit
        let result = await CockpitClient.shared.agentSessions(slug: currentSlug)

        guard result.mode == .observed, let sessions = result.value?.sessions else {
            let err = result.error ?? "no response"
            sessionState = .error("Cockpit unreachable: \(err). Check public gateway or Tailscale connectivity.")
            return
        }

        laneSessions = sessions

        let existing = sessions.first(where: { $0.kind == selectedKind.rawValue })

        if let existing {
            switch existing.phase {
            case .running:
                connectToSession(existing)
                return
            case .paused:
                sessionState = .pending(message: "Resuming \(selectedKind.displayName)...")
                let resumed = await CockpitClient.shared.resumeAgentSession(slug: currentSlug, kind: selectedKind.rawValue)
                if resumed.mode != .observed {
                    sessionState = .error("Could not resume session: \(resumed.error ?? "unknown")")
                    return
                }
            case .pending:
                sessionState = .pending(message: pendingMessage(for: existing, fallback: "Session pending..."))
            }
        } else {
            sessionState = .pending(message: "Starting \(selectedKind.displayName)...")
            let started = await CockpitClient.shared.startAgentSession(slug: currentSlug, kind: selectedKind.rawValue)
            if started.mode != .observed {
                sessionState = .error("Could not start session: \(started.error ?? "unknown")")
                return
            }
        }

        // Poll until the pod becomes ready (up to 120s)
        await pollUntilReady()
    }

    /// Poll `/api/projects/:slug/agent/session/:kind` until readyReplicas > 0 or timeout.
    private func pollUntilReady() async {
        let maxWait = 120  // seconds
        let pollInterval = 3  // seconds
        var elapsed = 0

        while elapsed < maxWait {
            try? await Task.sleep(for: .seconds(pollInterval))
            elapsed += pollInterval

            let detail = await CockpitClient.shared.agentSession(slug: currentSlug, kind: selectedKind.rawValue)
            guard let session = detail.value else {
                if let error = detail.error {
                    sessionState = .error(error)
                    return
                }
                continue
            }

            switch session.phase {
            case .running:
                connectToSession(session)
                return
            case .paused:
                terminal.disconnect()
                sessionState = .paused
                LiveActivityManager.shared.updateAgentActivity(status: "paused", tokens: 0, snippet: "session paused")
                return
            case .pending:
                let message = "\(pendingMessage(for: session, fallback: "Pod pending")) · \(elapsed)s elapsed"
                sessionState = .pending(message: message)
                terminal.appendDiagnosticLine("⏳ \(message)")
            }
        }

        sessionState = .error("Pod did not become ready in \(maxWait)s. Check cluster from workspace.")
    }

    private func pollUntilPaused() async {
        let maxWait = 30
        let pollInterval = 2
        var elapsed = 0

        while elapsed < maxWait {
            try? await Task.sleep(for: .seconds(pollInterval))
            elapsed += pollInterval

            let detail = await CockpitClient.shared.agentSession(slug: currentSlug, kind: selectedKind.rawValue)
            guard let session = detail.value else {
                if let error = detail.error {
                    sessionState = .error(error)
                    return
                }
                continue
            }

            switch session.phase {
            case .paused:
                terminal.disconnect()
                sessionState = .paused
                LiveActivityManager.shared.updateAgentActivity(status: "paused", tokens: 0, snippet: "session paused")
                return
            case .running, .pending:
                sessionState = .pending(message: "Pausing session... \(elapsed)s")
            }
        }

        sessionState = .error("Pause request did not settle within \(maxWait)s.")
    }

    private func connectToSession(_ session: AgentSession) {
        let podName = session.podName ?? session.name ?? "\(currentSlug)-\(selectedKind.rawValue)"
        sessionState = .running(podName: podName)
        terminal.connect(slug: currentSlug, kind: selectedKind.rawValue)
        LiveActivityManager.shared.startAgentActivity(slug: currentSlug, kind: selectedKind.rawValue, sessionId: podName)
        persistShellObjective(using: session)
    }

    func restoreExistingSession() async -> AgentSession? {
        let listResult = await CockpitClient.shared.agentSessions(slug: currentSlug)
        if let sessions = listResult.value?.sessions,
           let existing = sessions.first(where: { $0.kind == selectedKind.rawValue }) ?? sessions.first {
            laneSessions = sessions
            return existing
        }

        let detailResult = await CockpitClient.shared.agentSession(slug: currentSlug, kind: selectedKind.rawValue)
        guard let session = detailResult.value else { return nil }

        // Ignore explicit idle/not-created responses, but trust any real phase immediately.
        if (session.status ?? "").lowercased() == "idle",
           (session.name == nil || session.name?.isEmpty == true),
           session.pods?.isEmpty != false,
           session.readyReplicas ?? 0 == 0,
           session.replicas ?? 0 == 0 {
            return nil
        }

        return session
    }

    func applyRestoredSession(_ session: AgentSession) {
        switch session.phase {
        case .running:
            connectToSession(session)
        case .paused:
            terminal.disconnect()
            sessionState = .paused
            persistShellObjective(using: session)
        case .pending:
            sessionState = .pending(message: pendingMessage(for: session, fallback: "Session pending..."))
            persistShellObjective(using: session)
        }
    }

    func reconnectTerminal() async {
        if selectedKind == .openAIAgent {
            await spawnSession()
            return
        }
        guard sessionState.isRunning else {
            await spawnSession()
            return
        }

        let detail = await CockpitClient.shared.agentSession(slug: currentSlug, kind: selectedKind.rawValue)
        guard let session = detail.value else {
            sessionState = .error(detail.error ?? "Could not refresh session before reconnect.")
            return
        }

        switch session.phase {
        case .running:
            connectToSession(session)
        case .paused:
            terminal.disconnect()
            sessionState = .paused
        case .pending:
            sessionState = .pending(message: pendingMessage(for: session, fallback: "Session pending..."))
            await pollUntilReady()
        }
    }

    /// Pause the remote session and detach the terminal.
    func pauseSession() async {
        if selectedKind == .openAIAgent {
            terminal.disconnect()
            sessionState = .paused
            LiveActivityManager.shared.updateAgentActivity(status: "paused", tokens: 0, snippet: "OpenAI Agents session paused")
            return
        }
        sessionState = .pending(message: "Pausing session...")
        let paused = await CockpitClient.shared.pauseAgentSession(slug: currentSlug, kind: selectedKind.rawValue)
        guard paused.mode == .observed else {
            sessionState = .error("Could not pause session: \(paused.error ?? "unknown")")
            return
        }
        if let session = paused.value, session.phase == .paused {
            terminal.disconnect()
            sessionState = .paused
            LiveActivityManager.shared.updateAgentActivity(status: "paused", tokens: 0, snippet: "session paused")
            return
        }
        await pollUntilPaused()
    }

    /// Stop the remote session and return to idle.
    func stopSession() async {
        if selectedKind == .openAIAgent {
            terminal.stopProcess()
            terminal.resetOpenAIAgentSession(for: currentSlug)
            sessionState = .idle
            LiveActivityManager.shared.endAgentActivity(finalStatus: "stopped")
            return
        }
        let stopped = await CockpitClient.shared.stopAgentSession(slug: currentSlug, kind: selectedKind.rawValue)
        guard stopped.mode == .observed else {
            sessionState = .error("Could not stop session: \(stopped.error ?? "unknown")")
            return
        }
        terminal.disconnect()
        sessionState = .idle
        LiveActivityManager.shared.endAgentActivity(finalStatus: "stopped")
    }

    /// Same as spawnSession — checks for running session and connects.
    private func resumeLastSession() async {
        await spawnSession()
    }

    func switchProject(to slug: String) {
        guard slug != currentSlug else { return }
        terminal.disconnect()
        LiveActivityManager.shared.endAgentActivity(finalStatus: "lane switched")
        scratchpadEntries = []
        laneSessions = []
        sessionState = .idle
        currentSlug = slug
        cognitive.activeProjectSlug = slug
        persistShellObjective()
    }

    func refreshScratchpad() async {
        let result = await CockpitClient.shared.agentScratchpad(slug: currentSlug)
        if let entries = result.value?.entries, !entries.isEmpty {
            withAnimation(BeagleMotion.normal) {
                scratchpadEntries = Array(entries.suffix(5))
            }
        }
    }

    func refreshLaneSessions() async {
        let result = await CockpitClient.shared.agentSessions(slug: currentSlug)
        if let sessions = result.value?.sessions {
            laneSessions = sessions
            persistShellObjective()
        } else if result.mode != .observed {
            laneSessions = []
        }
    }

    // MARK: - Diagnostics & status formatting

    var terminalDiagnosticsText: String? {
        guard terminal.hasAbnormalExit else { return nil }
        let formatter = ISO8601DateFormatter()
        let sessionSummary: String = {
            switch sessionState {
            case .idle:
                return "idle"
            case .pending(let message):
                return "pending: \(message)"
            case .running(let podName):
                return "running: \(podName)"
            case .paused:
                return "paused"
            case .error(let message):
                return "error: \(message)"
            }
        }()
        let connectionSummary: String = {
            switch terminal.connectionState {
            case .disconnected:
                return "disconnected"
            case .connecting:
                return "connecting"
            case .connected(let source):
                return "connected via \(source)"
            case .reconnecting(let attempt):
                return "reconnecting attempt \(attempt)"
            case .failed(let message):
                return "failed: \(message)"
            }
        }()

        return [
            "Beagle terminal diagnostics",
            "timestamp: \(formatter.string(from: .now))",
            "project: \(currentSlug)",
            "agent: \(selectedKind.rawValue)",
            "session: \(sessionSummary)",
            "connection: \(connectionSummary)",
            "exit_code: \(terminal.lastExitCode ?? 0)",
            "exit_detail: \(terminal.lastExitDetail ?? "unknown")"
        ].joined(separator: "\n")
    }

    var terminalSessionIdentityText: String? {
        guard case .running(let podName) = sessionState else { return nil }
        switch terminal.connectionState {
        case .connected(let source):
            return "\(podName) via \(source)"
        case .connecting:
            return "\(podName) connecting"
        case .reconnecting(let attempt):
            return "\(podName) reconnecting (\(attempt))"
        case .failed(let message):
            return "\(podName) failed: \(message)"
        case .disconnected:
            return "\(podName) detached"
        }
    }

    private func pendingMessage(for session: AgentSession, fallback: String) -> String {
        if let action = session.action, !action.isEmpty {
            return action.replacingOccurrences(of: "-", with: " ").capitalized
        }
        if let podPhase = session.pods?.first?.phase, !podPhase.isEmpty {
            return "Pod \(podPhase.lowercased())"
        }
        if let status = session.status, !status.isEmpty {
            return status.replacingOccurrences(of: "-", with: " ").capitalized
        }
        return fallback
    }
}
