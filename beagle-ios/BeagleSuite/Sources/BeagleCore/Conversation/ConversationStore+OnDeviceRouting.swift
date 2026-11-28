//
//  ConversationStore+OnDeviceRouting.swift
//  BeagleCore
//
//  HRV-gated auto-routing, Apple Foundation Models fast path, and on-device MLX
//  streaming & MoE uncensored draft generation for ConversationStore.
//

import Foundation

@MainActor
extension ConversationStore {
    // MARK: - Send (auto-routing)

    /// Send a message with HRV-gated routing:
    /// FLOW → cloud (deep reasoning worth the latency)
    /// NORMAL → local MLX (balanced)
    /// STRESS → Foundation Models (fast, don't overwhelm)
    public func sendMessage(
        _ text: String,
        imageData: Data? = nil,
        document: ChatDocumentPayload? = nil
    ) async {
        // O tom vale para ESTE turno. `defer` roda depois de todos os awaits, então
        // o sinal chega às chamadas do cliente e some antes do turno seguinte —
        // senão a próxima mensagem digitada herdaria a fala anterior.
        defer { sinalDeVozDoTurno = nil }

        // Prepara payload multimodal fora da main thread (redimensiona <=1568px JPEG + OCR/cena Apple Vision).
        // Quando há PDF anexado sem imagem separada, usa a capa renderizada da Página 1 para visão + miniatura.
        let effectiveImageData = imageData ?? document?.coverJPEGData
        let vision: ChatVisionPayload?
        if let effectiveImageData, !effectiveImageData.isEmpty {
            vision = await ChatVisionPayload.prepare(from: effectiveImageData)
        } else {
            vision = nil
        }

        // Detecta automaticamente URLs, DOIs (10.xxxx/...), PMIDs e arXiv IDs na mensagem ou vindos do Share Sheet
        // e busca os metadados/abstracts/texto ao vivo antes do turno, valendo para TODOS os cérebros (inclusive Local Sem Censura).
        let detectedRefs = ScienceAndWebBridge.extractReferences(from: text)
        let webPrefetch: (contextBlock: String, executedTools: [String])?
        if !detectedRefs.isEmpty && NetworkMonitor.shared.isOnline {
            let previousPresence = presenceNote
            presenceNote = "lendo link / artigo compartilhado…"
            webPrefetch = await ScienceAndWebBridge.shared.prefetchContextForPrompt(text)
            if presenceNote == "lendo link / artigo compartilhado…" {
                presenceNote = previousPresence
            }
        } else {
            webPrefetch = nil
        }

        // Se o usuário escolheu explicitamente "Local Sem Censura", roda direto no modelo local MLX
        // (com grounding completo, fisioma ao vivo, OCR/PDF, links/PubMed/DOI, bula/PCDT e sincronização com a memória do cluster).
        if voiceModel == "local-uncensored" {
            var pronto = llm.isReady
            if !pronto { pronto = await llm.restaurarUltimoModelo() }
            if pronto {
                await sendMessageLocal(text, vision: vision, document: document, webPrefetch: webPrefetch)
                if NetworkMonitor.shared.isOnline {
                    Task { @MainActor [weak self] in await self?.refreshGroundingIfStale() }
                }
                return
            }
        }

        // Light, casual messages → instant on-device Apple Intelligence (never used when an attachment, link/DOI, or explicit voice is selected).
        if vision == nil, document == nil, detectedRefs.isEmpty, voiceModel == nil, isLight(text), fastAvailable, fastResponder != nil {
            await sendMessageFast(text)
            return
        }
        // Companion: cloud / Direct OpenAI / MoE / Claude when online; the on-device
        // MLX model when offline — and enqueue the offline turn so the memory spine receives it
        // once connectivity returns. `flowState` still travels in the cloud request body.
        if NetworkMonitor.shared.isOnline {
            await sendMessageCloud(text, vision: vision, document: document, webPrefetch: webPrefetch)
        } else {
            // Sem rede. O engine esquece o modelo a cada abertura do app, então
            // tentar restaurar AQUI é a diferença entre responder e não existir.
            // Só carrega o que já está no aparelho: nunca baixa GB no celular.
            var pronto = llm.isReady
            if !pronto { pronto = await llm.restaurarUltimoModelo() }
            if pronto {
                await sendMessageLocal(text, vision: vision, document: document, webPrefetch: webPrefetch)
            } else {
                await sendMessageCloud(text, vision: vision, document: document, webPrefetch: webPrefetch)
            }
        }
        // Mantém o grounding offline fresco enquanto há rede. Fire-and-forget: nunca
        // atrasa a resposta, nunca derruba o turno.
        if NetworkMonitor.shared.isOnline {
            Task { @MainActor [weak self] in await self?.refreshGroundingIfStale() }
        }
    }

