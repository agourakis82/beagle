//
//  EvidenceTag.swift
//  BeagleCockpit
//
import SwiftUI
import BeagleCore

struct EvidenceTag: View {
    let item: EvidenceItem

    var body: some View {
        HStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 11))
            Text(item.label)
                .font(BeagleFont.caption2.font)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }

    private var icon: String {
        switch item.confidence {
        case .cited:       return "✓"
        case .inferred:    return "◯"
        case .unverified:  return "?"
        case .conflict:    return "⚠"
        }
    }

    private var color: Color {
        switch item.confidence {
        case .cited:       return BeagleTheme.stateReady
        case .inferred:    return BeagleTheme.truthObserved
        case .unverified:  return BeagleTheme.textTertiary
        case .conflict:    return BeagleTheme.stateError
        }
    }
}
