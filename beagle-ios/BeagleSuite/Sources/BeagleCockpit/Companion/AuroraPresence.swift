//
//  AuroraPresence.swift
//  BeagleCockpit — Companion chat (2026-06-28)
//
//  REPLACES the vector beagle figure (BeagleFigure / BeagleSplatView) per user pivot
//  on 2026-06-28: "trocar por outra presença" + "minha paixão pelo clima espacial,
//  heliobiologia". The companion's body is now the sky — an aurora orb that breathes
//  with the user's HRV (breathRate), shifts hue with the hour of day, and saturates
//  when the geomagnetic field is active (Kp). It's not a mascot; it's the acoplamento
//  made visible — physiology + heliophysics + time.
//
//  Pure SwiftUI radial gradients + canvas. No 3D, no Metal, no MTKView teardown.
//  Cheap enough to live in the header during active conversation without contending
//  the keyboard / typing performance.
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

    @State private var phase: CGFloat = 0
    @State private var hueShift: CGFloat = 0

    private var diameter: CGFloat { size == .greeter ? 220 : 86 }
    private var ringWidth: CGFloat { size == .greeter ? 3 : 1.5 }

    // Hour-of-day color tone: madrugada (0–5)=índigo profundo+violeta,
    // manhã (6–11)=verde-água, tarde (12–17)=teal-pálido,
    // anoitecer (18–22)=rose-violeta, noite (23)=índigo. Cycles smooth.
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

    // Intensity from Kp: quiet (Kp ≤ 2) → calm; storm (Kp ≥ 6) → vivid + faster pulse.
    private var kpIntensity: Double {
        guard let kp = weather?.kp else { return 0.25 }
        return max(0.15, min(1.0, (kp - 1) / 5))
    }

    // Breath period in seconds — slower when calm, faster during storm (geomagnetic
    // activity quickens the pulse subliminally). Defaults to a resting 5.5 bpm.
    private var breathPeriod: Double {
        let bpm = max(4.0, min(20.0, breathRate ?? 5.5))
        let stormSpeedup = 1.0 - (kpIntensity * 0.25)   // up to 25% faster during storm
        return (60.0 / bpm) * stormSpeedup
    }

    var body: some View {
        ZStack {
            // OUTER halo — soft aurora glow that fades to background
            halo
            // RIBBON — the curtain itself, radial gradient with hour-tone hues
            ribbon
            // INNER core — bright still point
            core
            // Hairline ring to make the form sit definite
            Circle()
                .strokeBorder(BeagleTheme.companionHairline, lineWidth: ringWidth)
                .frame(width: diameter * 0.86, height: diameter * 0.86)
        }
        .frame(width: diameter * 1.4, height: diameter * 1.4)
        .compositingGroup()
        .onAppear {
            withAnimation(.easeInOut(duration: breathPeriod).repeatForever(autoreverses: true)) {
                phase = 1
            }
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: true)) {
                hueShift = 1
            }
        }
        .accessibilityHidden(true)
    }

    private var halo: some View {
        let tone = hourTone
        let pulseAlpha = 0.18 + 0.12 * phase + 0.10 * kpIntensity
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
            .scaleEffect(1.0 + 0.04 * phase)
    }

    private var ribbon: some View {
        let tone = hourTone
        // Mix the three tones across the disc; storm pushes more violet/pink
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
                    angle: .degrees(360 * hueShift)
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
            .scaleEffect(0.96 + 0.06 * phase)
    }

    private var core: some View {
        let coreAlpha = 0.65 + 0.20 * phase
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
