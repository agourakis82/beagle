//
//  ChatScreen+LiveVoice.swift
//  BeagleCockpit — Companion chat live voice UI, GPT-Live 1.1 & Walkie-Talkie state machine
//

import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

extension ChatScreen {

    // MARK: - Top bar voice control

    @ViewBuilder
    var voiceTopBarControl: some View {
        HStack(spacing: 6) {
            // Botão direto de 1 toque para Sessão de Voz Contínua (Walkie-Talkie Mãos-Livres + Dynamic Island)
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
                Task {
                    if liveVoice.isActive {
                        endLiveVoiceSession()
                    } else {
                        await startLiveVoiceSession()
                    }
                }
            } label: {
                Image(systemName: liveVoice.isActive ? "dot.radiowaves.left.and.right" : "waveform.badge.mic")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        liveVoice.isActive
                            ? liveVoiceAccent(for: liveVoice.phase)
                            : BeagleTheme.companionInk.opacity(0.88)
                    )
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().strokeBorder(
                            liveVoice.isActive
                                ? liveVoiceAccent(for: liveVoice.phase).opacity(0.55)
                                : Color.white.opacity(0.12),
                            lineWidth: liveVoice.isActive ? 1.0 : 0.5
                        )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liveVoice.isActive ? "Encerrar sessão de voz contínua" : "Iniciar sessão de voz contínua mãos-livres")

