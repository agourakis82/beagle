//
//  WorkView+VisualCanvas.swift
//  BeagleCockpit
//
//  Visual work canvas, artifact strips, memory & proof inspector,
//  evidence rails, and terminal block row for WorkView.
//

import SwiftUI
import BeagleCore
import BeagleWorkbenchKit

struct VisualWorkCanvas: View {
    let state: VisualWorkCanvasState
    let onSelectArtifact: (VisualWorkArtifact) -> Void
    let onRuntime: () -> Void
    let onRemember: () -> Void
    let onBakeOff: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                hero
                if state.recentArtifacts.isEmpty {
                    EmptyWorkdayPanel(onStart: onRuntime)
                } else {
                    WorkArtifactStrip(
                        artifacts: state.recentArtifacts,
                        selectedArtifactId: state.selectedArtifact?.id,
                        onSelect: onSelectArtifact
                    )
                }
                selectedArtifactPanel
            }
            .padding(BeagleSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [BeagleTheme.surface0.opacity(0.86), BeagleTheme.surface1.opacity(0.56)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active Work")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .textCase(.uppercase)
                    Text(displayHeadline)
                        .font(BeagleFont.title2.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(state.restrictedLeakCheck)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(state.restrictedLeakCheck.contains("redacted") ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(BeagleTheme.surface1.opacity(0.7), in: Capsule())
            }
            Text(displayPrimaryAction)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: onRemember) {
                    Label("Remember", systemImage: "externaldrive.connected.to.line.below")
                }
                .disabled(state.selectedArtifact == nil)
                Button(action: onBakeOff) {
                    Label("Bake-off", systemImage: "rectangle.split.2x1")
                }
                .disabled(state.selectedArtifact == nil)
                Button(action: onRuntime) {
                    Label("Runtime Log", systemImage: "terminal")
                }
            }
            .font(BeagleFont.caption.font)
            .buttonStyle(.bordered)
        }
        .padding(BeagleSpacing.lg)
        .background(BeagleTheme.surface1.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(BeagleTheme.hairline, lineWidth: 1))
    }

    private var displayHeadline: String {
        state.selectedArtifact == nil ? "Start a Sounio workday without staring at a terminal" : state.headline
    }

    private var displayPrimaryAction: String {
        state.selectedArtifact == nil
            ? "Choose Claude/Codex, MiniMax, Kimi, Qwen, GLM, or Shell. As work happens, Beagle turns meaningful blocks into visual artifacts you can remember."
            : state.primaryAction
    }

    @ViewBuilder
    private var selectedArtifactPanel: some View {
        if let artifact = state.selectedArtifact {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Selected artifact")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                    Image(systemName: artifactIcon(artifact.kind))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(artifact.restrictedRedacted ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(artifact.title)
                            .font(BeagleFont.headline.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(artifact.summary)
                            .font(BeagleFont.body.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if !artifact.touchedFiles.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Touched files")
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                ForEach(artifact.touchedFiles, id: \.self) { file in
                                    Label(file, systemImage: "doc.text")
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        FlowPillRow(labels: artifact.evidenceBadges)
                    }
                }
            }
            .padding(BeagleSpacing.lg)
            .background(BeagleTheme.surface1.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(BeagleTheme.hairline, lineWidth: 1))
        } else {
            EmptyProofPanel()
        }
    }

    private func artifactPill(_ label: String) -> some View {
        Text(label)
            .font(BeagleFont.caption2.font)
            .foregroundStyle(BeagleTheme.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(BeagleTheme.surface0.opacity(0.65), in: Capsule())
    }
}

private struct EmptyWorkdayPanel: View {
    let onStart: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: BeagleSpacing.md) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BeagleTheme.truthRemembered)
                .frame(width: 44, height: 44)
                .background(BeagleTheme.truthRemembered.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text("No work artifacts yet")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("Start or resume a lane. The first command, agent step, test, diff, approval, or memory import will appear here as an object, not as terminal noise.")
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onStart) {
                    Label("Open Runtime Only If Needed", systemImage: "terminal")
                }
                .font(BeagleFont.caption.font)
                .buttonStyle(.bordered)
            }
        }
        .padding(BeagleSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BeagleTheme.surface1.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(BeagleTheme.hairline, lineWidth: 1))
    }
}

private struct EmptyProofPanel: View {
    var body: some View {
        HStack(alignment: .top, spacing: BeagleSpacing.md) {
            Image(systemName: "doc.badge.clock")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(BeagleTheme.textTertiary)
                .frame(width: 42, height: 42)
                .background(BeagleTheme.surface1.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text("The bench is waiting for evidence")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("When a lane produces a block, this area becomes the interpreted summary: what changed, whether it touched files, memory status, provenance, and what to do next.")
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BeagleSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BeagleTheme.surface1.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WorkArtifactStrip: View {
    let artifacts: [VisualWorkArtifact]
    let selectedArtifactId: String?
    let onSelect: (VisualWorkArtifact) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text("Artifacts")
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
                .textCase(.uppercase)
            if artifacts.isEmpty {
                Text("No curated Workbench blocks observed yet.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BeagleTheme.surface1.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(artifacts) { artifact in
                        Button {
                            onSelect(artifact)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: artifactIcon(artifact.kind))
                                        .foregroundStyle(artifact.restrictedRedacted ? BeagleTheme.postureWarm : BeagleTheme.truthRemembered)
                                    Text(artifact.kind.rawValue)
                                        .font(BeagleFont.caption2.font)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                    Spacer(minLength: 4)
                                    if artifact.id == selectedArtifactId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(BeagleTheme.truthObserved)
                                    }
                                }
                                Text(artifact.title)
                                    .font(BeagleFont.caption.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .lineLimit(2)
                                Text(artifact.summary)
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                    .lineLimit(3)
                                if !artifact.touchedFiles.isEmpty {
                                    Label("\(artifact.touchedFiles.count) file\(artifact.touchedFiles.count == 1 ? "" : "s")", systemImage: "doc.on.doc")
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BeagleTheme.surface1.opacity(0.54), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(artifact.id == selectedArtifactId ? BeagleTheme.truthObserved.opacity(0.72) : BeagleTheme.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct FlowPillRow: View {
    let labels: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(label.contains("restricted") ? BeagleTheme.postureWarm : BeagleTheme.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BeagleTheme.surface0.opacity(0.65), in: Capsule())
                }
            }
        }
    }
}
