//
//  AgoraDetailView.swift
//  BeagleCockpit — the "Agora" detail screen
//
//  A real iOS 27 data screen: ambient aurora background tied to the live sky, glass cards,
//  Swift Charts (smooth gradient-filled lines, not a hand-rolled sparkline), a Weather-app-scale
//  hero. Céu (Kp/Dst/vento solar/Bz), ambiente (temp/pressão/umidade/UV), corpo (HRV/sono/pulso),
//  and body×sky correlations — each metric shows current value + a real trend from the backend's
//  history series.
//

import SwiftUI
import Charts
import BeagleCore

struct AgoraDetailView: View {
    let sky: SpaceWeatherStore.Snapshot?
    let summary: PhysioSummary
    /// Tapping a "mente maior" card asks the main companion chat to explain/analyze that
    /// measurement — same UX HomeView.swift (now dead) had, ported here since Agora is a
    /// sheet and can't hold its own ConversationStore.
    var onSendToChat: ((String) -> Void)? = nil

    @State private var history: AgoraHistory?
    @State private var corr: PhysioCorrelations?
    @State private var loading = true
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(CognitiveStore.self) private var cognitive

    private var band: SkyBand { sky?.band ?? .calm }
    private var ambient: WeatherPoint? { history?.weather.last }

    private var skyColor: Color {
        switch band {
        case .calm:   return BeagleTheme.truthObserved
        case .active: return BeagleTheme.auroraGreen
        case .storm:  return BeagleTheme.auroraViolet
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    VStack(spacing: BeagleSpacing.lg) {
                        hero
                        skyCard
                        ambientCard
                        bodyCard
                        correlationsCard
                        mindCard
                        if loading {
                            ProgressView().tint(BeagleTheme.textTertiary).padding(.top, BeagleSpacing.sm)
                        }
                        Text("Tendências das últimas \(history?.hours ?? 48)h · dados observados")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .padding(.top, BeagleSpacing.xs)
                            .padding(.bottom, BeagleSpacing.xl)
                    }
                    .padding(BeagleSpacing.md)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Agora")
            .navigationBarTitleDisplayModeIfAvailable(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.98, anchor: .top)
        .task {
            async let h = BeagleClient.shared.agoraHistory()
            async let c = BeagleClient.shared.correlations()
            history = await h
            corr = await c
            loading = false
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: - Background: the sky itself, ambient and quiet (not the chat's foreground aurora)

    private var background: some View {
        ZStack {
            BeagleTheme.auroraNight.ignoresSafeArea()
            RadialGradient(
                colors: [skyColor.opacity(band == .calm ? 0.10 : 0.22), .clear],
                center: .top, startRadius: 0, endRadius: 480
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2), value: band)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Hero — Weather-app scale: big number, named condition, glowing glyph

    private var hero: some View {
        VStack(spacing: BeagleSpacing.xs) {
            Image(systemName: heroGlyph)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(skyColor.gradient)
                .symbolEffect(.pulse, options: .repeating, isActive: band == .storm)
            if let t = ambient?.tempC {
                Text("\(Int(t.rounded()))°")
                    .font(.system(size: 68, weight: .thin, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [BeagleTheme.textPrimary, BeagleTheme.textPrimary.opacity(0.75)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }
            Text(headline)
                .font(BeagleFont.body.font.weight(.medium))
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BeagleSpacing.lg)
        .glassCard(tint: skyColor, reduceTransparency: reduceTransparency)
    }

    private var heroGlyph: String {
        switch band {
        case .calm:   return "moon.stars.fill"
        case .active: return "sparkles"
        case .storm:  return "cloud.bolt.fill"
        }
    }

    private var headline: String {
        var parts: [String] = []
        if sky != nil { parts.append("céu \(band.label)") }
        if summary.readiness != .unavailable { parts.append("corpo \(readinessPt(summary.readiness))") }
        return parts.isEmpty ? "seu instante agora" : parts.joined(separator: " · ")
    }

    // MARK: - Sky card (Kp + Dst + solar wind + Bz)

    private var skyCard: some View {
        glassSection("CÉU", tint: skyColor) {
            metricChart(
                "Kp", sky.map { String(format: "%.1f", $0.kp) } ?? "—", band.label,
                series: (history?.sky ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.kp.map { (d, $0) } } },
                color: skyColor
            )
            metricChart(
                "Dst", sky?.dst.map { "\(Int($0.rounded())) nT" } ?? "—", nil,
                series: (history?.sky ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.dst.map { (d, $0) } } },
                color: BeagleTheme.auroraViolet
            )
            metricChart(
                "Vento solar", sky.map { "\(Int($0.solarWindSpeed.rounded())) km/s" } ?? "—", nil,
                series: (history?.sky ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.solarWindSpeed.map { (d, $0) } } },
                color: BeagleTheme.truthRemembered
            )
            metricChart(
                "IMF Bz", sky.map { String(format: "%.1f nT", $0.bz) } ?? "—", nil,
                series: (history?.sky ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.bz.map { (d, $0) } } },
                color: BeagleTheme.truthDeclared
            )
        }
    }

    private var ambientCard: some View {
        glassSection("AMBIENTE", tint: BeagleTheme.truthRemembered) {
            metricChart(
                "Temperatura", ambient?.tempC.map { "\(Int($0.rounded()))°C" } ?? "—", nil,
                series: (history?.weather ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.tempC.map { (d, $0) } } },
                color: BeagleTheme.postureWarm
            )
            metricChart(
                "Pressão", ambient?.pressureHpa.map { "\(Int($0.rounded())) hPa" } ?? "—", nil,
                series: (history?.weather ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.pressureHpa.map { (d, $0) } } },
                color: BeagleTheme.truthRemembered
            )
            metricChart(
                "Umidade", ambient?.humidity.map { "\(Int($0.rounded()))%" } ?? "—", nil,
                series: (history?.weather ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.humidity.map { (d, $0) } } },
                color: BeagleTheme.truthObserved
            )
            metricChart(
                "UV", ambient?.uvIndex.map { String(format: "%.0f", $0) } ?? "—", nil,
                series: (history?.weather ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.uvIndex.map { (d, $0) } } },
                color: BeagleTheme.postureWarm
            )
            // Ambient decibel level (Tier 0 of the audio panorama) — loudness only, no scene
            // classification; just exposes what HealthKit already captures.
            metricChart(
                "Ruído", (history?.audioDb.last?.value).map { "\(Int($0.rounded())) dB" } ?? "—", nil,
                series: (history?.audioDb ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.value.map { (d, $0) } } },
                color: BeagleTheme.truthDeclared
            )
        }
    }

    private var bodyCard: some View {
        let hrvNow = summary.hrvMs ?? history?.hrv.last?.value
        return glassSection("CORPO", tint: BeagleTheme.truthObserved) {
            metricChart(
                "HRV", hrvNow.map { "\(Int($0.rounded())) ms" } ?? "—",
                summary.readiness != .unavailable ? readinessPt(summary.readiness) : nil,
                series: (history?.hrv ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.value.map { (d, $0) } } },
                color: BeagleTheme.truthObserved
            )
            if let s = summary.sleepHours {
                staticMetricRow("Sono", String(format: "%.1f h", s), color: BeagleTheme.truthRemembered)
            }
            if let r = summary.restingHeartRate {
                staticMetricRow("Pulso repouso", "\(Int(r.rounded())) bpm", color: BeagleTheme.stateError)
            }
        }
    }

    // MARK: - Correlations: body × sky (Spearman + lag scan). Exploratory — "afeto" joins once EMA exists.

    @ViewBuilder
    private var correlationsCard: some View {
        let all = corr?.correlations ?? []
        let notable = all.filter { $0.notable == true }
        let shown = Array((notable.isEmpty ? all : notable).prefix(6))
        glassSection("CORRELAÇÕES · corpo × céu", tint: BeagleTheme.auroraViolet) {
            if shown.isEmpty {
                Text(loading ? "Calculando…" : "Sem correlações com dados suficientes ainda (mín. ~7 dias pareados).")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            } else {
                ForEach(shown) { c in correlationRow(c) }
                Text("Spearman ρ · varredura de atraso · exploratório (n baixo → não causal)")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Mind (fractal/Φ/void — "LARGER MIND", ported from the now-dead HomeView.swift)

    @ViewBuilder
    private var mindCard: some View {
        let fractals = cognitive.state.value?.recentFractalTrees ?? []
        let phis = cognitive.state.value?.recentPhiMeasurements ?? []
        let voids = cognitive.state.value?.recentVoidJourneys ?? []

        if !fractals.isEmpty || !phis.isEmpty || !voids.isEmpty {
            glassSection("MENTE", tint: BeagleTheme.truthRemembered) {
                if let fractal = fractals.first {
                    Button {
                        let prompt = fractal.rootPrompt ?? "fractal tree"
                        onSendToChat?("Explain this fractal exploration: \(prompt) — it produced \(fractal.nodeCount ?? 0) nodes at depth \(fractal.maxDepth ?? 0) in \(fractal.durationMs ?? 0)ms")
                        dismiss()
                    } label: {
                        mindRow(
                            icon: "tree", color: BeagleTheme.truthObserved,
                            title: "Fractal: \(fractal.nodeCount ?? 0) nós",
                            subtitle: fractal.rootPrompt ?? "",
                            detail: "profundidade \(fractal.maxDepth ?? 0) · \(fractal.durationMs ?? 0)ms"
                        )
                    }
                    .buttonStyle(.plain)
                }
                if let phi = phis.first {
                    Button {
                        onSendToChat?("Analyze this IIT measurement: Φ = \(phi.phi ?? 0) for query '\(phi.querySnippet ?? "")'. Awareness: \(phi.awarenessLevel ?? "unknown"). What does this mean?")
                        dismiss()
                    } label: {
                        mindRow(
                            icon: "waveform.path.ecg", color: BeagleTheme.truthRemembered,
                            title: "Φ = \(String(format: "%.4f", phi.phi ?? 0))",
                            subtitle: phi.querySnippet ?? "",
                            detail: "\(phi.awarenessLevel ?? "") · \(phi.substrateSize ?? 0) substratos"
                        )
                    }
                    .buttonStyle(.plain)
                }
                if !voids.isEmpty {
                    mindRow(
                        icon: "circle.dotted", color: BeagleTheme.postureWarm,
                        title: "\(voids.count) jornada\(voids.count > 1 ? "s" : "") void",
                        subtitle: "\(voids.first?.insights?.count ?? 0) insights na última",
                        detail: "profundidade \(String(format: "%.1f", voids.first?.maxDepthReached ?? 0))"
                    )
                }
            }
        }
    }

    private func mindRow(icon: String, color: Color, title: String, subtitle: String, detail: String) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BeagleFont.footnote.font).fontWeight(.medium).foregroundStyle(BeagleTheme.textPrimary)
                Text(subtitle).font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textSecondary).lineLimit(1)
            }
            Spacer()
            Text(detail).font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(.vertical, 4)
    }

    private func correlationRow(_ c: PhysioCorrelations.Correlation) -> some View {
        let down = c.rho < 0
        let strength = min(1.0, abs(c.rho))
        let tint: Color = abs(c.rho) >= 0.5 ? (down ? BeagleTheme.stateError : BeagleTheme.truthObserved) : BeagleTheme.textSecondary
        return HStack(spacing: BeagleSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(label(c.driver)).foregroundStyle(BeagleTheme.textSecondary)
                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(BeagleTheme.textTertiary)
                    Text(label(c.outcome)).foregroundStyle(BeagleTheme.textPrimary)
                    Image(systemName: down ? "arrow.down" : "arrow.up").font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                }
                .font(BeagleFont.footnote.font)
                Text("atraso \(c.lag)d · n=\(c.n)\(c.p != nil ? String(format: " · p=%.3f", c.p!) : "")")
                    .font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
            }
            Spacer(minLength: BeagleSpacing.sm)
            Text(String(format: "ρ %.2f", c.rho))
                .font(BeagleFont.body.font.monospaced()).foregroundStyle(tint)
            Capsule().fill(tint.opacity(0.25)).frame(width: 36, height: 4)
                .overlay(alignment: .leading) { Capsule().fill(tint).frame(width: 36 * strength, height: 4) }
        }
        .padding(.vertical, 2)
    }

    private func label(_ key: String) -> String {
        switch key {
        case "kpMax": return "Kp (geomagnético)"
        case "hrvMs": return "HRV"
        case "restingHr": return "FC repouso"
        case "sleepHours": return "sono"
        case "mood": return "humor"
        case "steps": return "passos"
        case "pressureTrendHpa": return "tendência de pressão"
        case "solarWindSpeed": return "vento solar"
        case "f107": return "F10.7"
        case "uvMax": return "UV"
        case "aqi": return "AQI"
        case "tempMaxC": return "temp. máx"
        default: return key
        }
    }

    // MARK: - Glass building blocks (iOS 26/27 Liquid Glass, with Reduce Transparency fallback)

    @ViewBuilder
    private func glassSection<Content: View>(_ title: String, tint: Color, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            Text(title).font(BeagleFont.caption2.font).fontWeight(.semibold).foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BeagleSpacing.md)
        .glassCard(tint: tint, reduceTransparency: reduceTransparency)
    }

    /// A named metric with its current value + a REAL Swift Charts trend (gradient-filled smooth
    /// line), replacing the old hand-rolled Sparkline. `series` is (date, value) already parsed.
    private func metricChart(_ label: String, _ value: String, _ sub: String?, series: [(Date, Double)], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: BeagleSpacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
                    HStack(spacing: 6) {
                        Text(value).font(BeagleFont.body.font.monospaced()).foregroundStyle(BeagleTheme.textPrimary)
                        if let sub { Text(sub).font(BeagleFont.caption2.font).foregroundStyle(color) }
                    }
                }
                Spacer(minLength: BeagleSpacing.sm)
            }
            if series.count > 1 {
                Chart(series, id: \.0) { point in
                    AreaMark(x: .value("t", point.0), y: .value("v", point.1))
                        .foregroundStyle(
                            LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("t", point.0), y: .value("v", point.1))
                        .foregroundStyle(color.gradient)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 44)
            }
        }
        .padding(.vertical, 4)
    }

    private func staticMetricRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label).font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
            Text(value).font(BeagleFont.body.font.monospaced()).foregroundStyle(color)
        }
        .padding(.vertical, 4)
    }

    private func readinessPt(_ r: PhysioReadiness) -> String {
        switch r {
        case .restored: return "recuperado"
        case .steady:   return "estável"
        case .strained: return "tenso"
        case .unavailable: return "—"
        }
    }

    private func tsDate(_ ts: String) -> Date? {
        ISO8601DateFormatter().date(from: ts)
            ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: ts) }()
    }
}

// MARK: - Glass card modifier (Reduce Transparency → solid material, matching the chat's rule)

private struct GlassCard: ViewModifier {
    let tint: Color
    let reduceTransparency: Bool
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(BeagleTheme.surface1, in: RoundedRectangle(cornerRadius: BeagleRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: BeagleRadius.lg, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 0.8))
        } else {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: BeagleRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: BeagleRadius.lg, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 0.6))
        }
    }
}

private extension View {
    func glassCard(tint: Color, reduceTransparency: Bool) -> some View {
        modifier(GlassCard(tint: tint, reduceTransparency: reduceTransparency))
    }
}
