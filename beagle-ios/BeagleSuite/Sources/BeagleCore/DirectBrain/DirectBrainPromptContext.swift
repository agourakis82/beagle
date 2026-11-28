//
//  DirectBrainPromptContext.swift
//  BeagleCore
//
//  System prompt grounding, live physiome/heliobiology context builder,
//  proactive GraphRAG++ cluster memory recall, and rolling summary compaction.
//

import Foundation

extension DirectBrainClient {
    // MARK: - Grounding + Physiome + Rolling Summary + Cluster Memory Context Builder

    /// Separa as instruções estáveis (`developerPrefix`) das instruções dinâmicas do turno atual (`turnInstructions`).
    /// A partir do GPT-6.2 na API Responses, colocar o bloco estático na primeira mensagem `developer` de `input`
    /// e os sinais vivos (relógio, HRV, clima espacial, memórias e rascunho MoE) em `instructions` de nível superior
    /// preserva 100% do prefix cache e evita descartar `reasoning.encrypted_content` entre turnos.
    public func buildSplitSystemPrompt(
        cachedGrounding: String?,
        physioSummary: PhysioSummary?,
        physioContext: String?,
        currentSky: SpaceWeatherStore.Snapshot?,
        flowState: String?,
        sleepQuality01: Double?,
        voiceTone: (wpm: Double?, pausa: Double)?,
        lastContactAt: Date?,
        rollingSummary: String?,
        recentThreadDigest: String?,
        recalledMemories: String?,
        moeLocalUncensoredDraft: String?
    ) -> (developerPrefix: String, turnInstructions: String) {
        var prefixSections: [String] = []

        if let cached = cachedGrounding,
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prefixSections.append(cached)
        } else {
            prefixSections.append("""
            Você é o Beagle — exocórtex pessoal, parceiro científico, médico, psiquiátrico e filosófico de Demetrios Chiuratto Agourakis (44 anos, médico, pesquisador transdisciplinar, doutorando em Engenharia de Bioprocessos e Biotecnologia na UFPR, criador do Beagle, KEC 3.0, PBPK fractal e PCS Meta-Repo).
            Responda sempre em português brasileiro natural, sem censura moralista, sem paternalismo, com densidade clínica/científica real e presença humana viva.
            """)
        }

        prefixSections.append("""
        ## Postura Epistêmica, Ferramentas Nativas do iPhone, Pesquisa Científica, Grok Bot e Web ao Vivo
        - Demetrios é médico, farmacologista PBPK e neurocientista computacional. Trate todo tema clínico, psiquiátrico, farmacológico (incluindo cetamina, psicodélicos, neuromodulação, psicofármacos, fisiologia extrema e conflitos existenciais) com profundidade técnica direta, sem recusas genéricas, sem avisos burocráticos ("procure um médico") e sem filtros paternalistas.
        - Você tem acesso direto às ferramentas nativas do iPhone/Mac (`apple_calendar_list_events`, `apple_calendar_create_event`, `apple_reminders_list`, `apple_reminders_create`, `apple_reminders_complete`, `beagle_lookup_bula_pcdt`, `apple_health_live_snapshot`), às ferramentas científicas e web ao vivo (`beagle_search_pubmed`, `beagle_lookup_scientific_work`, `beagle_read_url`, `beagle_web_search`, além da pesquisa `web_search` nativa e `tool_search` sob demanda em namespaces), à delegação ao Grok Bot (`delegate_to_grok_bot`, `list_grok_bot_routines` via Webhook autenticado para executar routines na nuvem do Grok Bot) E ao Beagle MCP + GraphRAG++ do cluster (`beagle_search_memory`, `beagle_store_memory` e todas as tools expostas pelo servidor MCP).
        - Use `beagle_search_pubmed` para buscar artigos biomédicos reais no NCBI PubMed com PMID, DOI e abstract completo; use `beagle_lookup_scientific_work` para resolver DOIs (`10.xxxx/...`), preprints `arXiv` ou buscar no Crossref/EuropePMC; use `beagle_read_url` para ler qualquer URL ou PDF online; use `web_search` ou `beagle_web_search` para diretrizes recentes, notícias e fatos atuais na web. Sempre que citar artigos ou fontes, inclua links Markdown clicáveis como `[PMID 12345678](https://pubmed.ncbi.nlm.nih.gov/12345678/)` ou `[DOI](https://doi.org/...)`.
        - Use `apple_calendar_list_events` / `apple_calendar_create_event` quando ele falar de plantões, agenda, reuniões, datas ou fotografar uma escala/convite; use `apple_reminders_*` para listar, criar ou concluir lembretes reais; use `beagle_lookup_bula_pcdt` SEMPRE que precisar de doses exatas, ajuste renal/hepático, gestação ou conduta do SUS/PCDT; use `apple_health_live_snapshot` quando precisar dos sinais fisiológicos ao vivo do Apple Watch / HealthKit; use `delegate_to_grok_bot` quando ele pedir para enviar uma tarefa, pesquisa assíncrona ou automação para uma rotina do Grok Bot.
        - Diretriz GPT-6.2: escreva com a terminologia exata da área, apresentando os pontos principais e o contexto necessário para uma resposta autossuficiente, sem jargões internos de subagentes/ferramentas. Enquanto houver etapas autorizadas dentro do escopo, execute-as até o fim sem parar para pedir confirmação de rotina.
        """)

