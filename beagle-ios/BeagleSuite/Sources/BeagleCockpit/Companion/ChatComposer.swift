//
//  ChatComposer.swift
//  BeagleCockpit — Companion chat
//
//  The floating input bar — the ONLY Liquid Glass element in the chat (the navigation/
//  chrome layer floats above flat content). Multiline grow, attach (→ multimodal),
//  mic (→ voice), send. See docs/design/2026-06-24-companion-design-system.md (§2, §4).
//

import SwiftUI
import BeagleCore

struct ChatComposer: View {
    @Binding var text: String
    var isStreaming: Bool
    var onSend: () -> Void
    var onAttach: () -> Void
    var onVoice: () -> Void

    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty && !isStreaming }

    var body: some View {
        HStack(alignment: .bottom, spacing: BeagleSpacing.xs) {
            Button(action: onAttach) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Anexar")

            TextField("Fala comigo…", text: $text, axis: .vertical)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.companionInk)
                .tint(BeagleTheme.truthObserved)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.vertical, 4)

            Group {
                if canSend {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                    .accessibilityLabel("Enviar")
                } else {
                    Button(action: onVoice) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel("Voz")
                }
            }
            .buttonStyle(.plain)
            .animation(.snappy(duration: 0.2), value: canSend)
        }
        .padding(.vertical, BeagleSpacing.xs)
        .padding(.horizontal, BeagleSpacing.sm)
        .glassEffect(.regular, in: Capsule())
    }
}
