//
//  DreamInsightsView.swift
//  BeagleCockpit
//
//  The overnight Dream Synthesis reader — the only surfaced consumer of
//  DreamSynthesisEngine.overnightInsights. Salvaged from HomeView.swift's
//  overnightInsightsCard (HomeView is dead/unreferenced) after the header-bar chrome that
//  used to expose this got retired during the chat redesign and nothing replaced it —
//  insights were accumulating invisibly. Reached via BeagleSurface's drawer footer.
//

import SwiftUI
import BeagleCore

struct DreamInsightsView: View {
    @Environment(CognitiveStore.self) private var cognitive
    private var engine: DreamSynthesisEngine { DreamSynthesisEngine.shared }
    private let dreamTint = Color(red: 0.45, green: 0.35, blue: 0.75)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                let unread = engine.overnightInsights.filter { !$0.isRead }

                if unread.isEmpty {
                    emptyState
                } else {
                    GlassPanel(elevation: .floating, truth: .remembered) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                            header(count: unread.count)
                            ForEach(unread) { insight in
                                insightRow(insight)
                                if insight.id != unread.last?.id {
                                    Divider().overlay(dreamTint.opacity(0.08))
                                }
                            }
                            if unread.count > 1 {
                                Button {
                                    withAnimation(BeagleMotion.snappy) { engine.markAllRead() }
                                } label: {
                                    HStack(spacing: BeagleSpacing.xxs) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                        Text("Marcar tudo como lido")
                                            .font(BeagleFont.caption.font)
                                    }
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(BeagleSpacing.lg)
        }
        .navigationTitle("Insights da noite")
        .navigationBarTitleDisplayModeIfAvailable(.inline)
    }

    private func header(count: Int) -> some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 15))
                .foregroundStyle(
                    LinearGradient(colors: [dreamTint, Color(red: 0.6, green: 0.5, blue: 0.85)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("Seu exocórtex sonhou essa noite")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(dreamTint)
                    .textCase(.uppercase)
                    .tracking(0.5)
                if let last = engine.lastDreamSession {
                    Text(last, style: .relative)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
            Spacer()
            TruthBadge(.remembered, compact: true)
        }
    }

    private func insightRow(_ insight: DreamInsight) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            HStack(spacing: BeagleSpacing.xxs) {
                sleepStageBadge(insight.sleepStage)
                if let hrv = insight.hrvAtGeneration {
                    Text("HRV \(Int(hrv))")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
            Text(insight.text)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .lineSpacing(2)
            HStack(spacing: BeagleSpacing.sm) {
                Button {
                    Task {
                        _ = await cognitive.captureThought(text: insight.text, source: "dream-synthesis")
                        engine.markRead(insight.id)
                        #if os(iOS)
                        BeagleHaptics.capture()
                        #endif
                    }
                } label: {
                    HStack(spacing: BeagleSpacing.xxs) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 11))
                        Text("Capturar")
                            .font(BeagleFont.caption2.font)
                    }
                    .foregroundStyle(dreamTint)
                }
                .buttonStyle(.plain)

                GoDeepButton(prompt: "Explore this overnight insight: \(insight.text)")

                Spacer()

                Button { engine.markRead(insight.id) } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, BeagleSpacing.xs)
    }

    private var emptyState: some View {
        VStack(spacing: BeagleSpacing.sm) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 32))
                .foregroundStyle(BeagleTheme.textTertiary)
            Text("Nada novo por enquanto")
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textSecondary)
            Text("O exocórtex sintetiza insights durante o sono profundo/REM detectado pelo Watch.")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BeagleSpacing.xl)
    }

    private func sleepStageBadge(_ stage: String) -> some View {
        let (label, icon): (String, String) = {
            switch stage {
            case "deep-rem-phase": return ("REM", "moon.zzz.fill")
            case "core-sleep": return ("Core", "moon.fill")
            case "light-sleep": return ("Light", "moon.haze.fill")
            case "quantum-dream": return ("Quantum", "atom")
            case "serendipity-dream": return ("Serendipity", "sparkle")
            default: return ("Dream", "moon.stars")
            }
        }()
        return HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(label).font(BeagleFont.caption2.font)
        }
        .foregroundStyle(dreamTint)
    }
}
