//
//  GoDeepView.swift
//  BeagleCockpit
//
//  Go Deeper — multi-modal reasoning exploration.
//
//  Design principles:
//   - All modality slots visible from launch (skeleton → thinking → resolved)
//   - Per-modality thinking text that rotates ("Building research tree...")
//   - Dramatic background shift as results arrive
//   - Synthesis card at end integrates all findings
//   - Error cards have retry affordance
//   - Share/export for research results
//   - 44pt minimum tap targets everywhere
//   - Insight-focused rendering, not data dumps
//

import SwiftUI
import BeagleCore
import Charts

struct GoDeepView: View {
    @Bindable var store: GoDeepStore
    let prompt: String
    @State private var expandedModality: GoDeepModality?
    @State private var hasLaunched = false
    @State private var promptExpanded = false
    @State private var quickTake: String?
    @State var savedToExocortex = false
    @State var roundTable = RoundTableStore()
    @State private var showRoundTable = false
    @State private var showSimulationCard = false
    @State var simulationSteerText = ""
    @State var exportedItem: ExportedDossierItem? = nil
    @State var isPreparingExport = false
    @State var copiedBibTeXFeedback = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(CognitiveStore.self) var cognitive

    internal init(store: GoDeepStore, prompt: String) {
        self.store = store
        self.prompt = prompt
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: pageSpacing) {
                    promptHeader
                        .padding(.top, BeagleSpacing.sm)

                    lensSelectorStrip

                    // Quick-take: on-device instant insight while cloud runs
                    if let quickTake, store.synthesis == nil {
                        quickTakeCard(quickTake)
                    }

                    modalityStream

                    quantumHypothesesView

                    if store.isSynthesizing || store.synthesis != nil {
                        synthesisCard
                    }

                    if showSimulationCard || store.isSimulating || (store.simulationOutput?.isEmpty == false) {
                        simulationSandboxCard
                    }

                    if showRoundTable || roundTable.isRunning || roundTable.result != nil {
                        roundTableSection
                    }
                }
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.bottom, BeagleSpacing.jumbo + 20)
            }
            .background { depthGradient }
            .navigationTitle("Modo Fundo")
            .navigationBarTitleDisplayModeIfAvailable(.inline)
            .toolbar { toolbarContent }
            .sheet(item: $exportedItem) { item in
                DossierShareSheet(url: item.url)
            }
            .task {
                guard !hasLaunched else { return }
                hasLaunched = true

                // Wire Live Activity callbacks (with active lens + live summary snippet)
                let observedStore = store
                store.onResearchStart = { [weak observedStore] runId, name, slug in
                    let initialLens = observedStore?.modalityStates.first?.modality.shortBadge ?? "Astra xhigh"
                    LiveActivityManager.shared.startResearchActivity(
                        runId: runId,
                        campaign: name,
                        slug: slug,
                        totalSteps: max(2, (observedStore?.totalCount ?? 1) + 1),
                        activeLens: initialLens
                    )
                }
                store.onResearchStateChange = { step, total, eta, activeLens, snippet, isCompleted in
                    if isCompleted {
                        LiveActivityManager.shared.endResearchActivity(finalSummary: snippet)
                    } else {
                        LiveActivityManager.shared.updateResearchActivity(
                            step: step,
                            total: total,
                            eta: eta,
                            activeLens: activeLens,
                            summarySnippet: snippet
                        )
                    }
                }
                store.onResearchEnd = { [weak observedStore] _ in
                    LiveActivityManager.shared.endResearchActivity(finalSummary: observedStore?.synthesis)
                    #if os(iOS)
                    BeagleHaptics.goDeepComplete()
                    #endif
                }

                // Single launch. If this view was presented on a store that is
                // already running or already has results (e.g. a history replay
                // that called goDeeper before presenting the sheet), don't restart
                // it — that double-start was the visible "loop"/flash.
                if !store.isRunning && !store.hasAnyResult {
                    store.goDeeper(prompt: prompt)
                }

                // Fire quick-take on-device (arrives in ~1s, before cloud)
                Task {
                    quickTake = await FoundationModelsAgent.shared.summarize(
                        "A researcher asks: \(prompt)\n\nGive a quick initial take in 2 sentences — what's the most interesting angle to explore here?",
                        instructions: "Você é o parceiro científico de Demetrios. Responda SEMPRE em português brasileiro com uma reação inicial curta, densa e específica em 2 frases, sem clichês."
                    )
                }
            }
        }
    }

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var pageHorizontalPadding: CGFloat {
        isCompactWidth ? BeagleSpacing.md : BeagleSpacing.lg
    }

    private var pageSpacing: CGFloat {
        isCompactWidth ? BeagleSpacing.md : BeagleSpacing.lg
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: leadingToolbarPlacement) {
            Button { store.cancel(); dismiss() } label: {
                Text(store.isRunning ? "Cancelar" : "Fechar")
                    .foregroundStyle(BeagleTheme.textSecondary)
            }
        }
        ToolbarItem(placement: trailingToolbarPlacement) {
            Button {
                showSimulationCard = true
                if !store.isSimulating && (store.simulationOutput ?? "").isEmpty {
                    Task { await store.runSimulation(prompt: prompt) }
                }
            } label: {
                Label("Simular", systemImage: "terminal.fill")
            }
            .tint(BeagleTheme.truthObserved)
            .disabled(store.isSimulating)
        }
        ToolbarItem(placement: trailingToolbarPlacement) {
            Button {
                showRoundTable = true
                if !roundTable.isRunning && roundTable.result == nil {
                    Task { await roundTable.debate(prompt: prompt) }
                }
            } label: {
                Label("Mesa", systemImage: "person.3.sequence.fill")
            }
            .tint(BeagleTheme.postureWarm)
            .disabled(roundTable.isRunning)
        }
        ToolbarItem(placement: trailingToolbarPlacement) {
            Toggle(isOn: $store.quantumMode) {
                Label("Quântico", systemImage: "atom")
            }
            .toggleStyle(.button)
            .tint(BeagleTheme.truthRemembered)
            .disabled(store.isRunning)
            .onChange(of: store.quantumMode) { _, _ in
                guard !store.isRunning else { return }
                store.goDeeper(prompt: prompt)
            }
        }
        ToolbarItem(placement: trailingToolbarPlacement) {
            if !store.isRunning && (store.hasAnyResult || roundTable.result != nil) {
                dossierExportMenu
            }
        }
    }

    private var leadingToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarLeading
        #endif
    }

    private var trailingToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    // MARK: - Prompt Header

    private var promptHeader: some View {
        let citationCount = currentHarvestedCitations().count
        return Button {
            withAnimation(BeagleMotion.snappy) { promptExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "scope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BeagleTheme.truthRemembered)
                    Text(store.isRunning ? "Explorando em paralelo" : "Questão Investigada")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer()
                    if citationCount > 0 {
                        Text("\(citationCount) ref\(citationCount == 1 ? "" : "s")")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.truthObserved)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(BeagleTheme.truthObserved.opacity(0.12)))
                    }
                    if !promptExpanded {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                Text(prompt)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(promptExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .animation(BeagleMotion.snappy, value: promptExpanded)
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.vertical, BeagleSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(BeagleTheme.truthRemembered.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Interactive Lens Selector Strip

    private var lensSelectorStrip: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xxs + 2) {
            HStack(spacing: BeagleSpacing.xs) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BeagleSpacing.xs) {
                        ForEach(GoDeepModality.allCases) { modality in
                            let selected = store.enabledModalities.contains(modality)
                            Button {
                                guard !store.isRunning else { return }
                                if selected && store.enabledModalities.count > 1 {
                                    store.enabledModalities.remove(modality)
                                } else {
                                    store.enabledModalities.insert(modality)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: modality.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(modality.shortBadge)
                                        .font(BeagleFont.caption2.font)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(selected ? BeagleTheme.textPrimary : BeagleTheme.textTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(selected ? modality.themeColor.opacity(0.18) : Color.white.opacity(0.04))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(selected ? modality.themeColor.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 0.75)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isRunning)
                        }
                    }
                }

                if !store.isRunning && store.hasAnyResult {
                    Button {
                        store.goDeeper(prompt: prompt)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BeagleTheme.truthObserved)
                            .frame(width: 28, height: 28)
                            .background(BeagleTheme.truthObserved.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reexecutar com lentes selecionadas")
                }
            }
        }
    }

    // MARK: - Modality Stream (all slots always visible)

    /// When synthesis arrives, compress resolved modalities to compact rows
    /// unless the user has one expanded. The journey compresses; the destination expands.
    private var journeyCompressed: Bool {
        store.synthesis != nil && expandedModality == nil
    }

    private var modalityStream: some View {
        VStack(spacing: journeyCompressed ? BeagleSpacing.xs : BeagleSpacing.md) {
            ForEach(Array(store.modalityStates.enumerated()), id: \.element.id) { index, state in
                ModalitySlot(
                    state: state,
                    isExpanded: expandedModality == state.modality,
                    isCompact: journeyCompressed && state.isResolved,
                    onTap: {
                        withAnimation(BeagleMotion.snappy) {
                            expandedModality = expandedModality == state.modality ? nil : state.modality
                        }
                    },
                    onRetry: { store.retryModality(state.modality) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                .animation(
                    BeagleMotion.bouncy.delay(Double(index) * 0.06),
                    value: hasLaunched
                )
            }
        }
        .animation(BeagleMotion.slow, value: journeyCompressed)
    }

    // MARK: - Depth Gradient Background (living MeshGradient)

    private var depthGradient: some View {
        DepthMeshGradient(progress: store.progress, completedCount: store.completedCount)
    }
}

// MARK: - Depth Mesh Gradient

/// Living MeshGradient that breathes and shifts from deep indigo → teal
/// as reasoning results arrive. Same pattern as PostureGradientBackground.
private struct DepthMeshGradient: View {
    let progress: Double
    let completedCount: Int
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: animatedPoints,
                colors: gradientColors
            )

            // Radial pulse when results arriving
            if progress > 0 && progress < 1 {
                RadialGradient(
                    colors: [
                        BeagleTheme.truthObserved.opacity(phase > 0.5 ? 0.08 : 0.02),
                        .clear
                    ],
                    center: .center,
                    startRadius: 60,
                    endRadius: 600
                )
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: completedCount)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.07
        return [
            SIMD2(0,     0),     SIMD2(0.5,   0),       SIMD2(1,     0),
            SIMD2(0+d,   0.5-d), SIMD2(0.5+d, 0.5+d),   SIMD2(1-d,   0.5+d),
            SIMD2(0,     1),     SIMD2(0.5,   1),       SIMD2(1,     1)
        ]
    }

    private var gradientColors: [Color] {
        let p = progress
        // Shift from indigo void → teal glow as results arrive
        let tealIntensity = p * 0.30
        let warmIntensity = max(0, (p - 0.5) * 0.15)
        let base = Color(red: 0.02, green: 0.03, blue: 0.07)

        return [
            BeagleTheme.truthObserved.opacity(tealIntensity),
            BeagleTheme.truthRemembered.opacity(tealIntensity * 0.3),
            Color(white: 0.04),

            Color(white: 0.03),
            BeagleTheme.postureWarm.opacity(warmIntensity),
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }
}
