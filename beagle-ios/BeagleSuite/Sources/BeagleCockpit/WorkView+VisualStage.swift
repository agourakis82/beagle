//
//  WorkView+VisualStage.swift
//  BeagleCockpit
//
//  Visual workbench action dock, wide stage, and visual agent lane board/cards for WorkView.
//

import SwiftUI
import BeagleCore
import BeagleWorkbenchKit

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
