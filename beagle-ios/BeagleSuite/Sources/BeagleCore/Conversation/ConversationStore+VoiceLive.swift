//
//  ConversationStore+VoiceLive.swift
//  BeagleCore
//
//  GPT-Live (`gpt-live-1.1`) full-duplex voice bubbles, deep intent classification,
//  and asynchronous client delegation (Modo Fundo, GPT-Rosalind, Morning Synthesis, MoE + Bula + MCP).
//

import Foundation
import SwiftData

@MainActor
extension ConversationStore {

    // MARK: - GPT-Live (`gpt-live-1.1`) Full-Duplex Bubbles & Client Delegation (MoE + Bula + MCP)

    public enum DeepVoiceDelegationKind: String, Sendable, Equatable {
        case modoFundo = "modo_fundo"
        case rosalindBio = "rosalind_bio"
        case morningSynthesis = "morning_synthesis"
    }

    /// Detecta se o pedido falado na sessão `gpt-live-1.1` exige deliberação assíncrona pesada
    /// (`Modo Fundo`, `GPT-Rosalind PBPK/Bio` ou `Síntese Matinal`), permitindo retorno falado imediato
    /// + execução real em segundo plano com Dynamic Island e retorno por voz ao concluir.
    public nonisolated static func classifyDeepVoiceIntent(_ utterance: String) -> DeepVoiceDelegationKind? {
        let lower = utterance
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))

        if lower.contains("sintese matinal")
            || lower.contains("briefing matinal")
            || lower.contains("resumo da manha")
            || lower.contains("resumo do dia")
            || lower.contains("briefing do dia") {
            return .morningSynthesis
        }

        if lower.contains("modo fundo")
            || lower.contains("explora a fundo")
            || lower.contains("explorar a fundo")
            || lower.contains("pesquisa profunda")
            || lower.contains("go deeper")
            || lower.contains("mesa redonda") {
            return .modoFundo
        }

        if lower.contains("rosalind")
            || lower.contains("pbpk")
            || lower.contains("farmacocinetica")
            || lower.contains("biodisponibilidade")
            || lower.contains("meia-vida plasmatica") {
            return .rosalindBio
        }

        return nil
    }

    /// Nota contextual compacta (`developer` em `session.input`) para abrir sessões `gpt-live-1.1`
    /// já alinhadas ao fisioma, clima espacial, projeto ativo e memória episódica recente.
    public func buildGPTLiveAgoraNote() -> String? {
        var parts: [String] = ["Projeto ativo: \(projectSlug). Conversa: \(currentConversationTitle)."]
        if let physio = physioSummary {
            var p: [String] = ["Prontidão \(physio.readiness.rawValue)"]
            if let hrv = physio.hrvMs { p.append(String(format: "HRV %.0f ms", hrv)) }
            if let sleep = physio.sleepHours { p.append(String(format: "Sono %.1fh", sleep)) }
            parts.append("Fisioma: " + p.joined(separator: " · "))
        }
        if let sky = currentSky {
            parts.append(String(format: "Clima geomagnético: %@ (Kp %.1f)", sky.band.rawValue, sky.kp))
        }
        if let roll = currentRollingSummary(), !roll.isEmpty {
            parts.append("Resumo episódico desta conversa: " + String(roll.suffix(420)))
        } else if let cross = recentCrossThreadDigest(maxThreads: 2), !cross.isEmpty {
            parts.append("Conversas recentes: " + String(cross.prefix(320)))
        }
        return parts.joined(separator: " ")
    }

    /// Atualiza ou consolida uma bolha de transcrição full-duplex vinda do `gpt-live-1.1`,
    /// persistindo no SwiftData/Spotlight e sincronizando turnos fechados com a memória do cluster.
    public func upsertGPTLiveBubble(
        id: UUID,
        role: MessageRole,
        text: String,
        isFinal: Bool,
        executedTools: [String] = []
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let modelTag: String? = (role == .assistant) ? OpenAILiveProtocol.liveModel : nil
        let sourceTag: String? = (role == .assistant) ? "openai-gpt-live" : nil

        if let idx = messages.firstIndex(where: { $0.id == id }) {
            let wasAlreadyFinal = !messages[idx].isStreaming
            messages[idx].content = trimmed
            messages[idx].isStreaming = !isFinal
            if !executedTools.isEmpty {
                messages[idx].executedTools = Self.mergeUniqueTools([messages[idx].executedTools, executedTools])
            }
            if isFinal && !wasAlreadyFinal {
                persist(message: messages[idx])
                if role == .assistant,
                   let prevUser = messages[..<idx].last(where: { $0.role == .user }) {
                    let settledAssistant = messages[idx]
                    Task { @MainActor [weak self] in
                        await self?.syncTurnToClusterMemory(
                            user: prevUser,
                            assistant: settledAssistant,
                            sourceSurface: "beagle-apple-gpt-live",
                            alsoIngestSpine: true
                        )
                    }
                }
            }
        } else {
            let msg = ChatMessage(
                id: id,
                role: role,
                content: trimmed,
                isStreaming: !isFinal,
                model: modelTag,
                source: sourceTag,
                executedTools: executedTools
            )
            messages.append(msg)
            if isFinal {
                persist(message: msg)
                if role == .assistant,
                   let prevUser = messages.dropLast().last(where: { $0.role == .user }) {
                    Task { @MainActor [weak self] in
                        await self?.syncTurnToClusterMemory(
                            user: prevUser,
                            assistant: msg,
                            sourceSurface: "beagle-apple-gpt-live",
                            alsoIngestSpine: true
                        )
                    }
                }
            }
        }
    }

    /// Executa uma delegação `client` do `gpt-live-1.1` no cérebro MoE completo do Beagle
    /// (Bula/PCDT verbatim + GraphRAG++ + rascunho local sem censura + OpenAI/Claude + MCP + Apple Tools).
    public func executeGPTLiveDelegation(
        _ context: OpenAILiveDelegationContext,
        useMoE: Bool = true
    ) async -> OpenAILiveDelegationOutcome {
        let queryText = context.latestUserUtterance.isEmpty
            ? (context.transcriptWindow.last?.text ?? "Verifique o contexto recente da conversa.")
            : context.latestUserUtterance

        // Fast-path: deep asynchronous delegation (Modo Fundo / GPT-Rosalind / Síntese Matinal)
        if let deepKind = Self.classifyDeepVoiceIntent(queryText) {
            switch deepKind {
            case .morningSynthesis:
                if let cached = DailyBriefingBuilder.cachedTodaySynthesis() {
                    let spoken = OpenAILiveProtocol.truncateForLiveAppend(
                        "Síntese matinal de hoje pronta — resuma naturalmente em voz alta os pontos principais para o Demetrios:\n\(cached)",
                        maxChars: 1_200
                    )
                    return OpenAILiveDelegationOutcome(
                        spokenSummary: spoken,
                        backgroundFacts: cached,
                        executedTools: ["daily_briefing_cache"]
                    )
                }

                let slug = projectSlug
                let physio = physioSummary
                let sky = currentSky
                let flow = flowState ?? "NORMAL"
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let ctx = await DailyBriefingBuilder.gatherLiveContext(
                        captureLines: [],
                        physioSummary: physio,
                        sky: sky,
                        projectSlug: slug
                    )
                    guard let generated = try? await DailyBriefingBuilder.generateMorningSynthesis(
                        context: ctx,
                        projectSlug: slug,
                        flowState: flow
                    ), !generated.isEmpty else { return }
                    DailyBriefingBuilder.saveTodaySynthesis(generated, context: ctx)
                    let bubble = ChatMessage(
                        role: .assistant,
                        content: "### Síntese Matinal\n\n" + generated,
                        model: OpenAIModelCatalog.defaultFlagshipModel,
                        source: "daily-synthesis-voice",
                        executedTools: ["daily_briefing_astra"]
                    )
                    self.messages.append(bubble)
                    self.persist(message: bubble)
                    await self.onTriggerAsyncVoiceFollowup?(
                        "A Síntese Matinal do Demetrios acabou de ficar pronta. Comunique os destaques principais com naturalidade em 3 a 4 frases:\n\(String(generated.prefix(900)))",
                        generated,
                        ["daily_briefing_astra"]
                    )
                }

                return OpenAILiveDelegationOutcome(
                    spokenSummary: "Avise ao Demetrios em uma frase natural que você já está gerando a Síntese Matinal cruzando o fisioma do Apple Watch, o clima espacial NOAA e a agenda das próximas 48 horas, e que vai ler os destaques assim que fechar.",
                    backgroundFacts: nil,
                    executedTools: ["daily_briefing_launch"]
                )

            case .modoFundo, .rosalindBio:
                let lenses: Set<GoDeepModality> = (deepKind == .rosalindBio)
                    ? [.rosalindBio, .astraDeep]
                    : [.astraDeep, .rosalindBio, .swarmConsensus, .causalExtract]
                let label = (deepKind == .rosalindBio) ? "GPT-Rosalind (Bio/PBPK)" : "Modo Fundo (Astra + Rosalind)"
                let slug = projectSlug

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let deepStore = GoDeepStore(enabledModalities: lenses)
                    let persisted = PersistedDeepSession(prompt: queryText, modalityCount: deepStore.enabledModalities.count)
                    self.modelContext?.insert(persisted)
                    try? self.modelContext?.save()

                    deepStore.onResearchStart = { [weak self] runId, campaign, rSlug in
                        self?.onVoiceResearchStart?(runId, campaign, rSlug, max(2, lenses.count + 1), label)
                    }
                    deepStore.onResearchStateChange = { [weak self] step, total, eta, activeLens, snippet, isCompleted in
                        self?.onVoiceResearchUpdate?(step, total, eta, activeLens, snippet, isCompleted)
                    }
                    deepStore.onSessionComplete = { [weak self] payload in
                        persisted.synthesisText = payload.synthesis
                        persisted.modalityResults = payload.modalityResultsJSON
                        persisted.citationsJSON = payload.citationsJSON
                        persisted.modalityCount = payload.modalityCount
                        persisted.completedAt = payload.completedAt
                        try? self?.modelContext?.save()
                    }

                    await deepStore.goDeeperAndWait(prompt: queryText)
                    guard let synth = deepStore.synthesis, !synth.isEmpty else { return }

                    let tools = deepKind == .rosalindBio ? ["gpt_rosalind_pbpk", "astra_xhigh"] : ["modo_fundo_astra", "gpt_rosalind_pbpk"]
                    let bubble = ChatMessage(
                        role: .assistant,
                        content: "### \(label)\n\n" + synth,
                        model: deepKind == .rosalindBio ? OpenAIModelCatalog.lifeSciencesModel : OpenAIModelCatalog.defaultFlagshipModel,
                        source: "modo-fundo-voice",
                        executedTools: tools
                    )
                    self.messages.append(bubble)
                    self.persist(message: bubble)
                    _ = slug
                    await self.onTriggerAsyncVoiceFollowup?(
                        "A investigação profunda (\(label)) sobre '\(String(queryText.prefix(90)))' acabou de concluir em segundo plano. Sintetize em voz alta a conclusão central e a recomendação prática em 3 a 5 frases diretas:\n\(String(synth.prefix(950)))",
                        synth,
                        tools
                    )
                }

                return OpenAILiveDelegationOutcome(
                    spokenSummary: "Confirme em 1 frase curta e calorosa que você acabou de disparar \(label) em segundo plano (visível na Dynamic Island) e que já vai trazer a síntese verificada assim que as lentes terminarem, enquanto vocês continuam conversando normalmente.",
                    backgroundFacts: "Investigação \(label) iniciada assincronamente para: \(queryText)",
                    executedTools: [deepKind.rawValue]
                )
            }
        }

        presenceNote = useMoE
            ? "GPT-Live · delegando ao MoE, Bula & MCP…"
            : "GPT-Live · consultando memória & ferramentas…"
        defer { presenceNote = nil }

        async let recalledTask = DirectBrainClient.shared.recallRelevantMemory(
            for: queryText,
            projectSlug: projectSlug
        )
        let webPrefetch = await ScienceAndWebBridge.shared.prefetchContextForPrompt(queryText)
        var moeDraft: String? = nil
        if useMoE {
            moeDraft = await generateMoELocalUncensoredDraft(
                for: queryText,
                webBlock: webPrefetch.map { String($0.contextBlock.prefix(3_500)) }
            )
        }
        let recalledMemories = await recalledTask

        let splitBase = await DirectBrainClient.shared.buildSplitSystemPrompt(
            cachedGrounding: cachedGrounding,
            physioSummary: physioSummary,
            physioContext: activeSystemInstruction,
            currentSky: currentSky,
            flowState: flowState,
            sleepQuality01: sleepQuality01,
            voiceTone: nil,
            lastContactAt: lastContactAt,
            rollingSummary: currentRollingSummary(),
            recentThreadDigest: recentCrossThreadDigest(),
            recalledMemories: recalledMemories,
            moeLocalUncensoredDraft: moeDraft
        )

        let delegationSuffix = """


        ## Voice conversation context (GPT-Live Client Delegation)
        Você está apoiando o modelo de voz `gpt-live-1.1` durante uma conversa falada full-duplex ao vivo com o Demetrios.
        As transcrições de voz podem conter hesitações, palavras incompletas ou correções posteriores; use o contexto mais recente e os registros verificados (Bula/PCDT, MCP, GraphRAG++, agenda, lembretes, PubMed/Web).
        Se precisar acionar ferramentas MCP, científicas ou nativas do iPhone, execute-as agora.

        ## Return the result
        Devolva os fatos verificados em português do Brasil direto, objetivo e sem Markdown pesado, em até 140 palavras (~220 tokens), pronto para o `gpt-live-1.1` comunicar naturalmente em voz alta. Se uma ação foi concluída numa ferramenta, confirme o resultado; se faltar um dado indispensável, diga exatamente qual detalhe perguntar.
        """
        let delegationDeveloperPrefix = splitBase.developerPrefix + delegationSuffix
        let delegationFullSystem = splitBase.turnInstructions.isEmpty
            ? delegationDeveloperPrefix
            : delegationDeveloperPrefix + "\n\n" + splitBase.turnInstructions

        let groundedUserPrompt = offlineGroundedPrompt(
            queryText,
            webBlock: webPrefetch?.contextBlock
        )

        var history: [[String: String]] = []
        var turns: [DirectBrainTurn] = []
        for entry in context.transcriptWindow.dropLast() {
            history.append(["role": entry.role, "content": entry.text])
            turns.append(DirectBrainTurn(role: entry.role, content: entry.text))
        }
        history.append(["role": "user", "content": groundedUserPrompt])
        turns.append(DirectBrainTurn(role: "user", content: groundedUserPrompt))

        var toolsUsed: [String] = webPrefetch?.executedTools ?? []
        var rawOutput = ""

        if DirectBrainCredentials.hasOpenAI {
            do {
                let targetModel = DirectBrainCredentials.openAIModel
                let res = try await DirectBrainClient.shared.streamOpenAI(
                    model: targetModel,
                    systemPrompt: delegationFullSystem,
                    developerPrefix: delegationDeveloperPrefix,
                    turnInstructions: splitBase.turnInstructions,
                    reasoningEffort: "low",
                    history: history,
                    turns: turns,
                    projectSlug: projectSlug,
                    onStatus: { [weak self] status in
                        await MainActor.run {
                            self?.presenceNote = status
                        }
                    },
                    onToken: { _ in }
                )
                rawOutput = res.content
                toolsUsed = Self.mergeUniqueTools([toolsUsed, res.executedTools])
            } catch {
                rawOutput = ""
            }
        }

        if rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fallback = await client.chat(
                prompt: groundedUserPrompt,
                system: delegationFullSystem,
                projectSlug: projectSlug,
                projectFamily: projectFamily,
                publicationScope: publicationScope,
                discussionProfile: discussionProfile,
                flowState: flowState,
                physioPolicy: physioPolicy,
                history: history
            )
            rawOutput = fallback.value?.response ?? ""
        }

        let cleaned = stripReasoning(rawOutput)
        let summary = OpenAILiveProtocol.truncateForLiveAppend(
            cleaned.isEmpty
                ? "Não consegui confirmar esse dado externo agora; avise o Demetrios com transparência."
                : cleaned,
            maxChars: 1_400
        )

        var backgroundFacts: String? = nil
        if let bula = BulaStore.shared.consulta(queryText) {
            backgroundFacts = OpenAILiveProtocol.truncateForLiveAppend(
                "Referência de bula verificada (\(bula.nomePT) / \(bula.generico), \(bula.citacao)): \(String(bula.texto.prefix(900)))",
                maxChars: 1_200
            )
        }

        lastContactAt = Date()
        return OpenAILiveDelegationOutcome(
            spokenSummary: summary,
            backgroundFacts: backgroundFacts,
            executedTools: toolsUsed
        )
    }
}
