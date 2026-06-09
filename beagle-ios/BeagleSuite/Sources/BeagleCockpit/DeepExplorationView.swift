//
//  DeepExplorationView.swift
//  BeagleCockpit
//
//  Go Deeper as a first-class tab — not a disposable modal.
//  History of explorations, ability to reopen, continue, compare.
//  The intellectual engine room of the exocortex.
//

import SwiftUI
import SwiftData
import BeagleCore

struct DeepExplorationView: View {
    @State private var store = GoDeepStore()
    @State private var inputText = ""
    @State private var showActiveSession = false
    @Query(sort: \PersistedDeepSession.startedAt, order: .reverse)
    private var sessions: [PersistedDeepSession]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                    header
                    if store.isRunning || store.hasAnyResult {
                        activeSessionCard
                    }
                    if !sessions.isEmpty {
                        historySection
                    }
                    if sessions.isEmpty && !store.isRunning {
                        emptyState
                    }
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.md)
                .padding(.bottom, BeagleSpacing.jumbo)
            }

            // Always-visible input
            deepInput
        }
        .background { DeepExplorationGradient(hasHistory: !sessions.isEmpty, isRunning: store.isRunning) }
        .navigationTitle("Go Deeper")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: "triad-review") {
                    Label("Triad Review", systemImage: "person.3.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            Text("Explore any question through multiple reasoning modalities simultaneously.")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineSpacing(2)

            if !sessions.isEmpty {
                Text("\(sessions.count) exploration\(sessions.count == 1 ? "" : "s") in your history")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    // MARK: - Active Session

    private var activeSessionCard: some View {
        Button {
            showActiveSession = true
        } label: {
            GlassPanel(elevation: .floating, truth: store.isRunning ? nil : .observed) {
                VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    HStack(spacing: BeagleSpacing.xs) {
                        if store.isRunning {
                            Image(systemName: "scope")
                                .font(.system(size: 14))
                                .foregroundStyle(BeagleTheme.truthRemembered)
                                .symbolEffect(.pulse, isActive: true)
                            Text("Exploring...")
                                .font(BeagleFont.headline.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Spacer()
                            Text("\(store.completedCount)/\(store.totalCount)")
                                .font(BeagleFont.data.font)
                                .foregroundStyle(BeagleTheme.truthObserved)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(BeagleTheme.truthObserved)
                            Text("Latest exploration")
                                .font(BeagleFont.headline.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                    }

                    if let prompt = store.activeSession?.prompt {
                        Text(prompt)
                            .font(BeagleFont.subheadline.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                    }

                    if let synthesis = store.synthesis {
                        Text(synthesis)
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .lineLimit(3)
                            .lineSpacing(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showActiveSession) {
            if let prompt = store.activeSession?.prompt {
                GoDeepView(store: store, prompt: prompt)
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text("History")
                .font(BeagleFont.caption.font)
                .fontWeight(.medium)
                .foregroundStyle(BeagleTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(sessions.prefix(20)) { session in
                historyCard(session)
            }
        }
    }

    private func historyCard(_ session: PersistedDeepSession) -> some View {
        Button {
            // Reopen this exploration
            store = GoDeepStore()
            showActiveSession = true
            store.goDeeper(prompt: session.prompt)
        } label: {
            HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                Image(systemName: session.isComplete ? "checkmark.circle" : "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(session.isComplete ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.prompt)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: BeagleSpacing.sm) {
                        Text(session.startedAt, style: .relative)
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)

                        if session.modalityCount > 0 {
                            Text("\(session.modalityCount) modalities")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }

                        if let duration = session.duration {
                            Text("\(Int(duration))s")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                    }

                    if let synthesis = session.synthesisText {
                        Text(synthesis)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .lineLimit(2)
                            .lineSpacing(1)
                    }
                }

                Spacer()
            }
            .frame(minHeight: 44)
            .padding(.vertical, BeagleSpacing.xxs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: BeagleSpacing.lg) {
            Spacer(minLength: BeagleSpacing.xxxl)

            Image(systemName: "scope")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BeagleTheme.truthRemembered.opacity(0.5), BeagleTheme.truthObserved.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            Text("Go Deeper")
                .font(BeagleFont.title2.font)
                .foregroundStyle(BeagleTheme.textPrimary)

            Text("Type any question below and explore it through deep research, quantum reasoning, swarm consensus, causal graphs, and more — all at once.")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BeagleSpacing.xxl)
                .lineSpacing(2)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Input

    private var deepInput: some View {
        BeagleInputBar(
            text: $inputText,
            placeholder: "What do you want to explore deeply?",
            mode: .chat,
            isEnabled: !store.isRunning,
            onSubmit: { text in
                store = GoDeepStore()
                store.goDeeper(prompt: text)
                showActiveSession = true

                // Persist session
                let persisted = PersistedDeepSession(prompt: text, modalityCount: store.totalCount)
                modelContext.insert(persisted)
                try? modelContext.save()
            }
        )
    }
}

// MARK: - Background

private struct DeepExplorationGradient: View {
    let hasHistory: Bool
    let isRunning: Bool
    // Living mesh background removed — flat adaptive surface (redesign).
    var body: some View {
        BeagleTheme.surface0.ignoresSafeArea()
    }
}
