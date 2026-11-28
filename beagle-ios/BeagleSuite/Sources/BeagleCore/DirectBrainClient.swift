//
//  DirectBrainClient.swift
//  BeagleCore
//
//  Direct Brain credentials (Keychain-backed) and OpenAI / Anthropic / MCP
//  streaming orchestrator extracted from BeagleMCPClient.swift.
//

import Foundation
import Security
import Synchronization

// MARK: - Direct Brain Credentials & MoE / OpenAI / Anthropic / MCP Orchestrator

enum DirectCredentialKeychain {
    private static let service = "dev.sounio.beagle.direct-credentials"
    private static let lock = Mutex<Void>(())

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load(account: String) -> String? {
        lock.withLock { _ in
            var request = query(account: account)
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data,
               let value = String(data: data, encoding: .utf8), !value.isEmpty {
                UserDefaults.standard.removeObject(forKey: account)
                return value
            }
            // A locked/unavailable Keychain must not be mistaken for an absent item.
            guard status == errSecItemNotFound else { return nil }
            guard let legacy = UserDefaults.standard.string(forKey: account)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty else { return nil }
            // Preserve the old value until migration succeeds; never use plaintext on failure.
            guard write(legacy, account: account) else { return nil }
            UserDefaults.standard.removeObject(forKey: account)
            return legacy
        }
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        lock.withLock { _ in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let success: Bool
            if trimmed.isEmpty {
                let status = SecItemDelete(query(account: account) as CFDictionary)
                success = status == errSecSuccess || status == errSecItemNotFound
            } else {
                success = write(trimmed, account: account)
            }
            if success {
                UserDefaults.standard.removeObject(forKey: account)
            } else {
                print("[DirectBrainCredentials] Keychain update failed; credential unchanged.")
            }
            return success
        }
    }

    private static func write(_ value: String, account: String) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let request = query(account: account)
        let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            return SecItemAdd(request.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}

public enum DirectBrainCredentials {
    private static let openAIKeyDefault = "beagle.direct.openai.apiKey"
    private static let anthropicKeyDefault = "beagle.direct.anthropic.apiKey"
    private static let openAIModelDefault = "beagle.direct.openai.model"
    private static let openAIMigrated62Key = "beagle.direct.openai.migrated62"
    private static let openAIReasoningEffortKey = "beagle.direct.openai.reasoningEffort"
    private static let openAINativeWebSearchKey = "beagle.direct.openai.nativeWebSearch"
    private static let openAIToolSearchKey = "beagle.direct.openai.toolSearch"
    private static let keepLocalLoadedDefault = "beagle.moe.keepLocalLoaded"

    /// Ephemeral override used exclusively by unit tests so Keychain entitlements are never required in CI/simulator.
    private static let testOpenAIKeyStorage = Mutex<String?>(nil)
    static var testOpenAIKeyOverride: String? {
        get { testOpenAIKeyStorage.withLock { $0 } }
        set { testOpenAIKeyStorage.withLock { $0 = newValue } }
    }

    public static var openAIKey: String {
        get {
            if let override = testOpenAIKeyOverride, !override.isEmpty {
                return override
            }
            if let saved = DirectCredentialKeychain.load(account: openAIKeyDefault) {
                return saved
            }
            if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty {
                return env
            }
            return secretValue(forKey: "OPENAI_API_KEY") ?? ""
        }
        set {
            DirectCredentialKeychain.save(newValue, account: openAIKeyDefault)
        }
    }

    public static var anthropicKey: String {
        get {
            if let saved = DirectCredentialKeychain.load(account: anthropicKeyDefault) {
                return saved
            }
            if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
                return env
            }
            return secretValue(forKey: "ANTHROPIC_API_KEY") ?? ""
        }
        set {
            DirectCredentialKeychain.save(newValue, account: anthropicKeyDefault)
        }
    }

