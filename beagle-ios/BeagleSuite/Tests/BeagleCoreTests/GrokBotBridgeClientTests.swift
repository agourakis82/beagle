import Foundation
import Synchronization
import Testing
@testable import BeagleCore

private struct RecordedWebhookRequest: Sendable {
    let url: String
    let method: String
    let authHeader: String?
    let contentType: String?
    let bodyData: Data
}

private final class GrokBotStubProtocol: URLProtocol, @unchecked Sendable {
    struct StubResponse: Sendable {
        let statusCode: Int
        let body: Data
    }

    static let state = Mutex<(
        nextResponse: StubResponse,
        recorded: [RecordedWebhookRequest]
    )>((StubResponse(statusCode: 200, body: Data(#"{"status":"accepted"}"#.utf8)), []))

    static func reset(statusCode: Int = 200, bodyJSON: String = #"{"status":"accepted","run_id":"gb_01"}"#) {
        state.withLock {
            $0.nextResponse = StubResponse(statusCode: statusCode, body: Data(bodyJSON.utf8))
            $0.recorded = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var bodyData = request.httpBody ?? Data()
        if bodyData.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bodyData.append(contentsOf: buffer.prefix(count))
            }
        }

        let captured = RecordedWebhookRequest(
            url: request.url?.absoluteString ?? "",
            method: request.httpMethod ?? "",
            authHeader: request.value(forHTTPHeaderField: "Authorization"),
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            bodyData: bodyData
        )
        let responseSpec = Self.state.withLock {
            $0.recorded.append(captured)
            return $0.nextResponse
        }

        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                  url: url,
                  statusCode: responseSpec.statusCode,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseSpec.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct GrokBotBridgeClientTests {

    private func makeStubbedClient() -> GrokBotBridgeClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GrokBotStubProtocol.self]
        return GrokBotBridgeClient(session: URLSession(configuration: config))
    }

    @Test("Validação de URL Webhook exige HTTPS público ou Tailnet/localhost")
    func validatesWebhookURLs() {
        #expect(GrokBotBridgeClient.validateWebhookURL("https://grok.x.ai/webhooks/routine-123") != nil)
        #expect(GrokBotBridgeClient.validateWebhookURL("http://localhost:8080/webhook") != nil)
        #expect(GrokBotBridgeClient.validateWebhookURL("http://node.tail21cbc4.ts.net/hook") != nil)
        #expect(GrokBotBridgeClient.validateWebhookURL("http://insecure.example.com/hook") == nil)
        #expect(GrokBotBridgeClient.validateWebhookURL("   ") == nil)
    }

    @Test("Dispatch autenticado envia Bearer header e payload JSON completo com Physiome e MCP")
    func dispatchSendsExpectedHeadersAndPayload() async throws {
        GrokBotStubProtocol.reset(statusCode: 200, bodyJSON: #"{"status":"queued","job":"gb-77"}"#)
        let client = makeStubbedClient()
        let target = GrokBotRoutineTarget(
            id: "inbox",
            name: "Triagem Diária",
            webhookURLString: "https://api.grokbot.test/v1/routines/inbox/webhook",
            notes: "Inbox e agenda",
            includePhysioContext: true
        )
        let physio = PhysioSummary(
            hrvMs: 74,
            restingHeartRate: 54,
            sleepHours: 7.5,
            readiness: .restored
        )
        let sky = SpaceWeatherStore.Snapshot(
            ts: Date(timeIntervalSince1970: 1_795_000_000),
            kp: 5.3,
            dst: -55,
            f107: 145,
            solarWindSpeed: 520,
            bz: -6.2,
            source: "NOAA SWPC"
        )

        let result = await client.dispatchToExplicitTarget(
            target,
            bearerKey: "gb_secret_token_999",
            task: "Organizar compromissos da semana e levantar papers de PBPK.",
            priority: "high",
            contextSummary: "Foco doutorado UFPR",
            projectSlug: "sounio",
            physioSummary: physio,
            spaceWeather: sky
        )

        #expect(result.ok)
        #expect(result.httpStatus == 200)
        #expect(result.routineId == "inbox")
        #expect(result.routineName == "Triagem Diária")
        #expect(result.responsePreview.contains("queued"))

        let recorded = GrokBotStubProtocol.state.withLock { $0.recorded }
        #expect(recorded.count == 1)
        let req = try #require(recorded.first)
        #expect(req.method == "POST")
        #expect(req.authHeader == "Bearer gb_secret_token_999")
        #expect(req.contentType == "application/json")

        let json = try #require(try JSONSerialization.jsonObject(with: req.bodyData) as? [String: Any])
        #expect(json["source"] as? String == "beagle-cockpit")
        #expect(json["event"] as? String == "beagle_delegation")
        #expect(json["priority"] as? String == "high")
        #expect(json["project_slug"] as? String == "sounio")
        #expect((json["beagle_mcp"] as? [String: Any])?["endpoint"] as? String == BeagleEndpoints.mcpEndpoint.absoluteString)
        #expect((json["beagle_mcp"] as? [String: Any])?["source_surface"] as? String == "grok-bot")
        #expect((json["physiome"] as? [String: Any])?["hrv_ms"] as? Int == 74)
        #expect((json["space_weather"] as? [String: Any])?["kp"] as? Double == 5.3)
    }

    @Test("Dispatch mapeia erro HTTP e valida entradas ausentes sem disparar rede")
    func dispatchHandlesHTTPAndValidationErrors() async {
        GrokBotStubProtocol.reset(statusCode: 401, bodyJSON: #"{"error":"invalid bearer token"}"#)
        let client = makeStubbedClient()
        let target = GrokBotRoutineTarget(
            id: "primary",
            name: "Principal",
            webhookURLString: "https://api.grokbot.test/v1/routines/primary"
        )

        let unauth = await client.dispatchToExplicitTarget(
            target,
            bearerKey: "wrong_key",
            task: "Rodar síntese"
        )
        #expect(!unauth.ok)
        #expect(unauth.httpStatus == 401)
        #expect(unauth.errorMessage?.contains("401") == true)

        GrokBotStubProtocol.reset()
        let missingKey = await client.dispatchToExplicitTarget(
            target,
            bearerKey: "  ",
            task: "Rodar síntese"
        )
        #expect(!missingKey.ok)
        #expect(missingKey.httpStatus == nil)
        #expect(GrokBotStubProtocol.state.withLock { $0.recorded.isEmpty })
    }

    @Test("Resolução de rotina encontra por ID, nome exato, substring e fallback principal")
    func resolvesRoutinesByIdNameOrFallback() {
        let primary = GrokBotRoutineTarget(
            id: GrokBotRoutineTarget.primaryId,
            name: "Rotina Principal",
            webhookURLString: "https://grok.test/primary",
            notes: "Geral"
        )
        let inbox = GrokBotRoutineTarget(
            id: "inbox-ops",
            name: "Triagem e Agenda",
            webhookURLString: "https://grok.test/inbox",
            notes: "Emails e compromissos"
        )
        GrokBotCredentials.testRoutinesOverride = [
            (target: primary, bearerKey: "key-primary"),
            (target: inbox, bearerKey: "key-inbox")
        ]
        defer { GrokBotCredentials.testRoutinesOverride = nil }

        #expect(GrokBotCredentials.hasConfiguredRoutine)
        #expect(GrokBotCredentials.resolveTarget(namedOrId: nil)?.target.id == GrokBotRoutineTarget.primaryId)
        #expect(GrokBotCredentials.resolveTarget(namedOrId: "inbox-ops")?.bearerKey == "key-inbox")
        #expect(GrokBotCredentials.resolveTarget(namedOrId: "triagem e agenda")?.target.id == "inbox-ops")
        #expect(GrokBotCredentials.resolveTarget(namedOrId: "compromissos")?.target.id == "inbox-ops")
    }

    @Test("DirectBrainTools expõe namespace grok_bot sob demanda e AppleDeviceToolsBridge mapeia badge Grok Bot")
    func exposesDirectBrainToolsAndProvenanceBadges() {
        let responseTools = DirectBrainClient.shared.buildResponsesTools2026(
            mcpTools: [],
            model: OpenAIModelCatalog.defaultFlagshipModel,
            enableNativeWebSearch: true,
            enableToolSearch: true
        )
        let grokNamespace = responseTools.first {
            ($0["type"] as? String) == "namespace" && ($0["name"] as? String) == "grok_bot"
        }
        let nsToolNames = ((grokNamespace?["tools"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        #expect(nsToolNames.contains("delegate_to_grok_bot"))
        #expect(nsToolNames.contains("list_grok_bot_routines"))

        let legacyTools = DirectBrainClient.shared.buildResponsesTools2026(
            mcpTools: [],
            model: OpenAIModelCatalog.defaultFlagshipModel,
            enableNativeWebSearch: false,
            enableToolSearch: false
        )
        let legacyNames = legacyTools.compactMap { $0["name"] as? String }
        #expect(legacyNames.contains("delegate_to_grok_bot"))
        #expect(legacyNames.contains("list_grok_bot_routines"))

        #expect(AppleDeviceToolsBridge.humanStatus(for: "delegate_to_grok_bot").contains("Grok Bot"))
        #expect(AppleDeviceToolsBridge.provenanceBadges(for: ["delegate_to_grok_bot"]) == ["Grok Bot"])
    }

    @Test("Prompt de setup MCP para Grok Bot referencia conector oficial sem vazar segredo por padrão")
    func mcpSetupPromptContainsOfficialEndpointsWithoutRawSecret() {
        let prompt = GrokBotCredentials.beagleMCPSetupPrompt(includeCockpitToken: false)
        #expect(prompt.contains(BeagleEndpoints.mcpEndpoint.absoluteString))
        #expect(prompt.contains("https://beagle.chiuratto.ai/api/mobile/v1/memory/assisted-import"))
        #expect(prompt.contains("\"source_surface\": \"grok-bot\""))
        #expect(prompt.contains("<SEU_X_COCKPIT_TOKEN>"))
    }
}
