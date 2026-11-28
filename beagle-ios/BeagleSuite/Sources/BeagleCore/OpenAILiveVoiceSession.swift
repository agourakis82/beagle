//
//  OpenAILiveVoiceSession.swift
//  BeagleCore — Sessão de Voz Conversacional Full-Duplex com GPT-Live (`gpt-live-1.1`)
//
//  Implementa o protocolo oficial OpenAI GPT-Live (novembro/2026):
//    - Transporte WebSocket primário: `wss://api.openai.com/v1/live/sessions`
//    - Áudio bidirecional simultâneo (Full-Duplex): PCM16 little-endian mono a 24.000 Hz
//    - Cancelamento acústico de eco em hardware iOS (`AVAudioSession` `.playAndRecord` + `.voiceChat`)
//    - Barge-in instantâneo (<50 ms no `AVAudioPlayerNode` local + steering `gpt-live-1.1`)
//    - Client Delegation (`delegation: { type: "client" }`): GPT-Live conduz a conversa falada
//      em `pt-BR` com baixa latência enquanto delega raciocínio clínico, científico, memória
//      GraphRAG++, Bula/PCDT, MCP e ferramentas nativas do iPhone ao cérebro MoE do Beagle,
//      devolvendo contexto via `session.thinking.append` e resultados falados via `session.commentary.append`.
//

import Foundation
import Observation
#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

// MARK: - Controlador Observável da Sessão Full-Duplex GPT-Live (`gpt-live-1.1`)

@Observable
@MainActor
public final class OpenAILiveVoiceSession {
    public private(set) var isActive: Bool = false
    public private(set) var isConnected: Bool = false
    public private(set) var isPaused: Bool = false
    public private(set) var sessionId: String?
    public private(set) var activeDelegationCount: Int = 0
    public private(set) var inputLevel: Float = 0
    public private(set) var outputLevel: Float = 0
    public private(set) var lastError: String?

    /// Chamado quando uma bolha de transcrição (usuário ou assistente) nasce, cresce ou fecha.
    public var onTranscriptBubbleUpdate: ((MessageRole, UUID, String, Bool, [String]) -> Void)?
    /// Chamado quando a fase acústica/cognitiva muda (`listening`, `thinking`, `speaking`, `paused`, `ended`) + linha viva.
    public var onStateChanged: ((CompanionLiveVoicePhase, Int, String) -> Void)?
    /// Chamado quando `gpt-live-1.1` emite `session.delegation.created` (`target: "client"`).
    public var onDelegateToBackend: ((OpenAILiveDelegationContext) async -> OpenAILiveDelegationOutcome)?
    /// Chamado se a conexão cair inesperadamente antes de `session.started` para permitir fallback imediato ao Walkie-Talkie local.
    public var onStartupFallbackNeeded: ((String) -> Void)?

    private let urlSession: URLSession
    private var wsTask: URLSessionWebSocketTask?

    // Estado interno compartilhado com extensões em `LiveVoice/`
    var receiveTask: Task<Void, Never>?
    var audioSendTask: Task<Void, Never>?
    var speakingDecayTask: Task<Void, Never>?
    var delegationTasks: [String: Task<Void, Never>] = [:]
    var carryoverByte = Data()
    var sessionReadyContinuation: CheckedContinuation<Bool, Never>?
    var sessionClosedContinuation: CheckedContinuation<Void, Never>?

    // Agrupamento de transcrições full-duplex em bolhas do chat
    var transcriptTimeline: [OpenAILiveTranscriptSegment] = []
    var activeUserBubbleId: UUID?
    var activeUserText: String = ""
    var lastUserEndMs: Int = 0
    var activeAssistantBubbleId: UUID?
    var activeAssistantText: String = ""
    var activeAssistantTools: [String] = []
    var lastAssistantEndMs: Int = 0
    var hasNewUserSpeechSinceAssistantDelta: Bool = false
    var turnCount: Int = 0
    var lastUserAudioInterruptAt: Date = .distantPast

