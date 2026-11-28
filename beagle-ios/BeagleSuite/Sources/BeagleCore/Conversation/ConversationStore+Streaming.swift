//
//  ConversationStore+Streaming.swift
//  BeagleCore
//
//  Auto-routing (Fast Foundation Models, Local MLX, Direct Brain / MoE, Cloud SSE stream)
//  and typing reveal for ConversationStore.
//

import Foundation

@MainActor
extension ConversationStore {

    /// Friendly voice name for the Live Activity — mirrors ChatDepth's labels (BeagleCockpit layer,
    /// not importable from here) so the lock screen says "Sonnet 5" instead of "claude-sonnet-5".
    private func voiceLabel(for model: String?) -> String {
        if let friendly = OpenAIModelCatalog.friendlyVoiceLabel(for: model) {
            return friendly
        }
        switch model {
        case "moe": return "MoE Completo"
        case "local-uncensored": return "Local Sem Censura"
        case "claude-sonnet-5": return "Sonnet 5"
        case "claude-opus-4-8": return "Opus 4.8"
        case "grok": return "Grok 4.3"
        case "glm-5.2": return "GLM 5.2"
        case "kimi-k2.6": return "Kimi 2.6"
        case "minimax-m3": return "MiniMax M3"
        default: return "Beagle"
        }
    }



    /// Send using the cloud backend (beagle-core /api/v1/chat) OR Direct Brain (OpenAI GPT / Anthropic Claude / MoE + Beagle MCP).
    public func sendMessageCloud(
        _ text: String,
        vision: ChatVisionPayload? = nil,
        document: ChatDocumentPayload? = nil,
        webPrefetch: (contextBlock: String, executedTools: [String])? = nil
    ) async {
        // Build history BEFORE appending new user message — pass as STRUCTURED
        // turn-based messages (role+content) with a deep 60-message window (vs the old 10-message truncation).
        var history: [[String: String]] = []
        var directTurns: [DirectBrainTurn] = []
        if let summary = currentRollingSummary(), !summary.isEmpty {
            let epUser = "[Contexto episódico acumulado desta conversa: \(summary)]"
            let epAssistant = "Tenho todo esse contexto episódico vivo comigo."
            history.append(["role": "user", "content": epUser])
            history.append(["role": "assistant", "content": epAssistant])
            directTurns.append(DirectBrainTurn(role: "user", content: epUser))
            directTurns.append(DirectBrainTurn(role: "assistant", content: epAssistant))
        }

        let recentWindow = Array(messages.suffix(60))
        // Keep full base64 pixels on up to the 2 most recent historical visual turns so follow-up questions
        // ("e ali no canto?", "compara com a foto anterior") see real pixels without bloating 60 turns.
        let recentVisualIds = Set(
            recentWindow
                .filter { $0.role == .user && $0.imageData != nil }
                .suffix(2)
                .map(\.id)
        )

        let recentTurns: [[String: String]] = recentWindow.map { msg in
            let role = msg.role == .user ? "user" : "assistant"
            var content = msg.content
            if let digest = msg.imageLocalDigest, !digest.isEmpty, msg.role == .user {
                content = content.isEmpty
                    ? "[Imagem anexada — \(digest)]"
                    : "\(content)\n[Imagem anexada — \(digest)]"
            }
            return ["role": role, "content": content]
        }
        history.append(contentsOf: recentTurns)

        for msg in recentWindow {
            let role = msg.role == .user ? "user" : "assistant"
            var content = msg.content
            if let digest = msg.imageLocalDigest, !digest.isEmpty, msg.role == .user {
                content = content.isEmpty
                    ? "[Imagem anterior — \(digest)]"
                    : "\(content)\n[Imagem anterior — \(digest)]"
            }
            let b64: String? = (recentVisualIds.contains(msg.id)) ? msg.imageData?.base64EncodedString() : nil
            directTurns.append(DirectBrainTurn(
                role: role,
                content: content,
                imageBase64: b64,
                imageMediaType: b64 != nil ? "image/jpeg" : nil
            ))
        }

        let cloudDocBlock = document?.promptBlock(maxChars: 32_000)
        let cloudWebBlock = webPrefetch?.contextBlock
        let contextualPrompt = (vision != nil || document != nil || cloudWebBlock != nil)
            ? offlineGroundedPrompt(
                text,
                visionDigest: vision?.localDigest,
                documentBlock: cloudDocBlock,
                webBlock: cloudWebBlock
            )
            : text

        let userMessage = ChatMessage(
            role: .user,
            content: Self.composeUserBubbleContent(text: text, document: document),
            imageData: vision?.jpegData,
            imageLocalDigest: Self.composePersistedAttachmentDigest(
                vision: vision,
                document: document,
                webBlock: cloudWebBlock
            )
        )
        messages.append(userMessage)
        persist(message: userMessage)

        let initialCloudTools = Self.mergeUniqueTools([
            document != nil ? ["local_pdf_reader"] : [],
            webPrefetch?.executedTools ?? []
        ])
        let assistantId = UUID()
        let placeholder = ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "",
            isStreaming: true,
            hadVisualContext: vision != nil || document != nil,
            executedTools: initialCloudTools
        )
        messages.append(placeholder)
        isStreaming = true

