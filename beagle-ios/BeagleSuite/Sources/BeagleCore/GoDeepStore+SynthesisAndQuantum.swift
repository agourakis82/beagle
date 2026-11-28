//
//  GoDeepStore+SynthesisAndQuantum.swift
//  BeagleCore
//
//  Streaming pt-BR cross-modality synthesis, failed-modality retry, and
//  Quantum Hypothesis superposition / interference / collapse orchestration.
//

import Foundation

extension GoDeepStore {
    // MARK: - Synthesis (Streaming pt-BR via GPT-6.2 Astra -> Claude -> Cluster -> MLX)

    func generateSynthesis(prompt: String, sharedGrounding: String?) async -> String? {
        let summaries = modalityStates.compactMap { state -> String? in
            guard let result = state.result else { return nil }
            switch result {
            case .astraDeep(let t), .rosalindBio(let t):
                let body = t.value?.analysisMarkdown ?? result.summary
                return "[\(state.modality.displayName)]:\n\(String(body.prefix(3_000)))"
            default:
                return "[\(state.modality.displayName)]: \(result.summary)"
            }
        }
        guard !summaries.isEmpty else { return nil }

        let synthesisSystem = """
        Você é o motor de síntese executiva e científica do Modo Fundo do Beagle.
        Responda SEMPRE em português brasileiro natural, denso e incisivo, integrando todas as lentes em uma síntese decisiva:
        1) Convergência central e mecanismo dominante;
        2) Tensões reais, contradições ou limites de validade entre as lentes;
        3) Próxima ação experimental, clínica ou arquitetural concreta ( preservando links Markdown relevantes de PMID/DOI/fontes se houver).
        """

        let synthesisPrompt = """
        Integre os resultados das \(summaries.count) modalidades de raciocínio abaixo para a questão: "\(prompt)"

        \(summaries.joined(separator: "\n\n"))
        """

        return await streamOrFallbackSynthesis(
            systemPrompt: synthesisSystem,
            userPrompt: synthesisPrompt,
            turnInstructions: sharedGrounding
        )
    }

    private func streamOrFallbackSynthesis(
        systemPrompt: String,
        userPrompt: String,
        turnInstructions: String?
    ) async -> String? {
        if DirectBrainCredentials.hasOpenAI {
            var liveBuffer = ""
            if let res = try? await directBrain.streamOpenAI(
                model: OpenAIModelCatalog.defaultFlagshipModel,
                systemPrompt: systemPrompt,
                developerPrefix: systemPrompt,
                turnInstructions: turnInstructions,
                reasoningEffort: "high",
                enableNativeWebSearch: false,
                enableToolSearch: false,
                turns: [DirectBrainTurn(role: "user", content: userPrompt)],
                projectSlug: nil,
                onStatus: { _ in },
                onToken: { [weak self] delta in
                    await MainActor.run {
                        guard let self else { return }
                        liveBuffer += delta
                        self.synthesis = liveBuffer
                    }
                }
            ), !res.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return res.content
            }
        }

