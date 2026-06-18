//
//  AutonomyDial.swift
//  BeagleCockpit
//
//  Three-position control: Ask / Plan / Auto, stored per profile in UserDefaults.
//
import SwiftUI
import BeagleCore

struct AutonomyDial: View {
    @Bindable var conversation: ConversationStore

    private var current: AutonomyMode {
        conversation.autonomyMode(for: conversation.discussionProfile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(AutonomyMode.allCases, id: \.rawValue) { mode in
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            conversation.setAutonomyMode(mode, for: conversation.discussionProfile)
                        }
                    } label: {
                        Text(mode.label)
                            .font(BeagleFont.caption.font)
                            .fontWeight(current == mode ? .semibold : .regular)
                            .foregroundStyle(current == mode ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                current == mode
                                    ? BeagleTheme.truthObserved.opacity(0.15)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: BeagleRadius.sm)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(BeagleTheme.surface1.opacity(0.5), in: RoundedRectangle(cornerRadius: BeagleRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.sm)
                    .strokeBorder(BeagleTheme.hairline, lineWidth: 0.5)
            )

            Text(current.subtitle)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .padding(.horizontal, 4)
        }
    }
}
