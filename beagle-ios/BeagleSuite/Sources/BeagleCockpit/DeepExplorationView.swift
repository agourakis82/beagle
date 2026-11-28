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
    @State private var searchQuery = ""
    @State private var showActiveSession = false
    @State private var isComparing = false
    @State private var selectedForCompare: [PersistedDeepSession] = []
    @State private var showComparisonSheet = false
    @State private var comparisonMarkdown = ""
    @State private var isRunningComparison = false
    @Query(sort: \PersistedDeepSession.startedAt, order: .reverse)
    private var sessions: [PersistedDeepSession]
    @Environment(\.modelContext) private var modelContext

    private var filteredSessions: [PersistedDeepSession] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(sessions.prefix(40)) }
        return sessions.filter { s in
            s.prompt.localizedCaseInsensitiveContains(q)
                || (s.synthesisText?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

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

            if isComparing {
                comparisonBottomBar
            } else {
                // Always-visible input
                deepInput
            }
        }
        .background { DeepExplorationGradient(hasHistory: !sessions.isEmpty, isRunning: store.isRunning) }
        .navigationTitle("Modo Fundo")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: BeagleSpacing.sm) {
                    if sessions.filter(\.isComplete).count >= 2 {
                        Button {
                            withAnimation(BeagleMotion.snappy) {
                                isComparing.toggle()
                                if !isComparing {
                                    selectedForCompare.removeAll()
                                }
                            }
                        } label: {
                            Label(
                                isComparing ? "Concluir" : "Comparar",
                                systemImage: isComparing ? "checkmark.circle.fill" : "arrow.left.arrow.right"
                            )
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isComparing ? BeagleTheme.truthObserved : BeagleTheme.textSecondary)
                        }
                    }

                    NavigationLink(value: "triad-review") {
                        Label("Tríade", systemImage: "person.3.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showComparisonSheet) {
            comparisonSheetView
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            Text("Explore qualquer questão simultaneamente com GPT-6.2 Astra (xhigh), GPT-Rosalind (Bio/PBPK), enxame e grafos causais.")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineSpacing(2)

            if !sessions.isEmpty {
                Text("\(sessions.count) exploraç\(sessions.count == 1 ? "ão" : "ões") no histórico")
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
            HStack {
                Text(isComparing ? "Selecione 2 explorações para comparar" : "Histórico")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(isComparing ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if isComparing {
                    Text("\(selectedForCompare.count)/2")
                        .font(BeagleFont.dataSmall.font)
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
            }

            if sessions.count >= 3 {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(BeagleTheme.textTertiary)
                    TextField("Filtrar hipóteses, fármacos ou sínteses…", text: $searchQuery)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, BeagleSpacing.md)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: BeagleRadius.md)
                        .fill(BeagleTheme.surface1.opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.md)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                )
            }

            ForEach(filteredSessions) { session in
                historyCard(session)
            }
        }
    }

    private func openSavedSession(_ session: PersistedDeepSession) {
        if session.isComplete && (session.synthesisText != nil || session.modalityResults != nil) {
            let hydrated = GoDeepStore()
            hydrated.hydrateFromPersisted(
                prompt: session.prompt,
                startedAt: session.startedAt,
                completedAt: session.completedAt,
                synthesis: session.synthesisText,
                modalityResultsJSON: session.modalityResults,
                simulationOutput: session.simulationOutput
            )
            persistResults(into: session, from: hydrated)
            store = hydrated
            showActiveSession = true
        } else {
            rerunSession(session)
        }
    }

    private func rerunSession(_ session: PersistedDeepSession) {
        let fresh = GoDeepStore()
        persistResults(into: session, from: fresh)
        store = fresh
        showActiveSession = true
        fresh.goDeeper(prompt: session.prompt)
    }

    private func toggleCompareSelection(_ session: PersistedDeepSession) {
        if let idx = selectedForCompare.firstIndex(where: { $0.persistentModelID == session.persistentModelID }) {
            selectedForCompare.remove(at: idx)
        } else if selectedForCompare.count < 2 {
            selectedForCompare.append(session)
        } else {
            selectedForCompare[1] = session
        }
    }

    private func historyCard(_ session: PersistedDeepSession) -> some View {
        let isSelected = selectedForCompare.contains(where: { $0.persistentModelID == session.persistentModelID })

        return Button {
            if isComparing {
                guard session.isComplete else { return }
                toggleCompareSelection(session)
            } else {
                openSavedSession(session)
            }
        } label: {
            HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                if isComparing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                        .padding(.top, 2)
                } else {
                    Image(systemName: session.isComplete ? "checkmark.circle.fill" : "clock")
                        .font(.system(size: 13))
                        .foregroundStyle(session.isComplete ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                        .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.prompt)
                        .font(BeagleFont.footnote.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: BeagleSpacing.xs + 2) {
                        Text(session.startedAt, style: .relative)
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)

                        if session.modalityCount > 0 {
                            Text("\(session.modalityCount) lentes")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }

                        if session.citationCount > 0 {
                            Text("\(session.citationCount) ref\(session.citationCount == 1 ? "" : "s")")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.truthObserved)
                        }

                        if session.simulationOutput != nil {
                            Text("Simulação")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.truthRemembered)
                        }

                        if let duration = session.duration, duration > 0 {
                            Text("\(Int(duration))s")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                    }

                    if let synthesis = session.synthesisText {
                        Text(synthesis)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                            .lineSpacing(1)
                    }
                }

                Spacer(minLength: 4)

                if !isComparing {
                    Menu {
                        Button {
                            openSavedSession(session)
                        } label: {
                            Label("Abrir Dossiê Salvo", systemImage: "doc.text.magnifyingglass")
                        }

                        Button {
                            rerunSession(session)
                        } label: {
                            Label("Reexecutar Lentes ao Vivo", systemImage: "arrow.clockwise")
                        }

                        Divider()

                        Button(role: .destructive) {
                            modelContext.delete(session)
                            try? modelContext.save()
                        } label: {
                            Label("Excluir do Histórico", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.md)
                    .fill(isSelected ? BeagleTheme.truthObserved.opacity(0.10) : BeagleTheme.surface1.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.md)
                    .strokeBorder(
                        isSelected ? BeagleTheme.truthObserved.opacity(0.45) : Color.white.opacity(0.06),
                        lineWidth: isSelected ? 1.0 : 0.6
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var comparisonBottomBar: some View {
        HStack(spacing: BeagleSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Comparação Longitudinal")
                    .font(BeagleFont.caption.font.weight(.semibold))
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text(selectedForCompare.count == 2 ? "Pronto para cruzar convergências e deslocamentos" : "Toque em 2 explorações concluídas")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }
            Spacer()
            Button {
                launchComparison()
            } label: {
                Label("Comparar (2)", systemImage: "sparkles")
                    .font(BeagleFont.caption.font.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(selectedForCompare.count == 2 ? BeagleTheme.truthObserved : Color.white.opacity(0.08))
                    )
                    .foregroundStyle(selectedForCompare.count == 2 ? Color.black : BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(selectedForCompare.count != 2)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.sm)
        .background(.ultraThinMaterial)
    }

    private func launchComparison() {
        guard selectedForCompare.count == 2 else { return }
        let sorted = selectedForCompare.sorted(by: { $0.startedAt < $1.startedAt })
        let a = sorted[0]
        let b = sorted[1]
        comparisonMarkdown = ""
        isRunningComparison = true
        showComparisonSheet = true

        Task {
            let final = await GoDeepStore.compareExplorations(
                firstPrompt: a.prompt,
                firstDate: a.startedAt,
                firstSynthesis: a.synthesisText ?? a.prompt,
                secondPrompt: b.prompt,
                secondDate: b.startedAt,
                secondSynthesis: b.synthesisText ?? b.prompt,
                onToken: { delta in
                    await MainActor.run {
                        comparisonMarkdown += delta
                    }
                }
            )
            await MainActor.run {
                if comparisonMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    comparisonMarkdown = final
                }
                isRunningComparison = false
            }
        }
    }

    private var comparisonSheetView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                    if selectedForCompare.count == 2 {
                        let sorted = selectedForCompare.sorted(by: { $0.startedAt < $1.startedAt })
                        GlassPanel(elevation: .flush) {
                            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                                Text("Exploração A · \(sorted[0].startedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(BeagleFont.caption2.font.weight(.semibold))
                                    .foregroundStyle(BeagleTheme.truthRemembered)
                                Text(sorted[0].prompt)
                                    .font(BeagleFont.footnote.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .lineLimit(2)
                                Divider().opacity(0.2)
                                Text("Exploração B · \(sorted[1].startedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(BeagleFont.caption2.font.weight(.semibold))
                                    .foregroundStyle(BeagleTheme.truthObserved)
                                Text(sorted[1].prompt)
                                    .font(BeagleFont.footnote.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .lineLimit(2)
                            }
                        }
                    }

                    GlassPanel(elevation: .raised, truth: isRunningComparison ? nil : .observed) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                            HStack {
                                Image(systemName: "arrow.left.arrow.right.circle.fill")
                                    .foregroundStyle(BeagleTheme.truthObserved)
                                Text("Análise Longitudinal · Astra")
                                    .font(BeagleFont.headline.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                Spacer()
                                if isRunningComparison {
                                    ProgressView().controlSize(.small)
                                }
                            }

                            if comparisonMarkdown.isEmpty && isRunningComparison {
                                Text("Cruzando invariantes, mudanças de hipótese e novas evidências entre A e B…")
                                    .font(BeagleFont.footnote.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                    .italic()
                            } else {
                                Text(LocalizedStringKey(comparisonMarkdown))
                                    .font(BeagleFont.body.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .textSelection(.enabled)
                                    .lineSpacing(3)
                            }
                        }
                    }
                }
                .padding(BeagleSpacing.lg)
            }
            .background { BeagleTheme.surface0.ignoresSafeArea() }
            .navigationTitle("Comparar Explorações")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { showComparisonSheet = false }
                }
                if !comparisonMarkdown.isEmpty && !isRunningComparison {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: comparisonMarkdown, subject: Text("Comparação Modo Fundo")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
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

            Text("Modo Fundo")
                .font(BeagleFont.title2.font)
                .foregroundStyle(BeagleTheme.textPrimary)

            Text("Digite qualquer questão científica, clínica ou arquitetural abaixo para disparar GPT-6.2 Astra (xhigh), GPT-Rosalind (Bio/PBPK), consenso de enxame e grafos causais em paralelo.")
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
            placeholder: "O que você quer explorar a fundo?",
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
            session.citationsJSON = payload.citationsJSON
            session.simulationOutput = payload.simulationOutput
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
