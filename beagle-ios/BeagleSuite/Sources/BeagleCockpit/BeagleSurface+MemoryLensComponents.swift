//
//  BeagleSurface+MemoryLensComponents.swift
//  BeagleCockpit
//
//  Living memory report components and ProofSheet for MemoryLensSheet.
//

import SwiftUI
import BeagleCore

struct LivingMemoryReportHeader: View {
    let report: MemoryLensReport
    let onProve: () -> Void

    private var truthMode: TruthMode {
        report.degradedReason == nil ? .observed : .declared
    }

    var body: some View {
        GlassPanel(truth: truthMode) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                        Text("LIVING MEMORY REPORT")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text(report.headline)
                            .font(BeagleFont.title3.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: BeagleSpacing.sm)
                    TruthBadge(truthMode, compact: true)
                }

                Text(report.summary)
                    .font(BeagleFont.callout.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !report.changedSignals.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(report.changedSignals.prefix(3), id: \.self) { signal in
                            HStack(alignment: .top, spacing: BeagleSpacing.xs) {
                                Image(systemName: "sparkle.magnifyingglass")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(BeagleTheme.truthObserved)
                                    .frame(width: 16)
                                Text(signal)
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                HStack(spacing: BeagleSpacing.sm) {
                    Button {
                        onProve()
                    } label: {
                        Label("Provar", systemImage: "checkmark.shield")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)

                    Text("\(report.evidenceFrontier.count) evidências · confiança \(String(format: "%.2f", report.confidence))")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct SourceConfidenceStrip: View {
    let report: MemoryLensReport

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                ForEach(report.sourceConfidenceBadges, id: \.self) { badge in
                    Text(badge)
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .padding(.horizontal, BeagleSpacing.xs)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(BeagleTheme.surface1.opacity(0.72))
                        )
                }
            }
        }
        .accessibilityLabel("Source and confidence badges")
    }
}

struct MemoryQuestionDock: View {
    @Binding var query: String
    let isSearching: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BeagleTheme.textTertiary)

            TextField("Perguntar à memória viva...", text: $query)
                .textFieldStyle(.plain)
                .font(BeagleFont.callout.font)
                .submitLabel(.search)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Image(systemName: isSearching ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BeagleTheme.textTertiary : BeagleTheme.truthObserved)
            }
            .buttonStyle(.plain)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
        }
        .padding(.horizontal, BeagleSpacing.sm)
        .padding(.vertical, BeagleSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                .fill(BeagleTheme.surface1.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                        .stroke(BeagleTheme.truthObserved.opacity(0.18), lineWidth: 1)
                )
        )
        .accessibilityLabel("Memory Lens question")
    }
}

struct LensPresetRail: View {
    let presets: [MemoryLensPreset]
    let onSelect: (MemoryLensPreset) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.sm) {
                ForEach(presets) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: BeagleSpacing.xs) {
                                Image(systemName: preset.systemImage)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(preset.title)
                                    .font(BeagleFont.caption.font)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                            }
                            Text(preset.detail)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .frame(width: 176, alignment: .leading)
                        .padding(BeagleSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.sm, style: .continuous)
                                .fill(BeagleTheme.surface1.opacity(0.68))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityLabel("Memory Lens presets")
    }
}

struct EvidenceFrontier: View {
    let report: MemoryLensReport
    let onProve: (ProofSheetModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack {
                Text("FRONTEIRA DE EVIDÊNCIA")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                if report.restrictedContentFiltered {
                    Label("restricted filtrado", systemImage: "lock.shield")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }

            if report.evidenceFrontier.isEmpty {
                GlassPanel(truth: .declared) {
                    Text("Ainda não há evidência projetada para exibir. Use um preset ou capture uma nova intenção para acordar a lente.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(report.evidenceFrontier.prefix(4)) { item in
                    evidenceRow(item)
                }
            }
        }
    }

    private func evidenceRow(_ item: EvidenceFrontierItem) -> some View {
        let truth = TruthMode(rawValue: item.truthMode) ?? .remembered
        return GlassPanel(truth: truth) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title.uppercased())
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.color(for: truth))
                    Spacer()
                    Text(String(format: "%.2f", item.score))
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Text(item.detail)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: BeagleSpacing.xs) {
                    Text(item.sourceLabel)
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        onProve(item.proof)
                    } label: {
                        Label("Provar", systemImage: "doc.text.magnifyingglass")
                            .font(BeagleFont.caption2.font)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .onLongPressGesture {
            onProve(item.proof)
        }
    }
}

struct ProofSheet: View {
    let model: ProofSheetModel
    @Environment(\.dismiss) private var dismiss

    init(model: ProofSheetModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                    GlassPanel(truth: .observed) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                            Text("PROOF PACK")
                                .font(BeagleFont.caption2.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textTertiary)
                            Text(model.title)
                                .font(BeagleFont.title3.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Text(model.summary)
                                .font(BeagleFont.callout.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    proofSection("SOURCE REFS", model.sourceRefs)
                    proofSection("PROVENANCE", model.provenanceLines)
                    proofSection("TRACE", model.traceLines)

                    Text("\(model.runtime ?? "runtime unknown") · confidence \(String(format: "%.2f", model.confidence)) · \(model.restrictedLeakCheck)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(BeagleSpacing.lg)
            }
            .background(BeagleTheme.surface0.ignoresSafeArea())
            .navigationTitle("Provar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func proofSection(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            Text(title)
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
            if lines.isEmpty {
                Text("No entries recorded.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            } else {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(BeagleFont.caption.font.monospaced())
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