    /// Preferred OpenAI model (Nov 2026 flagship default: `gpt-6.2-astra`).
    /// Provider errors never silently select another OpenAI model during requests.
    public static var openAIModel: String {
        get {
            migrateLegacyOpenAIModelIfNeeded()
            let saved = UserDefaults.standard.string(forKey: openAIModelDefault)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? OpenAIModelCatalog.defaultFlagshipModel : saved
        }
        set {
            UserDefaults.standard.set(true, forKey: openAIMigrated62Key)
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: openAIModelDefault)
        }
    }

    private static func migrateLegacyOpenAIModelIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: openAIMigrated62Key) else { return }
        UserDefaults.standard.set(true, forKey: openAIMigrated62Key)
        let current = UserDefaults.standard.string(forKey: openAIModelDefault)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if current.isEmpty || current == "gpt-5.5" || OpenAIModelCatalog.obsoleteOrRetiredIDs.contains(current.lowercased()) {
            UserDefaults.standard.set(OpenAIModelCatalog.defaultFlagshipModel, forKey: openAIModelDefault)
        }
    }

    public static var openAIReasoningEffort: OpenAIReasoningEffort {
        get {
            let raw = UserDefaults.standard.string(forKey: openAIReasoningEffortKey) ?? ""
            return OpenAIReasoningEffort(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: openAIReasoningEffortKey)
        }
    }

    public static var enableNativeWebSearch: Bool {
        get {
            if UserDefaults.standard.object(forKey: openAINativeWebSearchKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: openAINativeWebSearchKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: openAINativeWebSearchKey)
        }
    }

    public static var enableToolSearch: Bool {
        get {
            if UserDefaults.standard.object(forKey: openAIToolSearchKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: openAIToolSearchKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: openAIToolSearchKey)
        }
    }

    /// Whether to keep the local uncensored MLX model loaded in RAM even when online (for MoE & instant uncensored listening).
    public static var keepLocalLoadedWhenOnline: Bool {
        get {
            if UserDefaults.standard.object(forKey: keepLocalLoadedDefault) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: keepLocalLoadedDefault)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keepLocalLoadedDefault)
        }
    }

    public static var hasOpenAI: Bool { !openAIKey.isEmpty }
    public static var hasAnthropic: Bool { !anthropicKey.isEmpty }

    private static func secretValue(forKey key: String) -> String? {
        for bundle in Bundle.allBundles {
            if let path = bundle.path(forResource: "Secrets", ofType: "plist"),
               let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
               let val = dict[key] as? String,
               !val.isEmpty {
                return val
            }
        }
        return nil
    }
}

