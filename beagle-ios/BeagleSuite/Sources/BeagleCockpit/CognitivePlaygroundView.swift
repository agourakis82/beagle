//
//  CognitivePlaygroundView.swift
//  BeagleCockpit
//
//  A real, Settings-reachable surface that exercises the live cognitive endpoints
//  on beagle-core. Truth-mode-honest by construction: it never renders a number the
//  backend didn't actually measure. Sections are wired one per pass.
//

import SwiftUI
import BeagleCore

struct CognitivePlaygroundView: View {
    enum Surface: String, CaseIterable, Identifiable {
        case phi = "Φ"
        case hyperedges = "Hyperedges"
        case fractal = "Fractal"
        case deepThink = "Deep-think"
        var id: String { rawValue }
    }

    @State private var surface: Surface = .phi

    var body: some View {
        VStack(spacing: 0) {
            Picker("Surface", selection: $surface) {
                ForEach(Surface.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(BeagleSpacing.md)

            ScrollView {
                switch surface {
                case .phi:        PhiLab()
                case .hyperedges: pending("Hyperedges", "The 35 real knowledge-graph edges from /api/hyperedges — wiring next.")
                case .fractal:    pending("Fractal", "Real node/depth structure from the Sounio fractal verb — wiring next.")
                case .deepThink:  pending("Deep-think", "Real multi-pass reasoning from /api/cognitive/deep-think — wiring next.")
                }
            }
        }
        .navigationTitle("Cognitive Playground")
        .background(BeagleTheme.surface0.ignoresSafeArea())
    }

    @ViewBuilder private func pending(_ title: String, _ message: String) -> some View {
        VStack(spacing: BeagleSpacing.sm) {
            Image(systemName: "hammer")
                .font(.system(size: 26))
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(title)
                .font(BeagleFont.headline.font)
                .foregroundStyle(BeagleTheme.textPrimary)
            Text(message)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, BeagleSpacing.lg)
    }
}

// MARK: - Φ Lab (IIT-4 over recalled memory atoms)

private struct PhiLab: View {
    @State private var query = ""
    @State private var measurement: PhiMeasurement?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text("Integrated Information (Φ)")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("Real IIT-4 Φ measured over the memory atoms recalled for your query. A measurement, not a gauge — it only shows a number when the substrate is sufficient.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }

            HStack(spacing: BeagleSpacing.xs) {
                TextField("Query to measure Φ over…", text: $query, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(BeagleSpacing.sm)
                    .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface1.opacity(0.6)))
                Button(action: measure) {
                    Image(systemName: "function")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(BeagleTheme.truthObserved.opacity(0.18), in: RoundedRectangle(cornerRadius: BeagleRadius.md))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                .buttonStyle(.plain)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || loading)
            }

            if loading {
                HStack(spacing: BeagleSpacing.xs) {
                    ProgressView().tint(BeagleTheme.truthObserved)
                    Text("Measuring Φ over recalled substrate…")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
                .padding(.top, BeagleSpacing.xs)
            } else if let error {
                card {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.stateError)
                }
            } else if let m = measurement {
                result(m)
            }

            Spacer(minLength: 0)
        }
        .padding(BeagleSpacing.md)
    }

    // MARK: Honest rendering — number ONLY when truth_mode == measured

    @ViewBuilder private func result(_ m: PhiMeasurement) -> some View {
        if m.truthMode == "measured", let phi = m.phi {
            card {
                VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Φ")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Spacer()
                        TruthBadge(.observed, observedAt: m.measuredAt.iso8601Date)
                    }
                    Text(String(format: "%.4f", phi))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(BeagleTheme.truthObserved)

                    stat("substrate", "\(m.substrateSize ?? 0) memory atoms")
                    if let a = m.awarenessLevel { stat("awareness", a) }
                    if let d = m.durationMs { stat("compute", "\(d) ms") }
                    if let t = m.routerTier { stat("router tier", t) }

                    if let mip = m.mipPartition, mip.count >= 2 {
                        Divider().overlay(Color.white.opacity(0.06))
                        Text("MINIMUM INFORMATION PARTITION")
                            .font(BeagleFont.dataSmall.font).tracking(1)
                            .foregroundStyle(BeagleTheme.textTertiary)
                        ForEach(Array(mip.prefix(2).enumerated()), id: \.offset) { idx, group in
                            partitionGroup(index: idx, atoms: group)
                        }
                    }
                }
            }
        } else {
            // truth_mode in {insufficient_substrate, verb_unavailable, empty_query, ...}
            // → explicit explanatory state. NEVER a fake 0/φ, never an endless spinner.
            card {
                VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                    HStack {
                        TruthBadge(.stale)
                        Spacer()
                        Text(m.truthMode ?? "unknown")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    Text(emptyTitle(m.truthMode))
                        .font(BeagleFont.subheadline.font.weight(.semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(emptyDetail(m.truthMode))
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
    }

    private func partitionGroup(index: Int, atoms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(index == 0 ? "PART A" : "PART B")
                .font(BeagleFont.dataSmall.font)
                .foregroundStyle(BeagleTheme.truthRemembered)
            ForEach(Array(atoms.prefix(4).enumerated()), id: \.offset) { _, atom in
                Text("• \(atom)")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BeagleSpacing.xs)
        .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface0.opacity(0.6)))
    }

    private func emptyTitle(_ mode: String?) -> String {
        switch mode {
        case "insufficient_substrate": return "Not enough memory to measure Φ"
        case "verb_unavailable":       return "Φ engine is unavailable"
        case "empty_query":            return "Enter a query first"
        default:                       return "No Φ measurement"
        }
    }

    private func emptyDetail(_ mode: String?) -> String {
        switch mode {
        case "insufficient_substrate":
            return "Φ needs at least 2 memory atoms recalled for this query. Capture or recall more on this topic, then measure again."
        case "verb_unavailable":
            return "The Sounio phi.compute verb is down right now, so no integrated-information measurement is possible. Nothing is faked."
        case "empty_query":
            return "Φ is measured over the memory recalled for a query. Type something to measure over."
        default:
            return "The backend returned no measurable Φ for this substrate. No number is shown because none was measured."
        }
    }

    private func stat(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
            Text(value)
                .font(BeagleFont.caption.font.weight(.medium))
                .foregroundStyle(BeagleTheme.textSecondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(BeagleSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BeagleRadius.lg).fill(BeagleTheme.surface1.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: BeagleRadius.lg).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func measure() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        loading = true; error = nil; measurement = nil
        Task {
            let result = await BeagleClient.shared.measurePhi(prompt: q)
            if let m = result.value {
                measurement = m
            } else {
                error = result.error ?? "Φ measurement failed to reach the backend."
            }
            loading = false
        }
    }
}
