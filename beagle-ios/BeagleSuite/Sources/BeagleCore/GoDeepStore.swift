//
//  GoDeepStore.swift
//  BeagleCore
//
//  Orchestration store for Go Deeper ("Modo Fundo") — fires multiple Nov 2026
//  frontier & exocortex reasoning modalities concurrently (GPT-6.2 Astra xhigh,
//  GPT-Rosalind Bio/PBPK, Swarm, Causal, Quantum, etc.), prefetches PubMed/DOI/URL
//  & GraphRAG++ context, provides resilient Direct Brain structured fallback when
//  cluster lanes are offline, and streams an incisive pt-BR synthesis.
//

import Foundation
import Observation

// MARK: - Per-Modality State

public enum ModalityPhase: Sendable {
    case waiting                       // queued but not started
    case thinking(String)              // in-flight, status message
    case resolved(GoDeepResult)        // completed with result
    case failed(String)                // error with message

    public var label: String {
        switch self {
        case .waiting:           return "waiting"
        case .thinking(let msg): return "thinking:\(msg)"
        case .resolved:          return "resolved"
        case .failed(let msg):   return "failed:\(msg)"
        }
    }
}

public struct ModalityState: Sendable, Identifiable {
    public let modality: GoDeepModality
    public var phase: ModalityPhase
    public var startedAt: Date?
    public var completedAt: Date?

    public var id: String { modality.id }
    public var isResolved: Bool {
        if case .resolved = phase { return true }
        return false
    }
    public var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
    public var isActive: Bool {
        if case .thinking = phase { return true }
        return false
    }
    public var durationMs: Int? {
        guard let start = startedAt, let end = completedAt else { return nil }
        return Int(end.timeIntervalSince(start) * 1000)
    }
    public var result: GoDeepResult? {
        if case .resolved(let r) = phase { return r }
        return nil
    }
    public var errorMessage: String? {
        if case .failed(let msg) = phase { return msg }
        return nil
    }

    public init(modality: GoDeepModality) {
        self.modality = modality
        self.phase = .waiting
    }
}

// MARK: - Store

@Observable
@MainActor
public final class GoDeepStore {

    // MARK: - Session State

    public private(set) var activeSession: GoDeepSession?
    public private(set) var isRunning = false
    public private(set) var completedCount = 0
    public private(set) var totalCount = 0

    /// Per-modality state — always contains one entry per enabled modality.
    /// UI shows ALL of these: waiting as skeleton, thinking as animated, resolved as card.
    public private(set) var modalityStates: [ModalityState] = []

    /// Synthesis generated after all modalities complete (streamed live in pt-BR).
    /// Cross-modality synthesis text (internal setter retained for `@testable` unit tests).
    public internal(set) var synthesis: String?
    public private(set) var isSynthesizing = false

    /// Verified quantitative/code simulation output produced via Astra Agent Sandbox (`v1/agents/sessions`).
    public internal(set) var simulationOutput: String?
    public internal(set) var simulationSessionId: String?
    public internal(set) var isSimulating = false
    public internal(set) var simulationStatusLine: String?

    // MARK: - Quantum Mode

    /// When true, `goDeeper` explores the question through multiple hypotheses
    /// in superposition, runs each through frontier/quantum reasoning, then
    /// interferes and collapses to the strongest.
    public var quantumMode = false

    /// Hypotheses currently in superposition (only populated when quantumMode is on).
    public private(set) var hypotheses: [QuantumHypothesisEngine.Hypothesis] = []

    /// Interference result after all hypotheses have been explored (quantum mode only).
    public private(set) var interferenceResult: QuantumHypothesisEngine.InterferenceResult?

    // MARK: - Configuration

    /// Default modalities: when Direct Brain OpenAI is configured, lead with
    /// GPT-6.2 Astra (xhigh) + GPT-Rosalind (Bio/PBPK) + Swarm Consensus + Causal Graph
    /// in parallel. Otherwise fall back to fast cluster lanes.
    public var enabledModalities: Set<GoDeepModality>

