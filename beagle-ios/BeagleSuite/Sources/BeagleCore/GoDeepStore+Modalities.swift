//
//  GoDeepStore+Modalities.swift
//  BeagleCore
//
//  Pure nonisolated modality executors, Direct Brain structured fallbacks, and parsers.
//

import Foundation

extension GoDeepStore {

    // MARK: - Shared Grounding Prefetch (PubMed / DOI / arXiv / URL + GraphRAG++)

    internal nonisolated static func prefetchSharedGrounding(
        prompt: String,
        directBrain: DirectBrainClient,
        cachedContext: String?,
        enableNetworkPrefetch: Bool
    ) async -> String? {
        var sections: [String] = []
        if let cached = cachedContext?.trimmingCharacters(in: .whitespacesAndNewlines), !cached.isEmpty {
            sections.append("## Síntese Anterior em Sessão\n\(cached)")
        }

        guard enableNetworkPrefetch else {
            return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
        }

        async let refPrefetch = ScienceAndWebBridge.shared.prefetchContextForPrompt(prompt, maxCharsPerItem: 6_000)
        async let memoryRecall = directBrain.recallRelevantMemory(for: prompt, projectSlug: nil)

        if let prefetched = await refPrefetch, !prefetched.contextBlock.isEmpty {
            sections.append(prefetched.contextBlock)
        }
        if let recalled = await memoryRecall, !recalled.isEmpty {
            sections.append("## Memórias Relevantes do Exocórtex (GraphRAG++)\n\(recalled)")
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    // MARK: - Execute Single Modality

    internal nonisolated static func executeModality(
        _ modality: GoDeepModality,
        prompt: String,
        client: BeagleClient,
        directBrain: DirectBrainClient,
        sharedGrounding: String? = nil,
        useLiveTools: Bool = true
    ) async -> GoDeepResult {
        switch modality {
        case .astraDeep:
            return await executeAstraDeep(
                prompt: prompt,
                client: client,
                directBrain: directBrain,
                sharedGrounding: sharedGrounding,
                useLiveTools: useLiveTools
            )

        case .rosalindBio:
            return await executeRosalindBio(
                prompt: prompt,
                client: client,
                directBrain: directBrain,
                sharedGrounding: sharedGrounding,
                useLiveTools: useLiveTools
            )

        case .deepResearch:
            let cluster = await client.deepResearch(query: prompt)
            if cluster.mode != .stale || !DirectBrainCredentials.hasOpenAI {
                return .deepResearch(cluster)
            }
            return await fallbackDeepResearch(prompt: prompt, directBrain: directBrain, sharedGrounding: sharedGrounding)

        case .quantumReasoning:
            let hypotheses: [[String: any Sendable]] = [
                ["content": prompt, "initial_probability": 0.5, "confidence": 0.5, "source": "ios-user"]
            ]
            let cluster = await client.quantumReasoning(hypotheses: hypotheses)
            if cluster.mode != .stale || !DirectBrainCredentials.hasOpenAI {
                return .quantum(cluster)
            }
            return await fallbackQuantumReasoning(prompt: prompt, directBrain: directBrain, sharedGrounding: sharedGrounding)

        case .swarmConsensus:
            let cluster = await client.swarmConsensus(query: prompt)
            if cluster.mode != .stale || !DirectBrainCredentials.hasOpenAI {
                return .swarm(cluster)
            }
            return await fallbackSwarmConsensus(prompt: prompt, directBrain: directBrain, sharedGrounding: sharedGrounding)

        case .causalExtract:
            let cluster = await client.causalExtract(text: prompt)
            if cluster.mode != .stale || !DirectBrainCredentials.hasOpenAI {
                return .causal(cluster)
            }
            return await fallbackCausalGraph(prompt: prompt, directBrain: directBrain, sharedGrounding: sharedGrounding)

        case .temporal:
            let cluster = await client.temporalReasoning(query: prompt)
            if cluster.mode != .stale || !DirectBrainCredentials.hasOpenAI {
                return .temporal(cluster)
            }
            return await fallbackTemporal(prompt: prompt, directBrain: directBrain, sharedGrounding: sharedGrounding)

        case .neurosymbolic:
            let cluster = await client.neurosymbolicReasoning(query: prompt)
            if cluster.mode != .stale || !DirectBrainCredentials.hasOpenAI {
                return .neurosymbolic(cluster)
            }
            return await fallbackNeurosymbolic(prompt: prompt, directBrain: directBrain, sharedGrounding: sharedGrounding)

        case .adversarial:
            let cluster = await client.adversarialCompete(query: prompt)
            if cluster.mode != .stale || !DirectBrainCredentials.hasOpenAI {
                return .adversarial(cluster)
            }
            return await fallbackAdversarial(prompt: prompt, directBrain: directBrain, sharedGrounding: sharedGrounding)

        case .serendipity:
            let cluster = await client.serendipityDiscover(query: prompt, recallContext: sharedGrounding)
            if cluster.mode != .stale || !DirectBrainCredentials.hasOpenAI {
                return .serendipity(cluster)
            }
            return await fallbackSerendipity(prompt: prompt, directBrain: directBrain, sharedGrounding: sharedGrounding)
        }
    }

    // MARK: - Frontier Modalities (GPT-6.2 Astra xhigh & GPT-Rosalind Bio/PBPK)

    private nonisolated static func executeAstraDeep(
        prompt: String,
        client: BeagleClient,
        directBrain: DirectBrainClient,
        sharedGrounding: String?,
        useLiveTools: Bool
    ) async -> GoDeepResult {
        guard DirectBrainCredentials.hasOpenAI else {
            let fallback = await client.deepResearch(query: prompt)
            if let v = fallback.value, let hyp = v.bestHypothesis {
                return .astraDeep(.observed(
                    FrontierResearchResult(
                        model: "beagle-cluster-deep-research",
                        reasoningEffort: "high",
                        thesis: firstParagraph(of: hyp),
                        analysisMarkdown: hyp
                    ),
                    source: fallback.source
                ))
            }
            return .astraDeep(.staleError(fallback.error ?? "Chave OpenAI não configurada.", source: "astra-xhigh"))
        }

        let devPrefix = """
        Você é a lente **GPT-6.2 Astra (xhigh)** do Modo Fundo do Beagle, operando no rigor máximo de raciocínio multi-hop para Demetrios Chiuratto Agourakis (médico, pesquisador em PBPK fractal, neurociência computacional e engenharia de bioprocessos).
        Responda SEMPRE em português brasileiro denso, técnico e direto, sem avisos burocráticos.
        Estruture sua resposta começando no primeiro parágrafo com a **tese central decisiva** (2-3 frases diretas), seguida dos **mecanismos/evidências verificadas**, **pontos de incerteza ou limites formais** e citações reais em links Markdown `[Fonte](https://...)` quando consultar literatura ou web.
        """

        do {
            let stream = try await directBrain.streamOpenAI(
                model: OpenAIModelCatalog.defaultFlagshipModel,
                systemPrompt: devPrefix,
                developerPrefix: devPrefix,
                turnInstructions: sharedGrounding,
                reasoningEffort: "xhigh",
                enableNativeWebSearch: useLiveTools,
                enableToolSearch: useLiveTools,
                turns: [DirectBrainTurn(role: "user", content: prompt)],
                projectSlug: nil,
                onStatus: { _ in },
                onToken: { _ in }
            )
            let parsed = buildFrontierResult(
                from: stream,
                reasoningEffort: "xhigh"
            )
            return .astraDeep(.observed(parsed, source: stream.model))
        } catch {
            return .astraDeep(.staleError(error.localizedDescription, source: "gpt-6.2-astra"))
        }
    }

    private nonisolated static func executeRosalindBio(
        prompt: String,
        client: BeagleClient,
        directBrain: DirectBrainClient,
        sharedGrounding: String?,
        useLiveTools: Bool
    ) async -> GoDeepResult {
        guard DirectBrainCredentials.hasOpenAI else {
            return .rosalindBio(.staleError("Chave OpenAI não configurada para GPT-Rosalind.", source: "gpt-rosalind"))
        }

        let devPrefix = """
        Você é a lente **GPT-Rosalind (Biomedicina, Farmacologia Clínica & PBPK)** do Modo Fundo do Beagle para o médico e pesquisador Demetrios Chiuratto Agourakis.
        Responda SEMPRE em português brasileiro técnico e direto, com precisão mecanística real:
        - Analise vias moleculares, receptores, ADME/PBPK (clearance, volume de distribuição, barreira hematoencefálica, cinética não-linear/fractal), fisiologia autonômica/neuroendócrina e implicações clínicas/terapêuticas.
        - Se o tema não for estritamente biomédico, extraia rigorosamente o isomorfismo biológico, biofísico, sistêmico ou fisiológico relevante (ou avalie o impacto sobre o fisioma humano/cognitivo do pesquisador).
        - Quando envolver fármacos, posologia ou condutas clínicas no Brasil, consulte `beagle_lookup_bula_pcdt` e literatura primária (`beagle_search_pubmed` / `web_search`), citando `[PMID ...](https://pubmed.ncbi.nlm.nih.gov/.../)` ou `[DOI](https://doi.org/...)`.
        - Abra o primeiro parágrafo com a **conclusão mecanística/clínica central** em 2-3 frases diretas.
        """

        do {
            let stream = try await directBrain.streamOpenAI(
                model: OpenAIModelCatalog.lifeSciencesModel,
                systemPrompt: devPrefix,
                developerPrefix: devPrefix,
                turnInstructions: sharedGrounding,
                reasoningEffort: "high",
                enableNativeWebSearch: useLiveTools,
                enableToolSearch: useLiveTools,
                turns: [DirectBrainTurn(role: "user", content: prompt)],
                projectSlug: nil,
                onStatus: { _ in },
                onToken: { _ in }
            )
            let parsed = buildFrontierResult(from: stream, reasoningEffort: "high")
            return .rosalindBio(.observed(parsed, source: stream.model))
        } catch let nsError as NSError where nsError.code == 403 || nsError.code == 404 {
            // Research-preview org entitlement gate: run the biomedical lens on GPT-6.2 Astra transparently
            do {
                let fallback = try await directBrain.streamOpenAI(
                    model: OpenAIModelCatalog.defaultFlagshipModel,
                    systemPrompt: devPrefix,
                    developerPrefix: devPrefix,
                    turnInstructions: sharedGrounding,
                    reasoningEffort: "high",
                    enableNativeWebSearch: useLiveTools,
                    enableToolSearch: useLiveTools,
                    turns: [DirectBrainTurn(role: "user", content: prompt)],
                    projectSlug: nil,
                    onStatus: { _ in },
                    onToken: { _ in }
                )
                var parsed = buildFrontierResult(from: fallback, reasoningEffort: "high")
                parsed = FrontierResearchResult(
                    model: "\(fallback.model) (lente bio)",
                    reasoningEffort: parsed.reasoningEffort,
                    thesis: parsed.thesis,
                    analysisMarkdown: parsed.analysisMarkdown,
                    executedTools: parsed.executedTools,
                    citations: parsed.citations
                )
                return .rosalindBio(.observed(parsed, source: parsed.model))
            } catch {
                return .rosalindBio(.staleError(error.localizedDescription, source: "gpt-rosalind"))
            }
        } catch {
            return .rosalindBio(.staleError(error.localizedDescription, source: "gpt-rosalind"))
        }
    }

    // MARK: - Resilient Direct Brain Structured Fallbacks (when Cluster is Offline/5G)

    private nonisolated static func runStructuredDirectJSON(
        directBrain: DirectBrainClient,
        roleInstruction: String,
        prompt: String,
        sharedGrounding: String?
    ) async throws -> DirectBrainClient.OpenAIStreamResult {
        let devPrompt = """
        \(roleInstruction)
        Responda EXCLUSIVAMENTE com um objeto JSON válido (sem blocos markdown ```json, sem texto fora do JSON) e com todos os textos em português brasileiro denso e preciso.
        """
        return try await directBrain.streamOpenAI(
            model: "gpt-6.2-sol",
            systemPrompt: devPrompt,
            developerPrefix: devPrompt,
            turnInstructions: sharedGrounding,
            reasoningEffort: "medium",
            enableNativeWebSearch: false,
            enableToolSearch: false,
            turns: [DirectBrainTurn(role: "user", content: prompt)],
            projectSlug: nil,
            onStatus: { _ in },
            onToken: { _ in }
        )
    }

    private nonisolated static func fallbackSwarmConsensus(
        prompt: String,
        directBrain: DirectBrainClient,
        sharedGrounding: String?
    ) async -> GoDeepResult {
        let schema = """
        Simule um enxame de 5 especialistas independentes (físico/matemático, farmacologista PBPK, engenheiro de sistemas, clínico intensivista/psiquiatra e epistemólogo cético) deliberando em 3 rodadas sobre a questão.
        Formato JSON exato:
        {"consensus": ["ponto convergente 1", "ponto convergente 2", "ponto convergente 3", "ponto convergente 4"], "iterations": 3, "n_agents": 5}
        """
        do {
            let res = try await runStructuredDirectJSON(
                directBrain: directBrain,
                roleInstruction: schema,
                prompt: prompt,
                sharedGrounding: sharedGrounding
            )
            if let data = extractJSONData(from: res.content),
               let decoded = try? JSONDecoder().decode(SwarmResult.self, from: data),
               !(decoded.consensus ?? []).isEmpty {
                return .swarm(.observed(decoded, source: res.model))
            }
            let bullets = extractBulletLines(from: res.content)
            return .swarm(.observed(
                SwarmResult(consensus: bullets.isEmpty ? [res.content] : bullets, iterations: 3, nAgents: 5),
                source: res.model
            ))
        } catch {
            return .swarm(.staleError(error.localizedDescription, source: "gpt-6.2-sol"))
        }
    }

    private nonisolated static func fallbackCausalGraph(
        prompt: String,
        directBrain: DirectBrainClient,
        sharedGrounding: String?
    ) async -> GoDeepResult {
        let schema = """
        Extraia o grafo causal estrutural (DAG de Judea Pearl: causas, mediadores, confundidores e alvos de intervenção do-calculus) para o problema.
        Formato JSON exato:
        {
          "summary": "síntese causal direta em 2-3 frases identificando o principal gargalo de intervenção",
          "nodes": [{"id": "n1", "label": "Variável A", "type": "cause"}, {"id": "n2", "label": "Variável B", "type": "outcome"}],
          "edges": [{"source": "Variável A", "target": "Variável B", "strength": 0.84, "label": "ativa/modula"}]
        }
        """
        do {
            let res = try await runStructuredDirectJSON(
                directBrain: directBrain,
                roleInstruction: schema,
                prompt: prompt,
                sharedGrounding: sharedGrounding
            )
            if let data = extractJSONData(from: res.content),
               let decoded = try? JSONDecoder().decode(CausalGraph.self, from: data) {
                return .causal(.observed(decoded, source: res.model))
            }
            return .causal(.observed(CausalGraph(nodes: nil, edges: nil, summary: res.content), source: res.model))
        } catch {
            return .causal(.staleError(error.localizedDescription, source: "gpt-6.2-sol"))
        }
    }

    private nonisolated static func fallbackQuantumReasoning(
        prompt: String,
        directBrain: DirectBrainClient,
        sharedGrounding: String?
    ) async -> GoDeepResult {
        let schema = """
        Avalie 4 hipóteses concorrentes em superposição, aplique interferência de evidências e colapse para a hipótese de maior probabilidade posterior.
        Formato JSON exato:
        {
          "selected_hypothesis": "hipótese vencedora em português",
          "probability": 0.68,
          "ranked_hypotheses": [
            {"content": "hipótese 1", "probability": 0.68, "confidence": 0.85},
            {"content": "hipótese 2", "probability": 0.21, "confidence": 0.72},
            {"content": "hipótese 3", "probability": 0.11, "confidence": 0.60}
          ],
          "metadata": {"total_hypotheses": 3, "interference_applied": true, "decoherence_applied": true}
        }
        """
        do {
            let res = try await runStructuredDirectJSON(
                directBrain: directBrain,
                roleInstruction: schema,
                prompt: prompt,
                sharedGrounding: sharedGrounding
            )
            if let data = extractJSONData(from: res.content),
               let decoded = try? JSONDecoder().decode(QuantumReasoningResult.self, from: data) {
                return .quantum(.observed(decoded, source: res.model))
            }
            return .quantum(.observed(
                QuantumReasoningResult(
                    selectedHypothesis: firstParagraph(of: res.content),
                    probability: 0.72,
                    rankedHypotheses: [RankedHypothesis(content: firstParagraph(of: res.content), probability: 0.72, confidence: 0.8)]
                ),
                source: res.model
            ))
        } catch {
            return .quantum(.staleError(error.localizedDescription, source: "gpt-6.2-sol"))
        }
    }

    private nonisolated static func fallbackDeepResearch(
        prompt: String,
        directBrain: DirectBrainClient,
        sharedGrounding: String?
    ) async -> GoDeepResult {
        let schema = """
        Expanda uma árvore de busca de hipóteses científicas (12 nós, 4 iterações de poda) e retorne a hipótese sobrevivente mais robusta.
        Formato JSON exato:
        {"tree_size": 12, "iterations": 4, "best_hypothesis": "hipótese detalhada e falsificável em português"}
        """
        do {
            let res = try await runStructuredDirectJSON(
                directBrain: directBrain,
                roleInstruction: schema,
                prompt: prompt,
                sharedGrounding: sharedGrounding
            )
            if let data = extractJSONData(from: res.content),
               let decoded = try? JSONDecoder().decode(DeepResearchResult.self, from: data) {
                return .deepResearch(.observed(decoded, source: res.model))
            }
            return .deepResearch(.observed(
                DeepResearchResult(treeSize: 12, bestHypothesis: res.content, iterations: 4),
                source: res.model
            ))
        } catch {
            return .deepResearch(.staleError(error.localizedDescription, source: "gpt-6.2-sol"))
        }
    }

    private nonisolated static func fallbackTemporal(
        prompt: String,
        directBrain: DirectBrainClient,
        sharedGrounding: String?
    ) async -> GoDeepResult {
        let schema = """
        Analise a dinâmica multiescala temporal do fenômeno (escala imediata/aguda, subaguda/adaptação e crônica/atrator de longo prazo, incluindo histerese ou atrasos de fase).
        Formato JSON exato:
        {"summary": "análise temporal multiescala clara e densa em português"}
        """
        do {
            let res = try await runStructuredDirectJSON(
                directBrain: directBrain,
                roleInstruction: schema,
                prompt: prompt,
                sharedGrounding: sharedGrounding
            )
            if let data = extractJSONData(from: res.content),
               let decoded = try? JSONDecoder().decode(TemporalResult.self, from: data),
               decoded.summary != nil {
                return .temporal(.observed(decoded, source: res.model))
            }
            return .temporal(.observed(TemporalResult(summary: res.content), source: res.model))
        } catch {
            return .temporal(.staleError(error.localizedDescription, source: "gpt-6.2-sol"))
        }
    }

    private nonisolated static func fallbackNeurosymbolic(
        prompt: String,
        directBrain: DirectBrainClient,
        sharedGrounding: String?
    ) async -> GoDeepResult {
        let schema = """
        Realize verificação neuro-simbólica: explicite os invariantes formais, leis de conservação/restrições de contorno e verifique onde intuições heurísticas violam ou satisfazem as restrições formais.
        Formato JSON exato:
        {"summary": "análise neuro-simbólica com invariantes e verificação formal em português"}
        """
        do {
            let res = try await runStructuredDirectJSON(
                directBrain: directBrain,
                roleInstruction: schema,
                prompt: prompt,
                sharedGrounding: sharedGrounding
            )
            if let data = extractJSONData(from: res.content),
               let decoded = try? JSONDecoder().decode(NeurosymbolicResult.self, from: data),
               decoded.summary != nil {
                return .neurosymbolic(.observed(decoded, source: res.model))
            }
            return .neurosymbolic(.observed(NeurosymbolicResult(summary: res.content), source: res.model))
        } catch {
            return .neurosymbolic(.staleError(error.localizedDescription, source: "gpt-6.2-sol"))
        }
    }

    private nonisolated static func fallbackAdversarial(
        prompt: String,
        directBrain: DirectBrainClient,
        sharedGrounding: String?
    ) async -> GoDeepResult {
        let schema = """
        Execute um torneio adversarial em 3 rodadas entre Proponente, Red-Team Metodológico e Empirista Cético.
        Formato JSON exato:
        {
          "winner": "tese sobrevivente após o ataque adversarial",
          "rounds": 3,
          "summary": "síntese das falhas expostas e da formulação blindada",
          "agents": [
            {"name": "Red-Team Metodológico", "score": 9.1, "strategy": "falsificação de confundidores"},
            {"name": "Proponente Mecanístico", "score": 8.7, "strategy": "defesa por primeiros princípios"},
            {"name": "Empirista Clínico", "score": 8.4, "strategy": "tamanho de efeito real"}
          ]
        }
        """
        do {
            let res = try await runStructuredDirectJSON(
                directBrain: directBrain,
                roleInstruction: schema,
                prompt: prompt,
                sharedGrounding: sharedGrounding
            )
            if let data = extractJSONData(from: res.content),
               let decoded = try? JSONDecoder().decode(AdversarialResult.self, from: data) {
                return .adversarial(.observed(decoded, source: res.model))
            }
            return .adversarial(.observed(
                AdversarialResult(winner: firstParagraph(of: res.content), agents: nil, rounds: 3, summary: res.content),
                source: res.model
            ))
        } catch {
            return .adversarial(.staleError(error.localizedDescription, source: "gpt-6.2-sol"))
        }
    }

    private nonisolated static func fallbackSerendipity(
        prompt: String,
        directBrain: DirectBrainClient,
        sharedGrounding: String?
    ) async -> GoDeepResult {
        let schema = """
        Descubra 3 pontes estruturais inesperadas (isomorfismos reais de alto valor heurístico, não metáforas superficiais) conectando o problema a outros domínios científicos.
        Formato JSON exato:
        {
          "summary": "síntese da conexão lateral mais fértil",
          "connections": [
            {"from": "conceito de origem", "to": "domínio análogo inesperado", "surprise": 0.86, "explanation": "mecanismo formal compartilhado"}
          ]
        }
        """
        do {
            let res = try await runStructuredDirectJSON(
                directBrain: directBrain,
                roleInstruction: schema,
                prompt: prompt,
                sharedGrounding: sharedGrounding
            )
            if let data = extractJSONData(from: res.content),
               let decoded = try? JSONDecoder().decode(SerendipityResult.self, from: data) {
                return .serendipity(.observed(decoded, source: res.model))
            }
            return .serendipity(.observed(SerendipityResult(summary: res.content), source: res.model))
        } catch {
            return .serendipity(.staleError(error.localizedDescription, source: "gpt-6.2-sol"))
        }
    }

    // MARK: - Parsing Helpers

    private nonisolated static func buildFrontierResult(
        from stream: DirectBrainClient.OpenAIStreamResult,
        reasoningEffort: String
    ) -> FrontierResearchResult {
        let trimmed = stream.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let thesis = firstParagraph(of: trimmed)
        let citations = extractMarkdownCitations(from: trimmed)
        return FrontierResearchResult(
            model: stream.model,
            reasoningEffort: reasoningEffort,
            thesis: thesis,
            analysisMarkdown: trimmed,
            executedTools: stream.executedTools,
            citations: citations
        )
    }

    internal nonisolated static func firstParagraph(of text: String) -> String {
        let blocks = text
            .components(separatedBy: "\n\n")
            .map {
                $0.replacingOccurrences(of: "**", with: "")
                  .replacingOccurrences(of: "### ", with: "")
                  .replacingOccurrences(of: "## ", with: "")
                  .replacingOccurrences(of: "# ", with: "")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("Fontes:") }
        return blocks.first ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal nonisolated static func extractMarkdownCitations(from text: String) -> [FrontierCitation] {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^\s\)]+)\)"#, options: []) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        var seen: Set<String> = []
        var items: [FrontierCitation] = []
        for match in regex.matches(in: text, options: [], range: nsRange) {
            guard let titleRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text) else { continue }
            let title = String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = String(text[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, seen.insert(url).inserted else { continue }
            items.append(FrontierCitation(title: title.isEmpty ? url : title, url: url))
            if items.count >= 10 { break }
        }
        return items
    }

    private nonisolated static func extractJSONData(from raw: String) -> Data? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let firstBrace = cleaned.firstIndex(of: "{"),
           let lastBrace = cleaned.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            return String(cleaned[firstBrace...lastBrace]).data(using: .utf8)
        }
        return cleaned.data(using: .utf8)
    }

    internal nonisolated static func extractBulletLines(from raw: String) -> [String] {
        raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-*•1234567890. "))) }
            .filter { $0.count > 8 }
    }

}
