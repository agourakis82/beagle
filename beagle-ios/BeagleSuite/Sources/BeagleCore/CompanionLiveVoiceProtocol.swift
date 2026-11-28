//
//  CompanionLiveVoiceProtocol.swift
//  BeagleCore
//
//  Protocolo compartilhado entre BeagleCockpit (app principal) e BeagleWidgets
//  (Dynamic Island + Tela Bloqueada) para Sessão de Voz Contínua Mãos-Livres:
//    - GPT-Live Full-Duplex (`gpt-live-1.1` via `wss://api.openai.com/v1/live/sessions` + Delegação MoE)
//    - Walkie-Talkie Local/Híbrido por Turnos (fallback 100% offline no hospital)
//

import Foundation

#if os(iOS)
import ActivityKit
import AppIntents
#endif

// MARK: - Modo de Transporte da Sessão de Voz Contínua

public enum CompanionLiveSessionTransportMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto = "auto"
    case gptLiveFullDuplex = "gpt-live"
    case walkieTalkieTurns = "walkie-talkie"

    public static let storageKey = "beagle.voice.liveTransportMode"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto:
            return "Automático (GPT-Live 1.1 Full-Duplex → Walkie-Talkie Offline)"
        case .gptLiveFullDuplex:
            return "GPT-Live 1.1 Full-Duplex (Marin · Delegação MoE)"
        case .walkieTalkieTurns:
            return "Walkie-Talkie por Turnos (Offline / Híbrido)"
        }
    }

    public static var current: CompanionLiveSessionTransportMode {
        get {
            let raw = UserDefaults.standard.string(forKey: storageKey) ?? Self.auto.rawValue
            return CompanionLiveSessionTransportMode(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }
}

// MARK: - Fase da Sessão Contínua de Voz

public enum CompanionLiveVoicePhase: String, Codable, Hashable, Sendable, CaseIterable {
    case listening = "listening"
    case thinking = "thinking"
    case speaking = "speaking"
    case paused = "paused"
    case ended = "ended"

    public var titlePtBR: String {
        switch self {
        case .listening: return "Ouvindo"
        case .thinking:  return "Pensando"
        case .speaking:  return "Falando"
        case .paused:    return "Em pausa"
        case .ended:     return "Encerrado"
        }
    }

    public var shortBadge: String {
        switch self {
        case .listening: return "OUV"
        case .thinking:  return "PENS"
        case .speaking:  return "VOZ"
        case .paused:    return "PAUS"
        case .ended:     return "FIM"
        }
    }

    public var symbolName: String {
        switch self {
        case .listening: return "waveform.circle.fill"
        case .thinking:  return "sparkles"
        case .speaking:  return "speaker.wave.3.fill"
        case .paused:    return "pause.circle.fill"
        case .ended:     return "checkmark.circle.fill"
        }
    }

    public var defaultLinePtBR: String {
        switch self {
        case .listening: return "Pode falar — estou te ouvindo…"
        case .thinking:  return "Pensando contigo…"
        case .speaking:  return "Respondendo em voz…"
        case .paused:    return "Sessão em pausa — toque para retomar"
        case .ended:     return "Sessão de voz encerrada"
        }
    }
}

// MARK: - Comandos Interativos (Dynamic Island / Tela Bloqueada / In-App)

public enum CompanionLiveVoiceCommand: String, Codable, Hashable, Sendable {
    case togglePause = "toggle_pause"
    case interruptAndListen = "interrupt_and_listen"
    case endSession = "end_session"
}

// MARK: - Máquina de Estado Determinística (GPT-Live Full-Duplex & Walkie-Talkie)

public struct CompanionLiveVoiceSessionState: Codable, Hashable, Sendable {
    public var isActive: Bool
    public var phase: CompanionLiveVoicePhase
    public var turnCount: Int
    public var emptySilenceStrikes: Int
    public var voiceLabel: String
    public var liveLine: String

    public init(
        isActive: Bool = false,
        phase: CompanionLiveVoicePhase = .ended,
        turnCount: Int = 0,
        emptySilenceStrikes: Int = 0,
        voiceLabel: String = "MoE",
        liveLine: String = ""
    ) {
        self.isActive = isActive
        self.phase = phase
        self.turnCount = turnCount
        self.emptySilenceStrikes = emptySilenceStrikes
        self.voiceLabel = voiceLabel
        self.liveLine = liveLine
    }

    public mutating func start(voiceLabel: String) {
        self.isActive = true
        self.phase = .listening
        self.turnCount = 0
        self.emptySilenceStrikes = 0
        self.voiceLabel = voiceLabel
        self.liveLine = CompanionLiveVoicePhase.listening.defaultLinePtBR
    }

    public mutating func updatePartialTranscript(_ partial: String) {
        guard isActive, phase != .paused, phase != .ended else { return }
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.emptySilenceStrikes = 0
        if phase != .speaking && phase != .thinking {
            self.phase = .listening
        }
        self.liveLine = String(trimmed.suffix(120))
    }

    public mutating func onUserUtteranceCommitted(_ transcript: String) {
        guard isActive else { return }
        self.emptySilenceStrikes = 0
        self.turnCount += 1
        self.phase = .thinking
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        self.liveLine = trimmed.isEmpty
            ? CompanionLiveVoicePhase.thinking.defaultLinePtBR
            : String(trimmed.prefix(120))
    }

    public mutating func updateThinkingNote(_ note: String) {
        guard isActive, phase != .paused, phase != .ended else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if phase != .speaking {
            self.phase = .thinking
        }
        self.liveLine = String(trimmed.prefix(120))
    }

    public mutating func onAssistantSpeaking(_ text: String) {
        guard isActive, phase != .paused, phase != .ended else { return }
        self.phase = .speaking
        let clean = CompanionVoice.prepararTextoParaFala(text)
        let source = clean.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : clean
        self.liveLine = source.isEmpty
            ? CompanionLiveVoicePhase.speaking.defaultLinePtBR
            : String(source.suffix(120))
    }

    /// Chamado após o término natural da fala e o compasso acústico.
    /// Retorna `true` se a sessão continua pronta para escuta.
    @discardableResult
    public mutating func onSpeechFinishedRearm() -> Bool {
        guard isActive, phase != .paused, phase != .ended else { return false }
        self.phase = .listening
        self.liveLine = CompanionLiveVoicePhase.listening.defaultLinePtBR
        return true
    }

    /// Chamado quando uma janela de escuta termina em silêncio completo (modo Walkie-Talkie).
    /// Na 1ª janela vazia rearma uma vez; após `maxStrikes` janelas vazias seguidas,
    /// entra em `.paused` automaticamente para proteger bateria e privacidade.
    @discardableResult
    public mutating func onEmptySilenceWindow(maxStrikes: Int = 2) -> Bool {
        guard isActive, phase != .paused, phase != .ended else { return false }
        self.emptySilenceStrikes += 1
        if self.emptySilenceStrikes >= max(1, maxStrikes) {
            self.phase = .paused
            self.liveLine = "Silêncio prolongado — em pausa (toque para retomar)"
            return false
        }
        self.phase = .listening
        self.liveLine = "Ainda te ouvindo — pode falar quando quiser…"
        return true
    }

    /// Aplica comando vindo da Dynamic Island, Tela Bloqueada ou barra flutuante.
    public mutating func apply(command: CompanionLiveVoiceCommand) {
        switch command {
        case .togglePause:
            guard isActive else { return }
            if phase == .paused {
                phase = .listening
                emptySilenceStrikes = 0
                liveLine = CompanionLiveVoicePhase.listening.defaultLinePtBR
            } else {
                phase = .paused
                liveLine = CompanionLiveVoicePhase.paused.defaultLinePtBR
            }

        case .interruptAndListen:
            guard isActive else { return }
            phase = .listening
            emptySilenceStrikes = 0
            liveLine = CompanionLiveVoicePhase.listening.defaultLinePtBR

        case .endSession:
            isActive = false
            phase = .ended
            liveLine = CompanionLiveVoicePhase.ended.defaultLinePtBR
        }
    }
}

// MARK: - Barramento de Comandos (In-Process + App Group Fallback)

@MainActor
public final class CompanionLiveVoiceBus {
    public static let shared = CompanionLiveVoiceBus()
    public static let appGroupIdentifier = "group.dev.sounio.cockpit"
    public static let pendingCommandKey = "beagle.liveVoice.pendingCommand"

    public var onCommand: ((CompanionLiveVoiceCommand) -> Void)?

    public init() {}

    /// Envia um comando ao controlador ativo de voz contínua; se nenhum controlador estiver montado
    /// (ou se `persistInDefaults` for fornecido), persiste no App Group para consumo imediato ao acordar.
    public func dispatch(
        _ command: CompanionLiveVoiceCommand,
        persistInDefaults: UserDefaults? = nil,
        forcePersist: Bool = false
    ) {
        if let onCommand, !forcePersist {
            onCommand(command)
            return
        }
        let store = persistInDefaults ?? UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
        store.set(command.rawValue, forKey: Self.pendingCommandKey)
        onCommand?(command)
    }

    public func consumePendingCommand(from defaults: UserDefaults? = nil) -> CompanionLiveVoiceCommand? {
        let store = defaults ?? UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
        guard let raw = store.string(forKey: Self.pendingCommandKey) else { return nil }
        store.removeObject(forKey: Self.pendingCommandKey)
        return CompanionLiveVoiceCommand(rawValue: raw)
    }
}

// MARK: - ActivityKit Attributes + Interactive LiveActivityIntents (iOS)

#if os(iOS)
extension ActivityKit.Activity where Attributes: Sendable, Attributes.ContentState: Sendable {
    @MainActor
    public func updateLocalContent(_ content: ActivityContent<Attributes.ContentState>) {
        nonisolated(unsafe) let activity = self
        Task { await activity.update(content) }
    }

    @MainActor
    public func endLocalContent(
        _ content: ActivityContent<Attributes.ContentState>,
        dismissalPolicy: ActivityUIDismissalPolicy,
        afterEnd: (@Sendable () async -> Void)? = nil
    ) {
        nonisolated(unsafe) let activity = self
        Task {
            await activity.end(content, dismissalPolicy: dismissalPolicy)
            if let afterEnd {
                await afterEnd()
            }
        }
    }

    @MainActor
    public func updateLocalContentAsync(_ content: ActivityContent<Attributes.ContentState>) async {
        nonisolated(unsafe) let activity = self
        await activity.update(content)
    }

    @MainActor
    public func endLocalContentAsync(
        _ content: ActivityContent<Attributes.ContentState>,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async {
        nonisolated(unsafe) let activity = self
        await activity.end(content, dismissalPolicy: dismissalPolicy)
    }
}

public struct CompanionVoiceSessionAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: CompanionLiveVoicePhase
        public var voiceLabel: String
        public var turnCount: Int
        public var liveLine: String

        public init(
            phase: CompanionLiveVoicePhase,
            voiceLabel: String,
            turnCount: Int = 0,
            liveLine: String = ""
        ) {
            self.phase = phase
            self.voiceLabel = voiceLabel
            self.turnCount = turnCount
            self.liveLine = liveLine.isEmpty ? phase.defaultLinePtBR : liveLine
        }
    }

    public var conversationTitle: String
    public var startedAt: Date

    public init(conversationTitle: String, startedAt: Date = .now) {
        self.conversationTitle = conversationTitle
        self.startedAt = startedAt
    }
}

public struct TogglePauseLiveVoiceIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Pausar ou Retomar Voz Beagle"
    public static let description = IntentDescription("Pausa ou retoma a sessão de voz contínua mãos-livres do Beagle direto da Dynamic Island ou Tela Bloqueada.")
    public static let openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if CompanionLiveVoiceBus.shared.onCommand != nil {
            CompanionLiveVoiceBus.shared.dispatch(.togglePause)
        } else {
            CompanionLiveVoiceBus.shared.dispatch(.togglePause, forcePersist: true)
            for activity in Activity<CompanionVoiceSessionAttributes>.activities {
                let current = activity.content.state
                let nextPhase: CompanionLiveVoicePhase = (current.phase == .paused) ? .listening : .paused
                let nextState = CompanionVoiceSessionAttributes.ContentState(
                    phase: nextPhase,
                    voiceLabel: current.voiceLabel,
                    turnCount: current.turnCount,
                    liveLine: nextPhase.defaultLinePtBR
                )
                let content = ActivityContent(state: nextState, staleDate: Date.now.addingTimeInterval(900))
                await activity.updateLocalContentAsync(content)
            }
        }
        return .result()
    }
}

public struct InterruptSpeechLiveVoiceIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Cortar Fala e Ouvir Agora"
    public static let description = IntentDescription("Interrompe a fala atual do Beagle e abre o microfone imediatamente para o próximo turno.")
    public static let openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if CompanionLiveVoiceBus.shared.onCommand != nil {
            CompanionLiveVoiceBus.shared.dispatch(.interruptAndListen)
        } else {
            CompanionLiveVoiceBus.shared.dispatch(.interruptAndListen, forcePersist: true)
            for activity in Activity<CompanionVoiceSessionAttributes>.activities {
                let current = activity.content.state
                let nextState = CompanionVoiceSessionAttributes.ContentState(
                    phase: .listening,
                    voiceLabel: current.voiceLabel,
                    turnCount: current.turnCount,
                    liveLine: CompanionLiveVoicePhase.listening.defaultLinePtBR
                )
                let content = ActivityContent(state: nextState, staleDate: Date.now.addingTimeInterval(900))
                await activity.updateLocalContentAsync(content)
            }
        }
        return .result()
    }
}

public struct EndLiveVoiceSessionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Encerrar Sessão de Voz Beagle"
    public static let description = IntentDescription("Encerra a sessão contínua de voz mãos-livres do Beagle e fecha a Live Activity.")
    public static let openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if CompanionLiveVoiceBus.shared.onCommand != nil {
            CompanionLiveVoiceBus.shared.dispatch(.endSession)
        } else {
            CompanionLiveVoiceBus.shared.dispatch(.endSession, forcePersist: true)
            for activity in Activity<CompanionVoiceSessionAttributes>.activities {
                let current = activity.content.state
                let finalState = CompanionVoiceSessionAttributes.ContentState(
                    phase: .ended,
                    voiceLabel: current.voiceLabel,
                    turnCount: current.turnCount,
                    liveLine: CompanionLiveVoicePhase.ended.defaultLinePtBR
                )
                let content = ActivityContent(state: finalState, staleDate: nil)
                await activity.endLocalContentAsync(content, dismissalPolicy: .immediate)
            }
        }
        return .result()
    }
}
#endif
