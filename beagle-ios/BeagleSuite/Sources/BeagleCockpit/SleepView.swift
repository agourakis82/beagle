//
//  SleepView.swift
//  BeagleCockpit
//
//  Last night's sleep, read from HealthKit via PhysioStore. Mirrors the visual
//  idiom of DreamInsightsView (GlassPanel + TruthBadge + BeagleTheme/Font/Spacing).
//

import SwiftUI
import BeagleCore

struct SleepView: View {
    @Environment(PhysioStore.self) private var physio
    @State private var night: SleepNight?
    @State private var loaded = false

    private let deepTint = Color(red: 0.35, green: 0.35, blue: 0.75)
    private let remTint = Color(red: 0.55, green: 0.35, blue: 0.75)
    private let coreTint = Color(red: 0.30, green: 0.60, blue: 0.60)
    private let awakeTint = Color.white.opacity(0.12)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                if let night {
                    GlassPanel(elevation: .floating, truth: .observed) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                            header(night)
                            stageBar(night)
                            stageLegend(night)
                            if night.hrvMs != nil || night.restingHeartRate != nil {
                                Divider().overlay(deepTint.opacity(0.08))
                                vitalsRow(night)
                            }
                        }
                    }
                } else if loaded {
                    emptyState
                }
            }
            .padding(BeagleSpacing.lg)
        }
        .task {
            night = await physio.lastNightSleep()
            loaded = true
        }
        .navigationTitle("Sono")
        .navigationBarTitleDisplayModeIfAvailable(.inline)
    }

    private func header(_ night: SleepNight) -> some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 15))
                .foregroundStyle(
                    LinearGradient(colors: [deepTint, remTint],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("Última noite")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(deepTint)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(formattedDuration(hours: night.totalAsleepHours))
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .monospacedDigit()
            }
            Spacer()
            TruthBadge(.observed, compact: true)
        }
    }

    private func stageBar(_ night: SleepNight) -> some View {
        let totalMinutes = night.deepMinutes + night.remMinutes + night.coreMinutes + night.awakeMinutes
        return GeometryReader { geo in
            HStack(spacing: 1) {
                stageSegment(minutes: night.deepMinutes, total: totalMinutes, width: geo.size.width, tint: deepTint)
                stageSegment(minutes: night.remMinutes, total: totalMinutes, width: geo.size.width, tint: remTint)
                stageSegment(minutes: night.coreMinutes, total: totalMinutes, width: geo.size.width, tint: coreTint)
                stageSegment(minutes: night.awakeMinutes, total: totalMinutes, width: geo.size.width, tint: awakeTint)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .frame(height: 8)
    }

    private func stageSegment(minutes: Double, total: Double, width: CGFloat, tint: Color) -> some View {
        let fraction = total > 0 ? minutes / total : 0
        return Rectangle()
            .fill(tint)
            .frame(width: max(0, width * fraction))
    }

    private func stageLegend(_ night: SleepNight) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            legendRow(label: "Profundo", minutes: night.deepMinutes, tint: deepTint)
            legendRow(label: "REM", minutes: night.remMinutes, tint: remTint)
            legendRow(label: "Leve", minutes: night.coreMinutes, tint: coreTint)
            legendRow(label: "Acordado", minutes: night.awakeMinutes, tint: BeagleTheme.textTertiary)
            Text("Profundo+REM: \(Int((night.deepREMFraction * 100).rounded()))%")
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .padding(.top, BeagleSpacing.xxs)
        }
    }

    private func legendRow(label: String, minutes: Double, tint: Color) -> some View {
        HStack(spacing: BeagleSpacing.xs) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(label)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
            Spacer()
            Text("\(Int(minutes.rounded()))min")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .monospacedDigit()
        }
    }

    private func vitalsRow(_ night: SleepNight) -> some View {
        HStack(spacing: BeagleSpacing.lg) {
            if let hrv = night.hrvMs {
                vitalStat(label: "HRV", value: "\(Int(hrv.rounded())) ms")
            }
            if let rhr = night.restingHeartRate {
                vitalStat(label: "FC de repouso", value: "\(Int(rhr.rounded())) bpm")
            }
            Spacer()
        }
    }

    private func vitalStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(value)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .monospacedDigit()
        }
    }

    private var emptyState: some View {
        VStack(spacing: BeagleSpacing.sm) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 32))
                .foregroundStyle(BeagleTheme.textTertiary)
            Text("Nenhum sono registrado ainda")
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textSecondary)
            Text("Ative o rastreamento de sono no seu Apple Watch — quando houver uma noite, a análise aparece aqui.")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BeagleSpacing.xl)
    }

    private func formattedDuration(hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(h)h \(m)min"
    }
}
