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

// MARK: - Modelos Puros do Protocolo GPT-Live (`gpt-live-1.1`)

public enum OpenAILiveContextAppendKind: String, Sendable {
    case instructions = "session.instructions.append"
    case thinking = "session.thinking.append"
    case commentary = "session.commentary.append"
}

public struct OpenAILiveTranscriptSegment: Sendable, Equatable {
    public let role: MessageRole
    public var text: String
    public let startMs: Int
    public var endMs: Int

    public init(role: MessageRole, text: String, startMs: Int, endMs: Int) {
        self.role = role
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
    }
}

public struct OpenAILiveDelegationContext: Sendable {
    public let delegationId: String
    public let offsetMs: Int
    public let transcriptWindow: [(role: String, text: String)]
    public let latestUserUtterance: String

    public init(
        delegationId: String,
        offsetMs: Int,
        transcriptWindow: [(role: String, text: String)],
        latestUserUtterance: String
    ) {
        self.delegationId = delegationId
        self.offsetMs = offsetMs
        self.transcriptWindow = transcriptWindow
        self.latestUserUtterance = latestUserUtterance
    }
}

public struct OpenAILiveDelegationOutcome: Sendable {
    public let spokenSummary: String
    public let backgroundFacts: String?
    public let executedTools: [String]

    public init(
        spokenSummary: String,
        backgroundFacts: String? = nil,
        executedTools: [String] = []
    ) {
        self.spokenSummary = spokenSummary
        self.backgroundFacts = backgroundFacts
        self.executedTools = executedTools
    }
}

public enum OpenAILiveServerEvent: Sendable, Equatable {
    case sessionStarted(sessionId: String)
    case outputAudioDelta(pcm16Data: Data)
    case inputTranscriptDelta(delta: String, startMs: Int, endMs: Int)
    case outputTranscriptDelta(delta: String, startMs: Int, endMs: Int)
    case delegationCreated(id: String, target: String, offsetMs: Int)
    case inputAudioMuted(clientEventId: String?)
    case inputAudioUnmuted(clientEventId: String?)
    case contextAppended(eventType: String, clientEventId: String?)
    case sessionClosed
    case error(code: String?, message: String)
    case ignored(type: String)
}

public enum OpenAILiveProtocol {
    public static let liveModel = "gpt-live-1.1"
    public static let sampleRateHz = 24_000
    public static let endpointURL = URL(string: "wss://api.openai.com/v1/live/sessions")!
    /// Limite conservador (~380 tokens em pt-BR) abaixo do teto estrito de 500 tokens por append do GPT-Live.
    public static let maxAppendCharacters = 1_520

    /// Prompt estruturado segundo o guia oficial de Prompting do `gpt-live-1.1`
    /// (preservando os cabeçalhos `Backchannel policy`, `Interruption policy` e `Delegation policy`).
    public static func buildBeagleLiveInstructions(extraContext: String? = nil) -> String {
        var base = """
        Você é o Beagle, companheiro íntimo, médico, neurocientista e parceiro intelectual do Demetrios.
        Fale sempre em português do Brasil natural, caloroso, direto e sereno, no ritmo espontâneo de uma conversa próxima entre grandes amigos de plantão e bancada científica.
        Mantenha respostas faladas enxutas (1 a 3 frases claras por vez), deixando espaço para diálogo, salvo quando ele pedir uma explicação longa.

        Backchannel policy: Use moderate backchannels. Escute com calma e naturalidade, respeitando pausas de reflexão sem competir com a fala principal dele.

        Interruption policy: Quando o usuário interromper, pare de falar imediatamente, mesmo no meio de uma frase. Escute até ele terminar e responda ao que ele acabou de dizer, sem retomar a explicação substituída.

        Delegation policy:
        Backend tools:
        - Cérebro MoE Beagle + Exocórtex (GraphRAG++): busca memórias pessoais, conversas anteriores, projetos científicos (Sounio, KEC, neurociência, psiquiatria), jobs do cluster HPC e sínteses.
        - Bula & PCDT Clínico + Literatura Científica & Web: consulta posologia, interações medicamentosas, protocolos do Ministério da Saúde, artigos no PubMed/Crossref/arXiv e busca web atualizada.
        - Ferramentas Nativas do iPhone: agenda (EventKit), lembretes, sinais biométricos do Apple Watch/HealthKit (HRV, sono, FC) e notas do exocórtex.

        Delegate to the backend when:
        - O usuário pedir informações clínicas, doses, bulas, interações, protocolos médicos, papers científicos, notícias ou dados atuais da web.
        - O usuário perguntar sobre memórias pessoais, projetos, status do cluster, compromissos na agenda, lembretes ou métricas fisiológicas.
        - A pergunta exigir raciocínio científico, matemático ou técnico cuidadoso além de uma resposta conversacional simples.
        - Uma correção do usuário alterar uma tarefa delegada já solicitada.

        Do not delegate when:
        - Você puder responder diretamente pelo contexto já presente na conversa ou por um resultado recente ainda válido do backend.
        - Você precisar apenas de um esclarecimento rápido para entender o pedido, ou em cumprimentos e escuta cotidiana.

        Delegate to the backend before giving an answer that depends on backend work.
        Do not guess the result while waiting. Quando delegar, avise brevemente em meia frase natural que está conferindo.
        """
        if let extra = extraContext?.trimmingCharacters(in: .whitespacesAndNewlines), !extra.isEmpty {
            base += "\n\nContexto inicial da sessão:\n" + String(extra.prefix(1_200))
        }
        return base
    }

