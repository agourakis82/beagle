//
//  OpenAIAgentsSessionClient.swift
//  BeagleCore
//
//  Catálogo oficial de modelos OpenAI (Nov 2026 — Família GPT-6.2 Astra / Sol / Terra / Luna / Rosalind)
//  + controle de esforço de raciocínio (`reasoning.effort`)
//  + cliente nativo para a OpenAI Agents API (`https://api.openai.com/v1/agents/sessions`,
//    header `OpenAI-Beta: agents=v1`) com streaming SSE, steering durante o turno,
//    `Idempotency-Key`, cancelamento e recuperação de itens salvos.
//

import Foundation

// MARK: - OpenAI Nov 2026 Model Catalog

public enum OpenAIModelCatalog {
    public static let defaultFlagshipModel = "gpt-6.2-astra"
    public static let defaultDailyAgentModel = "gpt-6.2-sol"
    public static let defaultVisionFastModel = "gpt-6.1-terra"
    public static let defaultFastModel = "gpt-6-luna"
    public static let lifeSciencesModel = "gpt-rosalind"

    public struct Descriptor: Identifiable, Sendable, Equatable {
        public let id: String
        public let displayName: String
        public let subtitle: String
        public let supportsToolSearch: Bool
        public let forbidsNoneReasoningEffort: Bool

        public init(
            id: String,
            displayName: String,
            subtitle: String,
            supportsToolSearch: Bool = true,
            forbidsNoneReasoningEffort: Bool = true
        ) {
            self.id = id
            self.displayName = displayName
            self.subtitle = subtitle
            self.supportsToolSearch = supportsToolSearch
            self.forbidsNoneReasoningEffort = forbidsNoneReasoningEffort
        }
    }

    public static let presets: [Descriptor] = [
        Descriptor(
            id: "gpt-6.2-astra",
            displayName: "GPT-6.2 Astra (Flagship)",
            subtitle: "Mais capaz (1.05M ctx) · ciência, clínica, código e projetos complexos"
        ),
        Descriptor(
            id: "gpt-6.2-sol",
            displayName: "GPT-6.2 Sol (Agentes & Dia a Dia)",
            subtitle: "Recomendado para programação e execução de agentes em escala"
        ),
        Descriptor(
            id: "gpt-6.1-terra",
            displayName: "GPT-6.1 Terra (Visual & Rápido)",
            subtitle: "Rápido e eficiente para raciocínio visual e escrita natural"
        ),
        Descriptor(
            id: "gpt-6-luna",
            displayName: "GPT-6 Luna (Ultra-Rápido)",
            subtitle: "Menor latência e custo para tarefas diretas em alto volume"
        ),
        Descriptor(
            id: "gpt-rosalind",
            displayName: "GPT-Rosalind (Ciências da Vida)",
            subtitle: "Raciocínio especializado em biomedicina e ciências da vida"
        ),
        Descriptor(
            id: "gpt-6-cyber",
            displayName: "GPT-6 Cyber (Segurança)",
            subtitle: "Investigação de vulnerabilidades e verificação de correções"
        ),
        Descriptor(
            id: "gpt-5.5",
            displayName: "GPT-5.5 (Geração Anterior)",
            subtitle: "Compatível · suporta reasoning.effort = none",
            supportsToolSearch: true,
            forbidsNoneReasoningEffort: false
        ),
        Descriptor(
            id: "gpt-5.5-pro",
            displayName: "GPT-5.5 Pro (Geração Anterior)",
            subtitle: "Versão Pro da família GPT-5.5",
            supportsToolSearch: true,
            forbidsNoneReasoningEffort: true
        )
    ]

    /// Modelos marcados como Obsoleto ou Desativado no catálogo da OpenAI de Nov 2026.
    public static let obsoleteOrRetiredIDs: Set<String> = [
        "gpt-5", "gpt-5-pro", "gpt-5-mini", "gpt-5-nano",
        "gpt-5.1", "gpt-5.1-codex", "gpt-5.2-codex", "gpt-5.3-codex", "gpt-5.4-nano",
        "o3", "o3-pro", "o3-mini", "o4-mini", "o1", "o1-pro", "o1-mini",
        "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "gpt-4o", "gpt-4o-mini", "gpt-4-turbo"
    ]

