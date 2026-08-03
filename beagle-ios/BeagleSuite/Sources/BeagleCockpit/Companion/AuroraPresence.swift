//
//  AuroraPresence.swift
//  BeagleCockpit — Companion chat (2026-06-28, v3 curtains)
//
//  Real aurora is a CURTAIN, not an orb: vertical drapes of oxygen-green at the
//  base climbing into nitrogen-violet/pink at the top, drifting horizontally
//  across the sky, rippling slowly like fabric in wind. v3 reflects this:
//
//    - Multiple overlapping vertical curtains drawn in a Canvas
//    - Vertical color gradient per curtain (green/teal → violet/pink ascending)
//    - Each curtain rides a sin-wave drift; phase offsets stagger them
//    - Hue cycles slowly with the hour-of-day
//    - Saturation + drape count rise with Kp (geomagnetic storm)
//    - Brightness pulses with the user's breath
//    - When the companion is streaming, the curtain glows brighter and pulses
//      faster — the sky responds to the conversation
//
//  Pure SwiftUI + Canvas + TimelineView. No state mutation per frame → no cycles.
//

import SwiftUI
import BeagleCore

struct AuroraPresence: View {
    /// Ritmo declarado. `.neutral` (Physiome mudo) respira mais lento E mais raso —
    /// antes isto era `breathRate ?? 5.5`, um ritmo inventado indistinguível de um medido.
    let breath: PresenceBreath
    let weather: SpaceWeatherStore.Snapshot?
    let isStreaming: Bool
    let size: Size
    enum Size { case greeter, header }

    /// Height of the aurora band relative to the available height.
    private var bandHeightFraction: CGFloat { size == .greeter ? 0.55 : 0.45 }

    /// Hour-of-day color tone: top (high-altitude, violet/pink) → mid (teal) →
    /// base (oxygen green). Real aurora reads pink/violet at peak, green at base.
    private var tone: (top: Color, mid: Color, base: Color) {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0...4:   return (BeagleTheme.auroraViolet, BeagleTheme.auroraTeal,  BeagleTheme.auroraGreen)   // madrugada
        case 5...8:   return (BeagleTheme.auroraPink,   BeagleTheme.auroraTeal,  BeagleTheme.auroraGreen)   // manhã
        case 9...13:  return (BeagleTheme.auroraTeal,   BeagleTheme.auroraGreen, BeagleTheme.auroraTeal)    // tarde-clara
        case 14...17: return (BeagleTheme.auroraViolet, BeagleTheme.auroraTeal,  BeagleTheme.auroraGreen)   // tarde
        case 18...21: return (BeagleTheme.auroraPink,   BeagleTheme.auroraViolet, BeagleTheme.auroraTeal)   // anoitecer
        default:      return (BeagleTheme.auroraViolet, BeagleTheme.auroraGreen, BeagleTheme.auroraTeal)    // noite
        }
    }

    /// Kp-driven intensity 0…1.
    private var kpIntensity: Double {
        guard let kp = weather?.kp else { return 0.25 }
        return max(0.15, min(1.0, (kp - 1) / 5))
    }

    /// Number of overlapping curtains. More drapes when geomagnetically active.
    private var drapeCount: Int { 3 + Int(round(kpIntensity * 3)) }   // 3…6

    /// Breath period in seconds — vem do tipo, sem default silencioso.
    private var breathPeriod: Double { breath.period }

    /// Pulse base — slow normally, faster during streaming (companion is talking).
    private var streamingBoost: Double { isStreaming ? 1.6 : 1.0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { context in
            Canvas(rendersAsynchronously: true) { ctx, sz in
                draw(ctx: ctx, sz: sz, time: context.date.timeIntervalSinceReferenceDate)
            }
        }
        .compositingGroup()
        .blur(radius: 6)
        .accessibilityHidden(true)
    }

    private func draw(ctx: GraphicsContext, sz: CGSize, time: TimeInterval) {
        let bandHeight = sz.height * bandHeightFraction
        let bandTop: CGFloat = sz.height * 0.05
        let baseAlpha = (0.18 + 0.30 * kpIntensity) * streamingBoost

        // Breath modulates overall brightness.
        let breath = (sin(time * .pi * 2 / breathPeriod) + 1) / 2
        let pulse = 0.85 + 0.30 * self.breath.amplitude * breath

        // Slow hue rotation — full cycle every 90s.
        let hueShift = (time / 90).truncatingRemainder(dividingBy: 1)

        for i in 0..<drapeCount {
            let p = Double(i) / Double(max(drapeCount - 1, 1))   // 0…1 across width
            // Each curtain drifts horizontally on its own sine, phase-offset
            let drift = sin(time * 0.10 + Double(i) * 0.8) * Double(sz.width * 0.08)
            let centerX = sz.width * (0.15 + 0.70 * p) + drift
            let curtainWidth = sz.width * (0.18 + 0.06 * kpIntensity)

            // Vertical wave deformation — fabric in wind. Each curtain has its own phase.
            let wavePhase = time * 0.6 + Double(i) * 1.3
            let waveAmp = 6.0 + 10.0 * kpIntensity

            // Pick a tone variant per drape, blending with hour-of-day tone shifts.
            // Phase the colors per drape index for iridescent variety.
            let mix = (Double(i) + hueShift) / Double(drapeCount)
            let topC  = blend(tone.top,  tone.mid, t: mix)
            let midC  = blend(tone.mid,  tone.base, t: mix)
            let baseC = tone.base

            // Build the drape as a closed path: top edge waves, bottom edge waves,
            // sides connect. Render via shading with a vertical gradient.
            var path = Path()
            let steps = 18
            // Top edge (left → right)
            for s in 0...steps {
                let frac = Double(s) / Double(steps)
                let y = bandTop + CGFloat(sin(wavePhase + frac * 4) * 2)
                let x = centerX - curtainWidth / 2 + curtainWidth * CGFloat(frac)
                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else      { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            // Bottom edge (right → left) with bigger wave amplitude
            for s in (0...steps).reversed() {
                let frac = Double(s) / Double(steps)
                let y = bandTop + bandHeight + CGFloat(sin(wavePhase * 1.1 + frac * 5) * waveAmp)
                let x = centerX - curtainWidth / 2 + curtainWidth * CGFloat(frac)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.closeSubpath()

            let gradient = Gradient(stops: [
                .init(color: topC.opacity(baseAlpha * 0.85 * pulse), location: 0.00),
                .init(color: midC.opacity(baseAlpha * 1.00 * pulse), location: 0.45),
                .init(color: baseC.opacity(baseAlpha * 0.70 * pulse), location: 0.85),
                .init(color: baseC.opacity(0.0),                       location: 1.00),
            ])
            ctx.fill(path, with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: centerX, y: bandTop),
                endPoint:   CGPoint(x: centerX, y: bandTop + bandHeight)
            ))
        }
    }

    /// Linear color blend (RGB). Avoids hue-rotation rainbows; just smooth mixing.
    private func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        let aC = a.resolve(in: .init())
        let bC = b.resolve(in: .init())
        return Color(
            red:   Double(aC.red   + (bC.red   - aC.red)   * Float(t)),
            green: Double(aC.green + (bC.green - aC.green) * Float(t)),
            blue:  Double(aC.blue  + (bC.blue  - aC.blue)  * Float(t))
        )
    }
}
