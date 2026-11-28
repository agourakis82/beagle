//
//  OpenAILiveProtocol.swift
//  BeagleCore — Codec e construtores de payload do protocolo GPT-Live (`gpt-live-1.1`)
//

import Foundation

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
        - Grok Bot Bridge (`delegate_to_grok_bot`): envia tarefas, automações e pesquisas assíncronas para rotinas do Grok Bot na nuvem via Webhook autenticado.

        Delegate to the backend when:
        - O usuário pedir informações clínicas, doses, bulas, interações, protocolos médicos, papers científicos, notícias ou dados atuais da web.
        - O usuário perguntar sobre memórias pessoais, projetos, status do cluster, compromissos na agenda, lembretes ou métricas fisiológicas.
        - O usuário pedir para enviar, delegar ou disparar uma tarefa, automação ou pesquisa no Grok Bot.
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
