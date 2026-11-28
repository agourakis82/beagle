//
//  CompanionVoice.swift
//  BeagleCore — a boca dele, do lado do aparelho (multi-motor: OpenAI Realtime TTS 2.1 Mini pt-BR, Cluster xAI, Neural Offline)
//
//  Roteamento resiliente em 3 camadas (arquitetura de Áudio OpenAI 2026/2027):
//    1. OpenAI Realtime TTS GA (`gpt-realtime-2.1-mini` via `wss://api.openai.com/v1/realtime`,
//       substituindo `gpt-4o-mini-tts` antes do desligamento em 06/01/2027, voz padrão `marin`, PCM16 24kHz → WAV)
//    2. Cluster Beagle (`/api/mobile/v1/companion/voice`, WAV xAI quando na Tailnet/online)
//    3. On-Device Neural (`AVSpeechSynthesizer` com voz `pt-BR` Premium/Enhanced, 100% offline no hospital)
//
//  AVAudioPlayer / AVSpeechSynthesizer, nunca AVAudioEngine para leitura avulsa: tocar áudio pronto
//  ou síntese nativa não disputa o grafo de captura do microfone quando `AVAudioSession` é devolvida ao terminar.
//

import Foundation
import Observation
#if canImport(AVFoundation)
import AVFoundation
#endif

public enum CompanionVoiceEnginePreference: String, CaseIterable, Sendable, Identifiable {
    case auto = "auto"
    case openAI = "openai"
    case cluster = "cluster"
    case appleOffline = "apple-offline"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: return "Automático (Realtime 2.1 → Cluster → Offline)"
        case .openAI: return "OpenAI Realtime TTS (gpt-realtime-2.1-mini · pt-BR)"
        case .cluster: return "Cluster Beagle (xAI)"
        case .appleOffline: return "100% Offline no Aparelho (Neural pt-BR)"
        }
    }
}

public enum CompanionAutoSpeakMode: String, CaseIterable, Sendable, Identifiable {
    case whenSpoken = "when-spoken"
    case always = "always"
    case manual = "manual"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .whenSpoken: return "Ao falar no microfone"
        case .always: return "Sempre falar respostas (Mãos-livres)"
        case .manual: return "Apenas manual (botão Ouvir)"
        }
    }
}

public enum CompanionVoiceActiveBackend: String, Sendable {
    case openAI = "OpenAI Realtime"
    case cluster = "Cluster"
    case neuralOffline = "Offline"
}

@Observable
@MainActor
public final class CompanionVoice: NSObject {
    nonisolated public static let enginePreferenceKey = "beagle.voice.enginePreference"
    nonisolated public static let openAIVoiceKey = "beagle.voice.openAIVoice"
    nonisolated public static let autoSpeakModeKey = "beagle.voice.autoSpeakMode"
    nonisolated public static let realtimeTTSModel = "gpt-realtime-2.1-mini"

    /// Vozes suportadas pelo endpoint GA Realtime (`gpt-realtime-2.1` / `gpt-realtime-2.1-mini`).
    nonisolated public static let supportedRealtimeVoices: Set<String> = [
        "marin", "cedar", "ash", "sage", "coral", "echo", "verse", "alloy", "ballad", "shimmer"
    ]

    /// Vozes adicionais nativas do `gpt-live-1.1` (incluindo `bossa` e `tempo` naturais em português do Brasil).
    nonisolated public static let supportedLiveVoices: Set<String> = supportedRealtimeVoices.union([
        "tempo", "bossa", "pearl", "quartz", "ripple", "halo", "vesper", "willow", "stone", "gleam", "meridian"
    ])

    public static var enginePreference: CompanionVoiceEnginePreference {
        get {
            let raw = UserDefaults.standard.string(forKey: enginePreferenceKey) ?? "auto"
            return CompanionVoiceEnginePreference(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: enginePreferenceKey)
        }
    }

