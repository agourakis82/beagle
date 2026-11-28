//
//  WorkView+RendererBakeOff.swift
//  BeagleCockpit
//
//  Side-by-side renderer bake-off comparison sheet and micro-Metal preview
//  for WorkView.
//

import SwiftUI
import BeagleCore
import BeagleWorkbenchKit

struct RendererBakeOffSheet: View {
    let sample: WorkbenchBakeOffSample
    let judgments: [RendererHumanJudgment]
    let onRecordJudgment: (RendererHumanJudgment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCandidate: WorkbenchRendererCandidate = .warpDerived
    @State private var humanScore = 3
    @State private var notes = ""
    @State private var openedAt = Date()

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                    header
                    if proxy.size.width >= 940 {
                        HStack(alignment: .top, spacing: BeagleSpacing.md) {
                            BeagleRendererPane(sample: sample)
                            WarpRendererPane(sample: sample, selectedCandidate: selectedCandidate)
                        }
                    } else {
                        VStack(spacing: BeagleSpacing.md) {
                            BeagleRendererPane(sample: sample)
                            WarpRendererPane(sample: sample, selectedCandidate: selectedCandidate)
                        }
                    }
                    appleDeviceGatePanel(width: proxy.size.width)
                    scorePanel
                    recentJudgments
                }
                .padding(BeagleSpacing.lg)
            }
        }
        .navigationTitle("Renderer Bake-off")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Record") {
                    onRecordJudgment(
                        RendererHumanJudgment(
                            sampleId: sample.id,
                            selectedCandidate: selectedCandidate,
                            score: humanScore,
                            notes: notes
                        )
                    )
                    notes = ""
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text(sample.title)
                .font(BeagleFont.title2.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .lineLimit(2)
            HStack(spacing: 8) {
                bakeOffPill("hot_path=beagle-terminal-v1", tint: BeagleTheme.truthObserved)
                bakeOffPill("warp_renderer=spike", tint: BeagleTheme.truthRemembered)
                bakeOffPill("canonical_memory=cluster-only", tint: BeagleTheme.textSecondary)
                if sample.restrictedRedacted {
                    bakeOffPill("restricted redacted", tint: BeagleTheme.postureWarm)
                }
            }
            Text("Exploratory gate: continue only if this reveals useful renderer learning; no renderer promotion occurs here.")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
        }
    }

    private var scorePanel: some View {
        GlassPanel(elevation: .flush, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Human judgment")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                Picker("Candidate", selection: $selectedCandidate) {
                    ForEach(WorkbenchRendererCandidate.allCases, id: \.self) { candidate in
                        Text(candidate.title).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                Stepper("UX score: \(humanScore)/5", value: $humanScore, in: 1...5)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                TextField("Notes: fidelity, latency, ergonomics, surprise", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    metricPill("sample \(sample.blockId)")
                    metricPill(sample.memoryStatus)
                    metricPill(sample.bridgeVersion)
                    metricPill("\(Int(Date().timeIntervalSince(openedAt) * 1000))ms open")
                }
            }
        }
    }

    private func appleDeviceGatePanel(width: CGFloat) -> some View {
        let gate = WorkbenchAppleDeviceGate.evaluate(
            sample: sample,
            judgments: judgments,
            viewportWidth: Double(width),
            dynamicTypeReady: true,
            touchTargetReady: true
        )
        return GlassPanel(elevation: .flush, truth: gate.status == "blocked" ? .stale : .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple device gate")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .textCase(.uppercase)
                        Text(gate.status.replacingOccurrences(of: "_", with: " "))
                            .font(BeagleFont.body.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(gate.blockers.isEmpty ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                    }
                    Spacer()
                    Text(gate.formFactor.rawValue)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BeagleTheme.surface1.opacity(0.7), in: Capsule())
                }
                HStack(spacing: 8) {
                    metricPill("width \(Int(gate.viewportWidth))")
                    metricPill(gate.restrictedLeakCheck)
                    metricPill("VT \(gate.vtFidelityStatus)")
                    metricPill("latency \(gate.latencyStatus)")
                    if let score = gate.humanJudgmentScore {
                        metricPill("human \(score)/5")
                    } else {
                        metricPill("human pending")
                    }
                }
                if !gate.blockers.isEmpty {
                    Text(gate.blockers.joined(separator: " · "))
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Promotion remains disabled here; this panel only proves whether the Apple surface is ready for a human device pass.")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var recentJudgments: some View {
        if !judgments.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text("Recent local judgments")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                ForEach(judgments.prefix(4)) { judgment in
                    HStack {
                        Text(judgment.selectedCandidate.title)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Spacer()
                        Text("\(judgment.score)/5")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                    .padding(8)
                    .background(BeagleTheme.surface1.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func bakeOffPill(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(BeagleFont.caption2.font)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func metricPill(_ label: String) -> some View {
        Text(label)
            .font(BeagleFont.caption2.font)
            .foregroundStyle(BeagleTheme.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(BeagleTheme.surface1.opacity(0.7), in: Capsule())
    }
}

private struct BeagleRendererPane: View {
    let sample: WorkbenchBakeOffSample

    var body: some View {
        rendererShell(title: "A · Beagle Terminal", subtitle: "TerminalGrid hot path") {
            Text(sample.outputPreview)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(sample.restrictedRedacted ? BeagleTheme.postureWarm : BeagleTheme.textData)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
        }
    }
}

private struct WarpRendererPane: View {
    let sample: WorkbenchBakeOffSample
    let selectedCandidate: WorkbenchRendererCandidate

    var body: some View {
        rendererShell(title: "B · \(selectedCandidate.title)", subtitle: subtitle) {
            MicroMetalWarpPreview(sample: sample, candidate: selectedCandidate)
                .frame(minHeight: 220)
                .padding(10)
        }
    }

    private var subtitle: String {
        #if os(macOS)
        return "Warp Metal probe may attach partial macOS output"
        #else
        return "Native micro-renderer compatible with WarpBlock"
        #endif
    }
}

private struct MicroMetalWarpPreview: View {
    let sample: WorkbenchBakeOffSample
    let candidate: WorkbenchRendererCandidate

    var body: some View {
        Canvas { context, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12)
            context.fill(bg, with: .color(Color(red: 0.035, green: 0.045, blue: 0.07)))
            let accentRect = CGRect(x: 0, y: 0, width: 4, height: size.height)
            context.fill(Path(accentRect), with: .color(accent))
            let text = sample.restrictedRedacted
                ? "[restricted output redacted]"
                : sample.outputPreview.isEmpty ? sample.command : sample.outputPreview
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(18)
            var y: CGFloat = 14
            for line in lines {
                let attributed = AttributedString(String(line.prefix(120)))
                var resolved = context.resolve(Text(attributed).font(.system(size: 12, design: .monospaced)).foregroundStyle(textColor))
                resolved.shading = .color(sample.restrictedRedacted ? BeagleTheme.postureWarm : BeagleTheme.textData)
                context.draw(resolved, at: CGPoint(x: 16, y: y), anchor: .topLeading)
                y += 16
                if y > size.height - 20 { break }
            }
        }
        .overlay(alignment: .topTrailing) {
            Text(candidate.rawValue)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(accent)
                .padding(7)
                .background(.black.opacity(0.24), in: Capsule())
                .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(sample.restrictedRedacted ? BeagleTheme.postureWarm.opacity(0.45) : accent.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var accent: Color {
        switch candidate {
        case .beagleTerminal: return BeagleTheme.truthObserved
        case .warpDerived: return BeagleTheme.truthRemembered
        case .warpMetalProbe: return BeagleTheme.postureWarm
        case .ipadMicroMetal: return BeagleTheme.textData
        }
    }

    private var textColor: Color {
        sample.restrictedRedacted ? BeagleTheme.postureWarm : BeagleTheme.textData
    }
}

private func rendererShell<Content: View>(
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(BeagleFont.body.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textPrimary)
            Text(subtitle)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        content()
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
            .background(BeagleTheme.surface0.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
    }
    .padding(12)
    .background(BeagleTheme.surface1.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .stroke(BeagleTheme.hairline, lineWidth: 1)
    )
}
