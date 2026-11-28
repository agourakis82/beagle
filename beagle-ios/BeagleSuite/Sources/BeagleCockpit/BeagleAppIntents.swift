//
//  BeagleAppIntents.swift
//  BeagleCockpit
//
//  App Intents para Botão de Ação (Action Button), Siri em Português, Apple Watch / AirPods,
//  Atalhos (Shortcuts), Tela Bloqueada e Spotlight.
//

import AppIntents
import BeagleCore
import Foundation

// MARK: - 1. Perguntar ao Beagle (Siri / Action Button / AirPods — sem precisar abrir o app)

struct AskBeagleIntent: AppIntent {
    static let title: LocalizedStringResource = "Perguntar ao Beagle"
    static let description: IntentDescription = IntentDescription(
        "Faz uma pergunta clínica, científica ou pessoal ao Beagle com acesso à memória do cluster, bula/PCDT, agenda, PubMed e web ao vivo."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Pergunta",
        requestValueDialog: IntentDialog("Pode falar — o que você quer perguntar ao Beagle?")
    )
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let msg = "Não ouvi a pergunta. Pode tentar de novo?"
            return .result(value: msg, dialog: IntentDialog(stringLiteral: msg))
        }

        // 1. Contexto clínico local (Bula FDA + PCDT SUS) + links/DOIs/PMIDs + memória GraphRAG++
        var groundedParts: [String] = []
        if let bula = BulaStore.shared.consulta(trimmed) {
            groundedParts.append(
                "## Bula em cache (\(bula.nomePT) / \(bula.generico) — \(bula.citacao))\n"
                + String(bula.texto.prefix(2_400))
            )
        }
        let pcdtList = BulaStore.shared.consultaPCDT(trimmed)
        if !pcdtList.isEmpty {
            let pcdtExcerpt = pcdtList.prefix(2)
                .map { "\($0.citacao):\n\(String($0.texto.prefix(1_600)))" }
                .joined(separator: "\n\n")
            groundedParts.append("## PCDT SUS em cache\n" + pcdtExcerpt)
        }

        let online = await MainActor.run { NetworkMonitor.shared.isOnline }
        if online, !ScienceAndWebBridge.extractReferences(from: trimmed).isEmpty,
           let webCtx = await ScienceAndWebBridge.shared.prefetchContextForPrompt(trimmed, maxCharsPerItem: 4_000) {
            groundedParts.append(webCtx.contextBlock)
        }

        let contextualPrompt: String = groundedParts.isEmpty
            ? trimmed
            : (groundedParts.joined(separator: "\n\n") + "\n\nPergunta de Demetrios: " + trimmed)

        var rawAnswer = ""

        if online {
            let recalled = await DirectBrainClient.shared.recallRelevantMemory(for: trimmed, projectSlug: "sounio")
            let systemPrompt = await DirectBrainClient.shared.buildFullSystemPrompt(
                cachedGrounding: nil,
                physioSummary: nil,
                physioContext: "Contexto: resposta falada rápida via Siri / Botão de Ação. Seja direto, denso, caloroso e conciso (2 a 5 frases naturais em português brasileiro).",
                currentSky: nil,
                flowState: nil,
                sleepQuality01: nil,
                voiceTone: nil,
                lastContactAt: nil,
                rollingSummary: nil,
                recentThreadDigest: nil,
                recalledMemories: recalled,
                moeLocalUncensoredDraft: nil
            )

            if DirectBrainCredentials.hasOpenAI {
                if let res = try? await DirectBrainClient.shared.streamOpenAI(
                    model: DirectBrainCredentials.openAIModel,
                    systemPrompt: systemPrompt,
                    history: [["role": "user", "content": contextualPrompt]],
                    turns: [DirectBrainTurn(role: "user", content: contextualPrompt)],
                    projectSlug: "sounio",
                    onStatus: { _ in },
                    onToken: { _ in }
                ) {
                    rawAnswer = res.content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if rawAnswer.isEmpty && DirectBrainCredentials.hasAnthropic {
                if let res = try? await DirectBrainClient.shared.streamAnthropic(
                    model: "claude-sonnet-5",
                    systemPrompt: systemPrompt,
                    history: [["role": "user", "content": contextualPrompt]],
                    turns: [DirectBrainTurn(role: "user", content: contextualPrompt)],
                    projectSlug: "sounio",
                    onStatus: { _ in },
                    onToken: { _ in }
                ) {
                    rawAnswer = res.content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if rawAnswer.isEmpty {
                let clusterRes = await BeagleClient.shared.chat(
                    prompt: contextualPrompt,
                    system: "Responda em português brasileiro natural, direto e conciso (2 a 5 frases) para leitura em voz pela Siri.",
                    projectSlug: "sounio"
                )
                rawAnswer = (clusterRes.value?.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Fallback Apple Intelligence (iOS 27 PCC se online sem cluster, ou AFM 3 on-device se offline)
        if rawAnswer.isEmpty {
            if let appleIntelligenceAnswer = await FoundationModelsAgent.shared.respondForIntent(
                to: contextualPrompt,
                preferCloud: online
            ) {
                rawAnswer = appleIntelligenceAnswer
            }
        }

        // Fallback estático offline se houver bula/PCDT local na consulta e nenhum modelo disponível
        if rawAnswer.isEmpty, !groundedParts.isEmpty {
            rawAnswer = String(groundedParts.joined(separator: "\n\n").prefix(900))
        }

        if rawAnswer.isEmpty {
            let fallbackMsg = "Estou sem conexão com o cluster agora. Abra o Beagle Cockpit para conversar usando o modelo local no aparelho."
            return .result(value: fallbackMsg, dialog: IntentDialog(stringLiteral: fallbackMsg))
        }

        // Registra o turno na espinha de memória do cluster sem bloquear a resposta da Siri
        let answerCopy = rawAnswer
        Task.detached(priority: .utility) {
            let nowISO = ISO8601DateFormatter().string(from: Date())
            _ = await CockpitClient.shared.ingestTurn(IngestTurnRequest(
                sessionId: "siri-action-button",
                userText: trimmed,
                assistantText: answerCopy,
                clientTime: nowISO,
                timezone: TimeZone.current.identifier
            ))
        }

        let spokenClean = CompanionVoice.prepararTextoParaFala(rawAnswer)
        let dialogText = spokenClean.isEmpty ? String(rawAnswer.prefix(600)) : String(spokenClean.prefix(800))
        return .result(value: rawAnswer, dialog: IntentDialog(stringLiteral: dialogText))
    }
}

// MARK: - 2. Conversar por Voz Mãos-Livres (Ideal para o Botão de Ação do iPhone)

struct StartBeagleVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Conversar por Voz com Beagle"
    static let description: IntentDescription = IntentDescription(
        "Abre o Beagle Cockpit em sessão contínua de voz mãos-livres (Walkie-Talkie + Dynamic Island) e responde em voz alta em português."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.requestCompanionAction(
            CompanionLaunchAction(startHandsFreeVoice: true, continuousVoiceSession: true)
        )
        return .result()
    }
}

// MARK: - 3. Consultar Bula / Protocolo SUS (Offline-First)

struct ConsultBulaIntent: AppIntent {
    static let title: LocalizedStringResource = "Consultar Bula ou Protocolo SUS"
    static let description: IntentDescription = IntentDescription(
        "Consulta instantaneamente bulas aprovadas e Protocolos Clínicos (PCDT SUS) no banco local offline do Beagle."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Medicamento ou condição",
        requestValueDialog: IntentDialog("Qual medicamento ou protocolo clínico você quer consultar?")
    )
    var query: String

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let msg = "Informe o nome do fármaco ou protocolo clínico."
            return .result(value: msg, dialog: IntentDialog(stringLiteral: msg))
        }

        var parts: [String] = []
        if let bula = BulaStore.shared.consulta(trimmed) {
            parts.append("\(bula.nomePT) (\(bula.generico)) — \(bula.citacao): \(String(bula.texto.prefix(700)))")
        }
        let pcdt = BulaStore.shared.consultaPCDT(trimmed)
        if let firstPCDT = pcdt.first {
            parts.append("Protocolo SUS (\(firstPCDT.citacao)): \(String(firstPCDT.texto.prefix(650)))")
        }

        if parts.isEmpty {
            let online = await MainActor.run { NetworkMonitor.shared.isOnline }
            if online {
                let pubmed = await ScienceAndWebBridge.shared.searchPubMed(query: trimmed, maxResults: 2)
                let clean = CompanionVoice.prepararTextoParaFala(pubmed)
                let spoken = String((clean.isEmpty ? pubmed : clean).prefix(700))
                return .result(value: pubmed, dialog: IntentDialog(stringLiteral: spoken))
            }
            let notFound = "Não encontrei '\(trimmed)' no cache offline de bulas e PCDT."
            return .result(value: notFound, dialog: IntentDialog(stringLiteral: notFound))
        }

        let fullText = parts.joined(separator: "\n\n")
        let spoken = String(CompanionVoice.prepararTextoParaFala(fullText).prefix(750))
        return .result(value: fullText, dialog: IntentDialog(stringLiteral: spoken.isEmpty ? fullText : spoken))
    }
}

// MARK: - 4. Capturar Ideia / Pensamento no Exocórtex

struct CaptureThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Capturar Pensamento no Beagle"
    static let description: IntentDescription = "Salva imediatamente uma ideia, nota clínica ou hipótese na memória GraphRAG++ do Beagle"
    static let openAppWhenRun = false

    @Parameter(
        title: "Pensamento",
        requestValueDialog: IntentDialog("Qual ideia ou nota você quer guardar no Beagle?")
    )
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await BeagleClient.shared.captureThought(text: text, source: "siri")

        if let refined = result.value?.response, !refined.isEmpty {
            _ = await CockpitClient.shared.saveIdea(
                slug: "sounio",
                text: text,
                source: "siri",
                refinedText: refined
            )
            let spoken = CompanionVoice.prepararTextoParaFala(refined)
            return .result(dialog: IntentDialog(stringLiteral: "Guardado na memória: \(spoken.isEmpty ? refined : spoken)"))
        }

        _ = await CockpitClient.shared.saveIdea(
            slug: "sounio",
            text: text,
            source: "siri-offline"
        )
        return .result(dialog: "Pensamento salvo localmente: \(text)")
    }
}

