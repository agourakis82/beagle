//
//  DailySynthesisView.swift
//  BeagleCockpit
//
//  "Síntese Matinal Diária" — cruza automaticamente Fisioma (Apple Watch / HealthKit),
//  Clima Espacial ao vivo (NOAA SWPC Kp/Dst/Bz), Plantões & Agenda (EventKit 48h),
//  Lembretes pendentes, Capturas de hoje e Memória GraphRAG++ via GPT-6.2 Astra.
//

import SwiftUI
import BeagleCore
#if canImport(WidgetKit)
import WidgetKit
#endif

struct DailySynthesisView: View {
    let captureLines: [String]
    var physioSummary: PhysioSummary? = nil
    var sky: SpaceWeatherStore.Snapshot? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(CognitiveStore.self) private var cognitive

    @State private var contextSnapshot: DailyBriefingBuilder.ContextSnapshot?
    @State private var streamedText = ""
    @State private var isGatheringContext = false
    @State private var isStreaming = false
    @State private var hasStarted = false
    @State private var streamError: String?
    @State private var savedToExocortex = false
    @State private var loadedFromCache = false
    @State private var sendingToGrokBot = false
    @State private var sentToGrokBot = false
    @State private var grokBotError: String?
    @State private var voz = CompanionVoice()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                    header
                    telemetryPillsRow
                    synthesisContentSection
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.sm)
                .padding(.bottom, BeagleSpacing.jumbo)
            }
            .background { BeagleTheme.surface0.ignoresSafeArea() }
            .navigationTitle("Síntese Matinal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: closePlacement) {
                    Button("Fechar") {
                        voz.parar()
                        dismiss()
                    }
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .accessibilityIdentifier("dailySynthesis.closeButton")
                }
                ToolbarItem(placement: trailingPlacement) {
                    HStack(spacing: BeagleSpacing.sm) {
                        if !streamedText.isEmpty && !isStreaming {
                            Button {
                                if voz.estaAtivo {
                                    voz.parar()
                                } else {
                                    Task { await voz.falar(streamedText, id: "daily-synthesis") }
                                }
                            } label: {
                                Image(systemName: voz.estaAtivo ? "stop.circle.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(voz.estaAtivo ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                            }
                            .accessibilityLabel(voz.estaAtivo ? "Parar leitura da síntese" : "Ouvir síntese matinal")
                        }
                        if !isStreaming && !isGatheringContext {
                            Button {
                                voz.parar()
                                Task { await runSynthesis(forceRefresh: true) }
                            } label: {
                                Label("Regerar", systemImage: "arrow.clockwise")
                            }
                            .tint(BeagleTheme.truthObserved)
                        }
                        if !streamedText.isEmpty && !isStreaming {
                            ShareLink(
                                item: streamedText,
                                subject: Text("Síntese Matinal Beagle")
                            ) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14))
                                    .foregroundStyle(BeagleTheme.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            voz.parar()
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await runSynthesis(forceRefresh: false)
        }
    }

    private var closePlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarLeading
        #endif
    }

    private var trailingPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BeagleTheme.postureWarm)
                Text("Briefing Integrado · GPT-6.2 Astra")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                if loadedFromCache && !isStreaming {
                    PresencePill(
                        label: "Hoje (cache)",
                        systemImage: "checkmark.seal.fill",
                        tint: BeagleTheme.truthObserved
                    )
                } else {
                    PresencePill(
                        label: "\(captureLines.count) captura\(captureLines.count == 1 ? "" : "s")",
                        systemImage: "tray.full",
                        tint: BeagleTheme.truthDeclared
                    )
                }
            }

            Text("Fisioma (Sono/HRV) × Clima Espacial (Kp/Dst) × Plantões & Agenda × Memória Exocórtex.")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineSpacing(2)
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

    // MARK: - Live Telemetry Pills

    private var telemetryPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                if let hrv = contextSnapshot?.hrvMs ?? physioSummary?.hrvMs {
                    PresencePill(
                        label: String(format: "HRV %.0f ms", hrv),
                        systemImage: "waveform.path.ecg",
                        tint: BeagleTheme.truthObserved
                    )
                }
                if let sleep = contextSnapshot?.sleepHours ?? physioSummary?.sleepHours {
                    PresencePill(
                        label: String(format: "Sono %.1fh", sleep),
                        systemImage: "bed.double.fill",
                        tint: BeagleTheme.truthRemembered
                    )
                }
                if let kp = contextSnapshot?.kpIndex ?? sky?.kp {
                    let storm = kp >= 5
                    PresencePill(
                        label: String(format: "Kp %.1f", kp),
                        systemImage: storm ? "sparkles" : "globe.americas.fill",
                        tint: storm ? BeagleTheme.auroraViolet : BeagleTheme.truthObserved
                    )
                }
                PresencePill(
                    label: "Agenda 48h",
                    systemImage: "calendar",
                    tint: BeagleTheme.postureWarm
                )
            }
        }
    }

    // MARK: - Synthesis Content (Live Stream -> Structured 4-Card Layout)

    @ViewBuilder
    private var synthesisContentSection: some View {
        let parsedSections = (!isStreaming && !isGatheringContext)
            ? DailyBriefingBuilder.parseSections(streamedText)
            : []

        if parsedSections.count >= 2 {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                ForEach(parsedSections) { section in
                    GlassPanel(elevation: .raised, truth: .observed) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.xs + 2) {
                            HStack(spacing: BeagleSpacing.xs) {
                                Image(systemName: section.systemImage)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(BeagleTheme.truthObserved)
                                Text(section.title)
                                    .font(BeagleFont.subheadline.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                Spacer()
                            }

                            Text(LocalizedStringKey(section.body))
                                .font(BeagleFont.body.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .textSelection(.enabled)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                synthesisFooterActions
            }
            .sensoryFeedback(.success, trigger: !isStreaming && !streamedText.isEmpty)
        } else {
            synthesisPanel
        }
    }

    private var synthesisFooterActions: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BeagleSpacing.sm) {
                    Button {
                        if voz.estaAtivo {
                            voz.parar()
                        } else {
                            Task { await voz.falar(streamedText, id: "daily-synthesis-footer") }
                        }
                    } label: {
                        HStack(spacing: BeagleSpacing.xxs + 1) {
                            Image(systemName: voz.estaAtivo ? "stop.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 12))
                            Text(voz.estaAtivo ? "Parar voz" : "Ouvir síntese")
                                .font(BeagleFont.caption.font)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(voz.estaAtivo ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                        .padding(.horizontal, BeagleSpacing.sm + 2)
                        .padding(.vertical, BeagleSpacing.xs)
                        .background(
                            Capsule()
                                .fill((voz.estaAtivo ? BeagleTheme.postureWarm : BeagleTheme.truthObserved).opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)

                    saveMemoryButton

                    if GrokBotCredentials.hasConfiguredRoutine {
                        sendToGrokBotButton
                    }

                    GoDeepButton(
                        prompt: "Aprofundar as hipóteses e prioridades desta Síntese Matinal:\n\n\(String(streamedText.prefix(1200)))",
                        compact: true
                    )
                }
            }
            .padding(.top, BeagleSpacing.xxs)

            if let grokBotError {
                Text(grokBotError)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.stateError)
            }
        }
    }

    private var saveMemoryButton: some View {
        Button {
            Task {
                savedToExocortex = true
                _ = await cognitive.captureThought(
                    text: streamedText,
                    source: "daily-synthesis-astra"
                )
            }
        } label: {
            HStack(spacing: BeagleSpacing.xxs + 1) {
                Image(systemName: savedToExocortex ? "checkmark.circle.fill" : "brain")
                    .font(.system(size: 12))
                Text(savedToExocortex ? "Salvo" : "Salvar na memória")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
            }
            .foregroundStyle(savedToExocortex ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered)
            .padding(.horizontal, BeagleSpacing.sm + 2)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                Capsule()
                    .fill((savedToExocortex ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered).opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(savedToExocortex)
        .sensoryFeedback(.success, trigger: savedToExocortex)
    }

    private var sendToGrokBotButton: some View {
        Button {
            Task { await dispatchSynthesisToGrokBot() }
        } label: {
            HStack(spacing: BeagleSpacing.xxs + 1) {
                if sendingToGrokBot {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: sentToGrokBot ? "checkmark.bolt.fill" : "bolt.horizontal.circle.fill")
                        .font(.system(size: 12))
                }
                Text(sentToGrokBot ? "Enviado ao Grok Bot" : "Enviar ao Grok Bot")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
            }
            .foregroundStyle(sentToGrokBot ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
            .padding(.horizontal, BeagleSpacing.sm + 2)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                Capsule()
                    .fill((sentToGrokBot ? BeagleTheme.truthObserved : BeagleTheme.postureWarm).opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .disabled(sendingToGrokBot || sentToGrokBot)
        .sensoryFeedback(.success, trigger: sentToGrokBot)
    }

    // MARK: - Synthesis panel

    private var synthesisPanel: some View {
        GlassPanel(elevation: .raised, truth: (isStreaming || isGatheringContext) ? nil : .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BeagleTheme.truthObserved, BeagleTheme.truthRemembered],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    Text("Síntese do Dia")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    if isGatheringContext || isStreaming {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BeagleTheme.truthObserved)
                    } else if !streamedText.isEmpty {
                        TruthBadge(.observed, compact: true)
                    }
                }

                if isGatheringContext && streamedText.isEmpty {
                    Text("Lendo sinais do Apple Watch, clima geomagnético NOAA, plantões na Agenda e memória GraphRAG++...")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .italic()
                } else if isStreaming && streamedText.isEmpty {
                    Text("GPT-6.2 Astra calibrando o pulso autonômico, agenda e frentes científicas de hoje...")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .italic()
                }

                if !streamedText.isEmpty {
                    Text(LocalizedStringKey(streamedText))
                        .font(BeagleFont.body.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let streamError, streamedText.isEmpty {
                    Text(streamError)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.stateError)
                }

                if !isStreaming && !isGatheringContext && !streamedText.isEmpty {
                    synthesisFooterActions
                }
            }
        }
        .sensoryFeedback(.success, trigger: !isStreaming && !streamedText.isEmpty)
    }

    // MARK: - Orchestration

    private func dispatchSynthesisToGrokBot() async {
        guard !streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sendingToGrokBot = true
        grokBotError = nil
        let slug = cognitive.activeProjectSlug ?? "sounio"
        let result = await GrokBotBridgeClient.shared.dispatch(
            task: "Organize as prioridades do dia, pendências e eventuais pesquisas de apoio a partir da Síntese Matinal do Beagle:\n\n\(String(streamedText.prefix(2_500)))",
            priority: "normal",
            contextSummary: "Enviado diretamente pela Síntese Matinal do Beagle Cockpit.",
            projectSlug: slug,
            physioSummary: physioSummary,
            spaceWeather: sky
        )
        sendingToGrokBot = false
        if result.ok {
            sentToGrokBot = true
        } else {
            grokBotError = result.errorMessage ?? "Falha ao enviar para o Grok Bot."
        }
    }

    private func runSynthesis(forceRefresh: Bool) async {
        let slug = cognitive.activeProjectSlug ?? "sounio"
        streamError = nil
        savedToExocortex = false
        sentToGrokBot = false
        grokBotError = nil

        isGatheringContext = true
        let ctx = await DailyBriefingBuilder.gatherLiveContext(
            captureLines: captureLines,
            physioSummary: physioSummary,
            sky: sky,
            projectSlug: slug
        )
        contextSnapshot = ctx
        isGatheringContext = false

        if !forceRefresh, let cached = DailyBriefingBuilder.cachedTodaySynthesis() {
            streamedText = cached
            loadedFromCache = true
            return
        }

        loadedFromCache = false
        streamedText = ""
        isStreaming = true

        do {
            let final = try await DailyBriefingBuilder.generateMorningSynthesis(
                context: ctx,
                projectSlug: slug,
                flowState: cognitive.flowState,
                onToken: { delta in
                    await MainActor.run {
                        streamedText += delta
                    }
                }
            )
            if streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                streamedText = final
            }
            DailyBriefingBuilder.saveTodaySynthesis(streamedText, context: ctx)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: "MorningBriefingWidget")
            #endif
        } catch {
            if streamedText.isEmpty {
                streamError = "Não foi possível concluir a síntese matinal: \(error.localizedDescription)"
            }
        }

        isStreaming = false
    }
}