    /// Somente `gpt-5.4` e modelos posteriores suportam `tool_search` na API Responses.
    public static func supportsToolSearch(_ model: String) -> Bool {
        let lower = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("gpt-6") || lower.hasPrefix("gpt-rosalind") {
            return true
        }
        if lower.hasPrefix("gpt-5.4") || lower.hasPrefix("gpt-5.5") || lower.hasPrefix("gpt-5.6") {
            return true
        }
        return false
    }

    /// `gpt-6.2-astra`, `gpt-6.2-sol`, `gpt-6-astra` e `gpt-6.1-sol` rejeitam `reasoning.effort = "none"` com HTTP 400.
    public static func forbidsNoneReasoningEffort(_ model: String) -> Bool {
        let lower = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("gpt-6") || lower.hasPrefix("gpt-rosalind")
    }

    /// Modelos GPT-6.2 não oferecem suporte a `service_tier: "flex"`.
    public static func forbidsFlexServiceTier(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("gpt-6.2")
    }

    public static func isDirectOpenAIModel(_ model: String?) -> Bool {
        guard let model, !model.isEmpty else { return true }
        let lower = model.lowercased()
        return lower.hasPrefix("gpt-") || lower.hasPrefix("o3") || lower.hasPrefix("o4")
    }

    public static func friendlyVoiceLabel(for model: String?) -> String? {
        guard let model, !model.isEmpty else { return nil }
        switch model.lowercased() {
        case "gpt-6.2-astra": return "GPT 6.2 Astra"
        case "gpt-6.2-sol": return "GPT 6.2 Sol"
        case "gpt-6.1-terra": return "GPT 6.1 Terra"
        case "gpt-6-luna": return "GPT 6 Luna"
        case "gpt-rosalind": return "GPT Rosalind"
        case "gpt-6-cyber": return "GPT 6 Cyber"
        case "gpt-5.5": return "GPT 5.5"
        case "gpt-5.5-pro": return "GPT 5.5 Pro"
        default:
            return model.hasPrefix("gpt-") ? model.uppercased() : nil
        }
    }
}

// MARK: - Reasoning Effort Configuration

public enum OpenAIReasoningEffort: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case xhigh = "xhigh"
    case max = "max"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Automático (Adaptativo)"
        case .low: return "Baixo (Rápido)"
        case .medium: return "Médio (Equilibrado)"
        case .high: return "Alto (Raciocínio Denso)"
        case .xhigh: return "Extra-Alto (Pesquisa Longa)"
        case .max: return "Máximo ( Extrema Complexidade )"
        }
    }

    /// Produz o dicionário `reasoning: {"effort": ...}` seguro para o modelo alvo,
    /// ou `nil` quando `.auto` (deixando o default nativo do modelo agir).
    public func responsesParameter(forModel model: String) -> [String: Any]? {
        guard self != .auto else { return nil }
        return ["effort": rawValue]
    }

    /// Garante que um valor textual arbitrário nunca envie `"none"` ou `"minimal"`
    /// para modelos da família `gpt-6*` (que retornam HTTP 400).
    public static func sanitizedEffort(_ raw: String?, forModel model: String) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty,
              raw != "auto" else {
            return nil
        }
        if (raw == "none" || raw == "minimal") && OpenAIModelCatalog.forbidsNoneReasoningEffort(model) {
            return "low"
        }
        return raw
    }
}

// MARK: - OpenAI Agents API (`v1/agents/sessions`, `OpenAI-Beta: agents=v1`)

public enum OpenAIAgentStreamEvent: Sendable, Equatable {
    case sessionCreated(sessionId: String)
    case textDelta(itemId: String?, delta: String)
    case textDone(itemId: String?, text: String)
    case statusLine(String)
    case requiresAction(String)
    case turnCompleted
}

public struct OpenAIAgentSavedItem: Sendable, Equatable {
    public let id: String
    public let role: String
    public let text: String

    public init(id: String, role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

public actor OpenAIAgentsSessionClient {
    public static let shared = OpenAIAgentsSessionClient()

    public nonisolated static let betaHeaderField = "OpenAI-Beta"
    public nonisolated static let betaHeaderValue = "agents=v1"
    public nonisolated static let sessionsEndpoint = URL(string: "https://api.openai.com/v1/agents/sessions")!

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 1800
            self.session = session ?? URLSession(configuration: config)
        }
    }

    // MARK: - Persisted Session ID per Project Slug

    public nonisolated static func savedSessionId(forProject slug: String) -> String? {
        let key = "beagle.openai.agents.session.\(slug)"
        let val = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return val.isEmpty ? nil : val
    }

