//
//  WorkView+AgentDeck.swift
//  BeagleCockpit
//
//  Agent deck header, lane cards, console views, action docks,
//  and wide-stage layout for WorkView.
//

import SwiftUI
import BeagleCore
import BeagleWorkbenchKit

struct ScoutLaneDrawer: View {
    @Binding var isExpanded: Bool
    let lanes: [AgentLaneState]
    let onOpenLane: (String) -> Void
    let onStartLane: (String) -> Void
    var onSetUpLane: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "tray.full" : "tray")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Drawer lanes")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                    Text("\(lanes.count)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer(minLength: BeagleSpacing.xs)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .foregroundStyle(BeagleTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(BeagleTheme.surface1.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: BeagleSpacing.xs) {
                    ForEach(lanes) { lane in
                        AgentLaneCard(
                            lane: lane,
                            onOpen: { onOpenLane(lane.id) },
                            onStart: { onStartLane(lane.id) },
                            onSetUp: { onSetUpLane(lane.id) }
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct WorkbenchHeader: View {
    let slug: String
    let session: WorkspaceSession?
    let pane: TerminalPane?
    let connectionState: WebSocketState
    let status: String
    let error: String?
    let blockCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: BeagleSpacing.sm) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: "rectangle.3.group.bubble.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .frame(width: 36, height: 36)
                    .background(BeagleTheme.truthObserved.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sounio Agent Deck")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(subtitle)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: BeagleSpacing.sm)
            HStack(spacing: 6) {
                headerPill(workspaceStateLabel, icon: connectionIcon, tint: connectionTint)
                if blockCount > 0 {
                    headerPill("\(blockCount) artifacts", icon: "text.badge.checkmark", tint: BeagleTheme.truthRemembered)
                }
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BeagleTheme.hairline)
                .frame(height: 1)
        }
    }

    private var subtitle: String {
        if let error, !error.isEmpty {
            return "\(slug) needs attention · \(error.replacingOccurrences(of: "fallback", with: "recovery"))"
        }
        if case .connected = connectionState {
            let lane = pane?.title ?? "visual lanes"
            return "\(slug) is live · \(lane) ready · memory is cluster-canonical"
        }
        return "\(slug) · choose a lane to begin a focused workday"
    }

    /// Single honest workspace-state label driven by the live connection.
    /// When connected and authority is known, append a small "· workspace"/
    /// "· local" hint. The vague "warming" authority pill is never shown on its
    /// own (it disappears entirely when disconnected).
    private var workspaceStateLabel: String {
        switch connectionState {
        case .disconnected:
            return "Workspace offline"
        case .connecting, .reconnecting:
            return "Waking workspace…"
        case .failed:
            return "Workspace needs attention"
        case .connected:
            if let hint = knownAuthorityHint {
                return "Workspace live · \(hint)"
            }
            return "Workspace live"
        }
    }

    /// Returns "workspace" or "local" only when authority is actually known;
    /// nil while authority is still warming/unknown so we never surface it.
    private var knownAuthorityHint: String? {
        switch session?.authorityStatus?.authority {
        case "workspace-agent": return "workspace"
        case "cockpit-local": return "local"
        default: return nil
        }
    }

    private var connectionIcon: String {
        switch connectionState {
        case .connected: return "dot.radiowaves.left.and.right"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle"
        case .disconnected: return "moon"
        }
    }

    private var connectionTint: Color {
        switch connectionState {
        case .connected: return BeagleTheme.truthObserved
        case .connecting, .reconnecting: return BeagleTheme.truthRemembered
        case .failed: return BeagleTheme.stateError
        case .disconnected: return BeagleTheme.textTertiary
        }
    }

    private func headerPill(_ label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct AgentConsoleView: View {
    let snapshot: AgentConsoleSnapshot
    let onOpenLane: (String) -> Void
    let onStartLane: (String) -> Void
    var onSetUpLane: (String) -> Void = { _ in }
    let onShowTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: BeagleSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent Console")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(subtitle)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: BeagleSpacing.sm)
                Button(action: onShowTerminal) {
                    Image(systemName: "terminal")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(BeagleTheme.surface1.opacity(0.78), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(BeagleTheme.truthObserved)
            }

            VStack(spacing: BeagleSpacing.sm) {
                ForEach(snapshot.lanes) { lane in
                    AgentLaneCard(
                        lane: lane,
                        onOpen: { onOpenLane(lane.id) },
                        onStart: { onStartLane(lane.id) },
                        onSetUp: { onSetUpLane(lane.id) }
                    )
                }
            }
        }
    }

    private var subtitle: String {
        let authority = snapshot.authority ?? "workspace"
        if snapshot.sessionId == nil {
            return "\(snapshot.projectSlug) · choose a lane to wake the workspace"
        }
        return "\(snapshot.projectSlug) · \(authority) · visual lanes ready"
    }
}

/// Maps a raw lane status token to human-readable English at render time.
/// The raw token is preserved everywhere it is used in logic; only the displayed
/// label is translated here.
private func humanLaneStatus(_ status: String) -> String {
    switch status {
    case "needs_setup": return "Needs setup"
    case "not_started": return "Not running"
    case "unknown": return "Not checked"
    case "ready": return "Ready"
    case "live", "running": return "Running"
    case "idle": return "Idle"
    case "blocked": return "Held (privacy)"
    case "failed": return "Failed"
    case "pending": return "Pending"
    default: return status
    }
}

/// Cleans machine reason/detail strings into human sentences. Pattern-based;
/// already-human sentences are returned unchanged.
private func humanLaneDetail(_ detail: String) -> String {
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasSuffix("is not on PATH") {
        let cli = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        return "\(cli) not installed on the workspace"
    }
    if trimmed.hasSuffix("PROVIDER_URL is not configured")
        || (trimmed.contains("PROVIDER_URL") && trimmed.hasSuffix("is not configured")) {
        return "Needs an API endpoint"
    }
    if trimmed == "provider slot not checked yet" {
        return "Not checked yet"
    }
    // Ready-state reasons (were leaking raw tokens like "codex is on PATH",
    // "QWEN_PROVIDER_URL configured via workspace setup", "MINIMAX_API_KEY is configured").
    if trimmed.hasSuffix("is on PATH") {
        return "Installed on the workspace"
    }
    if trimmed.contains("configured via workspace setup") {
        return "Configured here"
    }
    if trimmed.hasSuffix("is configured") && !trimmed.contains("not configured") {
        return "Configured"
    }
    if trimmed.hasSuffix("is not configured") {
        return "Needs an API key"
    }
    return detail
}

/// State-driven label for the lane action button.
/// Auth model of a lane, inferred from its kind. CLI / subscription lanes
/// (codex, claude-code, kimi) authenticate via the CLI's own subscription login
/// inside the workspace terminal — there is no API key to enter. API lanes
/// (minimax, qwen-coder, glm-air) use the provider Set-up form. The shell lane
/// is just a terminal.
func laneIsSubscriptionCLI(_ kind: String) -> Bool {
    switch kind {
    case "codex", "claude-code", "kimi": return true
    default: return false
    }
}

private func laneActionLabel(status: String, hasPane: Bool, kind: String) -> String {
    if laneIsSubscriptionCLI(kind) {
        switch status {
        case "needs_setup": return "Install"          // CLI not on the workspace PATH
        case "live", "running": return "Open"
        default: return hasPane ? "Open" : "Log in"    // opens the CLI → subscription login
        }
    }
    switch status {
    case "needs_setup": return "Set up"
    case "live", "running": return "Open"
    default: return hasPane ? "Open" : "Start"
    }
}

/// State-driven SF Symbol for the lane action button.
private func laneActionIcon(status: String, hasPane: Bool, kind: String) -> String {
    if laneIsSubscriptionCLI(kind) {
        switch status {
        case "needs_setup": return "arrow.down.circle"          // install
        case "live", "running": return "arrow.up.forward.app"
        default: return hasPane ? "arrow.up.forward.app" : "person.badge.key"  // log in
        }
    }
    switch status {
    case "needs_setup": return "slider.horizontal.3"
    case "live", "running": return "arrow.up.forward.app"
    default: return hasPane ? "play.circle" : "plus.circle"
    }
}

private struct AgentLaneCard: View {
    let lane: AgentLaneState
    let onOpen: () -> Void
    let onStart: () -> Void
    /// When lane.status == "needs_setup", presents the in-app provider Set-up
    /// form (API key + base URL + model) wired to the server-side per-slug
    /// provider-config path via ProviderSetupView. Falls back to onStart when
    /// no setup handler is supplied.
    var onSetUp: (() -> Void)? = nil

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lane.title)
                            .font(BeagleFont.body.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(1)
                        if let provider = lane.providerLabel {
                            Text(provider)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Text(humanLaneDetail(lane.detail))
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(humanLaneStatus(lane.status))
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                        if let memory = lane.memoryStatus {
                            Text(memory)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(memoryTint(memory))
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: 6) {
                    if let block = lane.lastBlockTitle {
                        Label(block, systemImage: "text.badge.checkmark")
                            .lineLimit(1)
                    } else {
                        Label("No block yet", systemImage: "rectangle.dashed")
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if lane.pendingApproval {
                        Label("approval", systemImage: "checkmark.circle")
                    }
                    Button(action: actionHandler) {
                        Label(
                            laneActionLabel(status: lane.status, hasPane: lane.paneId != nil, kind: lane.kind),
                            systemImage: laneActionIcon(status: lane.status, hasPane: lane.paneId != nil, kind: lane.kind)
                        )
                        .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(lane.status == "needs_setup" ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                    .accessibilityIdentifier("work.lane.\(lane.id).action")
                }
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
            }
            .padding(12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("work.lane.\(lane.id)")
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(lane.isActive ? BeagleTheme.truthObserved.opacity(0.55) : BeagleTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// needs_setup should eventually present the provider Set-up form via
    /// onSetUp; until that is wired we fall back to onStart (openLane).
    private var actionHandler: () -> Void {
        if lane.status == "needs_setup", let onSetUp { return onSetUp }
        return onStart
    }

    private var icon: String {
        switch lane.kind {
        case "codex": return "curlybraces.square"
        case "claude-code": return "bolt.square"
        case "minimax": return "hammer"
        case "kimi": return "brain.head.profile"
        case "qwen-coder": return "wrench.adjustable"
        case "glm-air": return "server.rack"
        case "palmyra-x5": return "doc.text.magnifyingglass"
        case "jamba": return "waveform.path.ecg"
        case "pegasus": return "video.badge.waveform"
        case "lfm2": return "sensor"
        case "cursor": return "cursorarrow.motionlines"
        default: return "terminal"
        }
    }

    private var tint: Color {
        if lane.memoryStatus == "blocked" || lane.status == "needs_setup" { return BeagleTheme.postureWarm }
        if lane.status == "failed" { return BeagleTheme.stateError }
        if lane.isActive || lane.status == "live" || lane.status == "running" { return BeagleTheme.truthObserved }
        return BeagleTheme.truthRemembered
    }

    private var background: Color {
        lane.isActive ? BeagleTheme.truthObserved.opacity(0.10) : BeagleTheme.surface1.opacity(0.62)
    }

    private func memoryTint(_ memory: String) -> Color {
        switch memory {
        case "remembered": return BeagleTheme.truthObserved
        case "blocked": return BeagleTheme.postureWarm
        case "failed": return BeagleTheme.stateError
        default: return BeagleTheme.textTertiary
        }
    }
}

struct AgentConsoleDock: View {
    let state: WorkbenchActionDockState
    let onInput: () -> Void
    let onInterrupt: () -> Void
    let onApprove: () -> Void
    let onRemember: () -> Void
    let onFocus: () -> Void
    let onScout: () -> Void
    let onCompare: () -> Void
    let onOpenTerminal: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                dockButton("Input", icon: "keyboard", isEnabled: state.canSendInput, action: onInput)
                dockButton("Interrupt", icon: "pause.circle", isEnabled: state.canInterrupt, action: onInterrupt)
                dockButton("Approve", icon: "checkmark.circle", isEnabled: state.canApprove, action: onApprove)
                dockButton("Remember", icon: "externaldrive.connected.to.line.below", isEnabled: state.canRemember, action: onRemember)
                dockButton("Focus", icon: "scope", action: onFocus)
                dockButton("Scout", icon: "brain.head.profile", action: onScout)
                dockButton("Compare", icon: "arrow.triangle.branch", action: onCompare)
                dockButton("Terminal", icon: "terminal", action: onOpenTerminal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, BeagleSpacing.xs)
        .background(.ultraThinMaterial)
    }

    private func dockButton(
        _ label: String,
        icon: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(BeagleFont.caption2.font)
                    .lineLimit(1)
            }
            .frame(width: 82)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? BeagleTheme.textSecondary : BeagleTheme.textTertiary.opacity(0.55))
        .disabled(!isEnabled)
    }
}

struct VisualWorkbenchActionDock: View {
    let state: WorkbenchActionDockState
    let onInterrupt: () -> Void
    let onApprove: () -> Void
    let onRemember: () -> Void
    let onFocus: () -> Void
    let onScout: () -> Void
    let onCompare: () -> Void
    let onRuntime: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            visualDockButton("Focus", icon: "scope", tint: BeagleTheme.truthObserved, action: onFocus)
            visualDockButton("Scout", icon: "brain.head.profile", tint: BeagleTheme.truthRemembered, action: onScout)
            visualDockButton("Compare", icon: "arrow.triangle.branch", tint: BeagleTheme.textData, action: onCompare)
            Divider().overlay(BeagleTheme.hairline).frame(height: 24)
            visualDockButton("Remember", icon: "externaldrive.connected.to.line.below", tint: BeagleTheme.truthObserved, isEnabled: state.canRemember, action: onRemember)
            visualDockButton("Approve", icon: "checkmark.seal", tint: BeagleTheme.truthObserved, isEnabled: state.canApprove, action: onApprove)
            visualDockButton("Interrupt", icon: "pause.circle", tint: BeagleTheme.postureWarm, isEnabled: state.canInterrupt, action: onInterrupt)
            Spacer(minLength: BeagleSpacing.md)
            visualDockButton("Refresh", icon: "arrow.clockwise", tint: BeagleTheme.textSecondary, action: onRefresh)
            visualDockButton("Runtime Log", icon: "terminal", tint: BeagleTheme.textTertiary, action: onRuntime)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(BeagleTheme.hairline).frame(height: 1)
        }
    }

    private func visualDockButton(
        _ label: String,
        icon: String,
        tint: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(tint.opacity(isEnabled ? 0.13 : 0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? tint : BeagleTheme.textTertiary.opacity(0.55))
        .disabled(!isEnabled)
    }
}

struct VisualWorkbenchStage: View {
    let state: VisualWorkCanvasState
    let onOpenLane: (VisualAgentLaneSnapshot) -> Void
    let onStartLane: (VisualAgentLaneSnapshot) -> Void
    var onSetUpLane: (VisualAgentLaneSnapshot) -> Void = { _ in }
    let onRuntimeLane: (VisualAgentLaneSnapshot) -> Void
    let onSelectArtifact: (VisualWorkArtifact) -> Void
    let onRememberArtifact: (VisualWorkArtifact) -> Void
    let onBakeOffArtifact: (VisualWorkArtifact) -> Void
    let onRuntime: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VisualAgentLaneBoard(
                lanes: state.lanes,
                onOpenLane: onOpenLane,
                onStartLane: onStartLane,
                onSetUpLane: onSetUpLane,
                onRuntime: onRuntimeLane
            )
            .frame(maxHeight: 252)

            Divider().overlay(BeagleTheme.hairline)

            HStack(spacing: 0) {
                VisualWorkCanvas(
                    state: state,
                    onSelectArtifact: onSelectArtifact,
                    onRuntime: onRuntime,
                    onRemember: {
                        if let artifact = state.selectedArtifact {
                            onRememberArtifact(artifact)
                        }
                    },
                    onBakeOff: {
                        if let artifact = state.selectedArtifact {
                            onBakeOffArtifact(artifact)
                        }
                    }
                )

                Divider().overlay(BeagleTheme.hairline)

                WorkMemoryInspector(
                    state: state,
                    selectedArtifactId: state.selectedArtifact?.id,
                    onSelect: onSelectArtifact,
                    onRemember: onRememberArtifact,
                    onBakeOff: onBakeOffArtifact,
                    onRuntime: onRuntime
                )
                .frame(width: 360)
            }
        }
    }
}

private struct VisualAgentLaneBoard: View {
    let lanes: [VisualAgentLaneSnapshot]
    let onOpenLane: (VisualAgentLaneSnapshot) -> Void
    let onStartLane: (VisualAgentLaneSnapshot) -> Void
    var onSetUpLane: (VisualAgentLaneSnapshot) -> Void = { _ in }
    let onRuntime: (VisualAgentLaneSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Agent Deck")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("roles first, providers second")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                Label("runtime hidden until requested", systemImage: "terminal.fill")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [
                        GridItem(.fixed(92), spacing: 10),
                        GridItem(.fixed(92), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(lanes) { lane in
                        VisualAgentLaneCard(
                            lane: lane,
                            onOpen: { onOpenLane(lane) },
                            onStart: { onStartLane(lane) },
                            onRuntime: { onRuntime(lane) },
                            onSetUp: { onSetUpLane(lane) }
                        )
                        .frame(width: 260)
                    }
                }
                .padding(.trailing, BeagleSpacing.lg)
            }
        }
        .padding(BeagleSpacing.lg)
        .background(
            LinearGradient(
                colors: [BeagleTheme.surface0.opacity(0.90), BeagleTheme.surface1.opacity(0.66)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct VisualAgentLaneCard: View {
    let lane: VisualAgentLaneSnapshot
    let onOpen: () -> Void
    let onStart: () -> Void
    let onRuntime: () -> Void
    /// When the lane needs setup, presents the in-app provider Set-up form
    /// (API key + base URL + model) wired to the server-side per-slug
    /// provider-config path via ProviderSetupView. Falls back to onStart when
    /// no setup handler is supplied.
    var onSetUp: (() -> Void)? = nil

    /// True when the lane is unconfigured and should read as a Set-up affordance.
    private var needsSetup: Bool {
        lane.readiness == "needs_setup" || lane.status == "needs_setup"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lane.title)
                            .font(BeagleFont.body.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(1)
                        if let provider = lane.providerLabel {
                            Text(provider)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Text(humanLaneDetail(lane.taskSummary))
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(humanLaneStatus(lane.status))
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                        if let memory = lane.memoryStatus {
                            Text(memory)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(memoryTint(memory))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("work.lane.\(lane.id)")

            VStack(spacing: 7) {
                Button(action: actionHandler) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(needsSetup ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                .accessibilityLabel(Text(laneActionLabel(status: needsSetup ? "needs_setup" : lane.status, hasPane: lane.runtimeAvailable, kind: lane.kind)))
                .accessibilityIdentifier("work.lane.\(lane.id).action")
                Button(action: onRuntime) {
                    Image(systemName: "terminal")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BeagleTheme.textTertiary)
                .accessibilityLabel(Text("Open runtime log"))
                .accessibilityIdentifier("work.lane.\(lane.id).runtime")
            }
        }
        .padding(11)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(lane.isActive ? BeagleTheme.truthObserved.opacity(0.55) : BeagleTheme.hairline, lineWidth: 1)
        )
    }

    /// needs_setup should eventually present the provider Set-up form via
    /// onSetUp; until that is wired we fall back to onStart (openLane).
    private var actionHandler: () -> Void {
        if needsSetup, let onSetUp { return onSetUp }
        return onStart
    }

    private var actionIcon: String {
        if laneIsSubscriptionCLI(lane.kind) {
            if needsSetup { return "arrow.down.circle.fill" }                 // install
            if lane.status == "live" || lane.status == "running" { return "arrow.up.forward.app.fill" }
            return lane.runtimeAvailable ? "arrow.up.forward.app.fill" : "person.badge.key.fill"  // log in
        }
        if needsSetup { return "slider.horizontal.3" }
        if lane.status == "live" || lane.status == "running" { return "arrow.up.forward.app.fill" }
        return lane.runtimeAvailable ? "play.circle.fill" : "plus.circle.fill"
    }

    private var icon: String {
        switch lane.kind {
        case "codex": return "curlybraces.square"
        case "claude-code": return "bolt.square"
        case "minimax": return "hammer"
        case "kimi": return "brain.head.profile"
        case "qwen-coder": return "wrench.adjustable"
        case "glm-air": return "server.rack"
        case "human": return "terminal"
        default: return "sparkles.rectangle.stack"
        }
    }

    private var tint: Color {
        if lane.readiness == "needs_setup" { return BeagleTheme.postureWarm }
        if lane.status == "failed" { return BeagleTheme.stateError }
        if lane.isActive || lane.status == "live" || lane.status == "running" { return BeagleTheme.truthObserved }
        return BeagleTheme.truthRemembered
    }

    private var background: Color {
        lane.isActive ? BeagleTheme.truthObserved.opacity(0.11) : BeagleTheme.surface1.opacity(0.62)
    }

    private func lanePill(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(BeagleFont.caption2.font)
            .lineLimit(1)
            .foregroundStyle(label == "redacted" || label == "needs_setup" ? BeagleTheme.postureWarm : BeagleTheme.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(BeagleTheme.surface0.opacity(0.62), in: Capsule())
    }

    private func memoryTint(_ memory: String) -> Color {
        switch memory {
        case "remembered": return BeagleTheme.truthObserved
        case "blocked": return BeagleTheme.postureWarm
        case "failed": return BeagleTheme.stateError
        default: return BeagleTheme.textTertiary
        }
    }
}