        onCompanionTurnStart?(currentConversationTitle, voiceLabel(for: voiceModel))

        // B-routing: instant on-device "presence". A warm pt-BR opener fills the ~14s cloud
        // latency with the friend's voice instead of typing dots — then the grounded cloud reply
        // replaces it the moment real tokens arrive. Best-effort; skipped if Apple FM is off.
        if let quickAck {
            Task { [assistantId] in
                guard let ack = await quickAck(text)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !ack.isEmpty else { return }
                guard let idx = messages.firstIndex(where: { $0.id == assistantId }),
                      messages[idx].content.isEmpty else { return }   // cloud already streaming → skip
                messages[idx].content = ack
                messages[idx].isProvisional = true
            }
        }

        // Temporal awareness: send the previous contact time (the client owns the thread),
        // then stamp this exchange as the new "last contact" for the next turn.
        let previousContact = lastContactAt
        lastContactAt = Date()

        // Presence is a signal about THIS turn; it must not survive it, on any exit path.
        defer { presenceNote = nil }

        // MARK: Direct Brain & MoE Routing (OpenAI GPT-6.2 Direct + Beagle MCP + Local Uncensored + Anthropic Direct)
        let wantsMoE = (voiceModel == "moe")
        let wantsDirectOpenAI = wantsMoE || ((voiceModel == nil || OpenAIModelCatalog.isDirectOpenAIModel(voiceModel)) && DirectBrainCredentials.hasOpenAI)
        let wantsDirectAnthropic = ((voiceModel == "claude-sonnet-5" || voiceModel == "claude-opus-4-8") && DirectBrainCredentials.hasAnthropic)

