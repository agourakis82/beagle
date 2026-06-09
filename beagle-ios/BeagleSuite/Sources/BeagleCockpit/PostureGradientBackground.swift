//
//  PostureGradientBackground.swift
//  BeagleCockpit
//
//  Living, breathing MeshGradient backgrounds that reflect cluster state.
//  The command bridge background is not dead black — it pulses with the
//  health of the sovereign infrastructure.
//

import SwiftUI
import BeagleCore

// MARK: - PostureGradientBackground (CommandBridgeView)

struct PostureGradientBackground: View {
    let counts: PostureCounts
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: animatedPoints,
            colors: gradientColors
        )
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.08
        return [
            SIMD2(0,       0),       SIMD2(0.5,     0),         SIMD2(1,       0),
            SIMD2(0+d,     0.5-d),   SIMD2(0.5+d,   0.5+d),    SIMD2(1-d,     0.5+d),
            SIMD2(0,       1),       SIMD2(0.5,     1),         SIMD2(1,       1)
        ]
    }

    private var gradientColors: [Color] {
        let hasOn = counts.alwaysOn > 0
        let hasWarm = counts.warm > 0

        // Top: teal glow from always-on projects
        let teal = hasOn ? BeagleTheme.truthObserved.opacity(0.35) : Color(white: 0.06)
        let tealFade = hasOn ? BeagleTheme.truthObserved.opacity(0.12) : Color(white: 0.05)
        // Mid: gold warmth from warm projects
        let gold = hasWarm ? BeagleTheme.postureWarm.opacity(0.18) : Color(white: 0.04)
        // Bottom: deep void
        let deep = Color(red: 0.02, green: 0.03, blue: 0.07)

        return [
            teal,               tealFade,            Color(white: 0.04),
            Color(white: 0.03), gold,                Color(white: 0.03),
            deep,               deep,                Color(white: 0.02)
        ]
    }
}

// MARK: - HealthPulseGradient (ControlRoomView per-project)

struct HealthPulseGradient: View {
    let truth: TruthMode
    @State private var phase: CGFloat = 0
    @State private var pulsePhase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: animatedPoints,
                colors: gradientColors
            )

            // Radial pulse overlay for observed data
            if truth == .observed {
                RadialGradient(
                    colors: [
                        BeagleTheme.truthObserved.opacity(pulsePhase ? 0.15 : 0.04),
                        .clear
                    ],
                    center: .center,
                    startRadius: 50,
                    endRadius: 500
                )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                phase = 1
            }
            if truth == .observed {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    pulsePhase = true
                }
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.06
        return [
            SIMD2(0,     0),     SIMD2(0.5,     0),       SIMD2(1,     0),
            SIMD2(0,     0.5),   SIMD2(0.5-d,   0.5+d),   SIMD2(1,     0.5),
            SIMD2(0,     1),     SIMD2(0.5,     1),       SIMD2(1,     1)
        ]
    }

    private var gradientColors: [Color] {
        let accent: Color
        let intensity: Double

        switch truth {
        case .observed:
            accent = BeagleTheme.truthObserved
            intensity = 0.30
        case .remembered:
            accent = BeagleTheme.truthRemembered
            intensity = 0.15
        case .declared:
            accent = BeagleTheme.truthDeclared
            intensity = 0.08
        case .stale:
            accent = BeagleTheme.truthStale
            intensity = 0.04
        }

        let base = Color(white: 0.03)
        let glow = accent.opacity(intensity)
        let dimGlow = accent.opacity(intensity * 0.4)

        return [
            base,    glow,    base,
            dimGlow, base,    dimGlow,
            base,    base,    base
        ]
    }
}
