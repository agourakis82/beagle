//
//  AgentSessionView+Chrome.swift
//  BeagleCockpit
//
//  Layout sections and visual subcomponents for AgentSessionView.
//

import SwiftUI
import BeagleCore

extension AgentSessionView {

    // MARK: - Header

    var header: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: selectedKind.iconSystemName)
                .font(.system(size: 20))
                .foregroundStyle(BeagleTheme.truthObserved)
                .symbolEffect(.pulse, isActive: terminal.connectionState.isConnected)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedKind.displayName)
                    .font(BeagleFont.title3.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                connectionStatus
            }

            Spacer()

            TruthBadge(terminal.truthMode)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(.ultraThinMaterial)
    }

    var projectPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                ForEach(projectOptions) { project in
                    Button {
                        switchProject(to: project.projectSlug)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: BeagleSpacing.xxs) {
                                Text(projectDisplayName(project.projectSlug))
                                    .font(BeagleFont.footnote.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(project.projectSlug == currentSlug ? BeagleTheme.textPrimary : BeagleTheme.textSecondary)
                                if project.projectSlug == currentSlug {
                                    PresencePill(label: "active", systemImage: "scope", tint: BeagleTheme.truthObserved)
                                }
                            }

                            Text(project.branch ?? project.preferredPrBase ?? "branch not declared")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)

                            HStack(spacing: BeagleSpacing.xxs) {
                                Image(systemName: project.workspacePod == nil ? "moon.zzz.fill" : "shippingbox.fill")
                                    .font(.system(size: 10))
                                Text(project.workspacePod ?? "habitat parked")
                                    .font(BeagleFont.caption2.font)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(project.projectSlug == currentSlug ? BeagleTheme.truthObserved.opacity(0.9) : BeagleTheme.textTertiary)
                        }
                        .frame(width: 196, alignment: .leading)
                        .padding(.horizontal, BeagleSpacing.md)
                        .padding(.vertical, BeagleSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                                .fill(project.projectSlug == currentSlug ? BeagleTheme.truthObserved.opacity(0.09) : BeagleTheme.surface1.opacity(0.62))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                                .strokeBorder(project.projectSlug == currentSlug ? BeagleTheme.truthObserved.opacity(0.24) : Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.sm)
        }
    }

    var companionPresenceCard: some View {
        PresenceFieldCard(
            state: companionPresenceState,
            eyebrow: "Live Companion",
            title: companionHeadline,
            body: companionBody,
            detail: companionDetail,
            truth: companionTruth
        ) {
            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(
                    label: selectedKind.displayName,
                    systemImage: selectedKind.iconSystemName,
                    tint: companionTint
                )
                if case .running(let podName) = sessionState {
                    PresencePill(
                        label: podName,
                        systemImage: "shippingbox",
                        tint: BeagleTheme.truthRemembered
                    )
                }
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.top, BeagleSpacing.sm)
        .padding(.bottom, BeagleSpacing.xs)
    }

    var laneOverviewCard: some View {
        PresenceFieldCard(
            state: .attentive,
            eyebrow: "Project Lane",
            title: laneOverviewTitle,
            body: laneOverviewBody,
            detail: laneOverviewDetail,
            truth: laneOverviewTruth
        ) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                ForEach(laneAgentStatuses) { status in
                    Button {
                        guard sessionState == .idle else { return }
                        selectedKind = status.kind
                        lastAgentKindRaw = status.kind.rawValue
                    } label: {
                        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                            PresencePill(
                                label: status.kind.displayName,
                                systemImage: status.kind.iconSystemName,
                                tint: laneStatusTint(status)
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(laneStatusActivity(status))
                                    .font(BeagleFont.footnote.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)

                                Text(laneStatusDetail(status))
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: BeagleSpacing.sm)

                            PresencePill(
                                label: laneStatusSelectionLabel(status),
                                systemImage: laneStatusSelectionIcon(status),
                                tint: laneStatusSelectionTint(status)
                            )
                        }
                        .padding(.horizontal, BeagleSpacing.sm)
                        .padding(.vertical, BeagleSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.md)
                                .fill(selectedKind == status.kind ? BeagleTheme.truthObserved.opacity(0.08) : BeagleTheme.surface0.opacity(0.34))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BeagleRadius.md)
                                .strokeBorder(selectedKind == status.kind ? BeagleTheme.truthObserved.opacity(0.22) : Color.white.opacity(0.05), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(sessionState != .idle)
                }
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.top, BeagleSpacing.sm)
        .padding(.bottom, BeagleSpacing.xs)
    }

    private var connectionStatus: some View {
        HStack(spacing: BeagleSpacing.xxs) {
            connectionIcon
            connectionText
        }
        .font(BeagleFont.data.font)
    }

    @ViewBuilder
    private var connectionIcon: some View {
        switch sessionState {
        case .idle:
            Image(systemName: "circle.dashed")
                .foregroundStyle(BeagleTheme.textTertiary)
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundStyle(BeagleTheme.postureWarm)
                .symbolEffect(.variableColor)
        case .running:
            switch terminal.connectionState {
            case .connected:
                Image(systemName: "circle.fill")
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .symbolEffect(.pulse)
            case .connecting:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(BeagleTheme.postureWarm)
                    .symbolEffect(.variableColor)
            case .reconnecting:
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(BeagleTheme.postureWarm)
            case .failed:
                Image(systemName: "xmark.circle")
                    .foregroundStyle(BeagleTheme.stateError)
            case .disconnected:
                Image(systemName: "circle")
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        case .paused:
            Image(systemName: "pause.circle")
                .foregroundStyle(BeagleTheme.postureWarm)
        case .error:
            Image(systemName: "xmark.circle")
                .foregroundStyle(BeagleTheme.stateError)
        }
    }

    @ViewBuilder
    private var connectionText: some View {
        switch sessionState {
        case .idle:
            Text("no active session").foregroundStyle(BeagleTheme.textTertiary)
        case .pending(let message):
            Text(message).foregroundStyle(BeagleTheme.postureWarm)
        case .running(let pod):
            switch terminal.connectionState {
            case .connected(let source):
                Text("live \u{00B7} \(pod) via \(source)").foregroundStyle(BeagleTheme.truthObserved)
            case .connecting:
                Text("connecting...").foregroundStyle(BeagleTheme.postureWarm)
            case .reconnecting(let n):
                Text("reconnecting (\(n))...").foregroundStyle(BeagleTheme.postureWarm)
            case .failed(let err):
                Text(err).foregroundStyle(BeagleTheme.stateError)
            case .disconnected:
                Text("running \u{00B7} \(pod)").foregroundStyle(BeagleTheme.textSecondary)
            }
        case .paused:
            Text("paused (state preserved)").foregroundStyle(BeagleTheme.postureWarm)
        case .error(let msg):
            Text(msg).foregroundStyle(BeagleTheme.stateError)
        }
    }

    // MARK: - Agent picker

    var agentPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                ForEach(AgentKind.allCases) { kind in
                    Button {
                        guard sessionState == .idle else { return }
                        withAnimation(BeagleMotion.snappy) {
                            selectedKind = kind
                            lastAgentKindRaw = kind.rawValue
                        }
                    } label: {
                        Label(kind.displayName, systemImage: kind.iconSystemName)
                            .font(BeagleFont.footnote.font)
                            .padding(.horizontal, BeagleSpacing.md)
                            .padding(.vertical, BeagleSpacing.xs + 2)
                            .frame(minHeight: 44)
                            .foregroundStyle(
                                selectedKind == kind ? BeagleTheme.truthObserved : BeagleTheme.textSecondary
                            )
                            .background(
                                Capsule().fill(
                                    selectedKind == kind
                                    ? BeagleTheme.truthObserved.opacity(0.12)
                                    : Color.white.opacity(0.04)
                                )
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    selectedKind == kind
                                    ? BeagleTheme.truthObserved.opacity(0.25)
                                    : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(sessionState != .idle)
                    .sensoryFeedback(.selection, trigger: selectedKind)
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.vertical, BeagleSpacing.sm)
        }
    }

    // MARK: - Scratchpad (agent-to-agent communication)

    var scratchpadStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                ForEach(scratchpadEntries.prefix(5)) { entry in
                    HStack(spacing: BeagleSpacing.xs) {
                        Text(entry.agent ?? "agent")
                            .font(BeagleFont.dataSmall.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthRemembered)
                        Text(entry.text ?? "")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, BeagleSpacing.sm)
                    .padding(.vertical, BeagleSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: BeagleRadius.sm)
                            .fill(BeagleTheme.surface1.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: BeagleRadius.sm)
                                    .strokeBorder(BeagleTheme.truthRemembered.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.vertical, BeagleSpacing.xs)
        }
        .background(.ultraThinMaterial.opacity(0.5))
    }

    // MARK: - Session controls

    var sessionControls: some View {
        HStack(spacing: BeagleSpacing.sm) {
            switch sessionState {
            case .idle:
                Button {
                    Task { await spawnSession() }
                } label: {
                    Label("Connect", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButton())

            case .running:
                Button {
                    Task { await pauseSession() }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.postureWarm))

                Button {
                    Task { await stopSession() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.stateError))

            case .paused:
                Button {
                    Task { await spawnSession() }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButton())

            case .pending(let message):
                SpawningIndicator(agentKind: selectedKind, messageOverride: message)

            case .error:
                Button {
                    Task { await spawnSession() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButton(color: BeagleTheme.stateError))
            }

            Spacer()
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.sm)
    }

    // MARK: - Input bar

    var inputBar: some View {
        BeagleInputBar(
            text: $inputText,
            placeholder: "command...",
            mode: .terminal,
            isEnabled: sessionState.isRunning,
            onSubmit: { cmd in
                terminal.sendInput(cmd + "\n")
            },
            onSpecialKey: { key in
                terminal.sendInput(key.escapeSequence)
            }
        )
    }
}

