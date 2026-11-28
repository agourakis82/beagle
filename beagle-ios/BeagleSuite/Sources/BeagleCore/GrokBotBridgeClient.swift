//
//  GrokBotBridgeClient.swift
//  BeagleCore
//
//  Bidirectional integration bridge between Beagle and Grok Bot 1.0 (xAI / SpaceXSI):
//  - Outbound: authenticated HTTP POST to Grok Bot Webhook-Triggered Routines
//    (`Authorization: Bearer <key>`, `Content-Type: application/json`)
//  - Inbound: ready-to-paste Custom MCP Connector (`https://mcp.agourakis.com/mcp`)
//    and `assisted-import` (`source_surface: "grok-bot"`) Skill/Routine prompts.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization

// MARK: - Routine Target & Dispatch Models

public struct GrokBotRoutineTarget: Codable, Identifiable, Equatable, Hashable, Sendable {
    public static let primaryId = "primary"

    public let id: String
    public var name: String
    public var webhookURLString: String
    public var notes: String
    public var includePhysioContext: Bool

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        webhookURLString: String,
        notes: String = "",
        includePhysioContext: Bool = true
    ) {
        self.id = id
        self.name = name
        self.webhookURLString = webhookURLString
        self.notes = notes
        self.includePhysioContext = includePhysioContext
    }

    public var isValidURL: Bool {
        GrokBotBridgeClient.validateWebhookURL(webhookURLString) != nil
    }

    var keychainAccount: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return "beagle.grokbot.routine.\(String(cleaned)).key"
    }
}

public struct GrokBotDispatchResult: Codable, Equatable, Sendable {
    public let ok: Bool
    public let httpStatus: Int?
    public let routineId: String
    public let routineName: String
    public let responsePreview: String
    public let errorMessage: String?
    public let dispatchedAt: Date

    public init(
        ok: Bool,
        httpStatus: Int?,
        routineId: String,
        routineName: String,
        responsePreview: String,
        errorMessage: String?,
        dispatchedAt: Date = Date()
    ) {
        self.ok = ok
        self.httpStatus = httpStatus
        self.routineId = routineId
        self.routineName = routineName
        self.responsePreview = responsePreview
        self.errorMessage = errorMessage
        self.dispatchedAt = dispatchedAt
    }
}

public struct GrokBotDispatchRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let routineId: String
    public let routineName: String
    public let taskPreview: String
    public let ok: Bool
    public let httpStatus: Int?
    public let summary: String
    public let dispatchedAt: Date
}

// MARK: - Keychain-Backed Credentials & Routine Registry

public enum GrokBotCredentials {
    private static let routinesDefaultsKey = "beagle.grokbot.routines.v1"
    private static let historyDefaultsKey = "beagle.grokbot.dispatchHistory.v1"
    private static let maxHistoryEntries = 10

    private static let testOverridesStorage = Mutex<[(target: GrokBotRoutineTarget, bearerKey: String)]?>(nil)
    static var testRoutinesOverride: [(target: GrokBotRoutineTarget, bearerKey: String)]? {
        get { testOverridesStorage.withLock { $0 } }
        set { testOverridesStorage.withLock { $0 = newValue } }
    }

