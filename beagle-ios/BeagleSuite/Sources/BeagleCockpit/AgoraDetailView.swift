//
//  AgoraDetailView.swift
//  BeagleCockpit — the "Agora" detail screen (scientific N-of-1 cockpit)
//
//  A real iOS 27 data screen: ambient aurora background tied to the live sky, glass cards,
//  Swift Charts with VISIBLE axes/units/log-scale and a forecast overlay (history solid,
//  future dashed, split at "now"). Céu is grouped Geomagnético / Solar / Heliobiológico,
//  each metric shown as a NAMED BAND (calmo/tempestade, sem-flare/C/M/X, escala S) not a raw
//  number. Correlations corpo×céu are surfaced as readable insights, and every exploratory
//  signal (raios cósmicos, Schumann, SYM-H retrospectivo, aurora) carries a rigor badge so
//  the screen never implies certainty the science doesn't have.
//

import SwiftUI
import Charts
import BeagleCore

struct AgoraDetailView: View {
    let sky: SpaceWeatherStore.Snapshot?
    let summary: PhysioSummary
    var onSendToChat: ((String) -> Void)? = nil

    @State private var history: AgoraHistory?
    @State private var corr: PhysioCorrelations?
    @State private var forecast: AgoraForecast?
    @State private var loading = true
    @State private var appeared = false
    @State private var isExploringFractal = false
    @State private var isMeasuringPhi = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(CognitiveStore.self) private var cognitive

    private var band: SkyBand { sky?.band ?? .calm }
    private var ambient: WeatherPoint? { history?.weather.last }

    // Overall severity = worst of sky / air / body — drives the hero color + glyph.
    private enum Severity: Int, Comparable {
        case good = 0, watch = 1, alert = 2
        static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
    }
    private var severity: Severity {
        var s = Severity.good
        switch band { case .active: s = max(s, .watch); case .storm: s = .alert; default: break }
        if let a = ambient?.aqi { if a > 150 { s = .alert } else if a > 100 { s = max(s, .watch) } }
        if summary.readiness == .strained { s = max(s, .watch) }
        return s
    }
    private var severityColor: Color {
        switch severity { case .good: return BeagleTheme.truthObserved
                          case .watch: return BeagleTheme.postureWarm
                          case .alert: return BeagleTheme.stateError }
    }
    private var skyColor: Color {
        switch band { case .calm: return BeagleTheme.truthObserved
                      case .active: return BeagleTheme.auroraGreen
                      case .storm: return BeagleTheme.auroraViolet }
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
                        Text("Passado observado (últimas \(history?.hours ?? 48)h) · futuro tracejado (previsão). Sinais exploratórios marcados.")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .multilineTextAlignment(.center)
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
            async let f = BeagleClient.shared.agoraForecast()
            history = await h
            corr = await c
            forecast = await f
            loading = false
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            BeagleTheme.auroraNight.ignoresSafeArea()
            RadialGradient(
                colors: [severityColor.opacity(severity == .good ? 0.10 : 0.22), .clear],
                center: .top, startRadius: 0, endRadius: 480
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2), value: severity)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Hero — living "## Agora" synthesis

