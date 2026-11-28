//
//  WorkView+InspectorRails.swift
//  BeagleCockpit
//
//  Work memory inspector, workspace session rail, workbench inspector,
//  compact evidence rail, and terminal block row for WorkView.
//

import SwiftUI
import BeagleCore
import BeagleWorkbenchKit
struct WorkMemoryInspector: View {
    let state: VisualWorkCanvasState
    let selectedArtifactId: String?
    let onSelect: (VisualWorkArtifact) -> Void
    let onRemember: (VisualWorkArtifact) -> Void
    let onBakeOff: (VisualWorkArtifact) -> Void
    let onRuntime: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .frame(width: 30, height: 30)
                    .background(BeagleTheme.truthObserved.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory & Proof")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("Cluster memory, provenance, review state.")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            GlassPanel(elevation: .flush, truth: .observed) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("What Beagle can safely remember")
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Text(state.workMemoryLine)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(5)
                    Text(state.workMemoryStatus)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                    Text(state.restrictedLeakCheck)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(state.restrictedLeakCheck.contains("redacted") ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                }
            }

            HStack {
                Text("Evidence Objects")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                Button(action: onRuntime) {
                    Label("Runtime Log", systemImage: "terminal")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BeagleTheme.textTertiary)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if state.recentArtifacts.isEmpty {
                        InspectorEmptyState(hasVisualArtifacts: !state.recentArtifacts.isEmpty)
                    } else {
                        ForEach(state.recentArtifacts) { artifact in
                            VisualProofArtifactRow(
                                artifact: artifact,
                                isSelected: artifact.id == selectedArtifactId,
                                onSelect: { onSelect(artifact) },
                                onRemember: { onRemember(artifact) },
                                onBakeOff: { onBakeOff(artifact) }
                            )
                        }
                    }
                }
                .padding(.bottom, BeagleSpacing.md)
            }
        }
        .padding(BeagleSpacing.md)
        .background(BeagleTheme.surface0.opacity(0.70))
    }
}

private struct VisualProofArtifactRow: View {
    let artifact: VisualWorkArtifact
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemember: () -> Void
    let onBakeOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: artifactIcon(artifact.kind))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artifact.title)
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(2)
                        Text(artifact.summary)
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(3)
                        FlowPillRow(labels: artifact.evidenceBadges)
                    }
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button(action: onRemember) {
                    Label("Remember", systemImage: "externaldrive.connected.to.line.below")
                }
                .disabled(artifact.sourceBlockId == nil)
                Button(action: onBakeOff) {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                }
                .disabled(artifact.sourceBlockId == nil || artifact.restrictedRedacted)
            }
            .font(BeagleFont.caption2.font)
            .buttonStyle(.borderless)
            .foregroundStyle(BeagleTheme.truthObserved)
        }
        .padding(12)
        .background(BeagleTheme.surface1.opacity(isSelected ? 0.68 : 0.44), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? BeagleTheme.truthObserved.opacity(0.70) : BeagleTheme.hairline, lineWidth: 1)
        )
    }

    private var tint: Color {
        if artifact.restrictedRedacted { return BeagleTheme.postureWarm }
        switch artifact.memoryStatus {
        case "remembered": return BeagleTheme.truthObserved
        case "blocked": return BeagleTheme.postureWarm
        case "failed": return BeagleTheme.stateError
        default: return BeagleTheme.truthRemembered
        }
    }
}

private struct InspectorEmptyState: View {
    let hasVisualArtifacts: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No replay blocks yet", systemImage: "rectangle.dashed")
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textSecondary)
            Text(hasVisualArtifacts
                ? "Live artifacts are visible on the bench. Replay will fill this proof list after refresh."
                : "Start a lane. Proof blocks will appear here after Beagle observes work.")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BeagleTheme.surface1.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(BeagleTheme.hairline, lineWidth: 1))
    }
}

func artifactIcon(_ kind: VisualWorkArtifactKind) -> String {
    switch kind {
    case .agent: return "sparkles.rectangle.stack"
    case .diff: return "plusminus"
    case .test: return "checklist.checked"
    case .deploy: return "shippingbox"
    case .memory: return "externaldrive.connected.to.line.below"
    case .runtime: return "terminal"
    case .approval: return "checkmark.seal"
    case .unknown: return "questionmark.square"
    }
}