    public static var routines: [GrokBotRoutineTarget] {
        if let overrides = testRoutinesOverride {
            return overrides.map(\.target)
        }
        if let data = UserDefaults.standard.data(forKey: routinesDefaultsKey),
           let decoded = try? JSONDecoder().decode([GrokBotRoutineTarget].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        if let seedURL = fallbackSeedURL(), !seedURL.isEmpty {
            return [
                GrokBotRoutineTarget(
                    id: GrokBotRoutineTarget.primaryId,
                    name: "Rotina Principal",
                    webhookURLString: seedURL,
                    notes: "Rotina padrão do Grok Bot (webhook configurado via Secrets/env)",
                    includePhysioContext: true
                )
            ]
        }
        return []
    }

    public static func saveRoutines(_ list: [GrokBotRoutineTarget]) {
        if let overrides = testRoutinesOverride {
            let updated = list.map { target in
                let existingKey = overrides.first(where: { $0.target.id == target.id })?.bearerKey ?? ""
                return (target: target, bearerKey: existingKey)
            }
            testRoutinesOverride = updated
            return
        }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: routinesDefaultsKey)
        }
    }

    public static var primaryRoutine: GrokBotRoutineTarget? {
        let all = routines
        return all.first(where: { $0.id == GrokBotRoutineTarget.primaryId }) ?? all.first
    }

    public static func upsertRoutine(_ target: GrokBotRoutineTarget, bearerKey: String? = nil) {
        var cleaned = target
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty {
            cleaned.name = cleaned.id == GrokBotRoutineTarget.primaryId ? "Rotina Principal" : "Rotina Grok Bot"
        }
        cleaned.webhookURLString = cleaned.webhookURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.notes = cleaned.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let overrides = testRoutinesOverride {
            var next = overrides
            if let idx = next.firstIndex(where: { $0.target.id == cleaned.id }) {
                let resolvedKey = bearerKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? next[idx].bearerKey
                next[idx] = (target: cleaned, bearerKey: resolvedKey)
            } else {
                next.append((target: cleaned, bearerKey: bearerKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""))
            }
            testRoutinesOverride = next
            return
        }

        var list = routines
        if let idx = list.firstIndex(where: { $0.id == cleaned.id }) {
            list[idx] = cleaned
        } else {
            list.append(cleaned)
        }
        saveRoutines(list)

        if let bearerKey {
            setBearerKey(bearerKey, forRoutineId: cleaned.id)
        }
    }

    public static func removeRoutine(id: String) {
        if let overrides = testRoutinesOverride {
            testRoutinesOverride = overrides.filter { $0.target.id != id }
            return
        }
        let existing = routines.first(where: { $0.id == id })
        let remaining = routines.filter { $0.id != id }
        saveRoutines(remaining)
        if let existing {
            DirectCredentialKeychain.save("", account: existing.keychainAccount)
        }
    }

    public static func bearerKey(forRoutineId id: String) -> String {
        if let overrides = testRoutinesOverride {
            return overrides.first(where: { $0.target.id == id })?.bearerKey ?? ""
        }
        let target = routines.first(where: { $0.id == id })
            ?? GrokBotRoutineTarget(id: id, name: "", webhookURLString: "")
        if let saved = DirectCredentialKeychain.load(account: target.keychainAccount), !saved.isEmpty {
            return saved
        }
        if id == GrokBotRoutineTarget.primaryId {
            return fallbackSeedKey() ?? ""
        }
        return ""
    }

    public static func setBearerKey(_ key: String, forRoutineId id: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let overrides = testRoutinesOverride {
            testRoutinesOverride = overrides.map { pair in
                pair.target.id == id ? (target: pair.target, bearerKey: trimmed) : pair
            }
            return
        }
        let target = routines.first(where: { $0.id == id })
            ?? GrokBotRoutineTarget(id: id, name: "", webhookURLString: "")
        DirectCredentialKeychain.save(trimmed, account: target.keychainAccount)
    }

    public static var hasConfiguredRoutine: Bool {
        routines.contains { routine in
            routine.isValidURL && !bearerKey(forRoutineId: routine.id).isEmpty
        }
    }

    public static func resolveTarget(namedOrId: String?) -> (target: GrokBotRoutineTarget, bearerKey: String)? {
        let all = routines
        guard !all.isEmpty else { return nil }
        let query = namedOrId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let chosen: GrokBotRoutineTarget?
        if query.isEmpty {
            chosen = all.first(where: {
                $0.id == GrokBotRoutineTarget.primaryId && $0.isValidURL && !bearerKey(forRoutineId: $0.id).isEmpty
            }) ?? all.first(where: {
                $0.isValidURL && !bearerKey(forRoutineId: $0.id).isEmpty
            }) ?? primaryRoutine
        } else {
            let lowered = query.lowercased()
            chosen = all.first(where: { $0.id.lowercased() == lowered })
                ?? all.first(where: { $0.name.lowercased() == lowered })
                ?? all.first(where: {
                    $0.name.lowercased().contains(lowered) || $0.notes.lowercased().contains(lowered)
                })
        }

        guard let target = chosen else { return nil }
        let key = bearerKey(forRoutineId: target.id)
        return (target, key)
    }

    public static var recentDispatches: [GrokBotDispatchRecord] {
        guard testRoutinesOverride == nil,
              let data = UserDefaults.standard.data(forKey: historyDefaultsKey),
              let decoded = try? JSONDecoder().decode([GrokBotDispatchRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    public static func recordDispatch(_ result: GrokBotDispatchResult, task: String) {
        guard testRoutinesOverride == nil else { return }
        var history = recentDispatches
        let cleanTask = String(
            task.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(120)
        )
        let summary: String
        if result.ok {
            let statusText = result.httpStatus.map { "HTTP \($0)" } ?? "OK"
            summary = result.responsePreview.isEmpty ? statusText : "\(statusText) · \(result.responsePreview)"
        } else {
            summary = result.errorMessage ?? "Falha no disparo"
        }

        let record = GrokBotDispatchRecord(
            id: UUID().uuidString.lowercased(),
            routineId: result.routineId,
            routineName: result.routineName,
            taskPreview: cleanTask,
            ok: result.ok,
            httpStatus: result.httpStatus,
            summary: String(summary.prefix(180)),
            dispatchedAt: result.dispatchedAt
        )
        history.insert(record, at: 0)
        if history.count > maxHistoryEntries {
            history = Array(history.prefix(maxHistoryEntries))
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyDefaultsKey)
        }
    }

    public static func clearDispatchHistory() {
        UserDefaults.standard.removeObject(forKey: historyDefaultsKey)
    }

    /// Ready-to-paste setup prompt for Grok Bot Desktop (`Custom MCP Connector` + `Skill` + `Webhook Routine`).
    public static func beagleMCPSetupPrompt(includeCockpitToken: Bool = false) -> String {
        let tokenDisplay: String
        if includeCockpitToken, let resolved = CockpitToken.resolve(), !resolved.isEmpty {
            tokenDisplay = resolved
        } else {
            tokenDisplay = "<SEU_X_COCKPIT_TOKEN>"
        }

        return """
        # Conectar Grok Bot 1.0 ↔ Beagle Exocortex

        ## 1. Custom MCP Connector (Grok Bot Desktop → Connect apps → Add a custom connector → Remote HTTPS)
        - Name: Beagle Exocortex
        - Server URL: \(BeagleEndpoints.mcpEndpoint.absoluteString)
        - Header obrigatório: x-cockpit-token: \(tokenDisplay)

        ## 2. Skill do Grok Bot (salvar como Skill reutilizável "Beagle Bridge")
        Use as tools MCP do conector `Beagle Exocortex` sempre que precisar consultar a memória GraphRAG++, projetos (Sounio/PBPK/KEC/UFPR), histórico clínico/científico ou contexto do Demetrios.
        Ao concluir pesquisas relevantes, triagens ou sínteses para devolver ao iPhone/Mac do Demetrios, registre via tool MCP `beagle_store_memory` ou envie via `POST https://beagle.chiuratto.ai/api/mobile/v1/memory/assisted-import` com header `x-cockpit-token` e `"source_surface": "grok-bot"`.
        Nunca salve chaves secretas ou tokens em texto aberto.

        ## 3. Rotina Webhook no Grok Bot Desktop
        Crie uma Routine chamada "Beagle Inbox & Pesquisa", adicione trigger **Webhook** e copie:
        - `POST to` URL → cole em Beagle Cockpit → Ajustes → Grok Bot → URL Webhook
        - `Authorization: Bearer <key>` → cole o `<key>` em Bearer Key (Keychain)

        Prompt sugerido da Routine:
        Receba o JSON do webhook enviado pelo `beagle-cockpit` (`task`, `priority`, `context`, `physiome`, `space_weather`, `project_slug`). Execute a tarefa usando suas ferramentas e o MCP `Beagle Exocortex` quando precisar de contexto prévio. Ao finalizar, grave a síntese útil no Exocórtex (`source_surface: "grok-bot"`) e responda HTTP 200 JSON `{ "status": "accepted", "summary": "..." }`.
        """
    }

    private static func fallbackSeedURL() -> String? {
        if let env = ProcessInfo.processInfo.environment["GROK_BOT_WEBHOOK_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        return secretValue(forKey: "GROK_BOT_WEBHOOK_URL")
    }

    private static func fallbackSeedKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["GROK_BOT_WEBHOOK_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        return secretValue(forKey: "GROK_BOT_WEBHOOK_KEY")
    }

    private static func secretValue(forKey key: String) -> String? {
        for bundle in Bundle.allBundles {
            if let path = bundle.path(forResource: "Secrets", ofType: "plist"),
               let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
               let val = dict[key] as? String {
                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}

// MARK: - Grok Bot Bridge Actor & DirectBrain Tool Surface

public actor GrokBotBridgeClient {
    public static let shared = GrokBotBridgeClient()

    public static let toolNames: Set<String> = [
        "delegate_to_grok_bot",
        "list_grok_bot_routines"
    ]

    public nonisolated static func isGrokBotTool(_ name: String) -> Bool {
        toolNames.contains(name)
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public nonisolated static func validateWebhookURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        if scheme == "https" {
            return url
        }
        if scheme == "http",
           host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".ts.net") {
            return url
        }
        return nil
    }

    public func dispatch(
        task: String,
        routineNameOrId: String? = nil,
        priority: String = "normal",
        contextSummary: String? = nil,
        projectSlug: String? = nil,
        physioSummary: PhysioSummary? = nil,
        spaceWeather: SpaceWeatherStore.Snapshot? = nil,
        isTestPing: Bool = false
    ) async -> GrokBotDispatchResult {
        guard let resolved = GrokBotCredentials.resolveTarget(namedOrId: routineNameOrId) else {
            let err = "Nenhuma rotina do Grok Bot configurada. Adicione o Webhook URL e Bearer Key em Ajustes → Grok Bot."
            let result = GrokBotDispatchResult(
                ok: false,
                httpStatus: nil,
                routineId: routineNameOrId ?? GrokBotRoutineTarget.primaryId,
                routineName: routineNameOrId ?? "Não configurada",
                responsePreview: "",
                errorMessage: err
            )
            return result
        }

        let result = await dispatchToExplicitTarget(
            resolved.target,
            bearerKey: resolved.bearerKey,
            task: task,
            priority: priority,
            contextSummary: contextSummary,
            projectSlug: projectSlug,
            physioSummary: physioSummary,
            spaceWeather: spaceWeather,
            isTestPing: isTestPing
        )
        GrokBotCredentials.recordDispatch(result, task: task)
        return result
    }

    public func pingRoutine(_ target: GrokBotRoutineTarget, bearerKey: String) async -> GrokBotDispatchResult {
        let result = await dispatchToExplicitTarget(
            target,
            bearerKey: bearerKey,
            task: "Beagle Cockpit connectivity ping (verificação de rotina webhook). Responda HTTP 200 OK.",
            priority: "low",
            contextSummary: "Ping disparado manualmente em Ajustes → Grok Bot.",
            projectSlug: nil,
            physioSummary: nil,
            spaceWeather: nil,
            isTestPing: true
        )
        GrokBotCredentials.recordDispatch(result, task: "Ping · \(target.name)")
        return result
    }

    public func dispatchToExplicitTarget(
        _ target: GrokBotRoutineTarget,
        bearerKey: String,
        task: String,
        priority: String = "normal",
        contextSummary: String? = nil,
        projectSlug: String? = nil,
        physioSummary: PhysioSummary? = nil,
        spaceWeather: SpaceWeatherStore.Snapshot? = nil,
        isTestPing: Bool = false
    ) async -> GrokBotDispatchResult {
        let cleanTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTask.isEmpty else {
            return GrokBotDispatchResult(
                ok: false,
                httpStatus: nil,
                routineId: target.id,
                routineName: target.name,
                responsePreview: "",
                errorMessage: "A tarefa para o Grok Bot está vazia."
            )
        }

        guard let url = Self.validateWebhookURL(target.webhookURLString) else {
            return GrokBotDispatchResult(
                ok: false,
                httpStatus: nil,
                routineId: target.id,
                routineName: target.name,
                responsePreview: "",
                errorMessage: "URL de webhook inválida para '\(target.name)'. Use o endpoint HTTPS `POST to` da Routine no Grok Bot Desktop."
            )
        }

        let cleanKey = bearerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            return GrokBotDispatchResult(
                ok: false,
                httpStatus: nil,
                routineId: target.id,
                routineName: target.name,
                responsePreview: "",
                errorMessage: "Bearer Key ausente para a rotina '\(target.name)'. Cole a chave da Routine no Grok Bot em Ajustes → Grok Bot."
            )
        }

        let payload = Self.buildPayload(
            target: target,
            task: cleanTask,
            priority: priority,
            contextSummary: contextSummary,
            projectSlug: projectSlug,
            physioSummary: physioSummary,
            spaceWeather: spaceWeather,
            isTestPing: isTestPing
        )

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return GrokBotDispatchResult(
                ok: false,
                httpStatus: nil,
                routineId: target.id,
                routineName: target.name,
                responsePreview: "",
                errorMessage: "Falha ao serializar payload JSON para o Grok Bot."
            )
        }

        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.setValue("BeagleCockpit/1.0 (GrokBotBridge)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            let preview = String(
                (String(data: data, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(400)
            )
            let ok = (status ?? 0) >= 200 && (status ?? 0) < 300
            return GrokBotDispatchResult(
                ok: ok,
                httpStatus: status,
                routineId: target.id,
                routineName: target.name,
                responsePreview: preview,
                errorMessage: ok ? nil : "Grok Bot retornou HTTP \(status ?? 0)\(preview.isEmpty ? "" : ": \(preview)")"
            )
        } catch {
            return GrokBotDispatchResult(
                ok: false,
                httpStatus: nil,
                routineId: target.id,
                routineName: target.name,
                responsePreview: "",
                errorMessage: "Erro de rede ao acionar Grok Bot: \(error.localizedDescription)"
            )
        }
    }

    static func buildPayload(
        target: GrokBotRoutineTarget,
        task: String,
        priority: String,
        contextSummary: String?,
        projectSlug: String?,
        physioSummary: PhysioSummary?,
        spaceWeather: SpaceWeatherStore.Snapshot?,
        isTestPing: Bool
    ) -> [String: Any] {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let normalizedPriority: String = {
            let p = priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["low", "normal", "high", "urgent"].contains(p) ? p : "normal"
        }()

        var payload: [String: Any] = [
            "source": "beagle-cockpit",
            "event": isTestPing ? "beagle_webhook_ping" : "beagle_delegation",
            "timestamp": nowISO,
            "priority": normalizedPriority,
            "routine": [
                "id": target.id,
                "name": target.name
            ],
            "task": task,
            "beagle_mcp": [
                "endpoint": BeagleEndpoints.mcpEndpoint.absoluteString,
                "assisted_import_url": "https://beagle.chiuratto.ai/api/mobile/v1/memory/assisted-import",
                "source_surface": "grok-bot"
            ]
        ]

        if let contextSummary,
           !contextSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["context"] = contextSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let projectSlug,
           !projectSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["project_slug"] = projectSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if target.includePhysioContext {
            if let physio = physioSummary {
                var physDict: [String: Any] = [
                    "readiness": physio.readiness.rawValue
                ]
                if let hrv = physio.hrvMs { physDict["hrv_ms"] = Int(hrv.rounded()) }
                if let rhr = physio.restingHeartRate { physDict["resting_hr_bpm"] = Int(rhr.rounded()) }
                if let sleep = physio.sleepHours { physDict["sleep_hours"] = Double(String(format: "%.1f", sleep)) ?? sleep }
                payload["physiome"] = physDict
            }
            if let sky = spaceWeather {
                var skyDict: [String: Any] = [
                    "band": sky.band.rawValue,
                    "kp": sky.kp
                ]
                if let dst = sky.dst { skyDict["dst_nt"] = dst }
                if let bz = sky.bz { skyDict["bz_nt"] = bz }
                if let wind = sky.solarWindSpeed { skyDict["solar_wind_kms"] = wind }
                payload["space_weather"] = skyDict
            }
        }

        return payload
    }

    // MARK: - OpenAI / Anthropic / Responses Tool Definitions & Execution

    public nonisolated static func openAIToolDefinitions() -> [[String: Any]] {
        [
            [
                "type": "function",
                "function": [
                    "name": "delegate_to_grok_bot",
                    "description": "Envia uma tarefa, automação em nuvem, triagem, pesquisa externa ou ação assíncrona para uma Routine do Grok Bot (xAI / SpaceXSI) via Webhook autenticado. Use quando Demetrios pedir para delegar/enviar ao Grok Bot ou disparar uma rotina dele em segundo plano.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "task": [
                                "type": "string",
                                "description": "Instrução completa e clara do que o Grok Bot deve executar."
                            ],
                            "routine_name": [
                                "type": "string",
                                "description": "Nome ou ID opcional da rotina do Grok Bot configurada no Beagle (se omitido, usa a rotina principal)."
                            ],
                            "priority": [
                                "type": "string",
                                "description": "Prioridade opcional: 'low', 'normal', 'high' ou 'urgent'."
                            ],
                            "context": [
                                "type": "string",
                                "description": "Contexto adicional resumido (sem chaves secretas) para orientar a execução do Grok Bot."
                            ]
                        ],
                        "required": ["task"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "list_grok_bot_routines",
                    "description": "Lista as rotinas do Grok Bot configuradas no Beagle (nomes, URLs mascaradas, notas e últimos disparos).",
                    "parameters": [
                        "type": "object",
                        "properties": [:] as [String: Any],
                        "required": [] as [String]
                    ]
                ]
            ]
        ]
    }

    public func execute(name: String, args: [String: Any], projectSlug: String?) async -> String {
        switch name {
        case "list_grok_bot_routines":
            let routines = GrokBotCredentials.routines
            if routines.isEmpty {
                return "Nenhuma rotina do Grok Bot está configurada ainda. Oriente Demetrios a abrir Ajustes → Grok Bot, criar uma Routine com Webhook Trigger no Grok Bot Desktop e colar o `POST to` + Bearer Key."
            }
            var lines: [String] = ["Rotinas Grok Bot configuradas (\(routines.count)):"]
            for r in routines {
                let hasKey = !GrokBotCredentials.bearerKey(forRoutineId: r.id).isEmpty
                let status = (r.isValidURL && hasKey) ? "pronta" : "incompleta (verifique URL/Key)"
                let host = URL(string: r.webhookURLString)?.host ?? "url inválida"
                let noteSuffix = r.notes.isEmpty ? "" : " · \(r.notes)"
                lines.append("- [\(r.id)] \(r.name) (\(status) · \(host))\(noteSuffix)")
            }
            let recent = GrokBotCredentials.recentDispatches.prefix(3)
            if !recent.isEmpty {
                lines.append("\nÚltimos disparos:")
                for item in recent {
                    lines.append("- \(item.routineName): \(item.ok ? "OK" : "Falha") — \(item.taskPreview) (\(item.summary))")
                }
            }
            return lines.joined(separator: "\n")

        case "delegate_to_grok_bot":
            let task = ((args["task"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else {
                return "Informe o campo 'task' com a instrução para enviar ao Grok Bot."
            }
            let routineName = (args["routine_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let priority = (args["priority"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "normal"
            let context = (args["context"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let result = await dispatch(
                task: task,
                routineNameOrId: routineName,
                priority: priority,
                contextSummary: context,
                projectSlug: projectSlug
            )

            if result.ok {
                let statusStr = result.httpStatus.map { "HTTP \($0)" } ?? "HTTP 2xx"
                let bodyNote = result.responsePreview.isEmpty
                    ? "Webhook aceito sem corpo adicional."
                    : "Retorno: \(result.responsePreview)"
                return "Tarefa enviada ao Grok Bot (rotina '\(result.routineName)', \(statusStr)). \(bodyNote)"
            } else {
                return "Não foi possível acionar o Grok Bot ('\(result.routineName)'): \(result.errorMessage ?? "erro desconhecido")."
            }

        default:
            return "Ferramenta Grok Bot desconhecida: \(name)."
        }
    }
}
