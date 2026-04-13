//
//  CognitiveStateView.swift
//  BeagleCockpit
//
//  Personal cognitive dashboard — HRV, Triad scores, active jobs, cluster.
//  The researcher's operational self-awareness at a glance.
//

import SwiftUI
import BeagleCore
import Charts

struct CognitiveStateView: View {
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                    if cognitive.state.mode == .stale, let error = cognitive.state.error {
                        errorBanner(error)
                    }
                    hrvSection
                    triadSection
                    jobsSection
                    clusterGlance
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.md)
            }
            .background { HealthPulseGradient(truth: cognitive.state.mode) }
            .navigationTitle("Home")
            .task { await cognitive.refresh() }
            .refreshable { await cognitive.refresh() }
        }
    }

    private func errorBanner(_ error: String) -> some View {
        GlassPanel(elevation: .raised, truth: .stale) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BeagleTheme.stateError)
                    Text("Could not refresh")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                }
                Text(error)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                Button {
                    Task { await cognitive.refresh() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButton(color: BeagleTheme.stateError))
            }
        }
    }

    // MARK: - HRV

    private var hrvSection: some View {
        GlassPanel(elevation: .floating, truth: cognitive.state.mode) {
            VStack(spacing: BeagleSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.0f", cognitive.hrvValue))
                        .font(BeagleFont.hero.font)
                        .foregroundStyle(hrvColor)
                    Text("ms")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    TruthBadge(cognitive.state.mode, compact: true)
                    Spacer()
                    Text(cognitive.flowState)
                        .font(BeagleFont.dataProminent.font)
                        .fontWeight(.bold)
                        .foregroundStyle(hrvColor)
                        .padding(.horizontal, BeagleSpacing.sm)
                        .padding(.vertical, BeagleSpacing.xxs)
                        .background(Capsule().fill(hrvColor.opacity(0.12)))
                }

                // HRV gauge
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(hrvColor.gradient)
                            .frame(width: geo.size.width * min(cognitive.hrvValue / 100.0, 1.0))
                    }
                }
                .frame(height: 8)

                Text("Heart rate variability · cognitive readiness")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    private var hrvColor: Color {
        switch cognitive.flowState {
        case "FLOW":    return BeagleTheme.truthObserved
        case "STRESS":  return BeagleTheme.stateError
        case "NORMAL":  return BeagleTheme.textData
        default:        return BeagleTheme.textTertiary
        }
    }

    // MARK: - Triad

    @ViewBuilder
    private var triadSection: some View {
        if let scores = cognitive.state.value?.triadLatest?.scores,
           (scores.athena != nil || scores.hermes != nil || scores.argos != nil || scores.judge != nil) {
            GlassPanel(elevation: .raised) {
                VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    HStack {
                        Text("Latest Triad")
                            .font(BeagleFont.headline.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        if let triad = cognitive.lastTriad {
                            TruthBadge(triad.mode, compact: true)
                        }
                        Spacer()
                        if let verdict = cognitive.triadVerdict {
                            Text(verdict)
                                .font(BeagleFont.data.font)
                                .foregroundStyle(BeagleTheme.truthObserved)
                        }
                    }

                    Chart {
                        if let v = scores.athena {
                            BarMark(x: .value("Score", v), y: .value("Agent", "ATH"))
                                .foregroundStyle(BeagleTheme.truthObserved.gradient)
                                .cornerRadius(BeagleRadius.sm)
                        }
                        if let v = scores.hermes {
                            BarMark(x: .value("Score", v), y: .value("Agent", "HER"))
                                .foregroundStyle(BeagleTheme.truthRemembered.gradient)
                                .cornerRadius(BeagleRadius.sm)
                        }
                        if let v = scores.argos {
                            BarMark(x: .value("Score", v), y: .value("Agent", "ARG"))
                                .foregroundStyle(BeagleTheme.postureWarm.gradient)
                                .cornerRadius(BeagleRadius.sm)
                        }
                        if let v = scores.judge {
                            BarMark(x: .value("Score", v), y: .value("Agent", "JDG"))
                                .foregroundStyle(BeagleTheme.textData.gradient)
                                .cornerRadius(BeagleRadius.sm)
                        }
                    }
                    .chartXScale(domain: 0...10)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(BeagleFont.dataSmall.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                        }
                    }
                    .frame(height: 100)
                }
            }
        }
    }

    // MARK: - Jobs

    @ViewBuilder
    private var jobsSection: some View {
        let running = cognitive.activeJobs.filter(\.isRunning)
        if !running.isEmpty {
            GlassPanel(elevation: .flush) {
                VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                    Text("Active Jobs")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    ForEach(running) { job in
                        HStack(spacing: BeagleSpacing.xs) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(BeagleTheme.postureWarm)
                                .symbolEffect(.pulse)
                            Text(job.kind ?? "job")
                                .font(BeagleFont.data.font)
                                .foregroundStyle(BeagleTheme.textData)
                            Spacer()
                            Text(job.status ?? "running")
                                .font(BeagleFont.dataSmall.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cluster glance

    private var clusterGlance: some View {
        GlassPanel(elevation: .flush, truth: catalog.executive.mode) {
            HStack(spacing: BeagleSpacing.lg) {
                let counts = catalog.postureCounts
                VStack(spacing: 2) {
                    Text("\(counts.totalProjects)")
                        .font(BeagleFont.title2.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("projects")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                TruthBadge(catalog.executive.mode, compact: true)
                Spacer()
                HStack(spacing: BeagleSpacing.md) {
                    miniStat(counts.alwaysOn, "on", BeagleTheme.postureOn)
                    miniStat(counts.warm, "warm", BeagleTheme.postureWarm)
                    miniStat(counts.cold, "cold", BeagleTheme.postureCold)
                }
            }
        }
    }

    private func miniStat(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(n)")
                .font(BeagleFont.dataProminent.font)
                .foregroundStyle(color)
            Text(label)
                .font(BeagleFont.dataSmall.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }
}