// MARK: - 5. Go Deeper (Exploração Científica Profunda)

struct GoDeepIntent: AppIntent {
    static let title: LocalizedStringResource = "Explorar a Fundo no Beagle"
    static let description: IntentDescription = "Inicia uma exploração científica profunda multimodal sobre um tema"
    static let openAppWhenRun = true

    @Parameter(
        title: "Tema de pesquisa",
        requestValueDialog: IntentDialog("Qual tema você quer explorar a fundo?")
    )
    var topic: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await BeagleClient.shared.deepResearch(query: topic)

        if let hypothesis = result.value?.bestHypothesis, !hypothesis.isEmpty {
            return .result(dialog: "Exploração profunda concluída: \(String(hypothesis.prefix(220)))")
        }

        if DirectBrainCredentials.hasOpenAI {
            let store = GoDeepStore(enabledModalities: [.astraDeep, .rosalindBio])
            await store.goDeeperAndWait(prompt: topic)
            if let synth = store.synthesis, !synth.isEmpty {
                return .result(dialog: "Modo Fundo concluído: \(String(synth.prefix(240)))")
            }
        }

        if let error = result.error {
            return .result(dialog: "Exploração iniciada para \(topic) (\(error))")
        }
        return .result(dialog: "Abrindo exploração profunda para \(topic)")
    }
}