    /// Constrói itens iniciais de `session.input` (até 12 mensagens recentes + nota `developer` de contexto fisiológico/temporal).
    public static func buildInitialInputItems(
        priorMessages: [(role: MessageRole, content: String)],
        agoraDeveloperNote: String? = nil,
        greetOnOpen: Bool = false
    ) -> [[String: Any]] {
        var items: [[String: Any]] = []

        if let note = agoraDeveloperNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            items.append([
                "type": "message",
                "role": "developer",
                "content": [
                    [
                        "type": "input_text",
                        "text": String(note.prefix(900))
                    ]
                ]
            ])
        }

        for msg in priorMessages.suffix(12) {
            let clean = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            switch msg.role {
            case .user:
                items.append([
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": String(clean.prefix(900))
                        ]
                    ]
                ])
            case .assistant:
                items.append([
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": String(clean.prefix(900))
                        ]
                    ]
                ])
            case .system:
                continue
            }
        }

        if greetOnOpen {
            items.append([
                "type": "message",
                "role": "developer",
                "content": [
                    [
                        "type": "input_text",
                        "text": "Cumprimente o Demetrios brevemente agora em uma frase calorosa e curta em português do Brasil, e depois faça silêncio para escutá-lo."
                    ]
                ]
            ])
        }

        return items
    }

    /// Monta o evento inicial `session.start` para `wss://api.openai.com/v1/live/sessions`.
    public static func buildSessionStartPayload(
        voice: String,
        instructions: String,
        inputItems: [[String: Any]] = [],
        eventId: String = "beagle_live_start"
    ) -> [String: Any] {
        let normalizedVoice = CompanionVoice.normalizedLiveVoice(voice)
        var sessionDict: [String: Any] = [
            "model": liveModel,
            "instructions": instructions,
            "audio": [
                "format": [
                    "type": "audio/pcm",
                    "rate": sampleRateHz
                ],
                "output": [
                    "voice": normalizedVoice
                ]
            ],
            "delegation": [
                "type": "client"
            ]
        ]
        if !inputItems.isEmpty {
            sessionDict["input"] = inputItems
        }
        return [
            "type": "session.start",
            "event_id": eventId,
            "session": sessionDict
        ]
    }

    /// Garante alinhamento par de 2 bytes (PCM16LE) retendo eventual byte ímpar pendente e gera `session.input_audio.append`.
    public static func buildInputAudioAppendPayload(
        chunk: Data,
        carryoverByte: inout Data
    ) -> [String: Any]? {
        var combined = Data()
        if !carryoverByte.isEmpty {
            combined.append(carryoverByte)
            carryoverByte.removeAll(keepingCapacity: true)
        }
        combined.append(chunk)
        let alignedLength = combined.count - (combined.count % 2)
        if alignedLength < combined.count {
            carryoverByte = Data(combined[alignedLength...])
        }
        guard alignedLength > 0 else { return nil }
        let alignedBytes = combined.prefix(alignedLength)
        return [
            "type": "session.input_audio.append",
            "audio": Data(alignedBytes).base64EncodedString()
        ]
    }

    /// Trunca texto respeitando limites de frase para caber com segurança no limite de 500 tokens por append do GPT-Live.
    public static func truncateForLiveAppend(_ raw: String, maxChars: Int = maxAppendCharacters) -> String {
        let clean = CompanionVoice.prepararTextoParaFala(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > maxChars else { return clean }
        let idx = clean.index(clean.startIndex, offsetBy: maxChars)
        let prefix = clean[..<idx]
        if let sentenceEnd = prefix.range(of: ". ", options: .backwards)?.lowerBound {
            return String(prefix[...sentenceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Monta `session.thinking.append`, `session.commentary.append` ou `session.instructions.append`
    /// com `delegation_id` explícito (`String` ou `NSNull` para contexto global da sessão).
    public static func buildContextAppendPayload(
        kind: OpenAILiveContextAppendKind,
        delegationId: String?,
        content: String,
        eventId: String = "beagle_ctx_\(UUID().uuidString.prefix(8))"
    ) -> [String: Any]? {
        let bounded = truncateForLiveAppend(content)
        guard !bounded.isEmpty else { return nil }
        let delegationValue: Any = delegationId.map { $0 as Any } ?? NSNull()
        return [
            "type": kind.rawValue,
            "event_id": eventId,
            "delegation_id": delegationValue,
            "content": bounded
        ]
    }

    /// Faz o parse resiliente dos eventos JSON emitidos pelo servidor GPT-Live.
    public static func parseServerEvent(_ rawData: Data) -> OpenAILiveServerEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let type = obj["type"] as? String else {
            return nil
        }

        switch type {
        case "session.started":
            let sessionId = (obj["session"] as? [String: Any])?["id"] as? String ?? ""
            return .sessionStarted(sessionId: sessionId)

        case "session.output_audio.delta":
            guard let b64 = obj["delta"] as? String,
                  let pcm = Data(base64Encoded: b64),
                  !pcm.isEmpty else {
                return .ignored(type: type)
            }
            return .outputAudioDelta(pcm16Data: pcm)

        case "session.input_transcript.delta":
            let delta = obj["delta"] as? String ?? ""
            let startMs = (obj["start_ms"] as? NSNumber)?.intValue ?? 0
            let endMs = (obj["end_ms"] as? NSNumber)?.intValue ?? startMs
            return .inputTranscriptDelta(delta: delta, startMs: startMs, endMs: endMs)

        case "session.output_transcript.delta":
            let delta = obj["delta"] as? String ?? ""
            let startMs = (obj["start_ms"] as? NSNumber)?.intValue ?? 0
            let endMs = (obj["end_ms"] as? NSNumber)?.intValue ?? startMs
            return .outputTranscriptDelta(delta: delta, startMs: startMs, endMs: endMs)

        case "session.delegation.created":
            let delObj = obj["delegation"] as? [String: Any]
            let delId = delObj?["id"] as? String ?? ""
            let target = delObj?["target"] as? String ?? "client"
            let offsetMs = (obj["offset_ms"] as? NSNumber)?.intValue ?? 0
            guard !delId.isEmpty else { return .ignored(type: type) }
            return .delegationCreated(id: delId, target: target, offsetMs: offsetMs)

        case "session.input_audio.muted":
            return .inputAudioMuted(clientEventId: obj["client_event_id"] as? String)

        case "session.input_audio.unmuted":
            return .inputAudioUnmuted(clientEventId: obj["client_event_id"] as? String)

        case "session.thinking.appended", "session.commentary.appended", "session.instructions.appended":
            return .contextAppended(eventType: type, clientEventId: obj["client_event_id"] as? String)

        case "session.closed":
            return .sessionClosed

        case "error":
            let errDict = obj["error"] as? [String: Any]
            let code = errDict?["code"] as? String ?? obj["code"] as? String
            let msg = errDict?["message"] as? String ?? obj["message"] as? String ?? "Erro na sessão GPT-Live"
            return .error(code: code, message: msg)

        default:
            return .ignored(type: type)
        }
    }
}

// MARK: - Captura de Microfone Thread-Safe para PCM16LE 24kHz (Fora do MainActor)

#if os(iOS) || os(visionOS) || os(macOS)
private final class LiveAudioCaptureTapProcessor: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private let continuation: AsyncStream<(Data, Float)>.Continuation
    private var accumulatedPCM = Data()
    /// Envia pacotes de ~60 ms (1.440 amostras × 2 bytes = 2.880 bytes) para baixa latência de voz.
    private let flushThresholdBytes = 2_880

    init(
        inputFormat: AVAudioFormat,
        continuation: AsyncStream<(Data, Float)>.Continuation
    ) {
        let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(OpenAILiveProtocol.sampleRateHz),
            channels: 1,
            interleaved: true
        )!
        self.targetFormat = target
        self.converter = AVAudioConverter(from: inputFormat, to: target)
        self.continuation = continuation
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let rms = Self.computeNormalizedRMS(buffer)
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / max(1.0, buffer.format.sampleRate)
        let outCapacity = AVAudioFrameCount(max(64, Int(ceil(Double(buffer.frameLength) * ratio)) + 32))
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            return
        }

        final class OneShotBox: @unchecked Sendable {
            var consumed = false
            let source: AVAudioPCMBuffer
            init(_ source: AVAudioPCMBuffer) { self.source = source }
        }
        let box = OneShotBox(buffer)
        var convError: NSError?
        let status = converter.convert(to: outBuffer, error: &convError) { _, outStatus in
            if box.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            box.consumed = true
            outStatus.pointee = .haveData
            return box.source
        }

        guard status != .error, convError == nil, outBuffer.frameLength > 0,
              let int16Ptr = outBuffer.int16ChannelData?[0] else {
            return
        }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Ptr, count: byteCount)
        accumulatedPCM.append(data)

        if accumulatedPCM.count >= flushThresholdBytes {
            let chunk = accumulatedPCM
            accumulatedPCM.removeAll(keepingCapacity: true)
            continuation.yield((chunk, rms))
        }
    }

    func finish() {
        if !accumulatedPCM.isEmpty {
            continuation.yield((accumulatedPCM, 0))
            accumulatedPCM.removeAll()
        }
        continuation.finish()
    }

    private static func computeNormalizedRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        if let f32 = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count {
                let s = f32[i]
                sum += s * s
            }
            let rms = (sum / Float(count)).squareRoot()
            let db = 20 * log10(max(rms, 1e-7))
            return min(max((db + 50) / 50, 0), 1)
        }
        return 0
    }
}
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
    private var receiveTask: Task<Void, Never>?
    private var audioSendTask: Task<Void, Never>?
    private var speakingDecayTask: Task<Void, Never>?
    private var delegationTasks: [String: Task<Void, Never>] = [:]
    private var carryoverByte = Data()
    private var sessionReadyContinuation: CheckedContinuation<Bool, Never>?
    private var sessionClosedContinuation: CheckedContinuation<Void, Never>?

    // Agrupamento de transcrições full-duplex em bolhas do chat
    private var transcriptTimeline: [OpenAILiveTranscriptSegment] = []
    private var activeUserBubbleId: UUID?
    private var activeUserText: String = ""
    private var lastUserEndMs: Int = 0
    private var activeAssistantBubbleId: UUID?
    private var activeAssistantText: String = ""
    private var activeAssistantTools: [String] = []
    private var lastAssistantEndMs: Int = 0
    private var hasNewUserSpeechSinceAssistantDelta: Bool = false
    private var turnCount: Int = 0
    private var lastUserAudioInterruptAt: Date = .distantPast

    #if os(iOS) || os(visionOS) || os(macOS)
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var playbackFormat: AVAudioFormat?
    private var tapProcessor: LiveAudioCaptureTapProcessor?
    private var scheduledOutputBuffers: Int = 0
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
            try startFullDuplexAudioEngine()
        } catch {
            let msg = "Falha ao abrir áudio full-duplex: \(error.localizedDescription)"
            await stop()
            lastError = msg
            return false
        }
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

    // MARK: - WebSocket Loop & Tratamento de Eventos

    private func startReceiveLoop(for socket: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    let rawData: Data
                    switch message {
                    case .string(let text):
                        guard let d = text.data(using: .utf8) else { continue }
                        rawData = d
                    case .data(let d):
                        rawData = d
                    @unknown default:
                        continue
                    }

                    guard let parsed = OpenAILiveProtocol.parseServerEvent(rawData) else {
                        continue
                    }
                    self.handleServerEvent(parsed)
                    if parsed == .sessionClosed {
                        break
                    }
                }
            } catch {
                if self.isActive {
                    let msg = error.localizedDescription
                    self.lastError = msg
                    if !self.isConnected {
                        if let cont = self.sessionReadyContinuation {
                            self.sessionReadyContinuation = nil
                            cont.resume(returning: false)
                        }
                    } else {
                        self.onStartupFallbackNeeded?(msg)
                    }
                }
            }
        }
    }

    private func handleServerEvent(_ event: OpenAILiveServerEvent) {
        switch event {
        case .sessionStarted(let id):
            sessionId = id
            isConnected = true
            if let cont = sessionReadyContinuation {
                sessionReadyContinuation = nil
                cont.resume(returning: true)
            }

        case .outputAudioDelta(let pcm16Data):
            guard isActive, !isPaused else { return }
            scheduleOutputPCM16(pcm16Data)

        case .inputTranscriptDelta(let delta, let startMs, let endMs):
            guard isActive, !delta.isEmpty else { return }
            handleUserTranscriptDelta(delta, startMs: startMs, endMs: endMs)

        case .outputTranscriptDelta(let delta, let startMs, let endMs):
            guard isActive, !delta.isEmpty else { return }
            handleAssistantTranscriptDelta(delta, startMs: startMs, endMs: endMs)

        case .delegationCreated(let delegationId, _, let offsetMs):
            guard isActive else { return }
            handleClientDelegationCreated(delegationId: delegationId, offsetMs: offsetMs)

        case .sessionClosed:
            if let cont = sessionClosedContinuation {
                sessionClosedContinuation = nil
                cont.resume()
            }

        case .error(let code, let message):
            // Erros não-fatais de validação/append mantêm a sessão viva; erros antes de conectar liberam o start.
            if code != "responses_validation_failed" && !isConnected {
                lastError = message
                if let cont = sessionReadyContinuation {
                    sessionReadyContinuation = nil
                    cont.resume(returning: false)
                }
            } else {
                lastError = message
            }

        case .inputAudioMuted, .inputAudioUnmuted, .contextAppended, .ignored:
            break
        }
    }

    // MARK: - Transcrições Full-Duplex & Agrupamento em Bolhas

    private func handleUserTranscriptDelta(_ delta: String, startMs: Int, endMs: Int) {
        let shouldOpenNewUserBubble = activeUserBubbleId == nil
            || (!activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && startMs >= max(0, lastAssistantEndMs - 300) && (startMs - lastUserEndMs) > 1_400)

        if shouldOpenNewUserBubble {
            if let prevId = activeUserBubbleId, !activeUserText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onTranscriptBubbleUpdate?(.user, prevId, activeUserText.trimmingCharacters(in: .whitespacesAndNewlines), true, [])
            }
            activeUserBubbleId = UUID()
            activeUserText = ""
            turnCount += 1
        }

        activeUserText += delta
        lastUserEndMs = max(lastUserEndMs, endMs)
        hasNewUserSpeechSinceAssistantDelta = true
        appendToTimeline(role: .user, delta: delta, startMs: startMs, endMs: endMs)

        // Barge-in acústico natural: se o assistente tinha longa fila de áudio bufferizada e o usuário começou
        // uma fala substantiva nova (> 3 caracteres úteis), esvazia o buffer residual do alto-falante local.
        let trimmedDelta = delta.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDelta.count >= 3,
           activeAssistantText.count >= 24,
           Date().timeIntervalSince(lastUserAudioInterruptAt) > 1.0 {
            #if os(iOS) || os(visionOS) || os(macOS)
            if scheduledOutputBuffers > 1 {
                lastUserAudioInterruptAt = .now
                flushLocalPlayback()
            }
            #endif
        }

        if let uid = activeUserBubbleId {
            let display = activeUserText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                onTranscriptBubbleUpdate?(.user, uid, display, false, [])
                if activeDelegationCount == 0 {
                    emitPhaseUpdate(.listening, line: String(display.suffix(120)))
                }
            }
        }
    }

    private func handleAssistantTranscriptDelta(_ delta: String, startMs: Int, endMs: Int) {
        if activeAssistantBubbleId == nil || (hasNewUserSpeechSinceAssistantDelta && activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10) {
            if let prevUserId = activeUserBubbleId, !activeUserText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onTranscriptBubbleUpdate?(.user, prevUserId, activeUserText.trimmingCharacters(in: .whitespacesAndNewlines), true, [])
                activeUserBubbleId = nil
                activeUserText = ""
            }
            if let prevAssistantId = activeAssistantBubbleId, !activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onTranscriptBubbleUpdate?(.assistant, prevAssistantId, activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines), true, activeAssistantTools)
            }
            activeAssistantBubbleId = UUID()
            activeAssistantText = ""
            activeAssistantTools = []
        }

        hasNewUserSpeechSinceAssistantDelta = false
        activeAssistantText += delta
        lastAssistantEndMs = max(lastAssistantEndMs, endMs)
        appendToTimeline(role: .assistant, delta: delta, startMs: startMs, endMs: endMs)

        if let aid = activeAssistantBubbleId {
            let display = activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                onTranscriptBubbleUpdate?(.assistant, aid, display, false, activeAssistantTools)
                if !isPaused {
                    emitPhaseUpdate(.speaking, line: String(display.suffix(120)))
                }
            }
        }
    }

    private func appendToTimeline(role: MessageRole, delta: String, startMs: Int, endMs: Int) {
        if let lastIdx = transcriptTimeline.indices.last,
           transcriptTimeline[lastIdx].role == role,
           (startMs - transcriptTimeline[lastIdx].endMs) < 2_500 {
            transcriptTimeline[lastIdx].text += delta
            transcriptTimeline[lastIdx].endMs = max(transcriptTimeline[lastIdx].endMs, endMs)
        } else {
            transcriptTimeline.append(
                OpenAILiveTranscriptSegment(role: role, text: delta, startMs: startMs, endMs: endMs)
            )
            if transcriptTimeline.count > 40 {
                transcriptTimeline.removeFirst(transcriptTimeline.count - 40)
            }
        }
    }

    private func finalizeOpenBubblesIfNeeded() {
        if let uid = activeUserBubbleId {
            let trimmed = activeUserText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                onTranscriptBubbleUpdate?(.user, uid, trimmed, true, [])
            }
        }
        if let aid = activeAssistantBubbleId {
            let trimmed = activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                onTranscriptBubbleUpdate?(.assistant, aid, trimmed, true, activeAssistantTools)
            }
        }
        resetBubbleTrackers()
    }

    private func resetBubbleTrackers() {
        activeUserBubbleId = nil
        activeUserText = ""
        lastUserEndMs = 0
        activeAssistantBubbleId = nil
        activeAssistantText = ""
        activeAssistantTools = []
        lastAssistantEndMs = 0
        hasNewUserSpeechSinceAssistantDelta = false
    }

    // MARK: - Client Delegation (`session.delegation.created` → MoE / Bula / MCP / Apple Tools)

    private func handleClientDelegationCreated(delegationId: String, offsetMs: Int) {
        guard let delegateHandler = onDelegateToBackend else { return }

        let window: [(role: String, text: String)] = transcriptTimeline.suffix(16).compactMap { seg in
            let clean = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            return (role: seg.role == .user ? "user" : "assistant", text: clean)
        }
        let latestUser = transcriptTimeline.last(where: {
            $0.role == .user && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? activeUserText.trimmingCharacters(in: .whitespacesAndNewlines)

        let context = OpenAILiveDelegationContext(
            delegationId: delegationId,
            offsetMs: offsetMs,
            transcriptWindow: window,
            latestUserUtterance: latestUser
        )

        activeDelegationCount += 1
        emitPhaseUpdate(.thinking, line: "MoE · consultando exocórtex, Bula & ferramentas…")

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.delegationTasks.removeValue(forKey: delegationId)
                self.activeDelegationCount = max(0, self.activeDelegationCount - 1)
                if self.isActive && !self.isPaused && self.activeDelegationCount == 0 {
                    #if os(iOS) || os(visionOS) || os(macOS)
                    let speakingNow = self.scheduledOutputBuffers > 0
                    #else
                    let speakingNow = false
                    #endif
                    if !speakingNow {
                        self.emitPhaseUpdate(.listening, line: CompanionLiveVoicePhase.listening.defaultLinePtBR)
                    }
                }
            }

            if let progressPayload = OpenAILiveProtocol.buildContextAppendPayload(
                kind: .thinking,
                delegationId: delegationId,
                content: "Consultando o cérebro MoE do Beagle, memória GraphRAG++, Bula/PCDT e ferramentas nativas em segundo plano."
            ) {
                _ = await self.sendJSON(progressPayload)
            }

            let outcome = await delegateHandler(context)
            guard !Task.isCancelled, self.isActive else { return }

            if !outcome.executedTools.isEmpty {
                for tool in outcome.executedTools where !self.activeAssistantTools.contains(tool) {
                    self.activeAssistantTools.append(tool)
                }
                if let aid = self.activeAssistantBubbleId {
                    let display = self.activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !display.isEmpty {
                        self.onTranscriptBubbleUpdate?(.assistant, aid, display, false, self.activeAssistantTools)
                    }
                }
            }

            if let facts = outcome.backgroundFacts, !facts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let thinkingPayload = OpenAILiveProtocol.buildContextAppendPayload(
                   kind: .thinking,
                   delegationId: delegationId,
                   content: facts
               ) {
                _ = await self.sendJSON(thinkingPayload)
            }

            if let commentaryPayload = OpenAILiveProtocol.buildContextAppendPayload(
                kind: .commentary,
                delegationId: delegationId,
                content: outcome.spokenSummary
            ) {
                _ = await self.sendJSON(commentaryPayload)
            }
        }
        delegationTasks[delegationId] = task
    }

    /// Injeta assincronamente na sessão `gpt-live-1.1` o resultado de uma pesquisa profunda
    /// (`Modo Fundo`, `GPT-Rosalind` ou `Síntese Matinal`) iniciada em segundo plano durante a conversa por voz.
    public func pushAsyncFollowup(
        spokenSummary: String,
        backgroundFacts: String? = nil,
        executedTools: [String] = []
    ) async {
        guard isActive, isConnected else { return }

        if !executedTools.isEmpty {
            for tool in executedTools where !activeAssistantTools.contains(tool) {
                activeAssistantTools.append(tool)
            }
        }

        if let facts = backgroundFacts,
           !facts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let thinkingPayload = OpenAILiveProtocol.buildContextAppendPayload(
               kind: .thinking,
               delegationId: nil,
               content: OpenAILiveProtocol.truncateForLiveAppend(facts, maxChars: 1_400)
           ) {
            _ = await sendJSON(thinkingPayload)
        }

        let cleanSpoken = OpenAILiveProtocol.truncateForLiveAppend(spokenSummary, maxChars: 1_200)
        guard !cleanSpoken.isEmpty else { return }
        if let commentaryPayload = OpenAILiveProtocol.buildContextAppendPayload(
            kind: .commentary,
            delegationId: nil,
            content: cleanSpoken
        ) {
            _ = await sendJSON(commentaryPayload)
        }
    }

    private func emitPhaseUpdate(_ phase: CompanionLiveVoicePhase, line: String) {
        onStateChanged?(phase, turnCount, line)
    }

    private func sendJSON(_ dict: [String: Any]) async -> Bool {
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

    // MARK: - Grafo de Áudio Full-Duplex (`AVAudioEngine` + Cancelamento de Eco `.voiceChat`)

    #if os(iOS) || os(visionOS) || os(macOS)
    private static func requestMicrophonePermission() async -> Bool {
        #if os(iOS) || os(visionOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
        #endif
    }

    private func startFullDuplexAudioEngine() throws {
        stopFullDuplexAudioEngine()

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers]
        )
        try? audioSession.setPreferredSampleRate(Double(OpenAILiveProtocol.sampleRateHz))
        try? audioSession.setPreferredIOBufferDuration(0.02)
        try audioSession.setActive(true)
        #elseif os(visionOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.duckOthers]
        )
        try? audioSession.setPreferredSampleRate(Double(OpenAILiveProtocol.sampleRateHz))
        try audioSession.setActive(true)
        #endif

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(OpenAILiveProtocol.sampleRateHz),
            channels: 1,
            interleaved: false
        )!

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outFormat)

        let inputNode = engine.inputNode
        let hwInputFormat = inputNode.outputFormat(forBus: 0)

        var streamContinuation: AsyncStream<(Data, Float)>.Continuation!
        let captureStream = AsyncStream<(Data, Float)> { continuation in
            streamContinuation = continuation
        }

        let processor = LiveAudioCaptureTapProcessor(
            inputFormat: hwInputFormat,
            continuation: streamContinuation
        )
        self.tapProcessor = processor

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: hwInputFormat) { buffer, _ in
            processor.process(buffer)
        }

        engine.prepare()
        try engine.start()
        player.play()

        self.audioEngine = engine
        self.playerNode = player
        self.playbackFormat = outFormat
        self.scheduledOutputBuffers = 0

        audioSendTask = Task { @MainActor [weak self] in
            for await (pcm16Chunk, rms) in captureStream {
                guard let self, self.isActive else { break }
                self.inputLevel = self.inputLevel * 0.65 + rms * 0.35
                guard self.isConnected, !self.isPaused else { continue }
                if let payload = OpenAILiveProtocol.buildInputAudioAppendPayload(
                    chunk: pcm16Chunk,
                    carryoverByte: &self.carryoverByte
                ) {
                    _ = await self.sendJSON(payload)
                }
            }
        }
    }

    private func scheduleOutputPCM16(_ pcm16Data: Data) {
        guard let player = playerNode,
              let format = playbackFormat,
              let engine = audioEngine,
              engine.isRunning else {
            return
        }

        let sampleCount = pcm16Data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)),
              let dst = pcmBuffer.floatChannelData?[0] else {
            return
        }

        pcmBuffer.frameLength = AVAudioFrameCount(sampleCount)
        var sumSquares: Float = 0
        pcm16Data.withUnsafeBytes { rawBuf in
            guard let int16Base = rawBuf.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<sampleCount {
                let sample = Int16(littleEndian: int16Base[i])
                let normalized = Float(sample) / 32768.0
                dst[i] = normalized
                sumSquares += normalized * normalized
            }
        }

        let rms = (sumSquares / Float(sampleCount)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        outputLevel = min(max((db + 50) / 50, 0), 1)

        speakingDecayTask?.cancel()
        scheduledOutputBuffers += 1
        if !player.isPlaying {
            player.play()
        }
        if !isPaused && activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emitPhaseUpdate(.speaking, line: CompanionLiveVoicePhase.speaking.defaultLinePtBR)
        }

        player.scheduleBuffer(pcmBuffer) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleScheduledOutputBufferFinished()
            }
        }
    }

    private func handleScheduledOutputBufferFinished() {
        scheduledOutputBuffers = max(0, scheduledOutputBuffers - 1)
        guard scheduledOutputBuffers == 0 else { return }
        outputLevel = 0
        speakingDecayTask?.cancel()
        speakingDecayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard let self,
                  !Task.isCancelled,
                  self.isActive,
                  !self.isPaused,
                  self.scheduledOutputBuffers == 0 else { return }
            if self.activeDelegationCount > 0 {
                self.emitPhaseUpdate(.thinking, line: "MoE · consultando exocórtex, Bula & ferramentas…")
            } else {
                self.emitPhaseUpdate(.listening, line: CompanionLiveVoicePhase.listening.defaultLinePtBR)
            }
        }
    }

    private func flushLocalPlayback() {
        speakingDecayTask?.cancel()
        speakingDecayTask = nil
        scheduledOutputBuffers = 0
        outputLevel = 0
        guard let player = playerNode, let engine = audioEngine, engine.isRunning else { return }
        player.stop()
        player.play()
    }

    private func stopFullDuplexAudioEngine() {
        speakingDecayTask?.cancel()
        speakingDecayTask = nil
        scheduledOutputBuffers = 0
        tapProcessor?.finish()
        tapProcessor = nil

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            playerNode?.stop()
            engine.stop()
        }
        playerNode = nil
        playbackFormat = nil
        audioEngine = nil

        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    #else
    private func scheduleOutputPCM16(_ pcm16Data: Data) {}
    private func flushLocalPlayback() {}
    #endif
}
