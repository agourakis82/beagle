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
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            Text("Explore any question through multiple reasoning modalities simultaneously.")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.companionInk.opacity(0.6))
                .lineSpacing(2)

            if !sessions.isEmpty {
                Text("\(sessions.count) exploration\(sessions.count == 1 ? "" : "s") in your history")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))
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
                                .foregroundStyle(BeagleTheme.companionInk)
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
                                .foregroundStyle(BeagleTheme.companionInk)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))
                        }
                    }

                    if let prompt = store.activeSession?.prompt {
                        Text(prompt)
                            .font(BeagleFont.subheadline.font)
                            .foregroundStyle(BeagleTheme.companionInk.opacity(0.6))
                            .lineLimit(2)
                    }

                    if let synthesis = store.synthesis {
                        Text(synthesis)
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))
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
                .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(sessions.prefix(20)) { session in
                historyCard(session)
            }
        }
    }

    private func historyCard(_ session: PersistedDeepSession) -> some View {
        Button {
            // Reopen this exploration; refresh its persisted results on completion.
            store = GoDeepStore()
            persistResults(into: session, from: store)
            showActiveSession = true
            store.goDeeper(prompt: session.prompt)
        } label: {
            HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                Image(systemName: session.isComplete ? "checkmark.circle" : "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(session.isComplete ? BeagleTheme.truthObserved : BeagleTheme.companionInk.opacity(0.42))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.prompt)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.companionInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: BeagleSpacing.sm) {
                        Text(session.startedAt, style: .relative)
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))

                        if session.modalityCount > 0 {
                            Text("\(session.modalityCount) modalities")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))
                        }

                        if let duration = session.duration {
                            Text("\(Int(duration))s")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))
                        }
                    }

                    if let synthesis = session.synthesisText {
                        Text(synthesis)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))
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
                .foregroundStyle(BeagleTheme.companionInk)

            Text("Type any question below and explore it through deep research, quantum reasoning, swarm consensus, causal graphs, and more — all at once.")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))
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

                // Persist the session shell now; fill in results on completion.
                let persisted = PersistedDeepSession(prompt: text, modalityCount: store.totalCount)
                modelContext.insert(persisted)
                try? modelContext.save()
                persistResults(into: persisted, from: store)

                store.goDeeper(prompt: text)
                showActiveSession = true
            }
        )
    }

    // MARK: - Persistence

    /// Wire the store so the full session result (synthesis + per-modality
    /// summaries) is written back into the SwiftData row when it completes.
    private func persistResults(into session: PersistedDeepSession, from store: GoDeepStore) {
        store.onSessionComplete = { payload in
            session.synthesisText = payload.synthesis
            session.modalityResults = payload.modalityResultsJSON
            session.modalityCount = payload.modalityCount
            session.completedAt = payload.completedAt
            try? modelContext.save()
        }
    }
}

// MARK: - Background

private struct DeepExplorationGradient: View {
    let hasHistory: Bool
    let isRunning: Bool
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
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.06
        return [
            SIMD2(0,     0),     SIMD2(0.5,   0),       SIMD2(1,     0),
            SIMD2(0+d,   0.5-d), SIMD2(0.5+d, 0.5+d),   SIMD2(1-d,   0.5+d),
            SIMD2(0,     1),     SIMD2(0.5,   1),       SIMD2(1,     1)
        ]
    }

    private var gradientColors: [Color] {
        let base = Color(red: 0.02, green: 0.03, blue: 0.06)
        return [
            BeagleTheme.truthRemembered.opacity(isRunning ? 0.15 : (hasHistory ? 0.06 : 0.0)),
            Color(white: 0.04),
            Color(white: 0.03),

            BeagleTheme.truthObserved.opacity(isRunning ? 0.08 : 0.0),
            base,
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }
}