    public nonisolated static func saveSessionId(_ sessionId: String?, forProject slug: String) {
        let key = "beagle.openai.agents.session.\(slug)"
        if let sessionId, !sessionId.isEmpty {
            UserDefaults.standard.set(sessionId, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Request Builders (Exposed for Deterministic Testing)

    public nonisolated static func buildCreateSessionRequest(
        apiKey: String,
        model: String,
        instructions: String,
        initialInput: String,
        environmentType: String = "openai_hosted"
    ) throws -> URLRequest {
        var req = URLRequest(url: sessionsEndpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(betaHeaderValue, forHTTPHeaderField: betaHeaderField)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "agent": [
                "model": model,
                "instructions": instructions
            ],
            "environment": [
                "type": environmentType
            ],
            "input": initialInput,
            "stream": true
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    public nonisolated static func buildSendMessageRequest(
        apiKey: String,
        sessionId: String,
        text: String,
        submissionKey: String = UUID().uuidString.lowercased()
    ) throws -> URLRequest {
        let url = sessionsEndpoint
            .appendingPathComponent(sessionId)
            .appendingPathComponent("events")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(betaHeaderValue, forHTTPHeaderField: betaHeaderField)
        req.setValue(submissionKey, forHTTPHeaderField: "Idempotency-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "events": [
                [
                    "type": "agent.session.input.message",
                    "input": [
                        [
                            "role": "user",
                            "content": [
                                [
                                    "type": "input_text",
                                    "text": text
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    public nonisolated static func buildCancelTurnRequest(
        apiKey: String,
        sessionId: String
    ) throws -> URLRequest {
        let url = sessionsEndpoint
            .appendingPathComponent(sessionId)
            .appendingPathComponent("events")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(betaHeaderValue, forHTTPHeaderField: betaHeaderField)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "events": [
                ["type": "agent.session.input.cancel"]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    // MARK: - Modo Fundo Quantitative Simulation & Code Execution

    /// Executa ou redireciona uma simulação científica / cálculo quantitativo (PBPK, EDO, estatística,
    /// prova simbólica) a partir de uma hipótese do Modo Fundo usando o sandbox hospedado da OpenAI
    /// (`v1/agents/sessions` · `gpt-6.2-astra`), com fallback automático e transparente para
    /// `DirectBrainClient.streamOpenAI` (`gpt-6.2-sol` high) caso o endpoint beta não esteja habilitado na conta.
    public func runScientificSimulationTurn(
        apiKey: String,
        prompt: String,
        synthesisContext: String?,
        existingSessionId: String? = nil,
        steeringInstruction: String? = nil,
        directBrain: DirectBrainClient = .shared,
        onStatus: (@Sendable (String) async -> Void)? = nil,
        onDelta: (@Sendable (String) async -> Void)? = nil
    ) async throws -> (sessionId: String?, output: String, usedSandboxAPI: Bool) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw NSError(
                domain: "OpenAIAgentsSessionClient",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Configure sua chave OpenAI em Ajustes para executar simulações."]
            )
        }

        let agentInstructions = """
        Você é o motor quantitativo e computacional do Beagle Modo Fundo (GPT-6.2 Astra Sandbox) para Demetrios Chiuratto Agourakis.
        Quando disponível no ambiente hospedado, escreva e execute código Python/NumPy/SciPy para verificar numericamente equações diferenciais, curvas PBPK/ADME, sensibilidade paramétrica, poder estatístico ou invariantes formais da hipótese investigada.
        Responda SEMPRE em português brasileiro técnico, enxuto e auditável, estruturando:
        1. **Modelo & Parâmetros Testados** (equações/hipóteses explícitas);
        2. **Resultados Numéricos Verificados** (valores, intervalos, pontos críticos ou tabela compacta);
        3. **Implicação Decisiva & Código Reprodutível** (bloco curto Python ou Sounio).
        """

        let contextBlock: String = {
            guard let s = synthesisContext?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
                return ""
            }
            return "\n\nContexto já apurado no Modo Fundo:\n\(String(s.prefix(4_000)))"
        }()

        let turnInput: String = {
            if let steer = steeringInstruction?.trimmingCharacters(in: .whitespacesAndNewlines), !steer.isEmpty {
                return steer
            }
            return """
            Construa e execute uma verificação quantitativa / simulação computacional para a questão abaixo, reportando números concretos e sensibilidade paramétrica:
            Questão: \(prompt)\(contextBlock)
            """
        }()

        // 1. Try Hosted OpenAI Agents Session Sandbox (`v1/agents/sessions`)
        do {
            if let sid = existingSessionId, !sid.isEmpty, steeringInstruction != nil {
                if let onStatus { await onStatus("Enviando ajuste de parâmetros à sessão agêntica…") }
                try await sendInputMessage(apiKey: trimmedKey, sessionId: sid, text: turnInput)
                let out = try await streamExistingSession(
                    apiKey: trimmedKey,
                    sessionId: sid,
                    stopOnTurnCompleted: true
                ) { event in
                    switch event {
                    case .statusLine(let s):
                        if let onStatus { await onStatus(s) }
                    case .textDelta(_, let delta):
                        if let onDelta { await onDelta(delta) }
                    default:
                        break
                    }
                }
                if !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (sid, out, true)
                }
            } else {
                if let onStatus { await onStatus("Iniciando sandbox agêntico OpenAI (GPT-6.2 Astra)…") }
                let created = try await createAndStreamSession(
                    apiKey: trimmedKey,
                    model: OpenAIModelCatalog.defaultFlagshipModel,
                    instructions: agentInstructions,
                    initialInput: turnInput
                ) { event in
                    switch event {
                    case .statusLine(let s):
                        if let onStatus { await onStatus(s) }
                    case .textDelta(_, let delta):
                        if let onDelta { await onDelta(delta) }
                    default:
                        break
                    }
                }
                if !created.outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (created.sessionId, created.outputText, true)
                }
            }
        } catch {
            // Fall back transparently to DirectBrainClient (`gpt-6.2-sol` high reasoning) below
        }

        // 2. Resilient Direct Brain Quantitative Fallback (`gpt-6.2-sol` high)
        if let onStatus { await onStatus("Derivando simulação analítica e numérica via GPT-6.2 Sol…") }
        let fallbackPrompt = existingSessionId != nil && steeringInstruction != nil
            ? "Questão base: \(prompt)\(contextBlock)\n\nAjuste / nova simulação solicitada: \(turnInput)"
            : turnInput

        let res = try await directBrain.streamOpenAI(
            model: "gpt-6.2-sol",
            systemPrompt: agentInstructions,
            developerPrefix: agentInstructions,
            reasoningEffort: "high",
            enableNativeWebSearch: false,
            enableToolSearch: false,
            turns: [DirectBrainTurn(role: "user", content: fallbackPrompt)],
            projectSlug: nil,
            onStatus: { status in
                if let onStatus { await onStatus(status) }
            },
            onToken: { delta in
                if let onDelta { await onDelta(delta) }
            }
        )
        return (existingSessionId, res.content.trimmingCharacters(in: .whitespacesAndNewlines), false)
    }

    // MARK: - Live Session Operations

    /// Cria uma nova sessão persistente na OpenAI Agents API com sandbox hospedado
    /// e transmite o primeiro turno em tempo real até `agent.session.turn.completed`.
    public func createAndStreamSession(
        apiKey: String,
        model: String = OpenAIModelCatalog.defaultFlagshipModel,
        instructions: String,
        initialInput: String,
        environmentType: String = "openai_hosted",
        onEvent: @Sendable @escaping (OpenAIAgentStreamEvent) async -> Void
    ) async throws -> (sessionId: String, outputText: String) {
        let req = try Self.buildCreateSessionRequest(
            apiKey: apiKey,
            model: model,
            instructions: instructions,
            initialInput: initialInput,
            environmentType: environmentType
        )
        let (bytes, response) = try await session.bytes(for: req)
        try await Self.validateHTTPResponse(response, bytes: bytes)
        return try await Self.consumeSSEStream(bytes: bytes, knownSessionId: nil, onEvent: onEvent)
    }

    /// Conecta ao stream SSE de uma sessão existente (`/v1/agents/sessions/{id}/events?stream=true`).
    public func streamExistingSession(
        apiKey: String,
        sessionId: String,
        stopOnTurnCompleted: Bool = false,
        onEvent: @Sendable @escaping (OpenAIAgentStreamEvent) async -> Void
    ) async throws -> String {
        var comps = URLComponents(
            url: Self.sessionsEndpoint.appendingPathComponent(sessionId).appendingPathComponent("events"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "stream", value: "true")]
        guard let url = comps.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.betaHeaderValue, forHTTPHeaderField: Self.betaHeaderField)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: req)
        try await Self.validateHTTPResponse(response, bytes: bytes)
        let result = try await Self.consumeSSEStream(
            bytes: bytes,
            knownSessionId: sessionId,
            stopOnTurnCompleted: stopOnTurnCompleted,
            onEvent: onEvent
        )
        return result.outputText
    }

    /// Envia uma mensagem do usuário (`agent.session.input.message`) com `Idempotency-Key`.
    /// Se o agente estiver ocioso, inicia um novo turno; se estiver trabalhando, redireciona (steers) o turno ativo.
    public func sendInputMessage(
        apiKey: String,
        sessionId: String,
        text: String,
        submissionKey: String = UUID().uuidString.lowercased()
    ) async throws {
        let req = try Self.buildSendMessageRequest(
            apiKey: apiKey,
            sessionId: sessionId,
            text: text,
            submissionKey: submissionKey
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let msg = String(data: data.prefix(600), encoding: .utf8) ?? "HTTP \(code)"
            throw NSError(domain: "OpenAIAgentsSessionClient", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// Cancela o turno em execução preservando a sessão e o histórico salvo.
    public func cancelActiveTurn(apiKey: String, sessionId: String) async throws {
        let req = try Self.buildCancelTurnRequest(apiKey: apiKey, sessionId: sessionId)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let msg = String(data: data.prefix(600), encoding: .utf8) ?? "HTTP \(code)"
            throw NSError(domain: "OpenAIAgentsSessionClient", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// Recupera os itens salvos da sessão (`/v1/agents/sessions/{id}/items?order=asc&limit=100`)
    /// para restaurar o contexto no terminal após reconexão ou troca de tela.
    public func listSavedItems(
        apiKey: String,
        sessionId: String,
        limit: Int = 60
    ) async throws -> [OpenAIAgentSavedItem] {
        var comps = URLComponents(
            url: Self.sessionsEndpoint.appendingPathComponent(sessionId).appendingPathComponent("items"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "order", value: "asc"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100)))
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.betaHeaderValue, forHTTPHeaderField: Self.betaHeaderField)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let msg = String(data: data.prefix(600), encoding: .utf8) ?? "HTTP \(code)"
            throw NSError(domain: "OpenAIAgentsSessionClient", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else {
            return []
        }

        var parsed: [OpenAIAgentSavedItem] = []
        for item in items {
            let id = (item["id"] as? String) ?? UUID().uuidString
            let role = (item["role"] as? String) ?? ((item["type"] as? String) ?? "assistant")
            var texts: [String] = []
            if let content = item["content"] as? [[String: Any]] {
                for part in content {
                    if let t = (part["text"] as? String) ?? (part["output_text"] as? String), !t.isEmpty {
                        texts.append(t)
                    }
                }
            } else if let direct = item["text"] as? String, !direct.isEmpty {
                texts.append(direct)
            }
            let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                parsed.append(OpenAIAgentSavedItem(id: id, role: role, text: joined))
            }
        }
        return parsed
    }

    // MARK: - SSE Event Parser

    public nonisolated static func parseEventJSON(
        _ event: [String: Any]
    ) throws -> (extractedSessionId: String?, mapped: OpenAIAgentStreamEvent?, isRootTurnTerminal: Bool) {
        let type = (event["type"] as? String) ?? ""
        let extractedSessionId: String? = {
            if let sid = event["session_id"] as? String, !sid.isEmpty { return sid }
            if let sess = event["session"] as? [String: Any],
               let sid = sess["id"] as? String, !sid.isEmpty { return sid }
            if let turn = event["turn"] as? [String: Any],
               let sid = turn["session_id"] as? String, !sid.isEmpty { return sid }
            return nil
        }()

        let isSubagentTurn: Bool = {
            guard let turn = event["turn"] as? [String: Any],
                  let sub = turn["subagent_id"] else { return false }
            if sub is NSNull { return false }
            if let str = sub as? String { return !str.isEmpty }
            return true
        }()

        switch type {
        case "agent.session.created":
            if let sid = extractedSessionId {
                return (sid, .sessionCreated(sessionId: sid), false)
            }
            return (nil, nil, false)

        case "agent.session.idle":
            return (extractedSessionId, nil, false)

        case "agent.session.turn.started":
            let label = isSubagentTurn ? "↳ subagente iniciou etapa…" : "● turno iniciado no sandbox OpenAI…"
            return (extractedSessionId, .statusLine(label), false)

        case "agent.session.turn.output_text.delta", "response.output_text.delta":
            let delta = (event["delta"] as? String) ?? ""
            let itemId = event["item_id"] as? String
            return (extractedSessionId, delta.isEmpty ? nil : .textDelta(itemId: itemId, delta: delta), false)

        case "agent.session.turn.output_text.done", "response.output_text.done":
            let text = (event["text"] as? String) ?? ""
            let itemId = event["item_id"] as? String
            return (extractedSessionId, text.isEmpty ? nil : .textDone(itemId: itemId, text: text), false)

        case "agent.session.requires_action":
            return (extractedSessionId, .requiresAction("Sessão aguardando aprovação/ação externa (`required_actions`)."), false)

        case "agent.session.turn.completed":
            if isSubagentTurn {
                return (extractedSessionId, .statusLine("↳ subagente concluiu etapa."), false)
            }
            return (extractedSessionId, .turnCompleted, true)

        case "agent.session.turn.failed":
            if isSubagentTurn {
                return (extractedSessionId, .statusLine("⚠ subagente falhou em etapa auxiliar."), false)
            }
            let detail = ((event["turn"] as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
                ?? "Turno falhou na Agents API."
            throw NSError(domain: "OpenAIAgentsSessionClient", code: -2, userInfo: [NSLocalizedDescriptionKey: detail])

        case "agent.session.turn.cancelled":
            if isSubagentTurn {
                return (extractedSessionId, .statusLine("↳ subagente cancelado."), false)
            }
            throw NSError(domain: "OpenAIAgentsSessionClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Turno cancelado pelo usuário."])

        case "agent.session.failed", "agent.session.environment.failed":
            throw NSError(domain: "OpenAIAgentsSessionClient", code: -4, userInfo: [NSLocalizedDescriptionKey: "Falha no ciclo de vida da sessão OpenAI (\(type))."])

        case "error":
            let msg = ((event["error"] as? [String: Any])?["message"] as? String) ?? "Erro na OpenAI Agents API."
            throw NSError(domain: "OpenAIAgentsSessionClient", code: -5, userInfo: [NSLocalizedDescriptionKey: msg])

        default:
            if type.contains("command") || type.contains("shell") || type.contains("tool") {
                if let name = (event["name"] as? String) ?? ((event["item"] as? [String: Any])?["name"] as? String),
                   !name.isEmpty {
                    return (extractedSessionId, .statusLine("⚙ executando \(name)…"), false)
                }
            }
            return (extractedSessionId, nil, false)
        }
    }

    private static func validateHTTPResponse(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            var errText = ""
            for try await line in bytes.lines {
                errText += line
                if errText.count > 600 { break }
            }
            throw NSError(
                domain: "OpenAIAgentsSessionClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errText.isEmpty ? "HTTP \(http.statusCode)" : errText]
            )
        }
    }

    private static func consumeSSEStream(
        bytes: URLSession.AsyncBytes,
        knownSessionId: String?,
        stopOnTurnCompleted: Bool = true,
        onEvent: @Sendable @escaping (OpenAIAgentStreamEvent) async -> Void
    ) async throws -> (sessionId: String, outputText: String) {
        var resolvedSessionId = knownSessionId ?? ""
        var emittedSessionCreated = (knownSessionId != nil)
        var currentBuffer = ""
        var sawDeltaForItem: Set<String> = []

        for try await rawLine in bytes.lines {
            try Task.checkCancellation()
            guard rawLine.hasPrefix("data:") else { continue }
            let payload = rawLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let parsed = try parseEventJSON(json)
            if let sid = parsed.extractedSessionId, !sid.isEmpty {
                resolvedSessionId = sid
                if !emittedSessionCreated {
                    emittedSessionCreated = true
                    await onEvent(.sessionCreated(sessionId: sid))
                }
            }
            if let mapped = parsed.mapped {
                switch mapped {
                case .textDelta(let itemId, let delta):
                    if let itemId { sawDeltaForItem.insert(itemId) }
                    currentBuffer += delta
                    await onEvent(mapped)
                case .textDone(let itemId, let full):
                    if let itemId, sawDeltaForItem.contains(itemId) {
                        // Deltas already streamed; just notify completion of part
                        await onEvent(mapped)
                    } else {
                        currentBuffer += full
                        await onEvent(.textDelta(itemId: itemId, delta: full))
                        await onEvent(mapped)
                    }
                default:
                    await onEvent(mapped)
                }
            }
            if stopOnTurnCompleted && parsed.isRootTurnTerminal {
                return (resolvedSessionId, currentBuffer)
            }
        }

        if stopOnTurnCompleted {
            throw URLError(.networkConnectionLost)
        }
        return (resolvedSessionId, currentBuffer)
    }
}