    /// A short, casual message worth answering instantly on-device.
    private func isLight(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count <= 140
    }

    /// Instant on-device reply via the injected fast responder (Apple Foundation Models).
    public func sendMessageFast(_ text: String) async {
        let history = messages.suffix(8).map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        persist(message: userMessage)

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: "", isStreaming: true))
        isStreaming = true

        let reply = await fastResponder?(text, history) ?? nil

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            if let reply, !reply.isEmpty {
                messages[idx].model = "apple-intelligence"
                messages[idx].isLocal = true
                await revealText(reply, for: assistantId)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
            } else {
                // On-device came back empty → hand this turn to the cloud on the same bubble.
                let history2 = messages.dropLast().suffix(10)
                    .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
                    .joined(separator: "\n")
                let prompt = history2.isEmpty ? text : "\(history2)\nUser: \(text)"
                let result = await client.chat(prompt: prompt, system: activeSystemInstruction,
                    projectSlug: projectSlug, projectFamily: projectFamily,
                    publicationScope: publicationScope, discussionProfile: discussionProfile,
                    flowState: flowState, physioPolicy: physioPolicy,
                    hrvMs: physioSummary?.hrvMs,
            voiceWpm: sinalDeVozDoTurno?.wpm, voicePausa: sinalDeVozDoTurno?.pausa,
            readiness: physioSummary?.readiness.rawValue,
                    sleepHours: physioSummary?.sleepHours,
                    kp: currentSky?.kp, dst: currentSky?.dst,
                    solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz)
                let full = result.value?.response ?? "Tô meio devagar agora — me dá um instante e tenta de novo?"
                messages[idx].source = result.value?.source
                await revealText(full, for: assistantId)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
            }
        }
        isStreaming = false
    }

    // MARK: - Send via on-device LLM

    /// Send using the on-device MLX model (streaming).
    public func sendMessageLocal(
        _ text: String,
        vision: ChatVisionPayload? = nil,
        document: ChatDocumentPayload? = nil,
        webPrefetch: (contextBlock: String, executedTools: [String])? = nil
    ) async {
        guard llm.isReady else {
            // Fallback to cloud
            await sendMessageCloud(text, vision: vision, document: document, webPrefetch: webPrefetch)
            return
        }

        let localWebBlock = webPrefetch.map { String($0.contextBlock.prefix(4_500)) }
        let userMessage = ChatMessage(
            role: .user,
            content: Self.composeUserBubbleContent(text: text, document: document),
            imageData: vision?.jpegData,
            imageLocalDigest: Self.composePersistedAttachmentDigest(
                vision: vision,
                document: document,
                webBlock: localWebBlock
            )
        )
        messages.append(userMessage)
        persist(message: userMessage)
        // Papéis separados: quem ele é vai como SISTEMA, o turno vai como fala.
        // O texto é o MESMO todo turno, então aplicarInstrucoes vira no-op depois
        // da primeira vez — a sessao sobrevive e o prefill fica pago.
        llm.aplicarInstrucoes(instrucoesOffline() + llm.sufixoSemRaciocinio)
        let prompt = offlineGroundedPrompt(
            text,
            visionDigest: vision?.localDigest,
            documentBlock: document?.promptBlock(maxChars: 6_000),
            webBlock: localWebBlock
        )

        let assistantId = UUID()
        let modelName = llm.currentModel?.displayName ?? "local"
        let initialLocalTools = Self.mergeUniqueTools([
            document != nil ? ["local_pdf_reader"] : [],
            webPrefetch?.executedTools ?? []
        ])
        let placeholder = ChatMessage(
            id: assistantId, role: .assistant, content: "",
            isStreaming: true, model: modelName, isLocal: true,
            hadVisualContext: vision != nil || document != nil,
            executedTools: initialLocalTools
        )
        messages.append(placeholder)
        isStreaming = true

        // Stream tokens from on-device model
        do {
            // O raciocínio do modelo NUNCA vai para a tela.
            //
            // `stripReasoning` já existia, mas só rodava no FIM: durante a geração
            // o texto cru ia direto para a bolha e ele via o bloco <think> inteiro
            // passando — em inglês, que é como o Qwen pensa. Acumula-se o cru e
            // publica-se o filtrado a cada pedaço.
            //
            // Enquanto só há raciocínio, a bolha fica vazia e a camada de presença
            // cobre a espera — que é exatamente o papel dela.
            var cruDoTurno = ""
            for try await chunk in llm.generate(prompt: prompt) {
                cruDoTurno += chunk
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx].content = stripReasoning(cruDoTurno)
                }
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                if messages[idx].content.isEmpty {
                    // O chão, não a string de erro. "Local model error: ..." já apareceu
                    // na bolha dele, em inglês, com a tipografia da carta.
                    messages[idx].content = PisoLocal.frase(.modeloLocal)
                }
            }
        }

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            messages[idx].content = stripReasoning(messages[idx].content)
            // Rede de segurança: se ele devolveu as instruções, não entregue isso.
            if Self.pareceEco(messages[idx].content, instrucoes: instrucoesOffline()) {
                messages[idx].content =
                    "Me perdi aqui dentro e comecei a repetir as minhas próprias instruções "
                    + "em vez de te responder. Não vou te entregar isso. Me pergunta de novo, "
                    + "com outras palavras — e se insistir, é defeito meu, não seu."
            }
            messages[idx].isStreaming = false
            persist(message: messages[idx])
            let respondidaLocal = messages[idx]
            Task { @MainActor [weak self] in
                await self?.syncTurnToClusterMemory(
                    user: userMessage,
                    assistant: respondidaLocal,
                    sourceSurface: "beagle-apple-local-uncensored",
                    vision: vision
                )
            }
        }
        isStreaming = false
    }

    // MARK: - Send via cloud (HERMES / Direct OpenAI / Direct Claude / MoE + Beagle MCP)

    /// Executa a Camada 1 do MoE: escuta rápida e sem censura no LLM local (se carregado na RAM)
    /// para extrair leitura clínica/humana sem filtros antes da síntese profunda do GPT / Claude.
    func generateMoELocalUncensoredDraft(
        for text: String,
        visionDigest: String? = nil,
        documentBlock: String? = nil,
        webBlock: String? = nil
    ) async -> String? {
        var ready = llm.isReady
        if !ready && DirectBrainCredentials.keepLocalLoadedWhenOnline {
            ready = await llm.restaurarUltimoModelo()
        }
        guard ready else { return nil }
        llm.aplicarInstrucoes(instrucoesOffline() + llm.sufixoSemRaciocinio)
        let prompt = offlineGroundedPrompt(
            text,
            visionDigest: visionDigest,
            documentBlock: documentBlock,
            webBlock: webBlock
        )
        var draft = ""
        do {
            for try await chunk in llm.generate(prompt: prompt) {
                draft += chunk
                if draft.count > 1600 { break }
            }
        } catch {
            return nil
        }
        let clean = stripReasoning(draft)
        if clean.isEmpty || Self.pareceEco(clean, instrucoes: instrucoesOffline()) {
            return nil
        }
        return clean
    }
}
