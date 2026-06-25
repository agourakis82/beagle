//
//  CompanionPresence.swift
//  BeagleCockpit — Companion chat
//
//  The continuous, emotionally-available presence (Gaggioli: social level + "alive vs
//  dead" = continuous presence, not a transactional utility). A soft warm ember-field
//  that breathes slowly — it fills what was a dead black void with quiet life. Subtle and
//  sophisticated, never a cartoon orb (research anti-pattern: over-cute). It carries a
//  faint hue of the current state (calm/tense) without morphing per-token (refuted pattern).
//

import SwiftUI
import BeagleCore

struct CompanionPresence: View {
    /// Optional state tint: "FLOW" (warm-calm), "STRESS" (cooler/dimmer), else neutral.
    var state: String?

    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ember: Color {
        switch state {
        case "FLOW":   return Color(red: 235/255, green: 165/255, blue: 110/255) // warm amber
        case "STRESS": return Color(red: 190/255, green: 150/255, blue: 175/255) // muted rose
        default:       return Color(red: 222/255, green: 158/255, blue: 120/255) // ember
        }
    }

    var body: some View {
        ZStack {
            // Outer aura — wide, very soft, the breath.
            Circle()
                .fill(RadialGradient(
                    colors: [ember.opacity(0.34), ember.opacity(0.08), .clear],
                    center: .center, startRadius: 2, endRadius: 130))
                .frame(width: 260, height: 260)
                .scaleEffect(breathe ? 1.06 : 0.94)
                .opacity(breathe ? 0.95 : 0.62)

            // Inner glow — the quiet core.
            Circle()
                .fill(RadialGradient(
                    colors: [ember.opacity(0.55), ember.opacity(0.12), .clear],
                    center: .center, startRadius: 0, endRadius: 46))
                .frame(width: 92, height: 92)
                .blur(radius: 6)
                .scaleEffect(breathe ? 1.05 : 0.95)
        }
        .blendMode(.screen)               // adds light to the dark surface — warmth, not a sticker
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { breathe = true; return }
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .accessibilityHidden(true)
    }
}