// MARK: - 6. Status do Cluster

struct ClusterStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Status do Cluster Beagle"
    static let description: IntentDescription = "Verifica a saúde e sessões ativas do cluster de supercomputação Beagle"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = await CockpitClient.shared.mobileSummary()

        if let data = summary.value {
            var parts: [String] = []

            if let health = data.clusterHealth, !health.isEmpty {
                parts.append("Cluster: \(health)")
            }
            if let agents = data.activeAgentsCount, agents > 0 {
                parts.append("\(agents) agente\(agents == 1 ? "" : "s") ativo\(agents == 1 ? "" : "s")")
            }
            if let sessions = data.activeSessionsCount, sessions > 0 {
                parts.append("\(sessions) sessão\(sessions == 1 ? "" : "ões")")
            }

            if parts.isEmpty {
                return .result(dialog: "Cluster conectado e saudável.")
            }
            let text = parts.joined(separator: ", ") + "."
            return .result(dialog: IntentDialog(stringLiteral: text))
        }

        let reachable = await BeagleClient.shared.isReachable()
        if reachable {
            return .result(dialog: "Servidor Beagle conectado.")
        }
        return .result(dialog: "Não foi possível alcançar o cluster Beagle agora.")
    }
}

// MARK: - 7. Prontidão Fisiológica (HRV + Sono)

struct CheckReadinessIntent: AppIntent {
    static let title: LocalizedStringResource = "Minha Prontidão no Beagle"
    static let description: IntentDescription = "Lê sua prontidão cognitiva e autonômica com base em HRV e sono do Apple Watch"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let posture = await MainActor.run {
            let store = PhysioStore()
            return store.cognitivePosture
        }

        if let readiness = posture.readiness {
            let pct = Int(readiness * 100)
            var response = "Prontidão cognitiva em \(pct)%."

            if let hrv = posture.hrv {
                response += " HRV de \(Int(hrv)) milissegundos."
            }
            if let sleep = posture.sleepQuality {
                response += " Qualidade do sono em \(Int(sleep * 100))%."
            }

            return .result(dialog: IntentDialog(stringLiteral: response))
        }

        return .result(dialog: "Ainda não há leitura recente do HealthKit. Abra o Beagle Cockpit para sincronizar.")
    }
}

// MARK: - 8. Síntese Matinal Diária (Siri / Action Button / AirPods — sem precisar abrir o app)

