//
//  JournalingSuggestionsView.swift
//  BeagleCockpit
//
//  Bridges Apple Journaling Suggestions into the exocortex thought stream.
//  When the user picks a suggestion, it becomes a captured thought.
//

import SwiftUI
import BeagleCore

#if canImport(JournalingSuggestions)
import JournalingSuggestions

struct JournalingSuggestionsCard: View {
    @Environment(CognitiveStore.self) private var cognitive

    var body: some View {
        GlassPanel(elevation: .floating, truth: .declared) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 12))
                        .foregroundStyle(BeagleTheme.truthDeclared)
                    Text("Journaling Suggestions")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                JournalingSuggestionsPicker { suggestion in
                    Task {
                        let text = "Inspired by: \(suggestion.title ?? "a moment")"
                        _ = await cognitive.captureThought(text: text, source: "journaling-suggestion")
                    }
                } label: {
                    HStack(spacing: BeagleSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(BeagleTheme.truthDeclared.opacity(0.08))
                                .frame(width: 36, height: 36)
                            Image(systemName: "sparkle")
                                .font(.system(size: 15))
                                .foregroundStyle(BeagleTheme.truthDeclared)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Capture a moment")
                                .font(BeagleFont.subheadline.font)
                                .fontWeight(.medium)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Text("Apple suggests moments worth remembering")
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                .buttonStyle(ScalePress())
            }
        }
    }
}
#endif
