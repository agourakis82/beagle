//
//  AuroraPresence.swift
//  BeagleCockpit — Companion chat (2026-06-28)
//
//  Aurora orb: pure SwiftUI radial/angular gradients animated by a TimelineView
//  (no @State mutation per frame → no AttributeGraph cycles). Breathes with the
//  user's HRV, shifts hue with the hour of day, saturates when Kp is active.
//

import SwiftUI
import BeagleCore

struct AuroraPresence: View {
    let breathRate: Double?
    let weather: SpaceWeatherStore.Snapshot?
    let size: Size
    enum Size { case greeter, header }

    private var diameter: CGFloat { size == .greeter ? 220 : 86 }
    private var ringWidth: CGFloat { size == .greeter ? 3 : 1.5 }

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

    private var kpIntensity: Double {
        guard let kp = weather?.kp else { return 0.25 }
        return max(0.15, min(1.0, (kp - 1) / 5))
    }

    private var breathPeriod: Double {
        let bpm = max(4.0, min(20.0, breathRate ?? 5.5))
        return (60.0 / bpm) * (1.0 - kpIntensity * 0.25)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.125)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breathPhase = CGFloat((sin(t * .pi * 2 / breathPeriod) + 1) / 2)
            let hueAngle = (t / 60).truncatingRemainder(dividingBy: 1)
            content(breathPhase: breathPhase, hueAngle: hueAngle)
        }
        .frame(width: diameter * 1.4, height: diameter * 1.4)
        .compositingGroup()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(breathPhase: CGFloat, hueAngle: Double) -> some View {
        let tone = hourTone
        let pulseAlpha = 0.18 + 0.12 * breathPhase + 0.10 * kpIntensity
        let saturation = 0.55 + 0.45 * kpIntensity
        let coreAlpha = 0.65 + 0.20 * breathPhase
        ZStack {
            // Halo
            Circle()
                .fill(RadialGradient(
                    colors: [tone.a.opacity(pulseAlpha), tone.b.opacity(pulseAlpha * 0.6), .clear],
                    center: .center, startRadius: diameter * 0.3, endRadius: diameter * 0.95))
                .blur(radius: 12)
                .scaleEffect(1.0 + 0.04 * breathPhase)
            // Ribbon
            Circle()
                .fill(AngularGradient(
                    colors: [tone.a.opacity(saturation), tone.b.opacity(saturation),
                             tone.c.opacity(saturation), tone.a.opacity(saturation)],
                    center: .center, angle: .degrees(360 * hueAngle)))
                .frame(width: diameter, height: diameter)
                .mask(RadialGradient(colors: [.black, .black.opacity(0.85), .black.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: diameter * 0.55))
                .blur(radius: 4)
                .scaleEffect(0.96 + 0.06 * breathPhase)
            // Core
            Circle()
                .fill(RadialGradient(
                    colors: [BeagleTheme.companionInk.opacity(coreAlpha),
                             BeagleTheme.auroraTeal.opacity(coreAlpha * 0.5), .clear],
                    center: .center, startRadius: 0, endRadius: diameter * 0.18))
                .frame(width: diameter * 0.32, height: diameter * 0.32)
                .blur(radius: 1)
            Circle()
                .strokeBorder(BeagleTheme.companionHairline, lineWidth: ringWidth)
                .frame(width: diameter * 0.86, height: diameter * 0.86)
        }
    }
}
