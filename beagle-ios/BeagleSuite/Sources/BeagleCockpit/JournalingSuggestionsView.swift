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

                JournalingSuggestionsPicker("Capture a moment") { suggestion in
                    Task {
                        let title = suggestion.title ?? "a moment"
                        let text = "Inspired by: \(title)"
                        _ = await cognitive.captureThought(text: text, source: "journaling-suggestion")
                    }
                }
                .buttonStyle(ScalePress())
            }
        }
    }
}
#endif
