//
//  AuroraPresence.swift
//  BeagleCockpit — Companion chat (2026-06-28, v2)
//
//  REPLACES the vector beagle figure. The companion's body is the sky: an aurora
//  orb that breathes with the user's HRV, shifts hue with the hour of day, and
//  saturates when the geomagnetic field is active (Kp).
//
//  v2: rewritten with TimelineView (driven by the system display link) instead
//  of withAnimation+repeatForever, which created an AttributeGraph cycle in v1
//  (199+ cycles per second → SIGKILL). TimelineView is the canonical SwiftUI
//  pattern for continuous animation — no @State mutation per frame, the view
//  receives a `context.date` and computes purely from it.
//

import SwiftUI
import BeagleCore

struct AuroraPresence: View {
    /// User's respiratory rate in breaths/min (HRV-derived). nil → calm 5.5 bpm.
    let breathRate: Double?
    /// Latest geomagnetic snapshot. nil → calm default intensity.
    let weather: SpaceWeatherStore.Snapshot?
    /// Container hint: greeter (large, empty state) vs header (compact during chat).
    let size: Size

    enum Size { case greeter, header }

    private var diameter: CGFloat { size == .greeter ? 220 : 86 }
    private var ringWidth: CGFloat { size == .greeter ? 3 : 1.5 }

    // Hour-of-day color tone: madrugada=índigo+violeta+verde, manhã=verde-água,
    // tarde=teal-pálido, anoitecer=rose-violeta, noite=índigo. Static per session.
    private var hourTone: (a: Color, b: Color, c: Color) {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0...4:   return (BeagleTheme.auroraViolet, BeagleTheme.auroraGreen,  BeagleTheme.auroraTeal)
        case 5...8:   return (BeagleTheme.auroraTeal,   BeagleTheme.auroraGreen,  BeagleTheme.auroraPink)
        case 9...13:  return (BeagleTheme.auroraGreen,  BeagleTheme.auroraTeal,   BeagleTheme.auroraViolet)
        case 14...17: return (BeagleTheme.auroraTeal,   BeagleTheme.auroraViolet, BeagleTheme.auroraGreen)
        case 18...21: return (BeagleTheme.auroraPink,   BeagleTheme.auroraViolet, BeagleTheme.auroraTeal)
        default:      return (BeagleTheme.auroraViolet, BeagleTheme.auroraGreen,  BeagleTheme.auroraTeal)
        }
    }

    // Intensity from Kp: quiet (Kp ≤ 2) → calm; storm (Kp ≥ 6) → vivid.
    private var kpIntensity: Double {
        guard let kp = weather?.kp else { return 0.25 }
        return max(0.15, min(1.0, (kp - 1) / 5))
    }

    // Breath period in seconds — slower when calm, faster during storm.
    private var breathPeriod: Double {
        let bpm = max(4.0, min(20.0, breathRate ?? 5.5))
        let stormSpeedup = 1.0 - (kpIntensity * 0.25)
        return (60.0 / bpm) * stormSpeedup
    }

    var body: some View {
        // 8 Hz tick — smooth enough for breathing, cheap enough to never hurt typing.
        TimelineView(.periodic(from: .now, by: 0.125)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breathPhase = CGFloat((sin(t * .pi * 2 / breathPeriod) + 1) / 2)   // 0…1
            let hueAngle = (t / 60).truncatingRemainder(dividingBy: 1)              // 0…1 per minute
            content(breathPhase: breathPhase, hueAngle: hueAngle)
        }
        .frame(width: diameter * 1.4, height: diameter * 1.4)
        .compositingGroup()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(breathPhase: CGFloat, hueAngle: Double) -> some View {
        ZStack {
            halo(breathPhase: breathPhase)
            ribbon(hueAngle: hueAngle, breathPhase: breathPhase)
            core(breathPhase: breathPhase)
            Circle()
                .strokeBorder(BeagleTheme.companionHairline, lineWidth: ringWidth)
                .frame(width: diameter * 0.86, height: diameter * 0.86)
        }
    }

    private func halo(breathPhase: CGFloat) -> some View {
        let tone = hourTone
        let pulseAlpha = 0.18 + 0.12 * breathPhase + 0.10 * kpIntensity
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        tone.a.opacity(pulseAlpha),
                        tone.b.opacity(pulseAlpha * 0.6),
                        Color.clear
                    ],
                    center: .center, startRadius: diameter * 0.3, endRadius: diameter * 0.95
                )
            )
            .blur(radius: 12)
            .scaleEffect(1.0 + 0.04 * breathPhase)
    }

    private func ribbon(hueAngle: Double, breathPhase: CGFloat) -> some View {
        let tone = hourTone
        let saturation = 0.55 + 0.45 * kpIntensity
        return Circle()
            .fill(
                AngularGradient(
                    colors: [
                        tone.a.opacity(saturation),
                        tone.b.opacity(saturation),
                        tone.c.opacity(saturation),
                        tone.a.opacity(saturation)
                    ],
                    center: .center,
                    angle: .degrees(360 * hueAngle)
                )
            )
            .frame(width: diameter, height: diameter)
            .mask(
                RadialGradient(
                    colors: [Color.black, Color.black.opacity(0.85), Color.black.opacity(0.0)],
                    center: .center, startRadius: 0, endRadius: diameter * 0.55
                )
            )
            .blur(radius: 4)
            .scaleEffect(0.96 + 0.06 * breathPhase)
    }

    private func core(breathPhase: CGFloat) -> some View {
        let coreAlpha = 0.65 + 0.20 * breathPhase
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        BeagleTheme.companionInk.opacity(coreAlpha),
                        BeagleTheme.auroraTeal.opacity(coreAlpha * 0.5),
                        Color.clear
                    ],
                    center: .center, startRadius: 0, endRadius: diameter * 0.18
                )
            )
            .frame(width: diameter * 0.32, height: diameter * 0.32)
            .blur(radius: 1)
    }
}
