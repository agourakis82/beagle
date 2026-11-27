//
//  APIConsistencyTests.swift
//  BeagleCoreTests
//
//  Verifies the unified endpoint/auth surface, Truthful projections, Codable wire contracts,
//  ProjectStore single-overview deduplication, CoordStore HTTP error propagation,
//  ConnectionStateRepresentable conformances, and English Fleet store APIs.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import BeagleCore

// MARK: - Swift 6 Concurrency-Safe Host-Keyed Mock URLProtocol

private final class HostKeyedMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let handlers = Mutex<[String: Handler]>([:])

    static func register(host: String, handler: @escaping Handler) {
        handlers.withLock { $0[host] = handler }
    }

    static func unregister(host: String) {
        handlers.withLock { _ = $0.removeValue(forKey: host) }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HostKeyedMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return handlers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host,
              let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - API Consistency Test Suite

@Suite("API Consistency")
struct APIConsistencyTests {

    // MARK: - BeagleEndpoints

    @Test("pathComponent percent-encodes slashes, query delimiters, fragments, and spaces")
    func pathComponentEncoding() {
        #expect(BeagleEndpoints.pathComponent("sounio-core") == "sounio-core")
        #expect(BeagleEndpoints.pathComponent("a/b?c=1#frag") == "a%2Fb%3Fc=1%23frag")
        #expect(BeagleEndpoints.pathComponent("hello world") == "hello%20world")
    }

    @Test("applyCockpitAuth injects trimmed x-cockpit-token header")
    func applyCockpitAuthHeader() {
        var request = URLRequest(url: URL(string: "https://beagle.chiuratto.ai/api/health")!)
        BeagleEndpoints.applyCockpitAuth(to: &request, explicitToken: "  test-secret-token\n")
        #expect(request.value(forHTTPHeaderField: BeagleEndpoints.cockpitTokenHeader) == "test-secret-token")
    }

    @Test("Canonical endpoint chains are non-empty and use HTTPS primary edge")
    func canonicalEndpointChains() {
        #expect(BeagleEndpoints.cockpitURLs.first?.scheme == "https")
        #expect(BeagleEndpoints.beagleServerURLs.first?.scheme == "https")
        #expect(BeagleEndpoints.physiomeURLs.first?.scheme == "https")
        #expect(BeagleEndpoints.mcpEndpoint.scheme == "https")
    }

    // MARK: - Truthful Projections

    @Test("Truthful.map and compactMap preserve epistemic metadata")
    func truthfulProjections() {
        let ts = Date(timeIntervalSince1970: 1_750_000_000)
        let original = Truthful(
            value: (count: 7, label: Optional("ready")),
            mode: .remembered,
            observedAt: ts,
            source: "beagle.chiuratto.ai",
            error: nil
        )

        let mapped = original.map(\.count)
        #expect(mapped.value == 7)
        #expect(mapped.mode == .remembered)
        #expect(mapped.observedAt == ts)
        #expect(mapped.source == "beagle.chiuratto.ai")
        #expect(mapped.error == nil)

        let projected = original.compactMap(\.label)
        #expect(projected?.value == "ready")
        #expect(projected?.mode == .remembered)
        #expect(projected?.observedAt == ts)
        #expect(projected?.source == "beagle.chiuratto.ai")

        let nilProjected: Truthful<Int>? = original.compactMap { _ in nil }
        #expect(nilProjected == nil)

        let stale = Truthful<Int>.staleError("timeout", source: "edge")
        let mappedStale = stale.map { $0 * 2 }
        #expect(mappedStale.value == nil)
        #expect(mappedStale.mode == .stale)
        #expect(mappedStale.error == "timeout")
        #expect(mappedStale.source == "edge")
    }

    // MARK: - IngestTurnRequest Codable Wire Contract

    @Test("IngestTurnRequest encodes canonical session_id JSON wire key")
    func ingestTurnRequestWireContract() throws {
        let req = IngestTurnRequest(
            sessionId: "sess-42",
            userText: "hello",
            assistantText: "world",
            clientTime: "2026-11-27T17:00:00Z",
            timezone: "America/Sao_Paulo"
        )
        let data = try JSONEncoder().encode(req)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])

        #expect(req.sessionId == "sess-42")
        #expect(obj["session_id"] == "sess-42")
        #expect(obj["sessionId"] == nil)
        #expect(obj["userText"] == "hello")
        #expect(obj["assistantText"] == "world")
    }

    // MARK: - ProjectStore Deduplication

    @Test("ProjectStore.refresh fires exactly one /overview call instead of four")
    @MainActor
    func projectStoreSingleOverviewFetch() async {
        let host = "project-store-dedup.beagle.test"
        let paths = Mutex<[String]>([])

        let overviewJSON = """
        {
          "ok": true,
          "meta": { "truthMode": "observed" },
          "data": {
            "missionControl": { "packetCount": 3, "generatedAt": "2026-11-27T17:00:00Z" },
            "clusterLaneTruth": { "generatedAt": "2026-11-27T17:00:00Z" },
            "researchOperations": { "generatedAt": "2026-11-27T17:00:00Z" },
            "inferenceRuntime": { "status": "ready", "configured": true, "reachable": true }
          }
        }
        """
        let clusterSummaryJSON = """
        {
          "nodes": [],
          "generatedAt": "2026-11-27T17:00:00Z",
          "truthMode": "observed"
        }
        """

        HostKeyedMockURLProtocol.register(host: host) { request in
            let path = request.url?.path ?? ""
            paths.withLock { $0.append(path) }

            let body: String
            if path.hasSuffix("/overview") {
                body = overviewJSON
            } else if path.hasSuffix("/cluster/summary") {
                body = clusterSummaryJSON
            } else {
                let notFound = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (notFound, Data())
            }

            let ok = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (ok, Data(body.utf8))
        }
        defer { HostKeyedMockURLProtocol.unregister(host: host) }

        let session = HostKeyedMockURLProtocol.makeSession()
        let baseURL = URL(string: "https://\(host)")!
        let client = CockpitClient(session: session, baseURLs: [baseURL])
        let store = ProjectStore(slug: "sounio-core", client: client)

        await store.refresh()

        let recordedPaths = paths.withLock { $0 }
        let overviewCalls = recordedPaths.filter { $0.hasSuffix("/overview") }
        let clusterSummaryCalls = recordedPaths.filter { $0.hasSuffix("/cluster/summary") }

        #expect(overviewCalls.count == 1)
        #expect(clusterSummaryCalls.count == 1)
        #expect(recordedPaths.count == 2)
        #expect(store.mission.mode == .observed)
        #expect(store.mission.value?.packetCount == 3)
        #expect(store.clusterTruth.mode == .observed)
        #expect(store.research.mode == .observed)
        #expect(store.inference.mode == .observed)
        #expect(store.inference.value?.status == "ready")
        #expect(store.clusterSummary.mode == .observed)
        #expect(store.isLoading == false)
    }

    // MARK: - CoordStore HTTP Status Validation & State Preservation

    @Test("CoordStore validates HTTP status codes and preserves last-known state on 401/503")
    @MainActor
    func coordStoreHTTPStatusValidation() async {
        let host = "coord-store-http.beagle.test"
        let statusToReturn = Mutex<Int>(200)

        let validCoordJSON = """
        {
          "data": {
            "observedAt": 1750000000000,
            "sharedTrees": [
              { "cwd": "/srv/sounio", "branch": "main", "lanes": ["claude-1", "codex-4"] }
            ],
            "conflicts": [],
            "claims": []
          }
        }
        """

        HostKeyedMockURLProtocol.register(host: host) { request in
            let code = statusToReturn.withLock { $0 }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: code,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, code == 200 ? Data(validCoordJSON.utf8) : Data(#"{"error":"denied"}"#.utf8))
        }
        defer { HostKeyedMockURLProtocol.unregister(host: host) }

        let session = HostKeyedMockURLProtocol.makeSession()
        let endpoint = FleetEndpoint(host: host, scheme: "wss", token: "valid-test-token")
        let store = CoordStore(endpoint: endpoint, session: session)

        // 1) HTTP 200 -> observed with hazards populated
        await store.refresh()
        #expect(store.fetchError == nil)
        #expect(store.truthfulState.mode == .observed)
        #expect(store.state.lanesAtRisk == 2)

        // 2) HTTP 401 -> surfaces 401 message in fetchError & truthfulState, keeps last-known state
        statusToReturn.withLock { $0 = 401 }
        await store.refresh()
        #expect(store.fetchError?.contains("401") == true)
        #expect(store.truthfulState.mode == .stale)
        #expect(store.state.lanesAtRisk == 2)

        // 3) HTTP 503 -> surfaces 503 message, still preserves last-known state
        statusToReturn.withLock { $0 = 503 }
        await store.refresh()
        #expect(store.fetchError?.contains("503") == true)
        #expect(store.truthfulState.mode == .stale)
        #expect(store.state.lanesAtRisk == 2)
    }

    // MARK: - ConnectionStateRepresentable Conformances

    @Test("All transport connection state enums conform cleanly to ConnectionStateRepresentable")
    func connectionStateConformances() {
        func verify<S: ConnectionStateRepresentable>(
            connected: S,
            connecting: S,
            expectedConnectingTruth: TruthMode,
            failed: S,
            expectedFailure: String
        ) {
            #expect(connected.isConnected)
            #expect(!connected.isConnecting)
            #expect(connected.failureMessage == nil)
            #expect(connected.truthMode == .observed)

            #expect(!connecting.isConnected)
            #expect(connecting.isConnecting)
            #expect(connecting.truthMode == expectedConnectingTruth)

            #expect(!failed.isConnected)
            #expect(!failed.isConnecting)
            #expect(failed.failureMessage == expectedFailure)
            #expect(failed.truthMode == .stale)
        }

        verify(
            connected: WebSocketState.connected(source: "beagle.chiuratto.ai"),
            connecting: WebSocketState.reconnecting(attempt: 2),
            expectedConnectingTruth: .remembered,
            failed: WebSocketState.failed("socket closed"),
            expectedFailure: "socket closed"
        )
        verify(
            connected: PTYClient.State.connected,
            connecting: PTYClient.State.reconnecting,
            expectedConnectingTruth: .stale,
            failed: PTYClient.State.failed("eof"),
            expectedFailure: "eof"
        )
        verify(
            connected: FleetStateStore.Link.live,
            connecting: FleetStateStore.Link.retrying(reason: "offline", attempts: 3),
            expectedConnectingTruth: .stale,
            failed: FleetStateStore.Link.failed("bad url"),
            expectedFailure: "bad url"
        )
        #expect(FleetStateStore.Link.retrying(reason: "offline", attempts: 3).failureMessage == "offline")

        #expect(SessionStore.Link.live.isConnected)
        #expect(SessionStore.Link.live.truthMode == .observed)
        #expect(!SessionStore.Link.idle.isConnected)
        #expect(SessionStore.Link.idle.truthMode == .declared)
        #expect(SessionStore.Link.failed("401").failureMessage == "401")
    }

    // MARK: - Fleet English API Surface

    @Test("SessionTurn, TurnUsage, and FleetStateStore English APIs produce expected results")
    @MainActor
    func fleetEnglishAPISurface() {
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        let t1 = t0.addingTimeInterval(12)
        let steps: [SessionStep] = [
            .prompt(id: 1, text: "Run checks", at: t0),
            .message(id: 2, text: "All green", at: t1),
            .usage(id: 3, contextUsed: 25_000, contextLimit: 200_000, usd: 0.14, at: t1)
        ]

        #expect(steps[0].isRenderable)
        #expect(!steps[2].isRenderable)
        #expect(steps[2].usageMetrics == TurnUsage(contextUsed: 25_000, contextLimit: 200_000, usd: 0.14))

        let turns = SessionTurn.group(steps)
        #expect(turns.count == 1)
        #expect(turns[0].prompt == "Run checks")
        #expect(turns[0].steps.count == 3)
        #expect(turns[0].duration(completed: true) == 12)
        #expect(turns[0].duration(completed: false) == nil)
        #expect(turns[0].usage?.ratio == 0.125)

        let footer = SessionStore.turnFooter(duration: 12, usage: turns[0].usage)
        #expect(footer != nil)
        #expect(footer?.contains("12s") == true)

        #expect(FleetStateStore.nextRetryDelayMs(retries: 0) == 500)
        #expect(FleetStateStore.nextRetryDelayMs(retries: 10) == 10_000)
        #expect(FleetStateStore.linkDescription(.retrying(reason: "timeout", attempts: 4)).contains("timeout"))

        let pty = PTYClient(agent: "claude-1")
        pty.title = "swift test"
        pty.recordBell()
        pty.recordBell()
        #expect(pty.title == "swift test")
        #expect(pty.bellCount == 2)
        pty.clearBells()
        #expect(pty.bellCount == 0)
    }
}