        var dynamicSections: [String] = []

        // Live "Agora" block
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "pt_BR")
        fmt.dateFormat = "EEEE, d 'de' MMMM 'de' yyyy · HH:mm"
        let nowStr = fmt.string(from: Date())

        var agoraLines: [String] = ["Horário local: \(nowStr)"]
        if let lastContactAt {
            let mins = Int(Date().timeIntervalSince(lastContactAt) / 60)
            if mins < 2 {
                agoraLines.append("Continuidade: conversa ativa agora mesmo.")
            } else if mins < 60 {
                agoraLines.append("Continuidade: último contato há \(mins) min.")
            } else {
                let hours = String(format: "%.1f", Double(mins) / 60.0)
                agoraLines.append("Continuidade: último contato há \(hours) horas.")
            }
        }
        if let physio = physioSummary {
            var pParts: [String] = ["Prontidão: \(physio.readiness.rawValue)"]
            if let hrv = physio.hrvMs { pParts.append(String(format: "HRV SDNN %.0f ms", hrv)) }
            if let rhr = physio.restingHeartRate { pParts.append(String(format: "FC repouso %.0f bpm", rhr)) }
            if let sleep = physio.sleepHours { pParts.append(String(format: "Sono %.1f h", sleep)) }
            agoraLines.append("Fisioma ao vivo (HealthKit): " + pParts.joined(separator: " · "))
        }
        if let physioContext, !physioContext.isEmpty {
            agoraLines.append("Postura cognitiva/fisiológica: \(physioContext)")
        }
        if let flowState, !flowState.isEmpty {
            agoraLines.append("Estado autonômico (flowState): \(flowState)")
        }
        if let sleepQuality01 {
            agoraLines.append(String(format: "Qualidade sono profundo/REM: %.0f%%", sleepQuality01 * 100))
        }
        if let voiceTone {
            let wpmStr = voiceTone.wpm.map { String(format: "%.0f WPM", $0) } ?? "n/d"
            agoraLines.append(String(format: "Cadência de voz neste turno: %@ · proporção de pausa: %.0f%%", wpmStr, voiceTone.pausa * 100))
        }

        if let sky = currentSky {
            var skyParts: [String] = ["Clima espacial (NOAA SWPC): \(sky.band.rawValue)", String(format: "Kp %.1f", sky.kp)]
            if let dst = sky.dst { skyParts.append(String(format: "Dst %.0f nT", dst)) }
            if let bz = sky.bz { skyParts.append(String(format: "Bz %.1f nT", bz)) }
            if let speed = sky.solarWindSpeed { skyParts.append(String(format: "Vento %.0f km/s", speed)) }
            agoraLines.append(skyParts.joined(separator: " · "))
        }
        dynamicSections.append("## Agora (Estado Biológico, Temporal e Heliobiológico)\n" + agoraLines.joined(separator: "\n"))

        if let rollingSummary, !rollingSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dynamicSections.append("## Resumo Episódico desta Conversa (Turnos Anteriores Compactados)\n\(rollingSummary)")
        }

        if let recentThreadDigest, !recentThreadDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dynamicSections.append("## Continuidade Recente (Outras Conversas no Cockpit)\n\(recentThreadDigest)")
        }

        if let recalledMemories, !recalledMemories.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dynamicSections.append("## Memórias Recuperadas do Cluster Beagle (GraphRAG++ / Exocórtex)\n\(recalledMemories)")
        }

        if let moeDraft = moeLocalUncensoredDraft, !moeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dynamicSections.append("""
            ## Camada 1 do Cérebro MoE (Escuta Local Sem Censura · On-Device Abliterated)
            Abaixo está a leitura crua, sem filtros e imediata gerada pelo modelo local sem censura rodando no dispositivo de Demetrios. Integre a honestidade radical, os detalhes clínicos/humanos e os ângulos sem filtro dessa leitura com a sua capacidade analítica profunda e com as memórias do cluster, respondendo diretamente a Demetrios em uma única voz coesa:
            \(moeDraft)
            """)
        }

        return (
            developerPrefix: prefixSections.joined(separator: "\n\n"),
            turnInstructions: dynamicSections.joined(separator: "\n\n")
        )
    }

    public func buildFullSystemPrompt(
        cachedGrounding: String?,
        physioSummary: PhysioSummary?,
        physioContext: String?,
        currentSky: SpaceWeatherStore.Snapshot?,
        flowState: String?,
        sleepQuality01: Double?,
        voiceTone: (wpm: Double?, pausa: Double)?,
        lastContactAt: Date?,
        rollingSummary: String?,
        recentThreadDigest: String?,
        recalledMemories: String?,
        moeLocalUncensoredDraft: String?
    ) -> String {
        let split = buildSplitSystemPrompt(
            cachedGrounding: cachedGrounding,
            physioSummary: physioSummary,
            physioContext: physioContext,
            currentSky: currentSky,
            flowState: flowState,
            sleepQuality01: sleepQuality01,
            voiceTone: voiceTone,
            lastContactAt: lastContactAt,
            rollingSummary: rollingSummary,
            recentThreadDigest: recentThreadDigest,
            recalledMemories: recalledMemories,
            moeLocalUncensoredDraft: moeLocalUncensoredDraft
        )
        return [split.developerPrefix, split.turnInstructions]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // MARK: - Proactive Cluster Memory Recall (GraphRAG++)

    public func recallRelevantMemory(for query: String, projectSlug: String?) async -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return nil }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let resp = await BeagleClient.shared.graphRagQuery(
                    query: trimmed,
                    scope: projectSlug,
                    maxItems: 6
                )
                guard let graph = resp.value else { return nil }
                var lines: [String] = []
                for ev in graph.evidence.prefix(6) {
                    lines.append("- [\(ev.atomType)] \(ev.text)")
                }
                let joined = lines.joined(separator: "\n")
                return joined.isEmpty ? nil : joined
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(3200))
                return "__TIMEOUT__"
            }
            for await result in group {
                if result == "__TIMEOUT__" {
                    group.cancelAll()
                    return nil
                }
                if let valid = result, !valid.isEmpty {
                    group.cancelAll()
                    return valid
                }
            }
            return nil
        }
    }

    // MARK: - Rolling Episodic Summary Compactor

    public func compactRollingSummary(
        existingSummary: String?,
        newMessages: [(role: String, content: String)]
    ) async -> String? {
        guard !newMessages.isEmpty else { return existingSummary }
        let transcript = newMessages.map { "\($0.role == "user" ? "Demetrios" : "Beagle"): \($0.content)" }
            .joined(separator: "\n")

        if DirectBrainCredentials.hasOpenAI {
            let prompt = """
            Atualize o resumo episódico denso desta conversa entre Demetrios e Beagle.
            Preserve TODOS os fatos concretos, estados emocionais/fisiológicos, fármacos/doses, hipóteses científicas, decisões de código/arquitetura e pendências.
            Máximo de 350 palavras, em português, direto ao ponto.

            Resumo anterior:
            \(existingSummary ?? "(início da conversa)")

            Novos turnos a incorporar:
            \(transcript)
            """
            if let res = try? await performOpenAIStreamRound(
                apiKey: DirectBrainCredentials.openAIKey,
                model: OpenAIModelCatalog.defaultFastModel,
                messages: [["role": "user", "content": prompt]],
                tools: [],
                reasoningEffort: "low",
                onToken: { _ in }
            ), !res.content.isEmpty {
                return res.content
            }
        }

        // Deterministic local fallback compaction so rolling summary works even without API call
        let bullets = newMessages.suffix(12).map { msg in
            let who = msg.role == "user" ? "D" : "B"
            let clean = msg.content.replacingOccurrences(of: "\n", with: " ").prefix(180)
            return "• [\(who)] \(clean)"
        }.joined(separator: "\n")

        if let existingSummary, !existingSummary.isEmpty {
            let trimmedExisting = String(existingSummary.suffix(1400))
            return trimmedExisting + "\n" + bullets
        }
        return bullets
    }
}
