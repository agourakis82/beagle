//
//  PresencePill.swift
//  BeagleCockpit
//
//  Small, reusable provenance/status pill used across Beagle, Ideas, and
//  Command Room to make device-vs-cluster state legible without turning the
//  app into a debug console.
//

import SwiftUI
import BeagleCore

struct PresencePill: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(BeagleFont.caption2.font)
            .foregroundStyle(tint.opacity(0.9))
            .padding(.horizontal, BeagleSpacing.xs + 2)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(tint.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.16), lineWidth: 1)
            )
    }
}