    /// Controls whether frontier modalities attach hosted `web_search` + `tool_search`.
    public var enableLiveResearchTools = true

    // MARK: - History

    public private(set) var recentSessions: [GoDeepSession] = []

    private let client: BeagleClient
    internal let directBrain: DirectBrainClient
    private var runTask: Task<Void, Never>?

    /// Callbacks for Live Activity (set by view layer, since LiveActivityManager is in BeagleCockpit).
    public var onResearchStart: ((String, String, String) -> Void)?   // (runId, name, slug)
    public var onResearchUpdate: ((Int, Int, Int) -> Void)?           // (step, total, eta)
    public var onResearchEnd: ((String) -> Void)?                     // (finalStatus)

    /// Rich Live Activity callbacks carrying active lens badge & live synthesis/modality snippet.
    /// `(step, total, etaSeconds, activeLens, summarySnippet, isCompleted)`
    public var onResearchStateChange: ((Int, Int, Int, String?, String?, Bool) -> Void)?

    /// Fired when a session finishes so the view layer can persist the full
    /// result (synthesis + per-modality summaries) into PersistedDeepSession.
    public var onSessionComplete: ((GoDeepPersistencePayload) -> Void)?

    public init(
        client: BeagleClient = .shared,
        directBrain: DirectBrainClient = .shared,
        enabledModalities: Set<GoDeepModality>? = nil
    ) {
        self.client = client
        self.directBrain = directBrain
        if let enabledModalities {
            self.enabledModalities = enabledModalities
        } else if DirectBrainCredentials.hasOpenAI {
            self.enabledModalities = [
                .astraDeep,
                .rosalindBio,
                .swarmConsensus,
                .causalExtract
            ]
        } else {
            self.enabledModalities = [
                .swarmConsensus,
                .temporal,
                .neurosymbolic
            ]
        }
    }

    /// Snapshot of a completed Go Deeper session, ready for SwiftData persistence.
    public struct GoDeepPersistencePayload: Sendable {
        public let prompt: String
        public let synthesis: String?
        /// JSON-encoded `[displayName: summary]` modality results.
        public let modalityResultsJSON: String?
        /// JSON-encoded `[ScientificDossierExporter.HarvestedCitation]` verified citations.
        public let citationsJSON: String?
        public let simulationOutput: String?
        public let modalityCount: Int
        public let completedAt: Date
    }

    /// Build the persistence payload from current state (synthesis + resolved modalities + citations).
    public func makePersistencePayload(prompt: String) -> GoDeepPersistencePayload {
        var summaries: [String: String] = [:]
        for state in modalityStates {
            if let result = state.result {
                summaries[state.modality.displayName] = result.summary
            }
        }
        let json = (try? JSONEncoder().encode(summaries)).flatMap { String(data: $0, encoding: .utf8) }
        let citations = ScientificDossierExporter.harvestCitations(
            prompt: prompt,
            modalityStates: modalityStates,
            synthesis: synthesis,
            roundTable: nil
        )
        let citationsJSON = citations.isEmpty
            ? nil
            : (try? JSONEncoder().encode(citations)).flatMap { String(data: $0, encoding: .utf8) }
        return GoDeepPersistencePayload(
            prompt: prompt,
            synthesis: synthesis,
            modalityResultsJSON: json,
            citationsJSON: citationsJSON,
            simulationOutput: simulationOutput,
            modalityCount: summaries.count,
            completedAt: .now
        )
    }

    /// Hydrates a `GoDeepStore` instantaneously from a saved `PersistedDeepSession` without re-running cloud APIs.
    public func hydrateFromPersisted(
        prompt: String,
        startedAt: Date,
        completedAt: Date?,
        synthesis: String?,
        modalityResultsJSON: String?,
        simulationOutput: String? = nil
    ) {
        runTask?.cancel()
        clearState()

        var decodedSummaries: [String: String] = [:]
        if let json = modalityResultsJSON,
           let data = json.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            decodedSummaries = dict
        }