// MARK: - Spawning Indicator (rotating messages)

struct SpawningIndicator: View {
    let agentKind: AgentKind
    let messageOverride: String?
    @State private var message = ""
    @State private var index = 0

    internal init(agentKind: AgentKind, messageOverride: String?) {
        self.agentKind = agentKind
        self.messageOverride = messageOverride
    }

    private var messages: [String] {
        [
            "Requesting pod from cluster...",
            "Pulling container image...",
            "Mounting persistent volume...",
            "Starting \(agentKind.displayName)...",
        ]
    }

    var body: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: agentKind.iconSystemName)
                .font(.system(size: 12))
                .foregroundStyle(BeagleTheme.postureWarm)
                .symbolEffect(.pulse, isActive: true)

            Text(message.isEmpty ? messages[0] : message)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.postureWarm)
                .contentTransition(.numericText())
                .animation(BeagleMotion.normal, value: message)

            ProgressView()
                .controlSize(.small)
                .tint(BeagleTheme.postureWarm)
        }
        .task {
            while !Task.isCancelled {
                if let messageOverride, !messageOverride.isEmpty {
                    message = messageOverride
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                message = messages[index % messages.count]
                index += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

// MARK: - Agent Session Gradient

/// Living background that reacts to session state.
struct AgentSessionGradient: View {
    let sessionState: AgentSessionView.AgentSessionState
    let connectionState: WebSocketState
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    internal init(
        sessionState: AgentSessionView.AgentSessionState,
        connectionState: WebSocketState
    ) {
        self.sessionState = sessionState
        self.connectionState = connectionState
    }

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: animatedPoints,
            colors: gradientColors
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: sessionState.isRunning)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.06
        return [
            SIMD2(0,     0),     SIMD2(0.5,   0),       SIMD2(1,     0),
            SIMD2(0+d,   0.5-d), SIMD2(0.5+d, 0.5+d),   SIMD2(1-d,   0.5+d),
            SIMD2(0,     1),     SIMD2(0.5,   1),       SIMD2(1,     1)
        ]
    }

    private var gradientColors: [Color] {
        let base = Color(red: 0.02, green: 0.03, blue: 0.07)
        let isLive = sessionState.isRunning && connectionState.isConnected

        return [
            BeagleTheme.truthObserved.opacity(isLive ? 0.25 : 0.0),
            Color(white: 0.04),
            Color(white: 0.03),

            BeagleTheme.postureWarm.opacity(isPending ? 0.15 : 0.0),
            base,
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }

    private var isPending: Bool {
        if case .pending = sessionState { return true }
        return false
    }
}
