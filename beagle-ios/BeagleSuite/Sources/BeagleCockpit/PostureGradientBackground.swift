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
    // Living mesh background removed — flat adaptive surface (redesign).
    var body: some View {
        BeagleTheme.surface0.ignoresSafeArea()
    }
}

// MARK: - HealthPulseGradient (ControlRoomView per-project)

struct HealthPulseGradient: View {
    let truth: TruthMode
    // Living mesh background removed — flat adaptive surface (redesign).
    var body: some View {
        BeagleTheme.surface0.ignoresSafeArea()
    }
}