struct MorningBriefingIntent: AppIntent {
    static let title: LocalizedStringResource = "Síntese Matinal no Beagle"
    static let description: IntentDescription = IntentDescription(
        "Lê ou gera sua Síntese Matinal integrando fisioma (Apple Watch), clima espacial NOAA, agenda de 48h e memória GraphRAG++."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        if let cached = DailyBriefingBuilder.cachedTodaySynthesis() {
            let spoken = CompanionVoice.prepararTextoParaFala(cached)
            let dialogText = String((spoken.isEmpty ? cached : spoken).prefix(850))
            return .result(value: cached, dialog: IntentDialog(stringLiteral: dialogText))
        }

        let physioSummary = await MainActor.run {
            PhysioStore().summary
        }
        let ctx = await DailyBriefingBuilder.gatherLiveContext(
            captureLines: [],
            physioSummary: physioSummary,
            sky: nil,
            projectSlug: "sounio"
        )

        if let generated = try? await DailyBriefingBuilder.generateMorningSynthesis(
            context: ctx,
            projectSlug: "sounio"
        ), !generated.isEmpty {
            DailyBriefingBuilder.saveTodaySynthesis(generated, context: ctx)
            let spoken = CompanionVoice.prepararTextoParaFala(generated)
            let dialogText = String((spoken.isEmpty ? generated : spoken).prefix(850))
            return .result(value: generated, dialog: IntentDialog(stringLiteral: dialogText))
        }

        let fallback = "Sua síntese matinal ainda não está em cache offline. Abra o Beagle Cockpit para gerá-la."
        return .result(value: fallback, dialog: IntentDialog(stringLiteral: fallback))
    }
}

// MARK: - 9. Abrir Modo Fundo Diretamente (Siri / Botão de Ação / Spotlight)

struct OpenModoFundoIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir Modo Fundo no Beagle"
    static let description: IntentDescription = IntentDescription(
        "Abre diretamente a sala do Modo Fundo (GPT-6.2 Astra xhigh + GPT-Rosalind Bio/PBPK + Enxame + Causal)."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "beagle://fundo") {
            _ = DeepLinkRouter.shared.open(url)
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider (Siri em Português + Inglês, Botão de Ação & Spotlight)

struct BeagleShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartBeagleVoiceIntent(),
            phrases: [
                "Conversar com \(.applicationName)",
                "Falar com \(.applicationName)",
                "Voz no \(.applicationName)",
                "Talk to \(.applicationName)"
            ],
            shortTitle: "Voz Mãos-Livres",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: MorningBriefingIntent(),
            phrases: [
                "Minha síntese matinal no \(.applicationName)",
                "Resumo do dia no \(.applicationName)",
                "Briefing matinal no \(.applicationName)",
                "Morning briefing in \(.applicationName)"
            ],
            shortTitle: "Síntese Matinal",
            systemImageName: "sun.horizon.fill"
        )
        AppShortcut(
            intent: OpenModoFundoIntent(),
            phrases: [
                "Abrir Modo Fundo no \(.applicationName)",
                "Modo Fundo no \(.applicationName)",
                "Go deeper in \(.applicationName)"
            ],
            shortTitle: "Modo Fundo",
            systemImageName: "scope"
        )
        AppShortcut(
            intent: AskBeagleIntent(),
            phrases: [
                "Perguntar ao \(.applicationName)",
                "Pergunta pro \(.applicationName)",
                "Ask \(.applicationName)"
            ],
            shortTitle: "Perguntar ao Beagle",
            systemImageName: "bubble.left.and.text.bubble.right.fill"
        )
        AppShortcut(
            intent: ConsultBulaIntent(),
            phrases: [
                "Consultar bula no \(.applicationName)",
                "Protocolo SUS no \(.applicationName)",
                "Check drug label in \(.applicationName)"
            ],
            shortTitle: "Bula & PCDT",
            systemImageName: "cross.case.fill"
        )
        AppShortcut(
            intent: CaptureThoughtIntent(),
            phrases: [
                "Guardar ideia no \(.applicationName)",
                "Capturar pensamento no \(.applicationName)",
                "Capture a thought in \(.applicationName)"
            ],
            shortTitle: "Guardar Ideia",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: CheckReadinessIntent(),
            phrases: [
                "Minha prontidão no \(.applicationName)",
                "Como está meu corpo no \(.applicationName)",
                "Check my readiness in \(.applicationName)"
            ],
            shortTitle: "Prontidão & HRV",
            systemImageName: "heart.text.clipboard"
        )
        AppShortcut(
            intent: ClusterStatusIntent(),
            phrases: [
                "Status do cluster no \(.applicationName)",
                "Check cluster in \(.applicationName)"
            ],
            shortTitle: "Status do Cluster",
            systemImageName: "server.rack"
        )
    }
}