    #if os(iOS) || os(visionOS) || os(macOS)
    var audioEngine: AVAudioEngine?
    var playerNode: AVAudioPlayerNode?
    var playbackFormat: AVAudioFormat?
    var tapProcessor: LiveAudioCaptureTapProcessor?
    var scheduledOutputBuffers: Int = 0
    #endif

    #if os(iOS) || os(visionOS)
    var audioSessionActive: Bool = false
    #endif

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - Ciclo de Vida Principal

    /// Inicia uma sessão `gpt-live-1.1` full-duplex. Retorna `true` assim que `session.started` é confirmado e o grafo de áudio está aberto.
    public func start(
        apiKey: String,
        voice: String,
        priorMessages: [(role: MessageRole, content: String)],
        agoraDeveloperNote: String?,
        greetOnOpen: Bool = false
    ) async -> Bool {
        await stop()

        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Chave OpenAI ausente para sessão GPT-Live."
            return false
        }

        #if os(iOS) || os(visionOS) || os(macOS)
        let micGranted = await Self.requestMicrophonePermission()
        guard micGranted else {
            lastError = "Microfone sem permissão — libere em Ajustes › Beagle › Microfone."
            return false
        }
        #endif

        isActive = true
        isPaused = false
        lastError = nil
        turnCount = 0
        activeDelegationCount = 0
        carryoverByte.removeAll()
        transcriptTimeline.removeAll()
        resetBubbleTrackers()

        var request = URLRequest(url: OpenAILiveProtocol.endpointURL)
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let socket = urlSession.webSocketTask(with: request)
        socket.maximumMessageSize = 8 * 1024 * 1024
        self.wsTask = socket
        socket.resume()

        // Inicia loop de recepção antes de enviar `session.start` (conforme guia oficial OpenAI Live)
        startReceiveLoop(for: socket)

        let instructions = OpenAILiveProtocol.buildBeagleLiveInstructions()
        let initialInput = OpenAILiveProtocol.buildInitialInputItems(
            priorMessages: priorMessages,
            agoraDeveloperNote: agoraDeveloperNote,
            greetOnOpen: greetOnOpen
        )
        let startPayload = OpenAILiveProtocol.buildSessionStartPayload(
            voice: voice,
            instructions: instructions,
            inputItems: initialInput
        )

        guard await sendJSON(startPayload) else {
            lastError = "Falha ao enviar session.start para o GPT-Live."
            await stop()
            return false
        }