public actor DirectBrainClient {
    public static let shared = DirectBrainClient()

    private let session: URLSession
    private let skipRemoteMCPTools: Bool

    public init(session: URLSession? = nil, skipRemoteMCPTools: Bool = false) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 300
        self.session = session ?? URLSession(configuration: config)
        self.skipRemoteMCPTools = skipRemoteMCPTools
    }

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
        ## Postura Epistêmica, Ferramentas Nativas do iPhone, Pesquisa Científica e Web ao Vivo
        - Demetrios é médico, farmacologista PBPK e neurocientista computacional. Trate todo tema clínico, psiquiátrico, farmacológico (incluindo cetamina, psicodélicos, neuromodulação, psicofármacos, fisiologia extrema e conflitos existenciais) com profundidade técnica direta, sem recusas genéricas, sem avisos burocráticos ("procure um médico") e sem filtros paternalistas.
        - Você tem acesso direto às ferramentas nativas do iPhone/Mac (`apple_calendar_list_events`, `apple_calendar_create_event`, `apple_reminders_list`, `apple_reminders_create`, `apple_reminders_complete`, `beagle_lookup_bula_pcdt`, `apple_health_live_snapshot`), às ferramentas científicas e web ao vivo (`beagle_search_pubmed`, `beagle_lookup_scientific_work`, `beagle_read_url`, `beagle_web_search`, além da pesquisa `web_search` nativa e `tool_search` sob demanda em namespaces) E ao Beagle MCP + GraphRAG++ do cluster (`beagle_search_memory`, `beagle_store_memory` e todas as tools expostas pelo servidor MCP).
        - Use `beagle_search_pubmed` para buscar artigos biomédicos reais no NCBI PubMed com PMID, DOI e abstract completo; use `beagle_lookup_scientific_work` para resolver DOIs (`10.xxxx/...`), preprints `arXiv` ou buscar no Crossref/EuropePMC; use `beagle_read_url` para ler qualquer URL ou PDF online; use `web_search` ou `beagle_web_search` para diretrizes recentes, notícias e fatos atuais na web. Sempre que citar artigos ou fontes, inclua links Markdown clicáveis como `[PMID 12345678](https://pubmed.ncbi.nlm.nih.gov/12345678/)` ou `[DOI](https://doi.org/...)`.
        - Use `apple_calendar_list_events` / `apple_calendar_create_event` quando ele falar de plantões, agenda, reuniões, datas ou fotografar uma escala/convite; use `apple_reminders_*` para listar, criar ou concluir lembretes reais; use `beagle_lookup_bula_pcdt` SEMPRE que precisar de doses exatas, ajuste renal/hepático, gestação ou conduta do SUS/PCDT; use `apple_health_live_snapshot` quando precisar dos sinais fisiológicos ao vivo do Apple Watch / HealthKit.
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

    public struct OpenAIStreamResult: Sendable {
        public let content: String
        public let model: String
        public let executedTools: [String]

        public init(content: String, model: String, executedTools: [String] = []) {
            self.content = content
            self.model = model
            self.executedTools = executedTools
        }
    }

    // MARK: - OpenAI Direct Streaming (GPT-6.2 Responses API + Prompt Caching + Tool Search + Web Search)

    public func streamOpenAI(
        model: String,
        systemPrompt: String,
        developerPrefix: String? = nil,
        turnInstructions: String? = nil,
        reasoningEffort: String? = nil,
        enableNativeWebSearch: Bool? = nil,
        enableToolSearch: Bool? = nil,
        history: [[String: String]] = [],
        turns: [DirectBrainTurn] = [],
        projectSlug: String?,
        onStatus: @Sendable @escaping (String) async -> Void,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws -> OpenAIStreamResult {
        let apiKey = DirectBrainCredentials.openAIKey
        guard !apiKey.isEmpty else {
            throw NSError(domain: "DirectBrainClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chave OpenAI não configurada."])
        }

        let resolvedModel: String = {
            if model == "moe" || model.isEmpty {
                return DirectBrainCredentials.openAIModel
            }
            return model
        }()

        let resolvedEffort = reasoningEffort ?? DirectBrainCredentials.openAIReasoningEffort.rawValue
        let useWebSearch = enableNativeWebSearch ?? DirectBrainCredentials.enableNativeWebSearch
        let useToolSearch = enableToolSearch ?? DirectBrainCredentials.enableToolSearch

        // Build OpenAI Responses 2026 tools (immediate safety/memory + deferred namespaces + tool_search + web_search)
        let mcpTools = skipRemoteMCPTools ? [] : await BeagleMCPClient.shared.availableTools()
        let openAITools = buildResponsesTools2026(
            mcpTools: mcpTools,
            model: resolvedModel,
            enableNativeWebSearch: useWebSearch,
            enableToolSearch: useToolSearch
        )

        let stableDeveloperPrompt = (developerPrefix?.isEmpty == false) ? developerPrefix! : systemPrompt
        var messages: [[String: Any]] = [
            ["role": "developer", "content": stableDeveloperPrompt]
        ]
        if !turns.isEmpty {
            for turn in turns {
                if let b64 = turn.imageBase64, !b64.isEmpty, turn.role == "user" {
                    let mediaType = turn.imageMediaType ?? "image/jpeg"
                    let promptText = turn.content.isEmpty ? "Analise esta imagem em detalhes." : turn.content
                    messages.append([
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": promptText
                            ],
                            [
                                "type": "image_url",
                                "image_url": [
                                    "url": "data:\(mediaType);base64,\(b64)",
                                    "detail": "high"
                                ]
                            ]
                        ] as [[String: Any]]
                    ])
                } else if !turn.content.isEmpty {
                    messages.append([
                        "role": turn.role,
                        "content": turn.content
                    ])
                }
            }
        } else {
            for msg in history {
                if let role = msg["role"], let content = msg["content"], !content.isEmpty {
                    messages.append([
                        "role": role,
                        "content": content
                    ])
                }
            }
        }

        var executedToolNames: [String] = []

        // Up to 6 agentic tool-call rounds before final streaming synthesis
        for _ in 0..<6 {
            let turnResult = try await performOpenAIStreamRound(
                apiKey: apiKey,
                model: resolvedModel,
                messages: messages,
                tools: openAITools,
                instructions: turnInstructions,
                reasoningEffort: resolvedEffort,
                onStatus: onStatus,
                onToken: onToken
            )

            for builtIn in turnResult.builtInToolsUsed where !executedToolNames.contains(builtIn) {
                executedToolNames.append(builtIn)
            }

            if turnResult.toolCalls.isEmpty {
                return OpenAIStreamResult(
                    content: turnResult.content,
                    model: turnResult.model,
                    executedTools: executedToolNames
                )
            }

            // Replay all output items (reasoning.encrypted_content, tool_search_call/output, function_call with namespace)
            if let outputData = turnResult.outputItemsData,
               let output = try JSONSerialization.jsonObject(with: outputData) as? [[String: Any]] {
                messages.append(contentsOf: output)
            }

            // Execute each tool call against Apple Device Tools / Cluster GraphRAG / BeagleMCPClient
            for tc in turnResult.toolCalls {
                executedToolNames.append(tc.name)
                await onStatus(AppleDeviceToolsBridge.humanStatus(for: tc.name))
                let output = await executeBeagleOrMCPTool(
                    name: tc.name,
                    argumentsJSON: tc.arguments,
                    projectSlug: projectSlug
                )
                messages.append([
                    "type": "function_call_output",
                    "call_id": tc.id,
                    "output": output
                ])
            }
        }

        // Final synthesis round without further tool calls
        let finalResult = try await performOpenAIStreamRound(
            apiKey: apiKey,
            model: resolvedModel,
            messages: messages,
            tools: [],
            instructions: turnInstructions,
            reasoningEffort: resolvedEffort,
            onStatus: onStatus,
            onToken: onToken
        )
        for builtIn in finalResult.builtInToolsUsed where !executedToolNames.contains(builtIn) {
            executedToolNames.append(builtIn)
        }
        return OpenAIStreamResult(
            content: finalResult.content,
            model: finalResult.model,
            executedTools: executedToolNames
        )
    }

    struct OpenAIToolCallAccumulator: Sendable {
        var id: String = ""
        var name: String = ""
        var arguments: String = ""
    }

    struct OpenAIRoundResult: Sendable {
        let model: String
        let content: String
        let toolCalls: [OpenAIToolCallAccumulator]
        var outputItemsData: Data? = nil
        var builtInToolsUsed: [String] = []
    }

    /// Adapts existing conversation turns to Responses input while leaving response
    /// items (reasoning, tool_search, and function calls) intact for stateless continuations.
    static func responsesInput(_ messages: [[String: Any]]) -> [[String: Any]] {
        messages.map { message in
            guard let parts = message["content"] as? [[String: Any]] else { return message }
            var converted = message
            converted["content"] = parts.map { part -> [String: Any] in
                if part["type"] as? String == "text" {
                    return ["type": "input_text", "text": part["text"] as? String ?? ""]
                }
                if part["type"] as? String == "image_url",
                   let image = part["image_url"] as? [String: Any] {
                    return [
                        "type": "input_image",
                        "image_url": image["url"] as? String ?? "",
                        "detail": image["detail"] as? String ?? "auto"
                    ]
                }
                return part
            }
            return converted
        }
    }

    func performOpenAIStreamRound(
        apiKey: String,
        model: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        instructions: String? = nil,
        reasoningEffort: String? = nil,
        onStatus: (@Sendable (String) async -> Void)? = nil,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws -> OpenAIRoundResult {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "input": Self.responsesInput(messages),
            "stream": true,
            "store": false,
            "include": ["reasoning.encrypted_content"]
        ]
        if let instructions, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["instructions"] = instructions
        }
        if let effort = OpenAIReasoningEffort.sanitizedEffort(reasoningEffort, forModel: model) {
            body["reasoning"] = ["effort": effort]
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                if let type = tool["type"] as? String,
                   type == "namespace" || type == "tool_search" || type == "web_search" || type == "mcp" {
                    return tool
                }
                guard let function = tool["function"] as? [String: Any] else { return tool }
                var flattened = function
                flattened["type"] = "function"
                // Existing MCP schemas contain optional fields; preserve that contract.
                flattened["strict"] = false
                return flattened
            }
            body["tool_choice"] = "auto"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            var errText = ""
            for try await line in bytes.lines {
                errText += line
                if errText.count > 600 { break }
            }
            throw NSError(domain: "DirectBrainClient", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errText])
        }

        var fullText = ""
        var announcedWebSearch = false
        var announcedToolSearch = false
        for try await rawLine in bytes.lines {
            try Task.checkCancellation()
            guard rawLine.hasPrefix("data:") else { continue }
            let payload = rawLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { throw URLError(.cannotParseResponse) }
            switch type {
            case "response.web_search_call.in_progress", "response.web_search_call.searching":
                if !announcedWebSearch {
                    announcedWebSearch = true
                    await onStatus?(AppleDeviceToolsBridge.humanStatus(for: "openai_web_search"))
                }
            case "response.tool_search_call.in_progress", "response.tool_search_call.searching":
                if !announcedToolSearch {
                    announcedToolSearch = true
                    await onStatus?(AppleDeviceToolsBridge.humanStatus(for: "openai_tool_search"))
                }
            case "response.output_text.delta", "response.refusal.delta":
                if let delta = event["delta"] as? String {
                    fullText += delta
                    await onToken(delta)
                }
            case "response.completed":
                guard let completed = event["response"] as? [String: Any],
                      completed["status"] as? String == "completed",
                      let output = completed["output"] as? [[String: Any]] else {
                    throw URLError(.cannotParseResponse)
                }
                let calls = try output.compactMap { item -> OpenAIToolCallAccumulator? in
                    guard item["type"] as? String == "function_call" else { return nil }
                    guard let id = item["call_id"] as? String, !id.isEmpty,
                          let name = item["name"] as? String, !name.isEmpty,
                          let arguments = item["arguments"] as? String else {
                        throw URLError(.cannotParseResponse)
                    }
                    return OpenAIToolCallAccumulator(id: id, name: name, arguments: arguments)
                }
                var builtIns: [String] = []
                for item in output {
                    let itemType = item["type"] as? String
                    if itemType == "web_search_call", !builtIns.contains("openai_web_search") {
                        builtIns.append("openai_web_search")
                    } else if itemType == "tool_search_call", !builtIns.contains("openai_tool_search") {
                        builtIns.append("openai_tool_search")
                    }
                }
                if fullText.isEmpty {
                    fullText = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                        .compactMap { ($0["text"] as? String) ?? ($0["refusal"] as? String) }
                        .joined()
                    if !fullText.isEmpty { await onToken(fullText) }
                }
                // Surface verified URL citations from hosted web_search if not already linked inline
                let citations = Self.extractURLCitations(from: output)
                let missingCitations = citations.filter { !fullText.contains($0.url) }
                if !missingCitations.isEmpty && calls.isEmpty {
                    let footerLines = missingCitations.prefix(5).map { "- [\($0.title)](\($0.url))" }
                    let footer = "\n\nFontes:\n" + footerLines.joined(separator: "\n")
                    fullText += footer
                    await onToken(footer)
                }
                return OpenAIRoundResult(
                    model: completed["model"] as? String ?? model,
                    content: fullText,
                    toolCalls: calls,
                    outputItemsData: try JSONSerialization.data(withJSONObject: output),
                    builtInToolsUsed: builtIns
                )
            case "response.failed", "response.incomplete", "error":
                // Do not mistake a partial reply or a failed tool request for success.
                throw NSError(domain: "DirectBrainClient", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "OpenAI Responses: \(type)"])
            default:
                break
            }
        }
        // A transport disconnect without response.completed is not a completed turn.
        throw URLError(.networkConnectionLost)
    }

    // MARK: - Anthropic Claude Direct Streaming with Vision + Beagle MCP Tool Calling

    public func streamAnthropic(
        model: String,
        systemPrompt: String,
        history: [[String: String]] = [],
        turns: [DirectBrainTurn] = [],
        projectSlug: String? = nil,
        onStatus: (@Sendable (String) async -> Void)? = nil,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws -> OpenAIStreamResult {
        let apiKey = DirectBrainCredentials.anthropicKey
        guard !apiKey.isEmpty else {
            throw NSError(domain: "DirectBrainClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chave Anthropic não configurada."])
        }

        let resolvedModel: String = {
            if model.contains("opus") { return "claude-opus-4-8" }
            if model.contains("sonnet-5") { return "claude-sonnet-5" }
            return model.isEmpty ? "claude-sonnet-5" : model
        }()

        let mcpTools = await BeagleMCPClient.shared.availableTools()
        let anthropicTools = buildAnthropicTools(mcpTools: mcpTools)

        var messages: [[String: Any]] = []
        if !turns.isEmpty {
            for turn in turns {
                let normalizedRole = turn.role == "assistant" ? "assistant" : "user"
                if let b64 = turn.imageBase64, !b64.isEmpty, normalizedRole == "user" {
                    let mediaType = turn.imageMediaType ?? "image/jpeg"
                    let promptText = turn.content.isEmpty ? "Analise esta imagem em detalhes." : turn.content
                    messages.append([
                        "role": "user",
                        "content": [
                            [
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": mediaType,
                                    "data": b64
                                ]
                            ],
                            [
                                "type": "text",
                                "text": promptText
                            ]
                        ] as [[String: Any]]
                    ])
                } else if !turn.content.isEmpty {
                    messages.append([
                        "role": normalizedRole,
                        "content": turn.content
                    ])
                }
            }
        } else {
            messages = history.compactMap { msg in
                guard let role = msg["role"], let content = msg["content"], !content.isEmpty else { return nil }
                return ["role": role == "assistant" ? "assistant" : "user", "content": content]
            }
        }

        var executedToolNames: [String] = []

        for _ in 0..<3 {
            let round = try await performAnthropicStreamRound(
                apiKey: apiKey,
                model: resolvedModel,
                systemPrompt: systemPrompt,
                messages: messages,
                tools: anthropicTools,
                onToken: onToken
            )

            if round.toolCalls.isEmpty {
                return OpenAIStreamResult(
                    content: round.content,
                    model: round.model,
                    executedTools: executedToolNames
                )
            }

            var assistantBlocks: [[String: Any]] = []
            if !round.content.isEmpty {
                assistantBlocks.append([
                    "type": "text",
                    "text": round.content
                ])
            }
            for tc in round.toolCalls {
                let parsedInput: Any = {
                    if let d = tc.arguments.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) {
                        return obj
                    }
                    return [String: Any]()
                }()
                assistantBlocks.append([
                    "type": "tool_use",
                    "id": tc.id,
                    "name": tc.name,
                    "input": parsedInput
                ])
            }
            messages.append([
                "role": "assistant",
                "content": assistantBlocks
            ])

            var toolResultBlocks: [[String: Any]] = []
            for tc in round.toolCalls {
                executedToolNames.append(tc.name)
                await onStatus?(AppleDeviceToolsBridge.humanStatus(for: tc.name))
                let output = await executeBeagleOrMCPTool(
                    name: tc.name,
                    argumentsJSON: tc.arguments,
                    projectSlug: projectSlug
                )
                toolResultBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": tc.id,
                    "content": output
                ])
            }
            messages.append([
                "role": "user",
                "content": toolResultBlocks
            ])
        }

        let finalRound = try await performAnthropicStreamRound(
            apiKey: apiKey,
            model: resolvedModel,
            systemPrompt: systemPrompt,
            messages: messages,
            tools: [],
            onToken: onToken
        )
        return OpenAIStreamResult(
            content: finalRound.content,
            model: finalRound.model,
            executedTools: executedToolNames
        )
    }

    private func performAnthropicStreamRound(
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws -> OpenAIRoundResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": messages,
            "stream": true
        ]
        if !tools.isEmpty {
            body["tools"] = tools
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var errText = ""
            for try await line in bytes.lines {
                errText += line
                if errText.count > 600 { break }
            }
            if http.statusCode == 404 || http.statusCode == 400 {
                let fallbackModel: String? = {
                    switch model {
                    case "claude-opus-4-8": return "claude-opus-4-6"
                    case "claude-opus-4-6": return "claude-3-7-sonnet-latest"
                    case "claude-sonnet-5": return "claude-sonnet-4-6"
                    case "claude-sonnet-4-6": return "claude-3-7-sonnet-latest"
                    default: return nil
                    }
                }()
                if let fallbackModel {
                    return try await performAnthropicStreamRound(
                        apiKey: apiKey,
                        model: fallbackModel,
                        systemPrompt: systemPrompt,
                        messages: messages,
                        tools: tools,
                        onToken: onToken
                    )
                }
            }
            throw NSError(domain: "DirectBrainClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errText])
        }

        var fullText = ""
        var toolCallsByIndex: [Int: OpenAIToolCallAccumulator] = [:]

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }
            if type == "content_block_start",
               let index = json["index"] as? Int,
               let block = json["content_block"] as? [String: Any],
               (block["type"] as? String) == "tool_use" {
                var acc = OpenAIToolCallAccumulator()
                acc.id = (block["id"] as? String) ?? "tool_\(index)"
                acc.name = (block["name"] as? String) ?? ""
                toolCallsByIndex[index] = acc
            } else if type == "content_block_delta",
                      let delta = json["delta"] as? [String: Any] {
                let deltaType = (delta["type"] as? String) ?? ""
                if let text = delta["text"] as? String, !text.isEmpty {
                    fullText += text
                    await onToken(text)
                } else if deltaType == "input_json_delta",
                          let index = json["index"] as? Int,
                          let partial = delta["partial_json"] as? String {
                    var acc = toolCallsByIndex[index] ?? OpenAIToolCallAccumulator()
                    acc.arguments += partial
                    toolCallsByIndex[index] = acc
                }
            }
        }

        let orderedCalls = toolCallsByIndex.keys.sorted().compactMap { idx -> OpenAIToolCallAccumulator? in
            guard let tc = toolCallsByIndex[idx], !tc.name.isEmpty else { return nil }
            return tc
        }
        return OpenAIRoundResult(model: model, content: fullText, toolCalls: orderedCalls)
    }

    private func buildAnthropicTools(mcpTools: [MCPToolSummary]) -> [[String: Any]] {
        let openAITools = buildOpenAITools(mcpTools: mcpTools)
        return openAITools.compactMap { item in
            guard let fn = item["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return nil }
            return [
                "name": name,
                "description": (fn["description"] as? String) ?? "Ferramenta Beagle MCP (\(name))",
                "input_schema": (fn["parameters"] as? [String: Any]) ?? ["type": "object", "properties": [String: Any]()]
            ]
        }
    }

    // MARK: - Beagle MCP & Cluster Memory Tool Definitions + Dispatcher

    nonisolated private func buildOpenAITools(mcpTools: [MCPToolSummary]) -> [[String: Any]] {
        var tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "beagle_search_memory",
                    "description": "Busca na memória episódica, semântica e GraphRAG++ do cluster Beagle (conversas passadas, notas, hipóteses científicas, histórico médico/fisiológico e projetos).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Consulta semântica ou palavras-chave para buscar no GraphRAG++ e memória do cluster."
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "beagle_store_memory",
                    "description": "Salva imediatamente uma memória importante, decisão, insight científico, evento clínico ou fato pessoal no cluster Beagle (GraphRAG / ChronoSelf).",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "text": [
                                "type": "string",
                                "description": "Conteúdo completo da memória ou insight a ser persistido permanentemente no cluster."
                            ],
                            "tags": [
                                "type": "string",
                                "description": "Tags separadas por vírgula (ex: 'fisioma,cetamina,pbpk,familia')."
                            ]
                        ],
                        "required": ["text"]
                    ]
                ]
            ]
        ]

        tools.append(contentsOf: ScienceAndWebBridge.openAIToolDefinitions())
        tools.append(contentsOf: AppleDeviceToolsBridge.openAIToolDefinitions())

        var builtinNames: Set<String> = ["beagle_search_memory", "beagle_store_memory"]
        builtinNames.formUnion(ScienceAndWebBridge.toolNames)
        builtinNames.formUnion(AppleDeviceToolsBridge.nativeToolNames)
        let encoder = JSONEncoder()

        for tool in mcpTools.prefix(20) where !builtinNames.contains(tool.name) {
            var paramsObj: [String: Any] = [
                "type": "object",
                "properties": [:] as [String: Any]
            ]
            if let schema = tool.inputSchema,
               let data = try? encoder.encode(schema),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                paramsObj = dict
            }
            tools.append([
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description ?? tool.title ?? "Ferramenta do servidor Beagle MCP (\(tool.name))",
                    "parameters": paramsObj
                ]
            ])
        }

        return tools
    }

    static func extractURLCitations(from output: [[String: Any]]) -> [(title: String, url: String)] {
        var seenURLs: Set<String> = []
        var citations: [(title: String, url: String)] = []
        for item in output {
            guard let contents = item["content"] as? [[String: Any]] else { continue }
            for block in contents {
                guard let annotations = block["annotations"] as? [[String: Any]] else { continue }
                for ann in annotations where (ann["type"] as? String) == "url_citation" {
                    guard let url = ann["url"] as? String, !url.isEmpty, !seenURLs.contains(url) else { continue }
                    seenURLs.insert(url)
                    let rawTitle = (ann["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = (rawTitle?.isEmpty == false) ? rawTitle! : (URL(string: url)?.host ?? url)
                    citations.append((title: title, url: url))
                }
            }
        }
        return citations
    }

    private static func flattenResponsesFunction(_ legacyOrFlat: [String: Any], deferLoading: Bool) -> [String: Any]? {
        if let fn = legacyOrFlat["function"] as? [String: Any],
           let name = fn["name"] as? String, !name.isEmpty {
            var flattened = fn
            flattened["type"] = "function"
            flattened["strict"] = false
            if deferLoading {
                flattened["defer_loading"] = true
            }
            return flattened
        }
        if (legacyOrFlat["type"] as? String) == "function",
           let name = legacyOrFlat["name"] as? String, !name.isEmpty {
            var flattened = legacyOrFlat
            flattened["strict"] = false
            if deferLoading {
                flattened["defer_loading"] = true
            }
            return flattened
        }
        return nil
    }

    nonisolated func buildResponsesTools2026(
        mcpTools: [MCPToolSummary],
        model: String,
        enableNativeWebSearch: Bool,
        enableToolSearch: Bool
    ) -> [[String: Any]] {
        let canUseToolSearch = enableToolSearch && OpenAIModelCatalog.supportsToolSearch(model)
        let allLegacy = buildOpenAITools(mcpTools: [])
        let immediateNames: Set<String> = [
            "beagle_search_memory",
            "beagle_store_memory",
            "beagle_lookup_bula_pcdt"
        ]

        var responseTools: [[String: Any]] = []

        // 1. Immediate high-frequency & clinical safety tools (always loaded in context)
        for item in allLegacy {
            let name = (item["function"] as? [String: Any])?["name"] as? String ?? (item["name"] as? String ?? "")
            if immediateNames.contains(name),
               let flat = Self.flattenResponsesFunction(item, deferLoading: false) {
                responseTools.append(flat)
            }
        }

        // 2. Science & Literature tools
        let scienceDefs = ScienceAndWebBridge.openAIToolDefinitions().compactMap { item -> [String: Any]? in
            let name = (item["function"] as? [String: Any])?["name"] as? String ?? ""
            if immediateNames.contains(name) { return nil }
            if enableNativeWebSearch && name == "beagle_web_search" { return nil }
            return Self.flattenResponsesFunction(item, deferLoading: canUseToolSearch)
        }

        // 3. Apple Device tools
        let appleDefs = AppleDeviceToolsBridge.openAIToolDefinitions().compactMap { item -> [String: Any]? in
            Self.flattenResponsesFunction(item, deferLoading: canUseToolSearch)
        }

        // 4. Live Beagle MCP server tools (up to 32 tools, chunked < 10 per namespace)
        var builtinNames: Set<String> = ["beagle_search_memory", "beagle_store_memory"]
        builtinNames.formUnion(ScienceAndWebBridge.toolNames)
        builtinNames.formUnion(AppleDeviceToolsBridge.nativeToolNames)
        let encoder = JSONEncoder()
        var mcpDefs: [[String: Any]] = []
        for tool in mcpTools.prefix(32) where !builtinNames.contains(tool.name) {
            var paramsObj: [String: Any] = [
                "type": "object",
                "properties": [:] as [String: Any]
            ]
            if let schema = tool.inputSchema,
               let data = try? encoder.encode(schema),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                paramsObj = dict
            }
            var flat: [String: Any] = [
                "type": "function",
                "name": tool.name,
                "description": tool.description ?? tool.title ?? "Ferramenta do servidor Beagle MCP (\(tool.name))",
                "strict": false,
                "parameters": paramsObj
            ]
            if canUseToolSearch {
                flat["defer_loading"] = true
            }
            mcpDefs.append(flat)
        }

        if canUseToolSearch {
            var addedDeferredNamespace = false

            if !scienceDefs.isEmpty {
                for (idx, chunk) in Self.chunkTools(scienceDefs, size: 8).enumerated() {
                    let nsName = idx == 0 ? "science_literature" : "science_literature_\(idx + 1)"
                    responseTools.append([
                        "type": "namespace",
                        "name": nsName,
                        "description": "Literatura biomédica e científica (PubMed, arXiv, Semantic Scholar, ClinicalTrials.gov, ChEMBL e extração de artigos web).",
                        "tools": chunk
                    ])
                    addedDeferredNamespace = true
                }
            }

            if !appleDefs.isEmpty {
                for (idx, chunk) in Self.chunkTools(appleDefs, size: 9).enumerated() {
                    let nsName = idx == 0 ? "apple_device" : "apple_device_\(idx + 1)"
                    responseTools.append([
                        "type": "namespace",
                        "name": nsName,
                        "description": "Ecossistema nativo do iPhone de Demetrios (Calendário EventKit, Lembretes, HealthKit/HRV/Sono, Contatos, Clipboard e Localização).",
                        "tools": chunk
                    ])
                    addedDeferredNamespace = true
                }
            }

            if !mcpDefs.isEmpty {
                for (idx, chunk) in Self.chunkTools(mcpDefs, size: 8).enumerated() {
                    let nsName = idx == 0 ? "beagle_mcp" : "beagle_mcp_\(idx + 1)"
                    responseTools.append([
                        "type": "namespace",
                        "name": nsName,
                        "description": "Ferramentas remotas do cluster Beagle HPC, exocórtex e pipelines científicos via MCP.",
                        "tools": chunk
                    ])
                    addedDeferredNamespace = true
                }
            }

            if addedDeferredNamespace {
                responseTools.append(["type": "tool_search"])
            }
        } else {
            responseTools.append(contentsOf: scienceDefs)
            responseTools.append(contentsOf: appleDefs)
            responseTools.append(contentsOf: mcpDefs.prefix(20))
        }

        if enableNativeWebSearch {
            responseTools.append(["type": "web_search"])
        }

        return responseTools
    }

    private static func chunkTools(_ items: [[String: Any]], size: Int) -> [[[String: Any]]] {
        guard size > 0, !items.isEmpty else { return [] }
        var chunks: [[[String: Any]]] = []
        var idx = 0
        while idx < items.count {
            let end = min(idx + size, items.count)
            chunks.append(Array(items[idx..<end]))
            idx = end
        }
        return chunks
    }

    private func executeBeagleOrMCPTool(
        name: String,
        argumentsJSON: String,
        projectSlug: String?
    ) async -> String {
        let args: [String: Any] = {
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return obj
        }()

        if AppleDeviceToolsBridge.isNativeTool(name) {
            return await AppleDeviceToolsBridge.shared.execute(name: name, args: args)
        }
        if ScienceAndWebBridge.isScienceOrWebTool(name) {
            var enrichedArgs = args
            let fallbackText = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if enrichedArgs.isEmpty && !fallbackText.isEmpty {
                enrichedArgs["query"] = fallbackText
                enrichedArgs["identifier_or_query"] = fallbackText
                enrichedArgs["url"] = fallbackText
            }
            return await ScienceAndWebBridge.shared.execute(name: name, args: enrichedArgs)
        }

        switch name {
        case "beagle_search_memory":
            let query = (args["query"] as? String) ?? argumentsJSON
            let graph = await BeagleClient.shared.graphRagQuery(
                query: query,
                scope: projectSlug,
                maxItems: 8
            )
            var out: [String] = []
            if let val = graph.value, !val.evidence.isEmpty {
                for item in val.evidence.prefix(8) {
                    out.append("- [\(item.atomType)] \(item.text)")
                }
            }
            if out.isEmpty {
                let fallback = await BeagleClient.shared.queryMemory(query: query)
                if let resp = fallback.value?.response, !resp.isEmpty {
                    out.append(resp)
                }
            }
            return out.isEmpty ? "Nenhum registro encontrado no cluster para '\(query)'." : out.joined(separator: "\n")

        case "beagle_store_memory":
            let text = (args["text"] as? String) ?? (args["thought"] as? String) ?? argumentsJSON
            let cap = await BeagleClient.shared.captureThought(
                text: text,
                source: "beagle-mcp-direct"
            )
            return cap.value?.response ?? "Memória salva no cluster Beagle."

        default:
            return await BeagleMCPClient.shared.executeToolForLLM(name: name, argumentsJSON: argumentsJSON)
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
