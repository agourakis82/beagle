//
//  AgoraDetailView.swift
//  BeagleCockpit — the "Agora" detail screen
//
//  A weather-app-style read of the user's whole instant: o céu (Kp/Dst/vento solar/Bz), o
//  ambiente (temp/pressão/umidade/UV) e o corpo (HRV/sono/pulso) — cada um com o valor atual e
//  uma tendência (sparkline) do histórico real do backend. Reuses the existing SpaceWeatherStore.
//

import SwiftUI
import BeagleCore

struct AgoraDetailView: View {
    let sky: SpaceWeatherStore.Snapshot?
    let summary: PhysioSummary

    @State private var history: AgoraHistory?
    @State private var loading = true
    @Environment(\.dismiss) private var dismiss

    private var band: SkyBand { sky?.band ?? .calm }
    /// Most-recent ambient reading comes from the history series' last point.
    private var ambient: WeatherPoint? { history?.weather.last }

    // Auroral palette (local — no dependency on Theme having sky colors).
    private static let auroraGreen = Color(red: 120/255, green: 230/255, blue: 170/255)
    private static let auroraViolet = Color(red: 170/255, green: 130/255, blue: 235/255)
    private var skyColor: Color { band == .storm ? Self.auroraViolet : (band == .active ? Self.auroraGreen : BeagleTheme.truthDeclared) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BeagleSpacing.md) {
                    hero
                    skyCard
                    ambientCard
                    bodyCard
                    if loading { ProgressView().tint(BeagleTheme.textTertiary).padding(.top, BeagleSpacing.sm) }
                    Text("Tendências das últimas \(history?.hours ?? 48)h · dados observados")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .padding(.top, BeagleSpacing.xs)
                }
                .padding(BeagleSpacing.md)
            }
            .background(BeagleTheme.surface0.ignoresSafeArea())
            .navigationTitle("Agora")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
        .task {
            history = await BeagleClient.shared.agoraHistory()
            loading = false
        }
    }

    private var hero: some View {
        VStack(spacing: BeagleSpacing.xs) {
            Image(systemName: heroGlyph)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(skyColor)
            if let t = ambient?.tempC {
                Text("\(Int(t.rounded()))°")
                    .font(.system(size: 56, weight: .thin, design: .rounded))
                    .foregroundStyle(BeagleTheme.textPrimary)
            }
            Text(headline)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BeagleSpacing.md)
    }

    private var heroGlyph: String {
        switch band {
        case .calm:   return "moon.stars"
        case .active: return "sparkles"
        case .storm:  return "cloud.bolt"
        }
    }

    private var headline: String {
        var parts: [String] = []
        if sky != nil { parts.append("céu \(band.label)") }
        if summary.readiness != .unavailable { parts.append("corpo \(readinessPt(summary.readiness))") }
        return parts.isEmpty ? "seu instante agora" : parts.joined(separator: " · ")
    }

    private var skyCard: some View {
        card("CÉU", tint: skyColor) {
            metric("Kp", sky.map { String(format: "%.1f", $0.kp) } ?? "—", band.label, trend: history?.sky.compactMap { $0.kp } ?? [], color: skyColor)
            metric("Dst", sky?.dst.map { "\(Int($0.rounded())) nT" } ?? "—", nil, trend: history?.sky.compactMap { $0.dst } ?? [], color: Self.auroraViolet)
            metric("Vento solar", sky.map { "\(Int($0.solarWindSpeed.rounded())) km/s" } ?? "—", nil, trend: history?.sky.compactMap { $0.solarWindSpeed } ?? [], color: BeagleTheme.truthRemembered)
            metric("IMF Bz", sky.map { String(format: "%.1f nT", $0.bz) } ?? "—", nil, trend: history?.sky.compactMap { $0.bz } ?? [], color: BeagleTheme.truthDeclared)
        }
    }

    private var ambientCard: some View {
        card("AMBIENTE", tint: BeagleTheme.truthRemembered) {
            metric("Temperatura", ambient?.tempC.map { "\(Int($0.rounded()))°C" } ?? "—", nil, trend: history?.weather.compactMap { $0.tempC } ?? [], color: BeagleTheme.postureWarm)
            metric("Pressão", ambient?.pressureHpa.map { "\(Int($0.rounded())) hPa" } ?? "—", nil, trend: history?.weather.compactMap { $0.pressureHpa } ?? [], color: BeagleTheme.truthRemembered)
            metric("Umidade", ambient?.humidity.map { "\(Int($0.rounded()))%" } ?? "—", nil, trend: history?.weather.compactMap { $0.humidity } ?? [], color: BeagleTheme.truthObserved)
            metric("UV", ambient?.uvIndex.map { String(format: "%.0f", $0) } ?? "—", nil, trend: history?.weather.compactMap { $0.uvIndex } ?? [], color: BeagleTheme.postureWarm)
        }
    }

    private var bodyCard: some View {
        // Current HRV prefers the live client summary, but falls back to the latest history
        // sample (the backend has thousands of fresh samples even when HealthKit isn't in scope).
        let hrvNow = summary.hrvMs ?? history?.hrv.last?.value
        return card("CORPO", tint: BeagleTheme.truthObserved) {
            metric("HRV", hrvNow.map { "\(Int($0.rounded())) ms" } ?? "—", summary.readiness != .unavailable ? readinessPt(summary.readiness) : nil, trend: history?.hrv.compactMap { $0.value } ?? [], color: BeagleTheme.truthObserved)
            if let s = summary.sleepHours {
                metric("Sono", String(format: "%.1f h", s), nil, trend: [], color: BeagleTheme.truthRemembered)
            }
            if let r = summary.restingHeartRate {
                metric("Pulso repouso", "\(Int(r.rounded())) bpm", nil, trend: [], color: BeagleTheme.stateError)
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(_ title: String, tint: Color, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text(title).font(BeagleFont.caption2.font).fontWeight(.semibold).foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BeagleSpacing.md)
        .background(RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous).fill(BeagleTheme.surface1.opacity(0.54)))
        .overlay(RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 0.8))
    }

    private func metric(_ label: String, _ value: String, _ sub: String?, trend: [Double], color: Color) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
                HStack(spacing: 6) {
                    Text(value).font(BeagleFont.body.font.monospaced()).foregroundStyle(BeagleTheme.textPrimary)
                    if let sub { Text(sub).font(BeagleFont.caption2.font).foregroundStyle(color) }
                }
            }
            Spacer(minLength: BeagleSpacing.sm)
            if trend.count > 1 { Sparkline(values: trend, color: color).frame(width: 84, height: 30) }
        }
        .padding(.vertical, 2)
    }

    private func readinessPt(_ r: PhysioReadiness) -> String {
        switch r {
        case .restored: return "recuperado"
        case .steady:   return "estável"
        case .strained: return "tenso"
        case .unavailable: return "—"
        }
    }
}

/// A minimal trend line normalized to its own min/max. No axes — a glanceable shape.
struct Sparkline: View {
    let values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                ZStack {
                    Path { p in
                        p.move(to: pts[0])
                        for q in pts.dropFirst() { p.addLine(to: q) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    Circle().fill(color).frame(width: 4, height: 4).position(pts[pts.count - 1])
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = hi - lo
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let normY = span > 0 ? (v - lo) / span : 0.5
            let y = size.height * (1 - CGFloat(normY)) * 0.86 + size.height * 0.07
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }
    }
}