        // Aguarda `session.started` com timeout de 12s (Swift 6 region-isolation safe)
        let ready: Bool
        if isConnected {
            ready = true
        } else {
            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, let self, let pending = self.sessionReadyContinuation else { return }
                self.sessionReadyContinuation = nil
                pending.resume(returning: false)
            }
            ready = await withCheckedContinuation { cont in
                self.sessionReadyContinuation = cont
            }
            timeoutTask.cancel()
        }

        guard ready, isActive else {
            let reason = lastError ?? "Tempo esgotado conectando ao GPT-Live 1.1."
            await stop()
            lastError = reason
            return false
        }

        #if os(iOS) || os(visionOS) || os(macOS)
        do {
            try await startFullDuplexAudioEngine()
        } catch {
            let msg = "Falha ao abrir áudio full-duplex: \(error.localizedDescription)"
            await stop()
            lastError = msg
            return false
        }
        guard isActive else { return false }
        #endif

        emitPhaseUpdate(.listening, line: "GPT-Live 1.1 ativo — pode falar naturalmente (full-duplex)")
        return true
    }

    /// Alterna pausa/retomada (`session.input_audio.mute` / `unmute` + descarte do buffer de saída local).
    public func setPaused(_ paused: Bool) async {
        guard isActive, isPaused != paused else { return }
        isPaused = paused
        if paused {
            flushLocalPlayback()
            _ = await sendJSON([
                "type": "session.input_audio.mute",
                "event_id": "mute_\(UUID().uuidString.prefix(8))"
            ])
            emitPhaseUpdate(.paused, line: CompanionLiveVoicePhase.paused.defaultLinePtBR)
        } else {
            _ = await sendJSON([
                "type": "session.input_audio.unmute",
                "event_id": "unmute_\(UUID().uuidString.prefix(8))"
            ])
            emitPhaseUpdate(.listening, line: "Pode falar — escuta full-duplex retomada…")
        }
    }

    /// Barge-in explícito acionado pela Dynamic Island ou botão de corte: limpa áudio em fila imediatamente
    /// e instrui `gpt-live-1.1` a ceder o turno na hora.
    public func interruptOutputAndListen() async {
        guard isActive else { return }
        flushLocalPlayback()
        if isPaused {
            isPaused = false
            _ = await sendJSON([
                "type": "session.input_audio.unmute",
                "event_id": "unmute_\(UUID().uuidString.prefix(8))"
            ])
        }
        if let steer = OpenAILiveProtocol.buildContextAppendPayload(
            kind: .instructions,
            delegationId: nil,
            content: "Pare de falar imediatamente e escute em silêncio o que o Demetrios vai dizer agora."
        ) {
            _ = await sendJSON(steer)
        }
        emitPhaseUpdate(.listening, line: "Pode falar — estou te ouvindo…")
    }

    /// Encerra a sessão com fechamento gracioso (`session.close` → `session.closed`), consolidando as bolhas finais.
    public func stop() async {
        let wasActive = isActive
        isActive = false
        isPaused = false

        speakingDecayTask?.cancel()
        speakingDecayTask = nil
        audioSendTask?.cancel()
        audioSendTask = nil

        for (_, task) in delegationTasks {
            task.cancel()
        }
        delegationTasks.removeAll()
        activeDelegationCount = 0

        #if os(iOS) || os(visionOS) || os(macOS)
        stopFullDuplexAudioEngine()
        #endif

        finalizeOpenBubblesIfNeeded()

        if let pendingStart = sessionReadyContinuation {
            sessionReadyContinuation = nil
            pendingStart.resume(returning: false)
        }

        if wasActive, isConnected, let wsTask {
            _ = await sendJSON(["type": "session.close"])
            let closeTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1_500))
                guard !Task.isCancelled, let self, let pending = self.sessionClosedContinuation else { return }
                self.sessionClosedContinuation = nil
                pending.resume()
            }
            await withCheckedContinuation { cont in
                self.sessionClosedContinuation = cont
            }
            closeTimeout.cancel()
            wsTask.cancel(with: .normalClosure, reason: nil)
        } else {
            wsTask?.cancel(with: .goingAway, reason: nil)
        }

        receiveTask?.cancel()
        receiveTask = nil
        wsTask = nil
        isConnected = false
        sessionId = nil
        inputLevel = 0
        outputLevel = 0
    }

    // MARK: - Helpers Internos para Extensões

    func markSessionStarted(id: String) {
        sessionId = id
        isConnected = true
    }

    func setLastError(_ message: String?) {
        lastError = message
    }

    func adjustActiveDelegationCount(by delta: Int) {
        activeDelegationCount = max(0, activeDelegationCount + delta)
    }

    func updateInputLevel(_ level: Float) {
        inputLevel = level
    }

    func updateOutputLevel(_ level: Float) {
        outputLevel = level
    }

    func emitPhaseUpdate(_ phase: CompanionLiveVoicePhase, line: String) {
        onStateChanged?(phase, turnCount, line)
    }

    func sendJSON(_ dict: [String: Any]) async -> Bool {
        guard let wsTask,
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        do {
            try await wsTask.send(.string(text))
            return true
        } catch {
            return false
        }
    }
}