    private var hero: some View {
        VStack(spacing: BeagleSpacing.xs) {
            Image(systemName: heroGlyph)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(severityColor.gradient)
                .symbolEffect(.pulse, options: .repeating, isActive: severity == .alert)
            if let t = ambient?.tempC {
                Text("\(Int(t.rounded()))°")
                    .font(.system(size: 66, weight: .thin, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [BeagleTheme.textPrimary, BeagleTheme.textPrimary.opacity(0.75)],
                                       startPoint: .top, endPoint: .bottom))
            }
            Text(headline)
                .font(BeagleFont.body.font.weight(.medium))
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
            if let sub = subHeadline {
                Text(sub)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BeagleSpacing.lg)
        .glassCard(tint: severityColor, reduceTransparency: reduceTransparency)
    }

    private var heroGlyph: String {
        switch severity { case .good: return "moon.stars.fill"
                          case .watch: return "sun.max.trianglebadge.exclamationmark"
                          case .alert: return "cloud.bolt.fill" }
    }

    // "Céu calmo · sem flare · ar bom · corpo pronto"
    private var headline: String {
        var parts: [String] = []
        if let k = sky?.kp { parts.append("céu \(kpBand(k).0)") }
        else if sky != nil { parts.append("céu \(band.label)") }
        if let f = sky?.xrayFlux { let fc = flareClass(f); parts.append(fc.0 == "sem flare" ? "sem flare" : "flare \(fc.0)") }
        if let a = ambient?.aqi { parts.append("ar \(aqiBand(a).0.lowercased())") }
        if summary.readiness != .unavailable { parts.append("corpo \(readinessPt(summary.readiness))") }
        return parts.isEmpty ? "seu instante agora" : parts.joined(separator: " · ")
    }
    private var subHeadline: String? {
        var p: [String] = []
        if let k = sky?.kp { p.append("Kp \(String(format: "%.1f", k))") }
        if let a = ambient?.aqi { p.append("AQI \(Int(a.rounded()))") }
        if let h = summary.hrvMs ?? history?.hrv.last?.value { p.append("HRV \(Int(h.rounded()))ms") }
        return p.isEmpty ? nil : p.joined(separator: "  ·  ")
    }

    // MARK: - CÉU — grouped: geomagnético / solar / heliobiológico

    private var skyCard: some View {
        glassSection("CÉU", tint: skyColor) {
            subHeader("Geomagnético")
            sciChart("Kp", value: sky.map { String(format: "%.1f", $0.kp) } ?? "—", unit: nil,
                     band: (sky?.kp).map(kpBand),
                     history: skySeries(\.kp), forecast: kpForecastSeries(), color: skyColor)
            sciChart("Dst / SYM-H", value: symDstValue, unit: "nT",
                     band: (sky?.dst ?? sky?.symH).map(dstBand),
                     history: skySeries(\.dst), color: BeagleTheme.auroraViolet)
            sciChart("Hp30", value: sky?.hp30.map { String(format: "%.2f", $0) } ?? "—", unit: "30-min",
                     band: (sky?.hp30).map { kpBand($0) },
                     history: skySeries(\.hp30), color: skyColor)
            sciChart("AE", value: sky?.aeIndex.map { "\(Int($0.rounded()))" } ?? "—", unit: "nT · eletrojato",
                     band: nil, history: skySeries(\.aeIndex), color: BeagleTheme.truthRemembered)

            subHeader("Solar")
            sciChart("Vento solar", value: sky.flatMap { $0.solarWindSpeed.map { "\(Int($0.rounded()))" } } ?? "—", unit: "km/s",
                     band: nil, history: skySeries(\.solarWindSpeed), color: BeagleTheme.truthRemembered)
            sciChart("IMF Bz", value: sky.flatMap { $0.bz.map { String(format: "%.1f", $0) } } ?? "—", unit: "nT",
                     band: (sky?.bz).map { $0 <= -5 ? ("acoplado", BeagleTheme.postureWarm) : ("norte", BeagleTheme.truthObserved) },
                     history: skySeries(\.bz), color: BeagleTheme.truthDeclared)
            sciChart("Raio-X (GOES)", value: sky?.xrayFlux.map { flareClass($0).0 } ?? "—", unit: "W/m² · flare",
                     band: (sky?.xrayFlux).map(flareClass),
                     history: skySeries(\.xrayFlux), logScale: true, color: BeagleTheme.postureWarm)
            sciChart("Prótons", value: sky?.protonFlux.map { sScale($0).0 } ?? "—", unit: "pfu · radiação",
                     band: (sky?.protonFlux).map(sScale),
                     history: skySeries(\.protonFlux), logScale: true, color: BeagleTheme.postureWarm)

            subHeader("Heliobiológico", exploratory: true)
            sciChart("Raios cósmicos", value: sky?.cosmicRayOulu.map { String(format: "%.1f%%", $0) } ?? "—", unit: "Oulu · Forbush",
                     band: nil, history: skySeries(\.cosmicRayOulu), color: BeagleTheme.truthObserved)
            sciChart("Aurora", value: sky?.auroraPower.map { "\(Int($0.rounded()))" } ?? "—", unit: "GW · OVATION",
                     band: nil, history: skySeries(\.auroraPower), color: BeagleTheme.auroraGreen)
            sciChart("Schumann", value: sky?.schumannF1.map { String(format: "%.2f", $0) } ?? "—", unit: "7.83 Hz",
                     band: nil, history: skySeries(\.schumannF1), color: BeagleTheme.auroraViolet)
        }
    }

    private var symDstValue: String {
        if let d = sky?.dst { return "\(Int(d.rounded()))" }
        if let s = sky?.symH { return "\(Int(s.rounded()))" }
        return "—"
    }

    // MARK: - AMBIENTE — with forecast overlay (temp/UV/AQI)

    private var ambientCard: some View {
        glassSection("AMBIENTE", tint: BeagleTheme.truthRemembered) {
            sciChart("Temperatura", value: ambient?.tempC.map { "\(Int($0.rounded()))" } ?? "—", unit: "°C",
                     band: nil, history: wxSeries(\.tempC), forecast: wxForecastSeries(\.tempC),
                     color: BeagleTheme.postureWarm)
            sciChart("Pressão", value: ambient?.pressureHpa.map { "\(Int($0.rounded()))" } ?? "—", unit: "hPa",
                     band: nil, history: wxSeries(\.pressureHpa), color: BeagleTheme.truthRemembered)
            sciChart("Umidade", value: ambient?.humidity.map { "\(Int($0.rounded()))" } ?? "—", unit: "%",
                     band: nil, history: wxSeries(\.humidity), color: BeagleTheme.truthObserved)
            sciChart("UV", value: ambient?.uvIndex.map { String(format: "%.0f", $0) } ?? "—", unit: "índice",
                     band: (ambient?.uvIndex).map(uvBand), history: wxSeries(\.uvIndex),
                     forecast: wxForecastSeries(\.uvIndex), color: BeagleTheme.postureWarm)
            sciChart("Qualidade do ar", value: ambient?.aqi.map { "AQI \(Int($0.rounded()))" } ?? "—", unit: nil,
                     band: (ambient?.aqi).map(aqiBand), history: wxSeries(\.aqi),
                     forecast: wxForecastSeries(\.aqi), color: BeagleTheme.truthObserved)
            sciChart("Ruído", value: (history?.audioDb.last?.value).map { "\(Int($0.rounded()))" } ?? "—", unit: "dB",
                     band: nil,
                     history: (history?.audioDb ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.value.map { (d, $0) } } },
                     color: BeagleTheme.truthDeclared)
        }
    }