        if DirectBrainCredentials.hasAnthropic {
            var liveBuffer = ""
            if let res = try? await directBrain.streamAnthropic(
                model: "claude-opus-4-8",
                systemPrompt: systemPrompt,
                turns: [DirectBrainTurn(role: "user", content: userPrompt)],
                projectSlug: nil,
                onToken: { [weak self] delta in
                    await MainActor.run {
                        guard let self else { return }
                        liveBuffer += delta
                        self.synthesis = liveBuffer
                    }
                }
            ), !res.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return res.content
            }
        }

        let cloudResult = await client.chat(prompt: userPrompt, system: systemPrompt)
        if let response = cloudResult.value?.response, !response.isEmpty {
            return response
        }

        let llm = LocalLLMEngine.shared
        if llm.isReady, let localResult = try? await llm.respond(to: "\(systemPrompt)\n\n\(userPrompt)") {
            return localResult
        }

        return nil
    }

    // MARK: - Retry Failed Modality

    public func retryModality(_ modality: GoDeepModality) {
        guard let idx = modalityStates.firstIndex(where: { $0.modality == modality }),
              modalityStates[idx].isFailed,
              let prompt = activeSession?.prompt else { return }

        modalityStates[idx].phase = .waiting
        modalityStates[idx].startedAt = nil
        modalityStates[idx].completedAt = nil

        let useLiveTools = enableLiveResearchTools
        Task { [weak self, client, directBrain] in
            guard let self else { return }
            let messages = Self.thinkingMessages[modality] ?? ["Repetindo análise..."]
            if let idx = self.modalityStates.firstIndex(where: { $0.modality == modality }) {
                self.modalityStates[idx].phase = .thinking(messages[0])
                self.modalityStates[idx].startedAt = .now
            }

            let result = await Self.executeModality(
                modality,
                prompt: prompt,
                client: client,
                directBrain: directBrain,
                useLiveTools: useLiveTools
            )
            self.resolveModality(modality, result: result)
        }
    }

    // MARK: - Quantum Go Deeper

    /// Quantum-mode exploration: generate hypotheses in superposition,
    /// explore each in parallel (using Rosalind for physiological/PBPK lens and Astra/Quantum for the others),
    /// interfere, and collapse into a pt-BR synthesis.
    func goDeeperQuantum(prompt: String, cachedContext: String?) {
        let modalities = orderedEnabledModalities()
        let session = GoDeepSession(prompt: prompt, modalities: modalities)
        activeSession = session
        isRunning = true
        synthesis = nil
        isSynthesizing = false

        let engine = QuantumHypothesisEngine.shared
        let useLiveTools = enableLiveResearchTools

        runTask = Task { [weak self, client, directBrain] in
            guard let self else { return }

            let sharedGrounding = await Self.prefetchSharedGrounding(
                prompt: prompt,
                directBrain: directBrain,
                cachedContext: cachedContext,
                enableNetworkPrefetch: useLiveTools
            )

            // 1. Generate hypotheses in superposition
            var hyps = await engine.superpose(question: prompt)
            self.hypotheses = hyps

            self.totalCount = hyps.count
            self.completedCount = 0

            self.modalityStates = hyps.map { hyp in
                let lane: GoDeepModality = hyp.perspective.contains("PBPK") ? .rosalindBio : .quantumReasoning
                var state = ModalityState(modality: lane)
                state.phase = .thinking("Explorando: \(hyp.perspective)...")
                state.startedAt = .now
                return state
            }

            self.onResearchStart?(session.id.uuidString, "Quântico: \(String(prompt.prefix(42)))", "exocortex")
            self.onResearchStateChange?(0, hyps.count + 1, hyps.count * 18, "Superposição Quântica", nil, false)

            // 2. Explore each hypothesis in parallel
            await withTaskGroup(of: (Int, GoDeepResult).self) { group in
                for (idx, hyp) in hyps.enumerated() {
                    let hypothesisPrompt = "[\(hyp.perspective)] \(prompt)"
                    let targetModality: GoDeepModality = hyp.perspective.contains("PBPK")
                        ? .rosalindBio
                        : (DirectBrainCredentials.hasOpenAI ? .astraDeep : .quantumReasoning)
                    group.addTask { [client, directBrain] in
                        let result = await Self.executeModality(
                            targetModality,
                            prompt: hypothesisPrompt,
                            client: client,
                            directBrain: directBrain,
                            sharedGrounding: sharedGrounding,
                            useLiveTools: useLiveTools
                        )
                        return (idx, result)
                    }
                }

                for await (idx, result) in group {
                    guard !Task.isCancelled else { return }

                    let resultText = result.summary
                    engine.evolve(&hyps, at: idx, withText: resultText)
                    self.hypotheses = hyps

                    if idx < self.modalityStates.count {
                        self.modalityStates[idx].completedAt = .now
                        if result.isError {
                            self.modalityStates[idx].phase = .failed(resultText)
                        } else {
                            self.modalityStates[idx].phase = .resolved(result)
                        }
                    }

                    self.completedCount += 1
                    let eta = max(8, (self.totalCount - self.completedCount) * 15)
                    self.onResearchUpdate?(
                        self.completedCount,
                        self.totalCount,
                        eta
                    )
                    let nextLens = Self.activeLensBadge(for: self.modalityStates, isSynthesizing: false)
                    self.onResearchStateChange?(
                        self.completedCount,
                        self.totalCount + 1,
                        eta,
                        nextLens,
                        result.isError ? nil : String(resultText.prefix(140)),
                        false
                    )
                }
            }

            guard !Task.isCancelled else { return }

            // 3. Interference
            let interference = engine.interfere(hyps)
            self.interferenceResult = interference

            // 4. Collapse
            engine.collapse(&hyps)
            self.hypotheses = hyps

            // 5. Synthesis in pt-BR
            self.isSynthesizing = true
            self.onResearchStateChange?(
                self.totalCount,
                self.totalCount + 1,
                10,
                "Colapso Quântico",
                hyps.first.map { String($0.text.prefix(140)) },
                false
            )

            let rankedSummaries = hyps
                .sorted { $0.probability > $1.probability }
                .map { "[\($0.perspective) | p=\(String(format: "%.2f", $0.probability))] \($0.text)" }

            var emergentNote = ""
            if !interference.novelEmergent.isEmpty {
                emergentNote = "\n\nTensões emergentes:\n" + interference.novelEmergent.joined(separator: "\n")
            }

            let synthesisSystem = """
            Você é o agente de colapso quântico de hipóteses do Beagle. Responda SEMPRE em português brasileiro denso, técnico e direto.
            """

            let synthesisPrompt = """
            Exploração em superposição quântica para: "\(prompt)"

            Hipóteses após interferência e colapso (ordenadas por probabilidade):
            \(rankedSummaries.joined(separator: "\n"))

            Reforços construtivos: \(interference.constructive.count)
            Interferências destrutivas: \(interference.destructive.count)\(emergentNote)

            Sintetize em português brasileiro: qual hipótese venceu o colapso e por quê? Integre o sinal dominante, destaque o que emergiu das interferências destrutivas e proponha um teste decisivo para falsear ou confirmar a conclusão.
            """

            self.synthesis = await self.streamOrFallbackSynthesis(
                systemPrompt: synthesisSystem,
                userPrompt: synthesisPrompt,
                turnInstructions: sharedGrounding
            )

            self.isSynthesizing = false
            self.onResearchStateChange?(
                self.totalCount + 1,
                self.totalCount + 1,
                0,
                "Concluído",
                self.synthesis.map { String($0.prefix(160)) },
                true
            )
            self.onResearchEnd?(self.synthesis != nil ? "quantum-complete" : "no synthesis")

            self.isRunning = false
            if var session = self.activeSession {
                session.completedAt = .now
                self.activeSession = session
                self.recentSessions.insert(session, at: 0)
                if self.recentSessions.count > 10 { self.recentSessions.removeLast() }
                self.onSessionComplete?(self.makePersistencePayload(prompt: session.prompt))
            }
        }
    }

}
