//
//  AgentSessionView+Presentation.swift
//  BeagleCockpit
//
//  Companion presence copy, project lane overview state, and status formatting.
//

import SwiftUI
import BeagleCore

extension AgentSessionView {

    // MARK: - Companion presence

    var companionHeadline: String {
        switch sessionState {
        case .idle:
            return "No live channel yet"
        case .pending:
            return "The companion is crossing into the cluster"
        case .running:
            if terminal.connectionState.isConnected {
                return "The channel is open"
            }
            return "The agent is present, but the line is unsettled"
        case .paused:
            return "The mind is resting in place"
        case .error:
            return "The channel broke, but the context remained"
        }
    }

    var companionBody: String {
        switch sessionState {
        case .idle:
            return "Wake a pod when you want a second intelligence in the room for \(projectDisplayName(currentSlug)). The workspace will hold its place once the channel is live."
        case .pending(let message):
            return message
        case .running(let podName):
            if terminal.connectionState.isConnected {
                return "\(selectedKind.displayName) is inhabiting \(podName). Speak plainly; this is a live working channel, not just a deployment."
            }
            return "\(selectedKind.displayName) is still anchored to \(podName), but the terminal line needs recovery."
        case .paused:
            return "The pod is paused without losing continuity. Resume when you want the same thread of work back in front of you."
        case .error(let error):
            return error
        }
    }

    var companionTint: Color {
        companionPresenceState.tint
    }

    var companionPresenceState: BeaglePresenceState {
        switch sessionState {
        case .idle:
            return .dormant
        case .pending:
            return .attentive
        case .running:
            return terminal.connectionState.isConnected ? .active : .attentive
        case .paused:
            return .dormant
        case .error:
            return .strained
        }
    }

    var companionDetail: String {
        switch terminal.connectionState {
        case .disconnected:
            return "no websocket attached right now, but the pod state may still be intact"
        case .connecting:
            return "opening the live shell and waiting for the channel to settle"
        case .connected(let source):
            return "source: \(source) · session continuity is preserved in the cluster"
        case .reconnecting(let attempt):
            return "reconnect attempt \(attempt) · context should survive the interruption"
        case .failed(let error):
            return error
        }
    }

    var companionTruth: TruthMode {
        switch sessionState {
        case .idle:
            return .declared
        case .pending:
            return .remembered
        case .running:
            return terminal.connectionState.isConnected ? .observed : .remembered
        case .paused:
            return .remembered
        case .error:
            return .stale
        }
    }

    // MARK: - Project & lane overview