    // MARK: - CORPO

    private var bodyCard: some View {
        let hrvNow = summary.hrvMs ?? history?.hrv.last?.value
        return glassSection("CORPO", tint: BeagleTheme.truthObserved) {
            sciChart("HRV", value: hrvNow.map { "\(Int($0.rounded()))" } ?? "—", unit: "ms",
                     band: summary.readiness != .unavailable ? (readinessPt(summary.readiness), BeagleTheme.truthObserved) : nil,
                     history: (history?.hrv ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p.value.map { (d, $0) } } },
                     color: BeagleTheme.truthObserved)
            if let s = summary.sleepHours {
                staticMetricRow("Sono", String(format: "%.1f h", s), color: BeagleTheme.truthRemembered)
            }
            if let r = summary.restingHeartRate {
                staticMetricRow("Pulso repouso", "\(Int(r.rounded())) bpm", color: BeagleTheme.stateError)
            }
        }
    }

    // MARK: - CORRELAÇÕES — readable insights + rigor badge

    @ViewBuilder
    private var correlationsCard: some View {
        let all = corr?.correlations ?? []
        let notable = all.filter { $0.notable == true }
        let shown = Array((notable.isEmpty ? all : notable).prefix(6))
        glassSection("CORRELAÇÕES · corpo × céu", tint: BeagleTheme.auroraViolet) {
            HStack(spacing: 6) {
                Text("o que teu corpo diz do céu")
                    .font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textSecondary)
                Spacer()
                provenanceBadge(true)
            }
            if shown.isEmpty {
                Text(loading ? "Calculando…" : "Sem correlações com dados suficientes ainda (mín. ~7 dias pareados).")
                    .font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
            } else {
                ForEach(shown) { c in correlationInsight(c) }
                Text("Spearman ρ · varredura de atraso · n baixo → associação, não causa · pré-registrar antes de concluir")
                    .font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary).padding(.top, 2)
            }
        }
    }

    // Readable one-liner: "HRV cai quando Kp sobe · ρ −0.30 · n=9 · atraso 1d"
    private func correlationInsight(_ c: PhysioCorrelations.Correlation) -> some View {
        let down = c.rho < 0
        let strong = abs(c.rho) >= 0.5
        let tint: Color = strong ? (down ? BeagleTheme.stateError : BeagleTheme.truthObserved) : BeagleTheme.textSecondary
        let verb = down ? "cai quando" : "sobe quando"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label(c.outcome)).font(BeagleFont.footnote.font.weight(.medium)).foregroundStyle(BeagleTheme.textPrimary)
                Text(verb).font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
                Text("\(label(c.driver)) sobe").font(BeagleFont.footnote.font).foregroundStyle(BeagleTheme.textSecondary)
                Spacer(minLength: 4)
                Text(String(format: "ρ %@%.2f", down ? "−" : "+", abs(c.rho)))
                    .font(BeagleFont.body.font.monospaced()).foregroundStyle(tint)
            }
            HStack(spacing: 6) {
                Text("n=\(c.n) · atraso \(c.lag)d\(c.p != nil ? String(format: " · p=%.3f", c.p!) : "")")
                    .font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                Capsule().fill(tint.opacity(0.22)).frame(width: 44, height: 4)
                    .overlay(alignment: .leading) { Capsule().fill(tint).frame(width: 44 * min(1, abs(c.rho)), height: 4) }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - MENTE (unchanged behavior)

    @ViewBuilder
    private var mindCard: some View {
        let fractals = cognitive.state.value?.recentFractalTrees ?? []
        let phis = cognitive.state.value?.recentPhiMeasurements ?? []
        let voids = cognitive.state.value?.recentVoidJourneys ?? []
        glassSection("MENTE", tint: BeagleTheme.truthRemembered) {
            if fractals.isEmpty && phis.isEmpty && voids.isEmpty {
                Text("Nenhuma exploração ainda.").font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
            } else {
                if let fractal = fractals.first {
                    Button {
                        let prompt = fractal.rootPrompt ?? "fractal tree"
                        onSendToChat?("Explain this fractal exploration: \(prompt) — it produced \(fractal.nodeCount ?? 0) nodes at depth \(fractal.maxDepth ?? 0) in \(fractal.durationMs ?? 0)ms")
                        dismiss()
                    } label: {
                        mindRow(icon: "tree", color: BeagleTheme.truthObserved,
                                title: "Fractal: \(fractal.nodeCount ?? 0) nós",
                                subtitle: fractal.rootPrompt ?? "",
                                detail: "profundidade \(fractal.maxDepth ?? 0) · \(fractal.durationMs ?? 0)ms")
                    }.buttonStyle(.plain)
                }
                if let phi = phis.first {
                    Button {
                        onSendToChat?("Analyze this IIT measurement: Φ = \(phi.phi ?? 0) for query '\(phi.querySnippet ?? "")'. Awareness: \(phi.awarenessLevel ?? "unknown"). What does this mean?")
                        dismiss()
                    } label: {
                        mindRow(icon: "waveform.path.ecg", color: BeagleTheme.truthRemembered,
                                title: "Φ = \(String(format: "%.4f", phi.phi ?? 0))",
                                subtitle: phi.querySnippet ?? "",
                                detail: "\(phi.awarenessLevel ?? "") · \(phi.substrateSize ?? 0) substratos")
                    }.buttonStyle(.plain)
                }
                if !voids.isEmpty {
                    mindRow(icon: "circle.dotted", color: BeagleTheme.postureWarm,
                            title: "\(voids.count) jornada\(voids.count > 1 ? "s" : "") void",
                            subtitle: "\(voids.first?.insights?.count ?? 0) insights na última",
                            detail: "profundidade \(String(format: "%.1f", voids.first?.maxDepthReached ?? 0))")
                }
            }
            Divider().overlay(BeagleTheme.truthRemembered.opacity(0.1)).padding(.vertical, 2)
            HStack(spacing: BeagleSpacing.md) {
                mindTriggerButton(label: "Explorar fractal", icon: "tree", isLoading: isExploringFractal) { await triggerFractalExploration() }
                mindTriggerButton(label: "Medir Φ agora", icon: "waveform.path.ecg", isLoading: isMeasuringPhi) { await triggerPhiMeasurement() }
            }
        }
    }

    private func mindTriggerButton(label: String, icon: String, isLoading: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack(spacing: BeagleSpacing.xxs) {
                if isLoading { ProgressView().controlSize(.mini) } else { Image(systemName: icon).font(.system(size: 11)) }
                Text(label).font(BeagleFont.caption2.font)
            }.foregroundStyle(BeagleTheme.truthRemembered)
        }.buttonStyle(.plain).disabled(isLoading)
    }

    private var explorationSeedPrompt: String {
        let thought = cognitive.recentThoughts.first
        return thought?.refinedText ?? thought?.rawText ?? "What is the current state of my exocortex?"
    }
    private func triggerFractalExploration() async {
        isExploringFractal = true
        _ = await BeagleClient.shared.startFractalTree(prompt: explorationSeedPrompt)
        await cognitive.refresh(); isExploringFractal = false
    }
    private func triggerPhiMeasurement() async {
        isMeasuringPhi = true
        _ = await BeagleClient.shared.measurePhi(prompt: explorationSeedPrompt)
        await cognitive.refresh(); isMeasuringPhi = false
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
        }.padding(.vertical, 4)
    }

    private func label(_ key: String) -> String {
        switch key {
        case "kpMax": return "Kp"
        case "hrvMs": return "HRV"
        case "restingHr": return "FC repouso"
        case "sleepHours": return "sono"
        case "mood": return "humor"
        case "steps": return "passos"
        case "pressureTrendHpa": return "pressão"
        case "solarWindSpeed": return "vento solar"
        case "f107": return "F10.7"
        case "uvMax": return "UV"
        case "aqi": return "AQI"
        case "tempMaxC": return "temp"
        default: return key
        }
    }

    // MARK: - Scientific chart (axes + units + log + forecast overlay)

    /// history = observed (solid), forecast = predicted (dashed), split at "now" by a rule mark.
    private func sciChart(_ title: String, value: String, unit: String?, band: (String, Color)?,
                          history: [(Date, Double)], forecast: [(Date, Double)] = [],
                          logScale: Bool = false, color: Color) -> some View {
        // Prep: drop NaN/Inf, de-dupe timestamps (duplicate ids break Charts), and for
        // orders-of-magnitude channels plot log10 on a LINEAR axis instead of using
        // .chartYScale(type: .log) — the framework's log scale segfaults on a degenerate
        // domain (single value / all-equal), which is exactly what a sparse feed produces.
        let hist = prepSeries(history, log: logScale)
        let fc = prepSeries(forecast, log: logScale)
        let hasSeries = hist.count > 1 || fc.count > 1
        let unitText = unit.map { logScale ? "\($0) (log₁₀)" : $0 }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
                Spacer(minLength: 4)
                Text(value).font(BeagleFont.footnote.font.monospaced().weight(.medium)).foregroundStyle(BeagleTheme.textPrimary)
                if let unitText { Text(unitText).font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary) }
                if let band { bandPill(band.0, band.1) }
            }
            if hasSeries {
                Chart {
                    ForEach(hist, id: \.0) { p in
                        AreaMark(x: .value("t", p.0), y: .value("v", p.1))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("t", p.0), y: .value("v", p.1), series: .value("s", "obs"))
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    ForEach(fc, id: \.0) { p in
                        LineMark(x: .value("t", p.0), y: .value("v", p.1), series: .value("s", "fc"))
                            .foregroundStyle(color.opacity(0.7))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                    if !fc.isEmpty {
                        RuleMark(x: .value("now", Date()))
                            .foregroundStyle(BeagleTheme.textTertiary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine().foregroundStyle(BeagleTheme.textTertiary.opacity(0.12))
                        AxisValueLabel().font(.system(size: 8)).foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisGridLine().foregroundStyle(BeagleTheme.textTertiary.opacity(0.08))
                        AxisValueLabel().font(.system(size: 8)).foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 62)
            }
        }
        .padding(.vertical, 4)
    }

    /// Finite-filter, de-dupe by timestamp (last wins), sort, and optionally log10-transform.
    private func prepSeries(_ s: [(Date, Double)], log: Bool) -> [(Date, Double)] {
        var byTs: [Date: Double] = [:]
        for (d, v) in s {
            guard v.isFinite else { continue }
            if log { guard v > 0 else { continue }; byTs[d] = log10(v) }
            else { byTs[d] = v }
        }
        return byTs.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: - Series extraction

    private func skySeries(_ kp: KeyPath<SkyPoint, Double?>) -> [(Date, Double)] {
        (history?.sky ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p[keyPath: kp].map { (d, $0) } } }
    }
    private func wxSeries(_ kp: KeyPath<WeatherPoint, Double?>) -> [(Date, Double)] {
        (history?.weather ?? []).compactMap { p in tsDate(p.ts).flatMap { d in p[keyPath: kp].map { (d, $0) } } }
    }
    private func wxForecastSeries(_ kp: KeyPath<WxForecastPoint, Double?>) -> [(Date, Double)] {
        let now = Date()
        return (forecast?.weather ?? []).compactMap { p in
            tsDate(p.ts).flatMap { d in d >= now ? p[keyPath: kp].map { (d, $0) } : nil }
        }
    }
    private func kpForecastSeries() -> [(Date, Double)] {
        (forecast?.skyKp ?? []).compactMap { p in
            (p.predicted ? tsDate(p.ts) : nil).flatMap { d in p.kp.map { (d, $0) } }
        }
    }

    // MARK: - Named bands (state, not raw number)

    private func kpBand(_ k: Double) -> (String, Color) {
        if k >= 7 { return ("tempestade G3+", BeagleTheme.stateError) }
        if k >= 5 { return ("tempestade G1", BeagleTheme.auroraViolet) }
        if k >= 4 { return ("ativo", BeagleTheme.postureWarm) }
        return ("calmo", BeagleTheme.truthObserved)
    }
    private func dstBand(_ d: Double) -> (String, Color) {
        if d <= -100 { return ("tempestade forte", BeagleTheme.stateError) }
        if d <= -50 { return ("tempestade", BeagleTheme.auroraViolet) }
        if d <= -30 { return ("perturbado", BeagleTheme.postureWarm) }
        return ("calmo", BeagleTheme.truthObserved)
    }
    private func aqiBand(_ a: Double) -> (String, Color) {
        if a > 150 { return ("insalubre", BeagleTheme.stateError) }
        if a > 100 { return ("sensíveis", BeagleTheme.postureWarm) }
        if a > 50 { return ("moderado", BeagleTheme.postureWarm) }
        return ("bom", BeagleTheme.truthObserved)
    }
    private func uvBand(_ u: Double) -> (String, Color) {
        if u >= 11 { return ("extremo", BeagleTheme.stateError) }
        if u >= 8 { return ("muito alto", BeagleTheme.stateError) }
        if u >= 6 { return ("alto", BeagleTheme.postureWarm) }
        if u >= 3 { return ("moderado", BeagleTheme.postureWarm) }
        return ("baixo", BeagleTheme.truthObserved)
    }
    private func flareClass(_ f: Double) -> (String, Color) {
        if f >= 1e-4 { return (String(format: "X%.0f", f / 1e-4), BeagleTheme.stateError) }
        if f >= 1e-5 { return (String(format: "M%.0f", f / 1e-5), BeagleTheme.stateError) }
        if f >= 1e-6 { return (String(format: "C%.0f", f / 1e-6), BeagleTheme.postureWarm) }
        return ("sem flare", BeagleTheme.truthObserved)
    }
    private func sScale(_ p: Double) -> (String, Color) {
        if p >= 1e5 { return ("S5", BeagleTheme.stateError) }
        if p >= 1e4 { return ("S4", BeagleTheme.stateError) }
        if p >= 1e3 { return ("S3", BeagleTheme.stateError) }
        if p >= 1e2 { return ("S2", BeagleTheme.postureWarm) }
        if p >= 10 { return ("S1", BeagleTheme.postureWarm) }
        return ("S0", BeagleTheme.truthObserved)
    }

    // MARK: - Small building blocks

    private func bandPill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
    }
    private func provenanceBadge(_ exploratory: Bool) -> some View {
        Text(exploratory ? "exploratório" : "mainstream")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(exploratory ? BeagleTheme.auroraViolet : BeagleTheme.truthObserved)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill((exploratory ? BeagleTheme.auroraViolet : BeagleTheme.truthObserved).opacity(0.14)))
    }
    private func subHeader(_ text: String, exploratory: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(BeagleTheme.textSecondary).tracking(0.5)
            if exploratory { provenanceBadge(true) }
            Spacer()
        }
        .padding(.top, 4)
    }

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

    private func staticMetricRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label).font(BeagleFont.caption2.font).foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
            Text(value).font(BeagleFont.body.font.monospaced()).foregroundStyle(color)
        }.padding(.vertical, 4)
    }

    private func readinessPt(_ r: PhysioReadiness) -> String {
        switch r { case .restored: return "recuperado"; case .steady: return "estável"; case .strained: return "tenso"; case .unavailable: return "—" }
    }
    private func tsDate(_ ts: String) -> Date? {
        ISO8601DateFormatter().date(from: ts)
            ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: ts) }()
    }
}

// MARK: - Glass card modifier

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