private struct WorkspaceSessionRail: View {
    let session: WorkspaceSession?
    let activePaneId: String?
    let onSelectPane: (TerminalPane) -> Void
    let onNewShell: () -> Void
    let onNewCodex: () -> Void
    let onNewClaude: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text("Workspace")
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
                .textCase(.uppercase)
            if let session {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(BeagleFont.body.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                    Text(session.id)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Divider().overlay(BeagleTheme.hairline)

            Text("Panes")
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
            ForEach(session?.panes ?? []) { pane in
                Button {
                    onSelectPane(pane)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: paneIcon(pane.kind))
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pane.title)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(1)
                            Text(pane.kind)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        (pane.id == activePaneId ? BeagleTheme.truthObserved.opacity(0.12) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(spacing: 8) {
                Button(action: onNewShell) {
                    Label("New Shell", systemImage: "plus.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: onNewCodex) {
                    Label("Codex Pane", systemImage: "sparkles.rectangle.stack")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: onNewClaude) {
                    Label("Claude Pane", systemImage: "bolt.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(BeagleFont.caption.font)
            .buttonStyle(.borderless)
            .foregroundStyle(BeagleTheme.textSecondary)
        }
        .padding(BeagleSpacing.md)
        .background(BeagleTheme.surface0.opacity(0.72))
    }

    private func paneIcon(_ kind: String) -> String {
        switch kind {
        case "codex": return "curlybraces.square"
        case "claude-code": return "bolt.square"
        case "cursor": return "cursorarrow.motionlines"
        case "opencode", "kimi": return "sparkles"
        default: return "terminal"
        }
    }
}

private struct WorkbenchInspector: View {
    let blocks: [TerminalBlock]
    let selectedBlockId: String?
    let workMemoryLine: String
    let workMemoryStatus: String
    let onSelect: (TerminalBlock) -> Void
    let onRemember: (TerminalBlock) -> Void
    let onBakeOff: (TerminalBlock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            Text("Inspector")
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
                .textCase(.uppercase)

            GlassPanel(elevation: .flush, truth: .observed) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Latest work memory")
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Text(workMemoryLine)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(4)
                    Text(workMemoryStatus)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                }
            }

            Text("Notebook Blocks")
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(blocks) { block in
                        TerminalBlockRow(
                            block: block,
                            isSelected: block.id == selectedBlockId,
                            onSelect: { onSelect(block) },
                            onRemember: { onRemember(block) },
                            onBakeOff: { onBakeOff(block) }
                        )
                    }
                }
                .padding(.bottom, BeagleSpacing.md)
            }
        }
        .padding(BeagleSpacing.md)
        .background(BeagleTheme.surface0.opacity(0.68))
    }
}

struct CompactEvidenceRail: View {
    let artifacts: [VisualWorkArtifact]
    let selectedArtifactId: String?
    let onSelect: (VisualWorkArtifact) -> Void
    let onRemember: (VisualWorkArtifact) -> Void
    let onBakeOff: (VisualWorkArtifact) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.sm) {
                if artifacts.isEmpty {
                    Text("Evidence will appear here after an agent or shell action.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .padding(12)
                        .frame(width: 280, alignment: .leading)
                        .background(BeagleTheme.surface1.opacity(0.44), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ForEach(artifacts.prefix(12)) { artifact in
                        VisualProofArtifactRow(
                            artifact: artifact,
                            isSelected: artifact.id == selectedArtifactId,
                            onSelect: { onSelect(artifact) },
                            onRemember: { onRemember(artifact) },
                            onBakeOff: { onBakeOff(artifact) }
                        )
                        .frame(width: 280)
                    }
                }
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
        }
        .background(BeagleTheme.surface0.opacity(0.72))
    }
}

private struct TerminalBlockRow: View {
    let block: TerminalBlock
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemember: () -> Void
    let onBakeOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: blockIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(statusTint)
                    Text(block.title.isEmpty ? block.kind.capitalized : block.title)
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(memoryLabel)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }
                if !block.command.isEmpty {
                    Text(block.command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(block.status)
                    if let exitCode = block.exitCode {
                        Text("exit \(exitCode)")
                    }
                    if let duration = block.durationMs {
                        Text("\(duration / 1000)s")
                    }
                }
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)

                if block.privacyClass != "restricted_local_only" {
                    HStack(spacing: 10) {
                        Button(action: onRemember) {
                            Label("Remember", systemImage: "externaldrive.connected.to.line.below")
                                .font(BeagleFont.caption2.font)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(BeagleTheme.truthObserved)

                        Button(action: onBakeOff) {
                            Label("Bake-off", systemImage: "rectangle.split.2x1")
                                .font(BeagleFont.caption2.font)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(BeagleTheme.truthRemembered)
                    }
                } else {
                    Button(action: onBakeOff) {
                        Label("Proof only", systemImage: "lock.shield")
                            .font(BeagleFont.caption2.font)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(BeagleTheme.postureWarm)
                }
            }
            .padding(10)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? BeagleTheme.truthObserved.opacity(0.55) : BeagleTheme.hairline, lineWidth: 1)
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
        .buttonStyle(.plain)
    }

    private var blockIcon: String {
        if block.privacyClass == "restricted_local_only" { return "lock.shield" }
        if block.kind == "test" { return "checkmark.rectangle.stack" }
        if block.kind == "agent" { return "sparkles.rectangle.stack" }
        return "terminal"
    }

    private var memoryLabel: String {
        switch block.memoryStatus {
        case "remembered": return "saved"
        case "blocked": return "blocked"
        case "queued": return "queued"
        case "failed": return "failed"
        default:
            return block.privacyClass == "restricted_local_only" ? "restricted" : "curated"
        }
    }

    private var statusTint: Color {
        if block.privacyClass == "restricted_local_only" || block.memoryStatus == "blocked" {
            return BeagleTheme.postureWarm
        }
        if block.memoryStatus == "failed" { return BeagleTheme.stateError }
        if block.memoryStatus == "remembered" { return BeagleTheme.truthObserved }
        return BeagleTheme.textTertiary
    }

    private var rowBackground: Color {
        isSelected ? BeagleTheme.truthObserved.opacity(0.10) : BeagleTheme.surface1.opacity(0.52)
    }
}