    func projectDisplayName(_ slug: String) -> String {
        slug
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var projectOptions: [Project] {
        if !catalog.projects.isEmpty {
            return catalog.projects
        }

        return [
            Project(projectSlug: "sounio", preferredPrBase: "integration/sounio-dev-ready-base"),
            Project(projectSlug: "scratch"),
            Project(projectSlug: "hyperbolic-semantic-networks")
        ]
    }

    var laneOverviewTitle: String {
        if let laneState, laneState.activeMindCount > 0 {
            return "Choose the mind you want to enter in \(laneState.displayName)"
        }
        if let laneState, laneState.pausedMindCount > 0 {
            return "\(laneState.displayName) is holding preserved threads"
        }
        return "\(projectDisplayName(currentSlug)) is ready for multiple minds"
    }

    var laneOverviewBody: String {
        if let laneState, let livingQuestion = laneState.livingQuestion {
            return "This lane is carrying a real living question: “\(livingQuestion)”. Read the board before you enter a terminal, then choose the mind that should carry that question forward."
        }
        if let laneState, let resultSignal = laneState.resultSignal {
            return "This lane already has a result trail: \(resultSignal). Choose the mind that should interpret it or move it forward."
        }
        return "Read this board before you drop into one terminal. It tells you which agent is active, which one is waiting, and which one has not been invited into the lane yet."
    }

    var laneOverviewDetail: String {
        if let laneState {
            return "\(laneState.countsLine) · \(laneState.nextRecommendedMove)"
        }
        return "\(laneSessions.filter { $0.isRunning }.count) live · \(laneSessions.filter { $0.phase == .paused }.count) paused · \(laneAgentStatuses.count) visible minds"
    }

    var laneOverviewTruth: TruthMode {
        if laneOverview?.value?.laneResult != nil {
            return laneOverview?.mode ?? .observed
        }
        return laneSessions.isEmpty ? .declared : .observed
    }

    var laneAgentStatuses: [LaneAgentStatus] {
        let knownKinds = AgentKind.allCases.filter { $0 != .custom }
        let known = knownKinds.map { kind in
            LaneAgentStatus(kind: kind, session: laneSessions.first(where: { $0.kind == kind.rawValue }))
        }

        let extra = laneSessions.compactMap { session -> LaneAgentStatus? in
            guard let kindRaw = session.kind,
                  AgentKind(rawValue: kindRaw) == nil else { return nil }
            return LaneAgentStatus(kind: .custom, session: session)
        }

        return known + extra
    }

    private var laneState: ProjectLaneState? {
        let project = projectOptions.first(where: { $0.projectSlug == currentSlug }) ?? catalog.primaryProject
        guard let project else { return nil }
        let carriedObjective =
            laneSessions.first(where: \.isRunning)?.presentedActivityLine
            ?? laneSessions.first(where: { $0.phase == .paused })?.presentedActivityLine
            ?? laneSessions.first?.presentedActivityLine
        return ProjectLaneState(
            project: project,
            sessions: laneSessions,
            scienceJobs: currentSlug == (cognitive.activeProjectSlug ?? currentSlug) ? cognitive.activeJobs : [],
            laneResult: laneOverview?.value?.laneResult,
            recentTrail: currentSlug == (cognitive.activeProjectSlug ?? currentSlug) ? CognitiveStore.recentTrailSnippets(from: cognitive.recentThoughts) : [],
            truth: laneOverviewTruth,
            isCurrent: currentSlug == (cognitive.activeProjectSlug ?? currentSlug),
            livingQuestion: pinnedLaneQuestions[project.projectSlug],
            carriedObjective: carriedObjective
        )
    }

    var pinnedLaneQuestions: [String: String] {
        guard let data = pinnedLaneQuestionsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    func laneStatusActivity(_ status: LaneAgentStatus) -> String {
        guard let session = status.session else {
            return "Not started in this lane yet."
        }

        if let summary = session.activity?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }

        if let excerpt = session.activity?.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !excerpt.isEmpty {
            return excerpt
        }

        if let action = session.action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty {
            return action
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        switch session.phase {
        case .running:
            return "Live and ready in the cluster."
        case .paused:
            return "Paused with context preserved."
        case .pending:
            return "Crossing into the cluster and not ready yet."
        }
    }

    func laneStatusDetail(_ status: LaneAgentStatus) -> String {
        guard let session = status.session else {
            return "Select \(status.kind.displayName) to start a fresh thread here."
        }

        if let source = session.activity?.source, !source.isEmpty,
           let updatedAt = session.activity?.updatedAt, !updatedAt.isEmpty,
           let relative = relativeTime(from: updatedAt) {
            return "\(source) update · \(relative)"
        }

        switch session.phase {
        case .running:
            if let pod = session.podName {
                return "live in \(pod)"
            }
            return "live now"
        case .paused:
            return "paused but recoverable"
        case .pending:
            if let status = session.status, !status.isEmpty {
                return status.replacingOccurrences(of: "-", with: " ").lowercased()
            }
            return "waiting for readiness"
        }
    }

    func laneStatusTint(_ status: LaneAgentStatus) -> Color {
        guard let session = status.session else {
            return BeagleTheme.textTertiary
        }

        switch session.phase {
        case .running:
            return BeagleTheme.truthObserved
        case .paused:
            return BeagleTheme.postureWarm
        case .pending:
            return BeagleTheme.truthRemembered
        }
    }

    private func sessionDisplayName(_ session: AgentSession) -> String {
        if let kind = session.kind, !kind.isEmpty {
            return kind
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        if let name = session.name, !name.isEmpty {
            return name
        }

        return "Agent"
    }

    func persistShellObjective(using session: AgentSession? = nil) {
        let candidate = session
            ?? laneSessions.first(where: { $0.kind == selectedKind.rawValue })
            ?? laneSessions.first(where: \.isRunning)
            ?? laneSessions.first

        let objective = candidate.flatMap(shellObjectiveText(for:)) ?? defaultShellObjective
        lastAgentObjective = objective
        lastAgentObjectiveProjectSlug = currentSlug
    }

    private func shellObjectiveText(for session: AgentSession) -> String? {
        if let summary = session.activity?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }

        if let excerpt = session.activity?.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !excerpt.isEmpty {
            return excerpt
        }

        if let action = session.action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty {
            return action
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        switch session.phase {
        case .running:
            return "\(sessionDisplayName(session)) is live and ready in the lane."
        case .paused:
            return "\(sessionDisplayName(session)) is paused with context preserved."
        case .pending:
            return "\(sessionDisplayName(session)) is still crossing into the cluster."
        }
    }

    private var defaultShellObjective: String {
        "Choose a mind in \(projectDisplayName(currentSlug)) to pick up the next thread."
    }

    func laneStatusSelectionLabel(_ status: LaneAgentStatus) -> String {
        if selectedKind == status.kind {
            return "entered"
        }
        if status.session == nil {
            return "dormant"
        }
        switch status.session?.phase {
        case .running:
            return "live"
        case .paused:
            return "paused"
        case .pending:
            return "waiting"
        case nil:
            return "dormant"
        }
    }

    func laneStatusSelectionIcon(_ status: LaneAgentStatus) -> String {
        if selectedKind == status.kind {
            return "arrow.down.right.circle.fill"
        }
        if status.session == nil {
            return "moon.zzz.fill"
        }
        switch status.session?.phase {
        case .running:
            return "waveform.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .pending:
            return "hourglass.circle.fill"
        case nil:
            return "moon.zzz.fill"
        }
    }

    func laneStatusSelectionTint(_ status: LaneAgentStatus) -> Color {
        if selectedKind == status.kind {
            return BeagleTheme.truthObserved
        }
        return laneStatusTint(status)
    }

    private func relativeTime(from isoString: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        if let date = formatter.date(from: isoString) ?? fallback.date(from: isoString) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
        }
        return nil
    }
}

struct LaneAgentStatus: Identifiable {
    let kind: AgentKind
    let session: AgentSession?

    internal init(kind: AgentKind, session: AgentSession?) {
        self.kind = kind
        self.session = session
    }

    var id: String {
        session?.kind ?? kind.rawValue
    }
}