        var restoredStates: [ModalityState] = []
        for modality in GoDeepModality.allCases {
            if let summaryText = decodedSummaries[modality.displayName] {
                var st = ModalityState(modality: modality)
                st.startedAt = startedAt
                st.completedAt = completedAt ?? startedAt
                st.phase = .resolved(Self.reconstructPersistedResult(for: modality, summaryText: summaryText))
                restoredStates.append(st)
                decodedSummaries.removeValue(forKey: modality.displayName)
            }
        }
        // Any legacy display names not matched by current GoDeepModality.displayName
        for (legacyName, summaryText) in decodedSummaries.sorted(by: { $0.key < $1.key }) {
            let mapped = Self.matchLegacyModality(legacyName)
            guard !restoredStates.contains(where: { $0.modality == mapped }) else { continue }
            var st = ModalityState(modality: mapped)
            st.startedAt = startedAt
            st.completedAt = completedAt ?? startedAt
            st.phase = .resolved(Self.reconstructPersistedResult(for: mapped, summaryText: summaryText))
            restoredStates.append(st)
        }

        var session = GoDeepSession(
            prompt: prompt,
            startedAt: startedAt,
            modalities: restoredStates.map(\.modality)
        )
        session.completedAt = completedAt ?? .now

        self.activeSession = session
        self.modalityStates = restoredStates
        self.totalCount = restoredStates.count
        self.completedCount = restoredStates.count
        self.synthesis = synthesis
        self.simulationOutput = simulationOutput
        self.isRunning = false
        self.isSynthesizing = false
    }

    private nonisolated static func matchLegacyModality(_ name: String) -> GoDeepModality {
        let lower = name.lowercased()
        if lower.contains("rosalind") || lower.contains("bio") || lower.contains("pbpk") { return .rosalindBio }
        if lower.contains("astra") { return .astraDeep }
        if lower.contains("swarm") || lower.contains("enxame") { return .swarmConsensus }
        if lower.contains("causal") { return .causalExtract }
        if lower.contains("quant") || lower.contains("quânt") { return .quantumReasoning }
        if lower.contains("temporal") { return .temporal }
        if lower.contains("neuro") { return .neurosymbolic }
        if lower.contains("advers") { return .adversarial }
        if lower.contains("serendip") { return .serendipity }
        return .deepResearch
    }

    private nonisolated static func reconstructPersistedResult(
        for modality: GoDeepModality,
        summaryText: String
    ) -> GoDeepResult {
        let cits = extractMarkdownCitations(from: summaryText)
        switch modality {
        case .astraDeep:
            return .astraDeep(.observed(
                FrontierResearchResult(
                    model: OpenAIModelCatalog.defaultFlagshipModel,
                    reasoningEffort: "xhigh",
                    thesis: firstParagraph(of: summaryText),
                    analysisMarkdown: summaryText,
                    citations: cits
                ),
                source: "histórico salvo"
            ))
        case .rosalindBio:
            return .rosalindBio(.observed(
                FrontierResearchResult(
                    model: OpenAIModelCatalog.lifeSciencesModel,
                    reasoningEffort: "high",
                    thesis: firstParagraph(of: summaryText),
                    analysisMarkdown: summaryText,
                    citations: cits
                ),
                source: "histórico salvo"
            ))
        case .swarmConsensus:
            let bullets = extractBulletLines(from: summaryText)
            return .swarm(.observed(
                SwarmResult(consensus: bullets.isEmpty ? [summaryText] : bullets, iterations: 3, nAgents: 5),
                source: "histórico salvo"
            ))
        case .causalExtract:
            return .causal(.observed(CausalGraph(nodes: nil, edges: nil, summary: summaryText), source: "histórico salvo"))
        case .quantumReasoning:
            return .quantum(.observed(
                QuantumReasoningResult(selectedHypothesis: summaryText, probability: 0.72),
                source: "histórico salvo"
            ))
        case .temporal:
            return .temporal(.observed(TemporalResult(summary: summaryText), source: "histórico salvo"))
        case .neurosymbolic:
            return .neurosymbolic(.observed(NeurosymbolicResult(summary: summaryText), source: "histórico salvo"))
        case .adversarial:
            return .adversarial(.observed(
                AdversarialResult(winner: firstParagraph(of: summaryText), agents: nil, rounds: 3, summary: summaryText),
                source: "histórico salvo"
            ))
        case .serendipity:
            return .serendipity(.observed(SerendipityResult(summary: summaryText), source: "histórico salvo"))
        case .deepResearch:
            return .deepResearch(.observed(
                DeepResearchResult(treeSize: 12, bestHypothesis: summaryText, iterations: 4),
                source: "histórico salvo"
            ))
        }
    }

    // MARK: - Thinking Status Messages (pt-BR)

    private static let thinkingMessages: [GoDeepModality: [String]] = [
        .astraDeep:        ["Ativando GPT-6.2 Astra (xhigh)...", "Pesquisando literatura e web ao vivo...", "Consolidando cadeia multi-hop..."],
        .rosalindBio:      ["Consultando GPT-Rosalind (Bio/PBPK)...", "Cruzando PubMed, Bula ANVISA e PCDT...", "Modelando mecanismos e farmacocinética..."],
        .deepResearch:     ["Expandindo árvore de pesquisa...", "Explorando hipóteses...", "Podando ramos fracos..."],
        .quantumReasoning: ["Preparando superposição de hipóteses...", "Aplicando interferência...", "Colapsando funções de onda..."],
        .swarmConsensus:   ["Disparando enxame de especialistas...", "Agentes deliberando...", "Convergindo consenso..."],
        .causalExtract:    ["Extraindo grafo causal...", "Mapeando mediadores e intervenções...", "Estimando força causal..."],
        .temporal:         ["Analisando escalas temporais...", "Rastreando dinâmica aguda vs. crônica...", "Projetando trajetórias..."],
        .neurosymbolic:    ["Codificando invariantes formais...", "Cruzando inferência neural e simbólica...", "Verificando consistência lógica..."],
        .adversarial:      ["Montando bancada adversarial...", "Executando refutação cruzada...", "Pontuando rodada final..."],
        .serendipity:      ["Buscando conexões laterais...", "Medindo surpresa epistêmica...", "Cristalizando pontes inesperadas..."],
    ]

    // MARK: - Run Go Deeper

    public func goDeeper(prompt: String) {
        runTask?.cancel()
        let cachedContext = synthesis
        clearState()

        if quantumMode {
            goDeeperQuantum(prompt: prompt, cachedContext: cachedContext)
            return
        }

        let modalities = orderedEnabledModalities()
        let session = GoDeepSession(prompt: prompt, modalities: modalities)
        activeSession = session
        totalCount = modalities.count
        completedCount = 0
        isRunning = true
        synthesis = nil
        isSynthesizing = false

        modalityStates = modalities.map { ModalityState(modality: $0) }

        let initialLens = Self.activeLensBadge(for: modalityStates, isSynthesizing: false)
        onResearchStart?(session.id.uuidString, String(prompt.prefix(56)), "exocortex")
        onResearchStateChange?(0, modalities.count + 1, modalities.count * 18, initialLens, nil, false)

        let useLiveTools = enableLiveResearchTools
        runTask = Task { [weak self, client, directBrain] in
            guard let self else { return }
            await self.runStandardSession(
                prompt: prompt,
                modalities: modalities,
                client: client,
                directBrain: directBrain,
                cachedContext: cachedContext,
                useLiveTools: useLiveTools
            )
        }
    }

    /// Awaits a full Go Deeper run to completion (ideal for unit tests & Siri App Intents).
    public func goDeeperAndWait(prompt: String) async {
        goDeeper(prompt: prompt)
        await runTask?.value
    }

    private static func activeLensBadge(for states: [ModalityState], isSynthesizing: Bool) -> String? {
        if isSynthesizing { return "Síntese Executiva" }
        let remaining = states.filter { !$0.isResolved && !$0.isFailed }.map(\.modality.shortBadge)
        guard !remaining.isEmpty else { return "Síntese Executiva" }
        if remaining.count == 1 { return remaining[0] }
        return "\(remaining[0]) · \(remaining[1])"
    }

    private func orderedEnabledModalities() -> [GoDeepModality] {
        let ordered = GoDeepModality.allCases.filter { enabledModalities.contains($0) }
        return ordered.isEmpty ? [.astraDeep, .swarmConsensus] : ordered
    }

    private func runStandardSession(
        prompt: String,
        modalities: [GoDeepModality],
        client: BeagleClient,
        directBrain: DirectBrainClient,
        cachedContext: String?,
        useLiveTools: Bool
    ) async {
        let thinkingTask = Task { [weak self] in
            await self?.animateThinkingStatuses()
        }

        // Prefetch explicit PMID/DOI/arXiv/URL references & GraphRAG++ memory once before fan-out
        let sharedGrounding = await Self.prefetchSharedGrounding(
            prompt: prompt,
            directBrain: directBrain,
            cachedContext: cachedContext,
            enableNetworkPrefetch: useLiveTools
        )

        await withTaskGroup(of: (GoDeepModality, GoDeepResult)?.self) { group in
            for modality in modalities {
                group.addTask { [client, directBrain] in
                    let result = await Self.executeModality(
                        modality,
                        prompt: prompt,
                        client: client,
                        directBrain: directBrain,
                        sharedGrounding: sharedGrounding,
                        useLiveTools: useLiveTools
                    )
                    return (modality, result)
                }
            }

            for await pair in group {
                guard !Task.isCancelled else { return }
                if let (modality, result) = pair {
                    self.completedCount += 1
                    self.resolveModality(modality, result: result)
                }
            }
        }

        thinkingTask.cancel()
        guard !Task.isCancelled else { return }

        // Generate streaming synthesis in pt-BR
        self.isSynthesizing = true
        let latestModalitySummary = self.modalityStates.compactMap(\.result?.summary).last
        self.onResearchStateChange?(
            self.totalCount,
            self.totalCount + 1,
            12,
            "Síntese Executiva",
            latestModalitySummary.map { String($0.prefix(140)) },
            false
        )
        let synthText = await self.generateSynthesis(prompt: prompt, sharedGrounding: sharedGrounding)
        guard !Task.isCancelled else { return }
        self.synthesis = synthText
        self.isSynthesizing = false

        let finalSnippet = (synthText ?? latestModalitySummary).map { String($0.prefix(160)) }
        self.onResearchStateChange?(
            self.totalCount + 1,
            self.totalCount + 1,
            0,
            "Concluído",
            finalSnippet,
            true
        )
        self.onResearchEnd?(synthText != nil ? "complete" : "no synthesis")

        self.isRunning = false
        if var session = self.activeSession {
            session.completedAt = .now
            self.activeSession = session
            self.recentSessions.insert(session, at: 0)
            if self.recentSessions.count > 10 { self.recentSessions.removeLast() }
            self.onSessionComplete?(self.makePersistencePayload(prompt: session.prompt))
        }

        // Archive synthesis into Exocortex GraphRAG++ memory asynchronously
        if let synthText, !synthText.isEmpty {
            let archiveText = "[Modo Fundo · \(prompt)]\n\(synthText)"
            Task.detached(priority: .utility) {
                _ = await client.captureThought(text: archiveText, source: "go-deeper-astra")
            }
        }
    }

    // MARK: - Resolve Modality

    private func resolveModality(_ modality: GoDeepModality, result: GoDeepResult) {
        guard let idx = modalityStates.firstIndex(where: { $0.modality == modality }) else { return }
        modalityStates[idx].completedAt = .now
        if result.isError {
            modalityStates[idx].phase = .failed(result.summary)
        } else {
            modalityStates[idx].phase = .resolved(result)
        }

        let currentCompleted = modalityStates.filter { $0.isResolved || $0.isFailed }.count
        let eta = max(8, (totalCount - currentCompleted) * 15)
        onResearchUpdate?(currentCompleted, totalCount, eta)
        let nextLens = Self.activeLensBadge(for: modalityStates, isSynthesizing: isSynthesizing)
        let snippet = result.isError ? nil : String(result.summary.prefix(140))
        onResearchStateChange?(currentCompleted, totalCount + 1, eta, nextLens, snippet, false)
    }

    // MARK: - Animate Thinking Statuses

    private func animateThinkingStatuses() async {
        var messageIndex = 0
        while !Task.isCancelled {
            let stillWorking = modalityStates.contains { state in
                switch state.phase {
                case .waiting, .thinking: return true
                default: return false
                }
            }
            guard stillWorking else { return }

            for i in modalityStates.indices {
                guard case .waiting = modalityStates[i].phase else { continue }
                let messages = Self.thinkingMessages[modalityStates[i].modality] ?? ["Processando..."]
                modalityStates[i].phase = .thinking(messages[messageIndex % messages.count])
                modalityStates[i].startedAt = modalityStates[i].startedAt ?? .now
            }
            for i in modalityStates.indices {
                guard case .thinking = modalityStates[i].phase else { continue }
                let messages = Self.thinkingMessages[modalityStates[i].modality] ?? ["Processando..."]
                modalityStates[i].phase = .thinking(messages[messageIndex % messages.count])
            }
            messageIndex += 1
            try? await Task.sleep(for: .seconds(2.5))
        }
    }

    // MARK: - Synthesis (Streaming pt-BR via GPT-6.2 Astra -> Claude -> Cluster -> MLX)

    private func generateSynthesis(prompt: String, sharedGrounding: String?) async -> String? {
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
    private func goDeeperQuantum(prompt: String, cachedContext: String?) {
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

    // MARK: - Cancel

    public func cancel() {
        runTask?.cancel()
        isRunning = false
        isSynthesizing = false
    }

    // MARK: - Clear

    private func clearState() {
        modalityStates = []
        synthesis = nil
        simulationOutput = nil
        simulationSessionId = nil
        simulationStatusLine = nil
        completedCount = 0
        totalCount = 0
        hypotheses = []
        interferenceResult = nil
    }

    // MARK: - Derived

    public var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    public var allResults: [GoDeepResult] {
        modalityStates.compactMap(\.result)
    }

    public var hasAnyResult: Bool { completedCount > 0 || synthesis != nil }
    public var hasErrors: Bool { modalityStates.contains(where: \.isFailed) }
    public var allComplete: Bool { completedCount == totalCount && totalCount > 0 }

    /// Full text for sharing / export.
    public var exportText: String {
        guard let session = activeSession else { return "" }
        var lines: [String] = ["# Modo Fundo: \(session.prompt)", ""]

        if !hypotheses.isEmpty {
            lines.append("## Superposição de Hipóteses")
            for hyp in hypotheses.sorted(by: { $0.probability > $1.probability }) {
                let prob = String(format: "%.0f%%", hyp.probability * 100)
                let status = hyp.isCollapsed ? "colapsada" : "superposta"
                lines.append("- [\(prob), \(status)] **\(hyp.perspective)**: \(hyp.text)")
            }
            lines.append("")

            if let interference = interferenceResult, !interference.novelEmergent.isEmpty {
                lines.append("### Tensões Emergentes")
                for insight in interference.novelEmergent {
                    lines.append("- \(insight)")
                }
                lines.append("")
            }
        }

        for state in modalityStates {
            if let result = state.result {
                lines.append("## \(state.modality.displayName)")
                switch result {
                case .astraDeep(let t), .rosalindBio(let t):
                    lines.append(t.value?.analysisMarkdown ?? result.summary)
                default:
                    lines.append(result.summary)
                }
                if let ms = state.durationMs { lines.append("(\(ms)ms)") }
                lines.append("")
            }
        }
        if let synthesis {
            lines.append("## Síntese")
            lines.append(synthesis)
        }
        return lines.joined(separator: "\n")
    }
}
