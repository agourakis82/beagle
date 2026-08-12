//
//  EmberField.swift
//  BeagleCockpit
//
//  The ember field the dog sits in — the ambient half of the presence.
//
//  Ported from the Figma composition (file dgN7JrAPdQnvKzccdBrlW5, page "Presença").
//  The palette is read from the loop posters themselves, NOT from BeagleTheme: the
//  presence runs hotter than the brand. Fire #FF6A33, ember #FF9A5A, deep #8C2A18.
//
//  Three decisions carried over from the Figma work, each for a measured reason:
//
//  1. The lights composite in .screen, not .normal. Light adds; paint covers. Three
//     overlapping radials in screen read as one field with a hot core instead of
//     three discs stacked on each other.
//
//  2. The base is #07070B, not black. Pure black on OLED switches pixels off, and
//     the field loses the sense of depth it needs — there is nothing for the glow
//     to fall off into.
//
//  3. There is grain. A dark radial gradient on an OLED panel bands visibly, and
//     banding is exactly what makes a screen look cheap at 4am. The noise is drawn
//     ONCE into a rasterized layer (.drawingGroup) — it does not re-render per
//     frame, so it costs nothing after the first pass.
//
//  On battery: the animation ticks at 12fps, not 60. Nothing here needs smoothness
//  — it is a breath, not a transition. This runs for entire night shifts.
//

import SwiftUI

public struct EmberField: View {

    /// Beats per minute driving the breath. `nil` → a resting cadence.
    private let breathRate: Double?
    /// 0…1 — how present the field is. The chat dims it; the greeter opens it up.
    private let intensity: Double

    public init(breathRate: Double? = nil, intensity: Double = 1.0) {
        self.breathRate = breathRate
        self.intensity = max(0, min(1, intensity))
    }

    // Read off the loop posters, not the theme.
    private static let fire  = Color(red: 1.00, green: 0.42, blue: 0.20)
    private static let ember = Color(red: 1.00, green: 0.60, blue: 0.35)
    private static let deep  = Color(red: 0.55, green: 0.16, blue: 0.09)
    private static let floor = Color(red: 0.027, green: 0.027, blue: 0.043)

    /// Where the dog's heart sits in the frame — every light is anchored to it.
    private static let heart = UnitPoint(x: 0.52, y: 0.34)

    /// Breaths per second. A resting adult is ~13/min; we follow the pulse when we
    /// have one, at a quarter of its rate, because breath is slower than heartbeat.
    private var breathHz: Double {
        let bpm = breathRate ?? 52
        return max(0.10, min(0.40, bpm / 4.0 / 60.0))
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Sine in 0…1. The core swells and settles; nothing else moves.
            let breath = (sin(t * breathHz * 2 * .pi) + 1) / 2
            let swell = 0.88 + 0.12 * breath

            ZStack {
                EmberField.floor

                light(EmberField.fire,  radius: 0.62 * swell, opacity: 0.55)
                light(EmberField.ember, radius: 0.45,         opacity: 0.20,
                      at: UnitPoint(x: 0.20, y: 0.18))
                light(EmberField.deep,  radius: 0.88,         opacity: 0.32)

                // The core: tight, bright, the point the light is born from.
                light(EmberField.fire, radius: 0.17 * swell, opacity: 0.72 * (0.85 + 0.15 * breath))

                vignette
                grain
            }
            .compositingGroup()      // required, or .screen leaks onto whatever is behind
            .opacity(intensity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func light(_ color: Color,
                       radius: Double,
                       opacity: Double,
                       at point: UnitPoint = EmberField.heart) -> some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height) * radius
            RadialGradient(
                stops: [
                    .init(color: color.opacity(opacity),        location: 0.00),
                    .init(color: color.opacity(opacity * 0.30), location: 0.45),
                    .init(color: color.opacity(0.0),            location: 1.00),
                ],
                center: point, startRadius: 0, endRadius: r
            )
        }
        .blendMode(.screen)
    }

    /// Closes the edges so the eye is pushed to the heart. Long falloff — a short
    /// one draws a visible ring, which is worse than no vignette at all.
    private var vignette: some View {
        RadialGradient(
            stops: [
                .init(color: .clear,                     location: 0.00),
                .init(color: .clear,                     location: 0.50),
                .init(color: Color.black.opacity(0.72),  location: 1.00),
            ],
            center: EmberField.heart, startRadius: 0, endRadius: 620
        )
        .blendMode(.multiply)
    }

    /// Drawn once and rasterized. Kills the banding a dark gradient shows on OLED.
    private var grain: some View {
        Canvas { ctx, size in
            // Deterministic — a fixed seed, so the texture never shimmers between frames.
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return Double(seed % 10_000) / 10_000
            }
            let count = Int(size.width * size.height / 90)
            for _ in 0..<count {
                let x = next() * size.width
                let y = next() * size.height
                let a = 0.020 + next() * 0.045
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1)),
                    with: .color(.white.opacity(a))
                )
            }
        }
        .drawingGroup()
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

#Preview("Ember field") {
    EmberField(breathRate: 52)
        .frame(width: 393, height: 852)
        .background(Color.black)
}
