//
//  GoDeepStore+Simulation.swift
//  BeagleCore
//
//  Quantitative simulation execution and longitudinal exploration comparison.
//

import Foundation

extension GoDeepStore {

    /// Runs or steers a quantitative simulation / code verification via `OpenAIAgentsSessionClient`
    /// and stores the verified output on this session (ready for `.pdf` / `.md` export).
    public func runSimulation(
        prompt: String,
        steeringInstruction: String? = nil,
        agentsClient: OpenAIAgentsSessionClient = .shared
    ) async {
        guard !isSimulating else { return }
        isSimulating = true
        simulationStatusLine = "Preparando simulação quantitativa…"
        if steeringInstruction == nil {
            simulationOutput = ""
        } else if let prev = simulationOutput, !prev.isEmpty {
            simulationOutput = prev + "\n\n---\n\n"
        }
        let basePrefix = simulationOutput ?? ""

        simulationOutput = basePrefix

        do {
            let result = try await agentsClient.runScientificSimulationTurn(
                apiKey: DirectBrainCredentials.openAIKey,
                prompt: prompt,
                synthesisContext: synthesis,
                existingSessionId: simulationSessionId,
                steeringInstruction: steeringInstruction,
                directBrain: directBrain,
                onStatus: { [weak self] line in
                    await MainActor.run {
                        self?.simulationStatusLine = line
                    }
                },
                onDelta: { [weak self] delta in
                    await MainActor.run {
                        guard let self else { return }
                        self.simulationOutput = (self.simulationOutput ?? basePrefix) + delta
                    }
                }
            )
            simulationSessionId = result.sessionId
            let currentText = simulationOutput ?? ""
            if currentText == basePrefix || currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                simulationOutput = basePrefix + result.output
            }
            simulationStatusLine = result.usedSandboxAPI
                ? "Sandbox agêntico concluído"
                : "Simulação analítica concluída (GPT-6.2 Sol)"
            if let activePrompt = activeSession?.prompt {
                onSessionComplete?(makePersistencePayload(prompt: activePrompt))
            }
        } catch {
            let errMsg = "Falha na simulação: \(error.localizedDescription)"
            simulationStatusLine = errMsg
            if (simulationOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                simulationOutput = errMsg
            }
        }
        isSimulating = false
    }

    /// Generates a longitudinal epistemic comparison between two saved Modo Fundo explorations in `pt-BR`.
    public static func compareExplorations(
        firstPrompt: String,
        firstDate: Date,
        firstSynthesis: String,
        secondPrompt: String,
        secondDate: Date,
        secondSynthesis: String,
        directBrain: DirectBrainClient = .shared,
        client: BeagleClient = .shared,
        onToken: (@Sendable (String) async -> Void)? = nil
    ) async -> String {
        let iso = ISO8601DateFormatter()
        let systemPrompt = """
        Você é o analista epistemológico longitudinal do Beagle Modo Fundo (GPT-6.2 Astra).
        Compare rigorosamente duas explorações científicas/clínicas de Demetrios em português brasileiro denso e direto:
        ### 1. Invariantes & Convergências
        O que permaneceu sólido, confirmado ou estruturalmente idêntico entre as duas investigações.
        ### 2. Deslocamentos, Refutações & Evolução
        O que mudou de foco, hipótese, mecanismo ou evidência da primeira para a segunda exploração.
        ### 3. Síntese Integrada & Próximo Experimento
        Qual a tese superior resultante da fusão das duas e qual o próximo passo concreto.
        """

        let userPrompt = """
        ## Exploração A (\(iso.string(from: firstDate)))
        Pergunta: \(firstPrompt)
        Síntese:
        \(String(firstSynthesis.prefix(3_500)))

        ## Exploração B (\(iso.string(from: secondDate)))
        Pergunta: \(secondPrompt)
        Síntese:
        \(String(secondSynthesis.prefix(3_500)))
        """

        if DirectBrainCredentials.hasOpenAI {
            if let res = try? await directBrain.streamOpenAI(
                model: OpenAIModelCatalog.defaultFlagshipModel,
                systemPrompt: systemPrompt,
                developerPrefix: systemPrompt,
                reasoningEffort: "medium",
                enableNativeWebSearch: false,
                enableToolSearch: false,
                turns: [DirectBrainTurn(role: "user", content: userPrompt)],
                projectSlug: nil,
                onStatus: { _ in },
                onToken: { delta in
                    if let onToken { await onToken(delta) }
                }
            ), !res.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return res.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let cloud = await client.chat(prompt: userPrompt, system: systemPrompt).value?.response,
           !cloud.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let onToken { await onToken(cloud) }
            return cloud.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Deterministic offline fallback comparison
        let offline = """
        ### 1. Invariantes & Convergências
        Ambas as explorações investigam eixos complementares entre **\(String(firstPrompt.prefix(80)))** e **\(String(secondPrompt.prefix(80)))**.

        ### 2. Deslocamentos & Evolução
        - **Exploração A**: \(String(firstSynthesis.prefix(320)))
        - **Exploração B**: \(String(secondSynthesis.prefix(320)))

        ### 3. Síntese Integrada
        Reconecte ao Direct Brain (GPT-6.2 Astra) ou ao cluster Beagle para gerar a inferência comparativa completa.
        """
        if let onToken { await onToken(offline) }
        return offline
    }

}