    public static var openAIVoice: String {
        get {
            let raw = UserDefaults.standard.string(forKey: openAIVoiceKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            return raw.isEmpty ? "marin" : raw
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), forKey: openAIVoiceKey)
        }
    }

    /// Normaliza um identificador de voz para sessões `gpt-live-1.1` (suporta `marin`, `cedar`, `tempo` pt-BR, `bossa` pt-BR etc.).
    nonisolated public static func normalizedLiveVoice(_ raw: String) -> String {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if candidate.isEmpty { return "marin" }
        if candidate == "onyx" { return "cedar" }
        if candidate == "nova" || candidate == "fable" { return "marin" }
        return supportedLiveVoices.contains(candidate) ? candidate : "marin"
    }

    /// Normaliza um identificador de voz para o `gpt-realtime-2.1-mini` (mapeando vozes exclusivas do Live ou legadas do `/v1/audio/speech`).
    nonisolated public static func normalizedRealtimeTTSVoice(_ raw: String) -> String {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if candidate.isEmpty { return "marin" }
        switch candidate {
        case "tempo", "onyx", "stone", "meridian", "vesper":
            return "cedar"
        case "bossa", "nova", "fable", "pearl", "gleam":
            return "marin"
        default:
            return supportedRealtimeVoices.contains(candidate) ? candidate : "marin"
        }
    }

    public static var autoSpeakMode: CompanionAutoSpeakMode {
        get {
            let raw = UserDefaults.standard.string(forKey: autoSpeakModeKey) ?? CompanionAutoSpeakMode.whenSpoken.rawValue
            return CompanionAutoSpeakMode(rawValue: raw) ?? .whenSpoken
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: autoSpeakModeKey)
        }
    }

    public private(set) var buscando: Bool = false
    public private(set) var buscandoId: String?
    public private(set) var falandoId: String?
    public private(set) var motorAtivo: CompanionVoiceActiveBackend?
    public private(set) var recusa: String?

    public var estaAtivo: Bool { buscando || falandoId != nil }

    private let client: BeagleClient
    private let urlSession: URLSession
    private var speechTask: Task<Void, Never>?
    private var turnGeneration: UInt64 = 0
    @ObservationIgnored private var audioSessionAtiva: Bool = false

    #if os(iOS) || os(visionOS) || os(macOS)
    private var player: AVAudioPlayer?
    private var playerContinuation: CheckedContinuation<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()
    private var synthContinuation: CheckedContinuation<Void, Never>?
    #endif

    public init(client: BeagleClient = .shared, session: URLSession = .shared) {
        self.client = client
        self.urlSession = session
        super.init()
        #if os(iOS) || os(visionOS) || os(macOS)
        self.synthesizer.delegate = self
        #endif
    }

    public func estaFalando(_ id: String) -> Bool { falandoId == id }
    public func estaBuscando(_ id: String) -> Bool { buscando && buscandoId == id }

    // MARK: - Higienização & Fatiamento para Fala Natural

    /// Remove o bloco de raciocínio interno acima de `---`, blocos de código extensos e marcações Markdown
    /// para que a síntese vocal leia apenas a fala humana limpa.
    nonisolated public static func prepararTextoParaFala(_ raw: String) -> String {
        var body = raw
        if let r = body.range(of: "\n---\n") ?? body.range(of: "\n---") {
            let before = body[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let after = body[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let looksLikeNote = ["nota", "pergunta viva", "interpretação", "próximo movimento", "abana"]
                .contains { before.range(of: $0, options: .caseInsensitive) != nil }
            if !after.isEmpty && looksLikeNote {
                body = String(after)
            }
        }

        // Substitui blocos de código cercados por aviso curto falado
        body = body.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: " Deixei o trecho de código escrito na mensagem. ",
            options: .regularExpression
        )
        // Links Markdown [texto](url) -> texto
        body = body.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^\\)]+\\)",
            with: "$1",
            options: .regularExpression
        )
        // Cabeçalhos Markdown, negrito, código inline e divisórias
        body = body.replacingOccurrences(
            of: "(?m)^\\s*#{1,6}\\s*",
            with: "",
            options: .regularExpression
        )
        body = body.replacingOccurrences(
            of: "(?m)^\\s*[-*•]\\s+",
            with: "",
            options: .regularExpression
        )
        body = body.replacingOccurrences(of: "**", with: "")
        body = body.replacingOccurrences(of: "__", with: "")
        body = body.replacingOccurrences(of: "`", with: "")
        body = body.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fatia textos longos respeitando parágrafos e frases para síntese fluida em blocos de baixa latência.
    nonisolated public static func fatiarEmBlocosDeFala(_ texto: String, limite: Int = 2400) -> [String] {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return [] }
        guard limpo.count > limite else { return [limpo] }

        var blocos: [String] = []
        var restante = limpo[...]

        while !restante.isEmpty {
            if restante.count <= limite {
                let final = restante.trimmingCharacters(in: .whitespacesAndNewlines)
                if !final.isEmpty { blocos.append(final) }
                break
            }
            let janelaFim = restante.index(restante.startIndex, offsetBy: limite)
            let fatia = restante[..<janelaFim]
            let pontoCorte = fatia.range(of: "\n\n", options: .backwards)?.lowerBound
                ?? fatia.range(of: "\n", options: .backwards)?.lowerBound
                ?? fatia.range(of: ". ", options: .backwards)?.upperBound
                ?? fatia.range(of: "! ", options: .backwards)?.upperBound
                ?? fatia.range(of: "? ", options: .backwards)?.upperBound
                ?? fatia.range(of: " ", options: .backwards)?.lowerBound
                ?? janelaFim

            let pedaco = restante[..<pontoCorte].trimmingCharacters(in: .whitespacesAndNewlines)
            if !pedaco.isEmpty {
                blocos.append(pedaco)
            }
            restante = restante[pontoCorte...].drop(while: { $0.isWhitespace || $0.isNewline })
        }
        return blocos
    }

    // MARK: - Encapsulamento PCM16LE 24kHz → RIFF/WAVE e Protocolo Realtime GA

    /// Encapsula amostras cruas PCM16 little-endian mono (24 kHz padrão OpenAI Realtime/Live) em um contêiner RIFF/WAVE de 44 bytes.
    nonisolated public static func encapsularPCM16EmWAV(
        _ pcmData: Data,
        sampleRate: UInt32 = 24_000,
        channels: UInt16 = 1,
        bitsPerSample: UInt16 = 16
    ) -> Data {
        let bytesPerSample = Int(channels) * Int(bitsPerSample / 8)
        let alignedCount = bytesPerSample > 0 ? (pcmData.count - (pcmData.count % bytesPerSample)) : pcmData.count
        guard alignedCount > 0 else { return Data() }

        let payload = pcmData.prefix(alignedCount)
        let dataSize = UInt32(clamping: payload.count)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let riffChunkSize = 36 &+ dataSize

        var wav = Data(capacity: 44 + payload.count)
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        wav.appendLittleEndian(riffChunkSize)
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        wav.appendLittleEndian(UInt32(16))               // Subchunk1Size (PCM)
        wav.appendLittleEndian(UInt16(1))                // AudioFormat = 1 (PCM)
        wav.appendLittleEndian(channels)
        wav.appendLittleEndian(sampleRate)
        wav.appendLittleEndian(byteRate)
        wav.appendLittleEndian(blockAlign)
        wav.appendLittleEndian(bitsPerSample)
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wav.appendLittleEndian(dataSize)
        wav.append(payload)
        return wav
    }

    /// Monta o evento GA `session.update` para `gpt-realtime-2.1-mini` (sem cabeçalho beta, `output_modalities: ["audio"]`).
    nonisolated public static func realtimeSessionUpdatePayload(voice: String, eventId: String = "beagle_tts_cfg") -> [String: Any] {
        let resolvedVoice = normalizedRealtimeTTSVoice(voice)
        return [
            "type": "session.update",
            "event_id": eventId,
            "session": [
                "type": "realtime",
                "output_modalities": ["audio"],
                "audio": [
                    "output": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000
                        ],
                        "voice": resolvedVoice
                    ]
                ]
            ]
        ]
    }

    /// Monta o evento out-of-band `response.create` (`conversation: "none"`) para síntese vocal fiel de `texto` em `pt-BR`.
    nonisolated public static func realtimeSpeechResponsePayload(texto: String, eventId: String = "beagle_tts_speak") -> [String: Any] {
        [
            "type": "response.create",
            "event_id": eventId,
            "response": [
                "conversation": "none",
                "output_modalities": ["audio"],
                "instructions": """
                Você é o motor de leitura vocal em português do Brasil do Beagle.
                Leia EXATAMENTE e na íntegra o texto da mensagem do usuário, palavra por palavra, sem acrescentar saudações, introduções, comentários nem omissões.
                Fale em português do Brasil natural, caloroso, íntimo e sereno, como um grande amigo médico e cientista conversando de perto, com pausas naturais e sem tom artificial de locutor.
                """,
                "input": [
                    [
                        "type": "message",
                        "role": "user",
                        "content": [
                            [
                                "type": "input_text",
                                "text": texto
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Controle Principal

    /// Vocaliza `texto` usando a cadeia configurada (OpenAI Realtime 2.1 Mini → Cluster → Neural Offline).
    public func falar(_ texto: String, id: String) async {
        let limpo = Self.prepararTextoParaFala(texto)
        guard !limpo.isEmpty else { return }

        parar()
        turnGeneration &+= 1
        let gen = turnGeneration
        recusa = nil
        buscando = true
        buscandoId = id

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.executarFala(textoLimpo: limpo, id: id, generation: gen)
        }
        speechTask = task
        await task.value
    }

    public func parar() {
        turnGeneration &+= 1
        speechTask?.cancel()
        speechTask = nil
        buscando = false
        buscandoId = nil
        falandoId = nil
        motorAtivo = nil

        #if os(iOS) || os(visionOS) || os(macOS)
        player?.stop()
        player = nil
        if let cont = playerContinuation {
            playerContinuation = nil
            cont.resume()
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if let cont = synthContinuation {
            synthContinuation = nil
            cont.resume()
        }
        #endif

        desativarSessaoDeAudio()
    }

    // MARK: - Pipeline de Síntese e Reprodução

    private func executarFala(textoLimpo: String, id: String, generation: UInt64) async {
        let pref = Self.enginePreference
        let online = NetworkMonitor.shared.isOnline
        let hasOpenAI = DirectBrainCredentials.hasOpenAI

        switch pref {
        case .appleOffline:
            buscando = false
            buscandoId = nil
            await falarComNeuralOffline(textoLimpo, id: id, generation: generation)
            return

        case .openAI:
            if hasOpenAI && online {
                if await falarComOpenAITTS(textoLimpo, id: id, generation: generation) { return }
            }
            guard estaValido(generation) else { return }
            buscando = false
            buscandoId = nil
            await falarComNeuralOffline(textoLimpo, id: id, generation: generation)
            return

        case .cluster:
            if online {
                if await falarComCluster(textoLimpo, id: id, generation: generation) { return }
                guard estaValido(generation) else { return }
                if hasOpenAI, await falarComOpenAITTS(textoLimpo, id: id, generation: generation) { return }
            }
            guard estaValido(generation) else { return }
            buscando = false
            buscandoId = nil
            await falarComNeuralOffline(textoLimpo, id: id, generation: generation)
            return

        case .auto:
            if hasOpenAI && online {
                if await falarComOpenAITTS(textoLimpo, id: id, generation: generation) { return }
            }
            guard estaValido(generation) else { return }
            if online {
                if await falarComCluster(textoLimpo, id: id, generation: generation) { return }
            }
            guard estaValido(generation) else { return }
            buscando = false
            buscandoId = nil
            await falarComNeuralOffline(textoLimpo, id: id, generation: generation)
        }
    }

    private func estaValido(_ generation: UInt64) -> Bool {
        !Task.isCancelled && turnGeneration == generation
    }

    private func falarComOpenAITTS(_ texto: String, id: String, generation: UInt64) async -> Bool {
        let apiKey = DirectBrainCredentials.openAIKey
        guard !apiKey.isEmpty else { return false }
        let blocos = Self.fatiarEmBlocosDeFala(texto, limite: 2400)
        guard !blocos.isEmpty else { return false }

        let voice = Self.openAIVoice
        var proximoFetch: Task<Data?, Never>? = Task { [urlSession] in
            await Self.requisitarAudioOpenAI(
                session: urlSession,
                apiKey: apiKey,
                voice: voice,
                texto: blocos[0]
            )
        }

        for indice in blocos.indices {
            guard estaValido(generation) else {
                proximoFetch?.cancel()
                return true
            }
            guard let audioAtual = await proximoFetch?.value, !audioAtual.isEmpty else {
                proximoFetch?.cancel()
                return indice > 0
            }
            guard estaValido(generation) else { return true }

            // Pré-carrega o próximo bloco via gpt-realtime-2.1-mini enquanto o atual está tocando
            if indice + 1 < blocos.count {
                let proximoTexto = blocos[indice + 1]
                proximoFetch = Task { [urlSession] in
                    await Self.requisitarAudioOpenAI(
                        session: urlSession,
                        apiKey: apiKey,
                        voice: voice,
                        texto: proximoTexto
                    )
                }
            } else {
                proximoFetch = nil
            }

            buscando = false
            buscandoId = nil
            motorAtivo = .openAI
            let tocou = await reproduzirDadosDeAudio(audioAtual, id: id, generation: generation)
            if !tocou {
                proximoFetch?.cancel()
                return false
            }
        }

        if estaValido(generation) {
            limparEstadoAoTerminar()
        }
        return true
    }

    /// Síntese vocal GA via `gpt-realtime-2.1-mini` (`wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1-mini`),
    /// substituindo o antigo `/v1/audio/speech` (`gpt-4o-mini-tts`). Retorna áudio WAV 24 kHz mono pronto para `AVAudioPlayer`.
    nonisolated public static func requisitarAudioOpenAI(
        session: URLSession,
        apiKey: String,
        voice: String,
        texto: String,
        timeoutSeconds: Double = 24
    ) async -> Data? {
        let trimmed = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !trimmed.isEmpty else { return nil }
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(realtimeTTSModel)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let wsTask = session.webSocketTask(with: request)
        wsTask.maximumMessageSize = 8 * 1024 * 1024
        wsTask.resume()

        let result: Data? = await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                await executarFluxoRealtimeTTS(wsTask: wsTask, voice: voice, texto: trimmed)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        wsTask.cancel(with: .normalClosure, reason: nil)
        return result
    }

    nonisolated private static func executarFluxoRealtimeTTS(
        wsTask: URLSessionWebSocketTask,
        voice: String,
        texto: String
    ) async -> Data? {
        var sentSessionUpdate = false
        var sentResponseCreate = false
        var pcmBuffer = Data()

        do {
            while !Task.isCancelled {
                let message = try await wsTask.receive()
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

                guard let json = try JSONSerialization.jsonObject(with: rawData) as? [String: Any],
                      let eventType = json["type"] as? String else {
                    continue
                }

                switch eventType {
                case "session.created":
                    guard !sentSessionUpdate else { continue }
                    sentSessionUpdate = true
                    let updatePayload = realtimeSessionUpdatePayload(voice: voice)
                    let encoded = try JSONSerialization.data(withJSONObject: updatePayload)
                    guard let str = String(data: encoded, encoding: .utf8) else { return nil }
                    try await wsTask.send(.string(str))

                case "session.updated":
                    guard !sentResponseCreate else { continue }
                    sentResponseCreate = true
                    let createPayload = realtimeSpeechResponsePayload(texto: texto)
                    let encoded = try JSONSerialization.data(withJSONObject: createPayload)
                    guard let str = String(data: encoded, encoding: .utf8) else { return nil }
                    try await wsTask.send(.string(str))

                case "response.output_audio.delta":
                    if let deltaBase64 = json["delta"] as? String,
                       let chunk = Data(base64Encoded: deltaBase64),
                       !chunk.isEmpty {
                        pcmBuffer.append(chunk)
                    }

                case "response.done":
                    if let responseObj = json["response"] as? [String: Any],
                       let status = responseObj["status"] as? String,
                       status != "completed",
                       pcmBuffer.isEmpty {
                        return nil
                    }
                    let wav = encapsularPCM16EmWAV(pcmBuffer, sampleRate: 24_000)
                    return wav.isEmpty ? nil : wav

                case "error":
                    return pcmBuffer.isEmpty ? nil : encapsularPCM16EmWAV(pcmBuffer, sampleRate: 24_000)

                default:
                    continue
                }
            }
        } catch {
            if !pcmBuffer.isEmpty {
                let wav = encapsularPCM16EmWAV(pcmBuffer, sampleRate: 24_000)
                return wav.isEmpty ? nil : wav
            }
            return nil
        }

        return nil
    }

    private func falarComCluster(_ texto: String, id: String, generation: UInt64) async -> Bool {
        let clientRef = client
        let wav: Data? = await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                let res = await clientRef.companionVoice(text: texto)
                return res.value
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(12))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard estaValido(generation) else { return true }
        guard let wav, !wav.isEmpty else { return false }

        buscando = false
        buscandoId = nil
        motorAtivo = .cluster
        let ok = await reproduzirDadosDeAudio(wav, id: id, generation: generation)
        if ok && estaValido(generation) {
            limparEstadoAoTerminar()
        }
        return ok
    }

    private func reproduzirDadosDeAudio(_ dados: Data, id: String, generation: UInt64) async -> Bool {
        #if os(iOS) || os(visionOS) || os(macOS)
        guard estaValido(generation) else { return false }
        do {
            await ativarSessaoDeAudio()
            guard estaValido(generation) else {
                desativarSessaoDeAudio()
                return false
            }
            let p = try AVAudioPlayer(data: dados)
            p.delegate = self
            guard p.prepareToPlay(), p.play() else {
                desativarSessaoDeAudio()
                return false
            }
            player = p
            falandoId = id
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.playerContinuation = continuation
            }
            return true
        } catch {
            desativarSessaoDeAudio()
            recusa = error.localizedDescription
            return false
        }
        #else
        recusa = "sem sessão de áudio nesta plataforma"
        return false
        #endif
    }

    private func falarComNeuralOffline(_ texto: String, id: String, generation: UInt64) async {
        #if os(iOS) || os(visionOS) || os(macOS)
        guard estaValido(generation) else { return }
        await ativarSessaoDeAudio()
        guard estaValido(generation) else {
            desativarSessaoDeAudio()
            return
        }
        motorAtivo = .neuralOffline
        falandoId = id

        let utterance = AVSpeechUtterance(string: texto)
        utterance.voice = Self.melhorVozPortuguesBrasil()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        utterance.pitchMultiplier = 0.98
        utterance.postUtteranceDelay = 0.05

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.synthContinuation = continuation
            self.synthesizer.speak(utterance)
        }

        if estaValido(generation) {
            limparEstadoAoTerminar()
        }
        #else
        recusa = "síntese offline indisponível nesta plataforma"
        #endif
    }

    #if os(iOS) || os(visionOS) || os(macOS)
    private static func melhorVozPortuguesBrasil() -> AVSpeechSynthesisVoice? {
        let vozes = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("pt-br")
        }
        if let premium = vozes.sorted(by: { $0.quality.rawValue > $1.quality.rawValue }).first {
            return premium
        }
        return AVSpeechSynthesisVoice(language: "pt-BR")
    }
    #endif

    private func ativarSessaoDeAudio() async {
        #if os(iOS) || os(visionOS)
        audioSessionAtiva = true
        await BeagleAudioSessionCoordinator.shared.activatePlayback()
        #endif
    }

    private func desativarSessaoDeAudio() {
        #if os(iOS) || os(visionOS)
        guard audioSessionAtiva else { return }
        audioSessionAtiva = false
        Task.detached(priority: .utility) {
            await BeagleAudioSessionCoordinator.shared.deactivate()
        }
        #endif
    }

    private func limparEstadoAoTerminar() {
        buscando = false
        buscandoId = nil
        falandoId = nil
        motorAtivo = nil
        desativarSessaoDeAudio()
    }

    fileprivate func notificarFimDoPlayer() {
        #if os(iOS) || os(visionOS) || os(macOS)
        player = nil
        if let cont = playerContinuation {
            playerContinuation = nil
            cont.resume()
        }
        #endif
    }

    fileprivate func notificarFimDoSynthesizer() {
        #if os(iOS) || os(visionOS) || os(macOS)
        if let cont = synthContinuation {
            synthContinuation = nil
            cont.resume()
        }
        #endif
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

#if os(iOS) || os(visionOS) || os(macOS)
extension CompanionVoice: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.notificarFimDoPlayer()
        }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in
            self?.notificarFimDoPlayer()
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.notificarFimDoSynthesizer()
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.notificarFimDoSynthesizer()
        }
    }
}
#endif