            if voz.estaAtivo && !liveVoice.isActive {
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                    voz.parar()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(voz.buscando ? "voz…" : "parar")
                            .font(BeagleFont.caption2.font.weight(.semibold))
                    }
                    .foregroundStyle(MessageBubble.marcaAmbar)
                    .frame(height: 40)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(MessageBubble.marcaAmbar.opacity(0.45), lineWidth: 0.75))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Parar leitura em voz")
            } else if !liveVoice.isActive {
                Menu {
                    Button {
                        Task { await startLiveVoiceSession() }
                    } label: {
                        Label("Iniciar Conversa de Voz Contínua", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Picker("Modo Mãos-Livres", selection: $liveTransportRaw) {
                        ForEach(CompanionLiveSessionTransportMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    Divider()
                    Picker("Resposta em Voz", selection: $autoSpeakRaw) {
                        ForEach(CompanionAutoSpeakMode.allCases) { mode in
                            Label(
                                mode.label,
                                systemImage: mode == .always
                                    ? "waveform"
                                    : (mode == .whenSpoken ? "speaker.wave.2" : "speaker.slash")
                            )
                            .tag(mode.rawValue)
                        }
                    }
                } label: {
                    Image(
                        systemName: autoSpeakRaw == CompanionAutoSpeakMode.always.rawValue
                            ? "waveform"
                            : (autoSpeakRaw == CompanionAutoSpeakMode.manual.rawValue ? "speaker.slash" : "speaker.wave.2")
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        autoSpeakRaw == CompanionAutoSpeakMode.always.rawValue
                            ? BeagleTheme.truthObserved
                            : BeagleTheme.companionInk.opacity(0.88)
                    )
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modo de resposta em voz")
            }
        }
    }

    // MARK: - Barra Flutuante da Sessão Contínua Mãos-Livres (Walkie-Talkie)

    private func liveVoiceAccent(for phase: CompanionLiveVoicePhase) -> Color {
        switch phase {
        case .listening: return BeagleTheme.truthObserved
        case .thinking:  return BeagleTheme.truthRemembered
        case .speaking:  return MessageBubble.marcaAmbar
        case .paused:    return BeagleTheme.textSecondary
        case .ended:     return BeagleTheme.textTertiary
        }
    }

    private var liveVoiceDisplayedLine: String {
        if !usingGPTLiveFullDuplex && liveVoice.phase == .listening {
            let partial = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty { return partial }
        } else if liveVoice.phase == .thinking || gptLive.activeDelegationCount > 0 {
            if let note = store.presenceNote, !note.isEmpty { return note }
        }
        return liveVoice.liveLine.isEmpty ? liveVoice.phase.defaultLinePtBR : liveVoice.liveLine
    }

    var liveVoiceFloatingBar: some View {
        let tint = liveVoiceAccent(for: liveVoice.phase)
        return HStack(spacing: 10) {
            Image(systemName: liveVoice.phase.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: liveVoice.phase == .listening || liveVoice.phase == .speaking)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(usingGPTLiveFullDuplex ? "GPT-Live 1.1" : "Voz Contínua") · \(liveVoice.phase.titlePtBR)")
                        .font(BeagleFont.caption.font.weight(.semibold))
                        .foregroundStyle(BeagleTheme.companionInk)
                    if gptLive.activeDelegationCount > 0 {
                        Text("MoE")
                            .font(BeagleFont.caption2.font.monospaced())
                            .foregroundStyle(BeagleTheme.truthRemembered)
                    }
                    if liveVoice.turnCount > 0 {
                        Text("T\(liveVoice.turnCount)")
                            .font(BeagleFont.caption2.font.monospaced())
                            .foregroundStyle(tint)
                    }
                }
                Text(liveVoiceDisplayedLine)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if liveVoice.phase == .speaking {
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                    handleLiveVoiceCommand(.interruptAndListen)
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(BeagleTheme.truthObserved)
                        .frame(width: 32, height: 32)
                        .background(BeagleTheme.truthObserved.opacity(0.18), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cortar resposta e falar agora")
            }

            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
                handleLiveVoiceCommand(.togglePause)
            } label: {
                Image(systemName: liveVoice.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BeagleTheme.companionInk)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liveVoice.phase == .paused ? "Retomar voz contínua" : "Pausar voz contínua")

            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
                endLiveVoiceSession()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BeagleTheme.stateError)
                    .frame(width: 32, height: 32)
                    .background(BeagleTheme.stateError.opacity(0.18), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Encerrar voz contínua")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.42), lineWidth: 0.85))
        .padding(.horizontal, BeagleSpacing.md)
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
    }

    // MARK: - Voice turn completion & callbacks

    func handleStreamingFinished() {
        if liveVoice.isActive {
            guard !usingGPTLiveFullDuplex else { return }
            turnoVeioDeVoz = false
            liveVoiceLoopTask?.cancel()
            liveVoiceLoopTask = Task { @MainActor in
                guard liveVoice.isActive,
                      liveVoice.phase != .paused,
                      liveVoice.phase != .ended else { return }

                if let ultima = store.messages.last,
                   ultima.role == .assistant,
                   !ultima.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    liveVoice.voiceLabel = depth.label
                    liveVoice.onAssistantSpeaking(ultima.content)
                    LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
                    await voz.falar(ultima.content, id: ultima.id.uuidString)
                }

                guard !Task.isCancelled,
                      liveVoice.isActive,
                      liveVoice.phase != .paused,
                      liveVoice.phase != .ended else { return }

                // Compasso acústico de 320ms para dissipar reverberação do alto-falante antes de rearmar o STT
                try? await Task.sleep(for: .milliseconds(320))

                guard !Task.isCancelled,
                      liveVoice.isActive,
                      liveVoice.phase != .paused,
                      liveVoice.phase != .ended else { return }

                if liveVoice.onSpeechFinishedRearm() {
                    lastForwardedTranscriptLength = 0
                    LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
                    await armNextLiveVoiceTurn()
                }
            }
            return
        }

        // Fim do turno avulso: se ele FALOU (modo padrão) ou ativou Mãos-livres ("always"), ouve de volta.
        let deveFalar = (autoSpeakRaw == CompanionAutoSpeakMode.always.rawValue)
            || (autoSpeakRaw == CompanionAutoSpeakMode.whenSpoken.rawValue && turnoVeioDeVoz)
        turnoVeioDeVoz = false
        guard deveFalar,
              let ultima = store.messages.last,
              ultima.role == .assistant,
              !ultima.content.isEmpty else { return }
        Task { await voz.falar(ultima.content, id: ultima.id.uuidString) }
    }

    func bindVoiceCallbacks() {
        voice.onCommit = { falado in
            handleVoiceCommittedUtterance(falado)
        }
        voice.onEmptyFinish = {
            guard liveVoice.isActive, liveVoice.phase == .listening else { return }
            let shouldRearm = liveVoice.onEmptySilenceWindow(maxStrikes: 2)
            lastForwardedTranscriptLength = 0
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            guard shouldRearm else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard liveVoice.isActive, liveVoice.phase == .listening else { return }
                await armNextLiveVoiceTurn()
            }
        }
    }

    func handleVoiceCommittedUtterance(_ falado: String) {
        store.sinalDeVozDoTurno = voice.sinalDoUltimoTurno
        turnoVeioDeVoz = true
        lastForwardedTranscriptLength = 0
        if liveVoice.isActive {
            liveVoice.voiceLabel = depth.label
            liveVoice.onUserUtteranceCommitted(falado)
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
        }
        sendText(falado)
    }

    // MARK: - Live voice session lifecycle

    func startLiveVoiceSession() async {
        liveVoiceLoopTask?.cancel()
        liveVoiceLoopTask = nil
        if usingGPTLiveFullDuplex || gptLive.isActive {
            await gptLive.stop()
        }
        usingGPTLiveFullDuplex = false
        voz.parar()
        voice.stopQuietly()
        bindVoiceCallbacks()

        lastForwardedTranscriptLength = 0

        let transportMode = CompanionLiveSessionTransportMode(rawValue: liveTransportRaw) ?? .auto
        let wantsGPTLive: Bool = {
            switch transportMode {
            case .gptLiveFullDuplex:
                return true
            case .auto:
                return DirectBrainCredentials.hasOpenAI && NetworkMonitor.shared.isOnline
            case .walkieTalkieTurns:
                return false
            }
        }()

        if wantsGPTLive {
            let rawTimbre = UserDefaults.standard.string(forKey: CompanionVoice.openAIVoiceKey) ?? "marin"
            let normalizedTimbre = CompanionVoice.normalizedLiveVoice(rawTimbre)
            let voiceBadge = "GPT-Live · \(normalizedTimbre.capitalized)"

            gptLive.onTranscriptBubbleUpdate = { role, bubbleId, text, isFinal, tools in
                store.upsertGPTLiveBubble(
                    id: bubbleId,
                    role: role,
                    text: text,
                    isFinal: isFinal,
                    executedTools: tools
                )
            }
            gptLive.onStateChanged = { phase, turns, line in
                guard liveVoice.isActive, usingGPTLiveFullDuplex else { return }
                liveVoice.phase = phase
                liveVoice.turnCount = max(liveVoice.turnCount, turns)
                liveVoice.liveLine = line
                LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            }
            gptLive.onDelegateToBackend = { delegationCtx in
                let useMoE = (depth == .moe || depth == .fundo)
                return await store.executeGPTLiveDelegation(delegationCtx, useMoE: useMoE)
            }
            store.onVoiceResearchStart = { runId, campaign, slug, totalSteps, activeLens in
                LiveActivityManager.shared.startResearchActivity(
                    runId: runId,
                    campaign: campaign,
                    slug: slug,
                    totalSteps: totalSteps,
                    activeLens: activeLens
                )
            }
            store.onVoiceResearchUpdate = { step, total, eta, activeLens, snippet, isCompleted in
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
            store.onTriggerAsyncVoiceFollowup = { spokenSummary, backgroundFacts, tools in
                await gptLive.pushAsyncFollowup(
                    spokenSummary: spokenSummary,
                    backgroundFacts: backgroundFacts,
                    executedTools: tools
                )
            }
            gptLive.onStartupFallbackNeeded = { _ in
                guard liveVoice.isActive, usingGPTLiveFullDuplex else { return }
                usingGPTLiveFullDuplex = false
                Task { @MainActor in
                    await gptLive.stop()
                    guard liveVoice.isActive else { return }
                    liveVoice.voiceLabel = depth.label
                    liveVoice.phase = .listening
                    liveVoice.liveLine = "Rede oscilou — retomando Walkie-Talkie local…"
                    LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
                    await armNextLiveVoiceTurn()
                }
            }

            usingGPTLiveFullDuplex = true
            liveVoice.start(voiceLabel: voiceBadge)
            liveVoice.liveLine = "Conectando ao GPT-Live 1.1 (full-duplex)…"
            LiveActivityManager.shared.startVoiceSession(
                conversationTitle: store.currentConversationTitle,
                voiceLabel: voiceBadge
            )
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)

            let priorHistory = store.messages.suffix(12).map { (role: $0.role, content: $0.content) }
            let started = await gptLive.start(
                apiKey: DirectBrainCredentials.openAIKey,
                voice: normalizedTimbre,
                priorMessages: priorHistory,
                agoraDeveloperNote: store.buildGPTLiveAgoraNote(),
                greetOnOpen: store.messages.isEmpty
            )

            if started {
                return
            }

            usingGPTLiveFullDuplex = false
            if transportMode == .gptLiveFullDuplex {
                liveVoice.phase = .paused
                liveVoice.liveLine = gptLive.lastError ?? "GPT-Live 1.1 indisponível agora — verifique sua chave OpenAI ou conexão."
                LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
                return
            }

            // Modo Automático: fallback contínuo e silencioso para Walkie-Talkie Offline/Híbrido no hospital
            liveVoice.voiceLabel = depth.label
            liveVoice.phase = .listening
            liveVoice.liveLine = "Modo Walkie-Talkie ativo — pode falar…"
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            await armNextLiveVoiceTurn()
            return
        }

        liveVoice.start(voiceLabel: depth.label)
        LiveActivityManager.shared.startVoiceSession(
            conversationTitle: store.currentConversationTitle,
            voiceLabel: depth.label
        )
        await armNextLiveVoiceTurn()
    }

    private func armNextLiveVoiceTurn() async {
        guard liveVoice.isActive, !usingGPTLiveFullDuplex, liveVoice.phase == .listening else { return }
        let started = await voice.startContinuousTurn()
        if !started && liveVoice.isActive {
            liveVoice.phase = .paused
            liveVoice.liveLine = voice.erro
                ?? voice.motivoDaRecusa
                ?? "Microfone indisponível agora — toque para retomar"
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
        }
    }

    func handleLiveVoiceCommand(_ command: CompanionLiveVoiceCommand) {
        switch command {
        case .togglePause:
            guard liveVoice.isActive else { return }
            if usingGPTLiveFullDuplex {
                let targetPaused = (liveVoice.phase != .paused)
                Task { @MainActor in
                    await gptLive.setPaused(targetPaused)
                }
                return
            }
            liveVoiceLoopTask?.cancel()
            liveVoiceLoopTask = nil
            liveVoice.apply(command: .togglePause)
            lastForwardedTranscriptLength = 0
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            if liveVoice.phase == .paused {
                voz.parar()
                voice.stopQuietly()
            } else if liveVoice.phase == .listening {
                voz.parar()
                Task { await armNextLiveVoiceTurn() }
            }

        case .interruptAndListen:
            guard liveVoice.isActive else { return }
            if usingGPTLiveFullDuplex {
                Task { @MainActor in
                    await gptLive.interruptOutputAndListen()
                }
                return
            }
            liveVoiceLoopTask?.cancel()
            liveVoiceLoopTask = nil
            voz.parar()
            voice.stopQuietly()
            liveVoice.apply(command: .interruptAndListen)
            lastForwardedTranscriptLength = 0
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard liveVoice.isActive, !usingGPTLiveFullDuplex, liveVoice.phase == .listening else { return }
                await armNextLiveVoiceTurn()
            }

        case .endSession:
            endLiveVoiceSession()
        }
    }

    func endLiveVoiceSession() {
        let finalTurns = liveVoice.turnCount
        let finalVoiceLabel = liveVoice.voiceLabel
        let wasGPTLive = usingGPTLiveFullDuplex || gptLive.isActive
        usingGPTLiveFullDuplex = false
        liveVoiceLoopTask?.cancel()
        liveVoiceLoopTask = nil
        if wasGPTLive {
            Task { @MainActor in
                await gptLive.stop()
            }
        }
        voz.parar()
        voice.stopQuietly()
        lastForwardedTranscriptLength = 0
        liveVoice.apply(command: .endSession)
        LiveActivityManager.shared.endVoiceSession(
            turnCount: finalTurns,
            voiceLabel: finalVoiceLabel
        )
    }
}
