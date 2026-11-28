//
//  CompanionVoice+AudioFormatting.swift
//  BeagleCore
//
//  Speech text sanitization, sentence chunking, PCM16LE-to-WAV RIFF encapsulation,
//  and OpenAI Realtime GA payload builders for CompanionVoice.
//

import Foundation

extension CompanionVoice {
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