        if wantsDirectOpenAI || wantsDirectAnthropic {
            if let document {
                presenceNote = wantsMoE
                    ? "MoE · lendo PDF (\(document.pageCount) pág.) + GPT + memória do cluster…"
                    : "lendo PDF (\(document.pageCount) pág.) + memória do cluster & MCP…"
            } else if vision != nil {
                presenceNote = wantsMoE
                    ? "MoE · lendo imagem local + GPT + memória do cluster…"
                    : "lendo tua imagem + memória do cluster & MCP…"
            } else if cloudWebBlock != nil {
                presenceNote = wantsMoE
                    ? "MoE · lendo artigo/link + escuta local + memória do cluster…"
                    : "lendo artigo / link + memória do cluster & MCP…"
            } else {
                presenceNote = wantsMoE
                    ? "MoE · escuta local sem censura + memória do cluster…"
                    : "consultando memória do cluster & MCP…"
            }

            // Run GraphRAG++ cluster memory recall (using text + any OCR/PDF/Web excerpt)
            let recallQuery: String = {
                var parts = [text]
                if let doc = document, !doc.extractedText.isEmpty {
                    parts.append(String(doc.extractedText.prefix(280)))
                } else if let ocr = vision?.extractedOCR, !ocr.isEmpty {
                    parts.append(String(ocr.prefix(240)))
                } else if let web = cloudWebBlock, !web.isEmpty {
                    parts.append(String(web.prefix(260)))
                }
                return parts.joined(separator: " ")
            }()
            async let recalledTask = DirectBrainClient.shared.recallRelevantMemory(for: recallQuery, projectSlug: projectSlug)
            var moeDraft: String? = nil
            if wantsMoE {
                moeDraft = await generateMoELocalUncensoredDraft(
                    for: text,
                    visionDigest: vision?.localDigest,
                    documentBlock: document?.promptBlock(maxChars: 6_000),
                    webBlock: cloudWebBlock.map { String($0.prefix(4_500)) }
                )
            }
            let recalledMemories = await recalledTask

            let splitPrompt = await DirectBrainClient.shared.buildSplitSystemPrompt(
                cachedGrounding: cachedGrounding,
                physioSummary: physioSummary,
                physioContext: activeSystemInstruction,
                currentSky: currentSky,
                flowState: flowState,
                sleepQuality01: sleepQuality01,
                voiceTone: sinalDeVozDoTurno,
                lastContactAt: previousContact,
                rollingSummary: currentRollingSummary(),
                recentThreadDigest: recentCrossThreadDigest(),
                recalledMemories: recalledMemories,
                moeLocalUncensoredDraft: moeDraft
            )
            let fullSystem = splitPrompt.turnInstructions.isEmpty
                ? splitPrompt.developerPrefix
                : splitPrompt.developerPrefix + "\n\n" + splitPrompt.turnInstructions

            // Include Bula/PCDT verbatim clinical grounding + Apple Vision OCR + multi-page PDF text + live Web/PubMed/DOI context alongside Page 1 pixels
            let userTurnWithClinicalCache = offlineGroundedPrompt(
                text,
                visionDigest: vision?.localDigest,
                documentBlock: cloudDocBlock,
                webBlock: cloudWebBlock
            )
            var directHistory = recentTurns
            directHistory.append(["role": "user", "content": userTurnWithClinicalCache])
            directTurns.append(DirectBrainTurn(
                role: "user",
                content: userTurnWithClinicalCache,
                imageBase64: vision?.base64JPEG,
                imageMediaType: vision?.mimeType
            ))

            var directStreamed = ""
            var directResponseModel: String?
            var directExecutedTools: [String] = initialCloudTools
            do {
                if wantsDirectOpenAI && DirectBrainCredentials.hasOpenAI {
                    let targetModel = wantsMoE ? DirectBrainCredentials.openAIModel : (voiceModel ?? DirectBrainCredentials.openAIModel)
                    let response = try await DirectBrainClient.shared.streamOpenAI(
                        model: targetModel,
                        systemPrompt: fullSystem,
                        developerPrefix: splitPrompt.developerPrefix,
                        turnInstructions: splitPrompt.turnInstructions,
                        history: directHistory,
                        turns: directTurns,
                        projectSlug: projectSlug,
                        onStatus: { [weak self] statusText in
                            await MainActor.run {
                                self?.presenceNote = statusText
                            }
                        },
                        onToken: { [weak self] token in
                            await MainActor.run {
                                guard let self else { return }
                                directStreamed += token
                                self.presenceNote = nil
                                if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                                    if self.messages[idx].isProvisional { self.messages[idx].isProvisional = false }
                                    self.messages[idx].content = self.stripReasoning(directStreamed)
                                }
                            }
                        }
                    )
                    directResponseModel = response.model
                    directExecutedTools = Self.mergeUniqueTools([directExecutedTools, response.executedTools])
                } else if wantsDirectAnthropic && DirectBrainCredentials.hasAnthropic {
                    let response = try await DirectBrainClient.shared.streamAnthropic(
                        model: voiceModel ?? "claude-sonnet-5",
                        systemPrompt: fullSystem,
                        history: directHistory,
                        turns: directTurns,
                        projectSlug: projectSlug,
                        onStatus: { [weak self] statusText in
                            await MainActor.run {
                                self?.presenceNote = statusText
                            }
                        },
                        onToken: { [weak self] token in
                            await MainActor.run {
                                guard let self else { return }
                                directStreamed += token
                                self.presenceNote = nil
                                if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                                    if self.messages[idx].isProvisional { self.messages[idx].isProvisional = false }
                                    self.messages[idx].content = self.stripReasoning(directStreamed)
                                }
                            }
                        }
                    )
                    directResponseModel = response.model
                    directExecutedTools = Self.mergeUniqueTools([directExecutedTools, response.executedTools])
                }
            } catch {
                // If direct API call fails (e.g. key quota/network), fall through seamlessly to cluster stream below
                directStreamed = ""
            }

            if !directStreamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx].content = stripReasoning(directStreamed)
                    messages[idx].isStreaming = false
                    messages[idx].model = wantsMoE ? directResponseModel.map { "moe-local+\($0)" } : (directResponseModel ?? voiceModel)
                    messages[idx].source = wantsMoE ? "beagle-moe-mcp" : "beagle-direct-mcp"
                    messages[idx].executedTools = directExecutedTools
                    persist(message: messages[idx])
                    onCompanionTurnEnd?(messages[idx].content)
                    let respondidaDireta = messages[idx]
                    Task { @MainActor [weak self] in
                        await self?.syncTurnToClusterMemory(
                            user: userMessage,
                            assistant: respondidaDireta,
                            sourceSurface: wantsMoE ? "beagle-apple-moe" : "beagle-apple-direct-mcp",
                            alsoIngestSpine: true,
                            vision: vision
                        )
                    }
                }
                isStreaming = false
                return
            }

            // If user selected MoE without a direct OpenAI key yet, inject the local uncensored draft into the cluster request
            if wantsMoE, let moeDraft, !moeDraft.isEmpty {
                history.append([
                    "role": "assistant",
                    "content": "[Leitura inicial sem filtro do modelo local no dispositivo: \(moeDraft)]"
                ])
            }
        }

        // Enrich system instruction with rolling summary & cross-thread continuity for cluster turns
        let clusterSystemInstruction: String? = {
            var parts: [String] = []
            if let base = activeSystemInstruction, !base.isEmpty { parts.append(base) }
            if let roll = currentRollingSummary(), !roll.isEmpty {
                parts.append("Resumo episódico anterior desta conversa:\n\(roll)")
            }
            if let cross = recentCrossThreadDigest(), !cross.isEmpty {
                parts.append("Continuidade de conversas recentes no Cockpit:\n\(cross)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }()
        let clusterVoiceModel: String? = (voiceModel == "moe" || voiceModel == "local-uncensored") ? DirectBrainCredentials.openAIModel : voiceModel

        // STREAM tokens live from /api/mobile/v1/chat/stream. The user sees the
        // companion typing as the model emits — no more 7-9s frozen wait.
        // Falls back to the buffered /chat endpoint on stream failure so the chat
        // never goes completely dark.
        let stream = client.chatStream(
            prompt: contextualPrompt,
            system: clusterSystemInstruction,
            projectSlug: projectSlug,
            projectFamily: projectFamily,
            publicationScope: publicationScope,
            discussionProfile: discussionProfile,
            flowState: flowState,
            physioPolicy: physioPolicy,
            lastContactAt: previousContact,
            history: history,
            hrvMs: physioSummary?.hrvMs,
            voiceWpm: sinalDeVozDoTurno?.wpm, voicePausa: sinalDeVozDoTurno?.pausa,
            readiness: physioSummary?.readiness.rawValue,
            sleepHours: physioSummary?.sleepHours,
            kp: currentSky?.kp, dst: currentSky?.dst,
            solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz,
            voiceModel: clusterVoiceModel,
            imageBase64: vision?.base64JPEG,
            imageMimeType: vision?.mimeType,
            // Presence: written to the presence LAYER, not to the message slot — so the
            // on-device quickAck (which owns that slot) always wins, by construction, and
            // no server-authored sentence can ever be mistaken for his voice.
            onPhase: { [weak self] phase, text in
                Task { @MainActor [weak self] in
                    guard let self, self.isStreaming else { return }
                    guard let idx = self.messages.firstIndex(where: { $0.id == assistantId }),
                          self.messages[idx].content.isEmpty || self.messages[idx].isProvisional else {
                        self.presenceNote = nil
                        return
                    }
                    switch phase {
                    case "voice":
                        self.presenceNote = "pensando…"
                    case "alive":
                        if self.presenceNote == nil { self.presenceNote = "ainda com você…" }
                    default:
                        self.presenceNote = text.isEmpty ? "estou com você…" : text + "…"
                    }
                }
            }
        )

        var streamedText = ""
        // Commit by PARAGRAPH, not by character: publish only up to the last "\n\n" so each
        // paragraph lands whole. Ceiling below covers the single-paragraph answer, which would
        // otherwise stay invisible for the whole turn.
        var publishedLen = 0
        var lastPublish = Date()
        var streamErr: Error? = nil
        do {
            for try await token in stream {
                streamedText += token
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    // First real token evicts the provisional on-device ack and the presence line.
                    if messages[idx].isProvisional { messages[idx].isProvisional = false }
                    presenceNote = nil
                    let cleaned = stripReasoning(streamedText)
                    var publish: String? = nil
                    if let br = cleaned.range(of: "\n\n", options: .backwards) {
                        let upto = String(cleaned[..<br.lowerBound])
                        if upto.count > publishedLen { publish = upto }
                    }
                    // Ceiling: an answer with no paragraph break must not sit invisible.
                    if publish == nil, cleaned.count > publishedLen,
                       Date().timeIntervalSince(lastPublish) > 2.0 {
                        publish = cleaned
                    }
                    if let publish {
                        messages[idx].content = publish
                        publishedLen = publish.count
                        lastPublish = Date()
                    }
                }
            }
        } catch {
            streamErr = error
        }

        if !streamedText.isEmpty {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                // Portão da última milha. O app fala com quatro gateways e com o
                // modelo local; nem todo caminho passa pelo portão do cockpit, e
                // esta é sempre a última parada antes da bolha.
                let limpo = stripReasoning(streamedText)
                messages[idx].content = PisoLocal.ehFala(limpo)
                    ? limpo
                    : PisoLocal.frase(PisoLocal.motivo(de: streamErr, temRede: NetworkMonitor.shared.isOnline))
                messages[idx].isStreaming = false
                messages[idx].source = "cloud-stream"
                persist(message: messages[idx])
                onCompanionTurnEnd?(messages[idx].content)
                // A conversa NÃO espera durabilidade.
                //
                // Medido: o servidor já grava o turno (ingestPersonalTurn, com
                // proveniência carimbada na escrita), e este assisted-import
                // devolve 404 — a rota vive no beagle-core, não no cockpit, e o
                // cliente ainda tenta os três gateways antes de desistir. O
                // resultado era a resposta já inteira na tela e o composer preso
                // esperando uma requisição condenada.
                //
                // Fica como fire-and-forget em vez de sumir porque ela também
                // trata conteúdo restrito localmente; remover de vez é decisão
                // separada, com o 404 consertado antes.
                let respondida = messages[idx]
                Task { @MainActor [weak self] in
                    await self?.syncTurnToClusterMemory(
                        user: userMessage,
                        assistant: respondida,
                        sourceSurface: "beagle-apple-cloud",
                        alsoIngestSpine: false,
                        vision: vision
                    )
                }
            }
            isStreaming = false
            return
        }

        // Stream produced nothing (gateway hiccup or 5xx). Fall back to the
        // buffered /chat endpoint so the user always gets a reply.
        let result = await client.chat(
            prompt: contextualPrompt,
            system: clusterSystemInstruction,
            projectSlug: projectSlug,
            projectFamily: projectFamily,
            publicationScope: publicationScope,
            discussionProfile: discussionProfile,
            flowState: flowState,
            physioPolicy: physioPolicy,
            lastContactAt: previousContact,
            history: history,
            hrvMs: physioSummary?.hrvMs,
            voiceWpm: sinalDeVozDoTurno?.wpm, voicePausa: sinalDeVozDoTurno?.pausa,
            readiness: physioSummary?.readiness.rawValue,
            sleepHours: physioSummary?.sleepHours,
            kp: currentSky?.kp, dst: currentSky?.dst,
            solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz,
            voiceModel: clusterVoiceModel,
            imageBase64: vision?.base64JPEG,
            imageMimeType: vision?.mimeType
        )

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            messages[idx].isProvisional = false   // evict any on-device ack before the real reply
            if let response = result.value {
                let fullText = stripReasoning(response.response ?? "")
                messages[idx].model = response.model
                messages[idx].tokensUsed = response.tokensUsed
                messages[idx].source = response.source
                messages[idx].agentKind = response.agentKind
                messages[idx].sessionId = response.sessionId
                messages[idx].podName = response.podName
                await revealText(fullText, for: assistantId)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
                onCompanionTurnEnd?(messages[idx].content)
                // Mesma razão do caminho de streaming: durabilidade não segura a conversa.
                let respondidaBuf = messages[idx]
                Task { @MainActor [weak self] in
                    await self?.syncTurnToClusterMemory(
                        user: userMessage,
                        assistant: respondidaBuf,
                        sourceSurface: "beagle-apple-cloud",
                        alsoIngestSpine: false,
                        vision: vision
                    )
                }
            } else {
                // O CHÃO DO APARELHO. O chão do servidor não cobre servidor
                // inalcançável — foi exatamente o que aconteceu em 07-ago, e o
                // que sobrava aqui era a mensagem crua do erro virando fala.
                let motivo = PisoLocal.motivo(de: streamErr, temRede: NetworkMonitor.shared.isOnline)
                messages[idx].content = PisoLocal.frase(motivo)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
                onCompanionTurnEnd?(nil)
            }
        }

        isStreaming = false
    }

    // MARK: - Typing reveal (cloud responses)

    func revealText(_ text: String, for messageId: UUID) async {
        let chars = Array(text)
        let chunkSize = 30
        var pos = 0

        while pos < chars.count {
            // Guard against clear() being called mid-reveal
            guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
            let end = min(pos + chunkSize, chars.count)
            messages[idx].content = String(chars[0..<end])
            pos = end
            if pos < chars.count {
                // Propagate cancellation instead of swallowing it with try?
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(35))
                if Task.isCancelled { return }
            }
        }
    }
}
