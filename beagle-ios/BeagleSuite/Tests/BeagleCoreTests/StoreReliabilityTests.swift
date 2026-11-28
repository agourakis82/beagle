//
//  StoreReliabilityTests.swift
//  BeagleCoreTests
//
//  End-to-end deterministic unit tests (zero live network) covering DI-enabled stores and clients:
//  HPCStore, SpaceWeatherStore, OficinaStore, CatalogStore, and BeagleMCPClient.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import BeagleCore

private final class StoreMockURLProtocol: URLProtocol, @unchecked Sendable {
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
        config.protocolClasses = [StoreMockURLProtocol.self]
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

@Suite("Store & Client Reliability")
struct StoreReliabilityTests {

    // MARK: - HPCStore

    @Test("HPCStore refreshes queue, submits jobs with Truthful error tracking, and encodes jobId")
    @MainActor
    func hpcStoreLifecycleAndEncoding() async {
        let host = "hpc-store.beagle.test"
        let recorded = Mutex<[String]>([])
        let submitStatus = Mutex<Int>(200)

        let queueJSON = """
        {
          "jobs": [
            { "job_id": "job-1", "kind": "pbpk-sim", "status": "running", "gpu_count": 2 }
          ],
          "total_gpus": 8,
          "allocated_gpus": 2,
          "generated_at": "2026-11-27T17:00:00Z"
        }
        """
        let submittedJSON = """
        { "job_id": "job-2", "kind": "darwin-sweep", "status": "queued", "gpu_count": 1 }
        """
        let stdoutJSON = """
        { "response": "epoch=10 loss=0.012" }
        """

        StoreMockURLProtocol.register(host: host) { request in
            let url = request.url!
            let path = url.path
            recorded.withLock { $0.append(url.absoluteString) }

            let code: Int
            let body: String
            if path == "/api/jobs/queue" {
                code = 200
                body = queueJSON
            } else if path == "/api/darwin/hpc/jobs/submit" {
                code = submitStatus.withLock { $0 }
                body = code == 200 ? submittedJSON : #"{"error":"cluster maintenance"}"#
            } else if path.hasSuffix("/stdout") {
                code = 200
                body = stdoutJSON
            } else {
                code = 404
                body = "{}"
            }

            let resp = HTTPURLResponse(
                url: url,
                statusCode: code,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, Data(body.utf8))
        }
        defer { StoreMockURLProtocol.unregister(host: host) }

        let session = StoreMockURLProtocol.makeSession()
        let base = URL(string: "https://\(host)")!
        let cockpit = CockpitClient(session: session, baseURLs: [base])
        let beagle = BeagleClient(session: session, baseURLs: [base])
        await beagle.configure(baseURLs: [base], consumerId: "test", token: "tok-test")
        let store = HPCStore(cockpitClient: cockpit, beagleClient: beagle)

        await store.refresh()
        #expect(store.jobQueue.mode == .observed)
        #expect(store.jobs.count == 1)
        #expect(store.totalGPUs == 8)
        #expect(store.allocatedGPUs == 2)
        #expect(store.gpuUtilizationPercent == 25.0)
        #expect(store.isLoading == false)

        let okResult = await store.submitJobResult(kind: "darwin-sweep")
        #expect(okResult.mode == .observed)
        #expect(okResult.value?.id == "job-2")
        #expect(store.lastSubmissionError == nil)

        submitStatus.withLock { $0 = 503 }
        let failResult = await store.submitJobResult(kind: "darwin-sweep")
        #expect(failResult.mode == .stale)
        #expect(store.lastSubmissionError?.contains("503") == true)

        let out = await store.jobStdout(jobId: "run/42?x=1")
        #expect(out == "epoch=10 loss=0.012")
        let urls = recorded.withLock { $0 }
        #expect(urls.contains { $0.contains("run%2F42%3Fx=1/stdout") })
    }

    // MARK: - SpaceWeatherStore

    @Test("SpaceWeatherStore records observed latestTruth and degrades cleanly on HTTP 503")
    @MainActor
    func spaceWeatherStoreTruthModes() async {
        let host = "space-weather.beagle.test"
        let status = Mutex<Int>(200)

        let payload = """
        {
          "ok": true,
          "latest": {
            "ts": "2026-11-27T16:00:00Z",
            "kp": 5.3,
            "dst": -62.0,
            "f107": 168.0,
            "solar_wind_speed": 590.0,
            "bz": -7.5,
            "source": "noaa-swpc"
          }
        }
        """

        StoreMockURLProtocol.register(host: host) { request in
            let code = status.withLock { $0 }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: code,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, code == 200 ? Data(payload.utf8) : Data("unavailable".utf8))
        }
        defer { StoreMockURLProtocol.unregister(host: host) }

        let session = StoreMockURLProtocol.makeSession()
        let base = URL(string: "https://\(host)")!
        let beagle = BeagleClient(session: session, baseURLs: [base])
        await beagle.configure(baseURLs: [base], consumerId: "test", token: "tok-test")
        let store = SpaceWeatherStore(client: beagle)

        await store.refresh()
        #expect(store.latestTruth?.mode == .observed)
        #expect(store.latest?.kp == 5.3)
        #expect(store.isStorm == true)

        status.withLock { $0 = 503 }
        await store.refresh()
        #expect(store.latestTruth?.mode == .stale)
        #expect(store.latest?.kp == 5.3)
    }

    // MARK: - OficinaStore

    @Test("OficinaStore decodes observed state and preserves last-known PRs on 401/503")
    @MainActor
    func oficinaStoreReliability() async {
        let host = "oficina-store.beagle.test"
        let status = Mutex<Int>(200)

        let okJSON = """
        {
          "data": {
            "mainVerdict": "green",
            "observedAt": 1750000000000,
            "prs": [
              {
                "number": 108,
                "title": "Unify BeagleCore API",
                "branch": "feat/api-sota",
                "url": "https://example.invalid/pr/108",
                "draft": false,
                "verdict": "green",
                "failing": [],
                "checksTotal": 12,
                "checksGreen": 12
              }
            ]
          }
        }
        """

        StoreMockURLProtocol.register(host: host) { request in
            let code = status.withLock { $0 }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: code,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, code == 200 ? Data(okJSON.utf8) : Data(#"{"error":"unauthorized"}"#.utf8))
        }
        defer { StoreMockURLProtocol.unregister(host: host) }

        let session = StoreMockURLProtocol.makeSession()
        let endpoint = FleetEndpoint(host: host, scheme: "wss", token: "oficina-tok")
        let store = OficinaStore(endpoint: endpoint, session: session)

        await store.refresh()
        #expect(store.fetchError == nil)
        #expect(store.truthfulState.mode == .observed)
        #expect(store.state.prs.count == 1)
        #expect(store.state.prs.first?.number == 108)
        #expect(store.isLoading == false)

        status.withLock { $0 = 401 }
        await store.refresh()
        #expect(store.fetchError?.contains("401") == true)
        #expect(store.truthfulState.mode == .stale)
        #expect(store.state.prs.count == 1)
    }

    // MARK: - CatalogStore

    @Test("CatalogStore injects CockpitClient and refreshes projects + summary")
    @MainActor
    func catalogStoreRefresh() async {
        let host = "catalog-store.beagle.test"

        let catalogJSON = """
        {
          "ok": true,
          "meta": { "truthMode": "observed" },
          "data": {
            "projects": [
              {
                "projectSlug": "sounio-core",
                "mode": "always-on"
              }
            ]
          }
        }
        """
        let policyJSON = """
        {
          "title": "Posture Policy",
          "counts": { "totalProjects": 1, "alwaysOn": 1, "warm": 0, "cold": 0 }
        }
        """

        StoreMockURLProtocol.register(host: host) { request in
            let path = request.url?.path ?? ""
            let body = path.hasSuffix("/project-posture-policy") ? policyJSON : catalogJSON
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, Data(body.utf8))
        }
        defer { StoreMockURLProtocol.unregister(host: host) }

        let session = StoreMockURLProtocol.makeSession()
        let client = CockpitClient(session: session, baseURLs: [URL(string: "https://\(host)")!])
        let store = CatalogStore(client: client)

        await store.refresh()
        #expect(store.executive.mode == .observed)
        #expect(store.posturePolicy.mode == .observed)
        #expect(store.projects.first?.projectSlug == "sounio-core")
        #expect(store.alwaysOnProjects.count == 1)
        #expect(store.isLoading == false)
    }

    // MARK: - BeagleMCPClient

    @Test("BeagleMCPClient sends Bearer auth and decodes JSON-RPC tools/list")
    func mcpClientListTools() async throws {
        let host = "mcp-client.beagle.test"
        let capturedAuth = Mutex<String?>(nil)

        let rpcResponse = """
        {
          "jsonrpc": "2.0",
          "id": 1,
          "result": {
            "tools": [
              {
                "name": "beagle_graph_query",
                "title": "GraphRAG Query",
                "description": "Query the Beagle knowledge graph"
              }
            ]
          }
        }
        """

        StoreMockURLProtocol.register(host: host) { request in
            capturedAuth.withLock { $0 = request.value(forHTTPHeaderField: "Authorization") }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, Data(rpcResponse.utf8))
        }
        defer { StoreMockURLProtocol.unregister(host: host) }

        let session = StoreMockURLProtocol.makeSession()
        let client = BeagleMCPClient(
            endpoint: URL(string: "https://\(host)/mcp")!,
            session: session,
            accessToken: "mcp-test-bearer"
        )

        let result = try await client.listTools()
        #expect(result.tools.count == 1)
        #expect(result.tools.first?.name == "beagle_graph_query")
        #expect(capturedAuth.withLock { $0 } == "Bearer mcp-test-bearer")
    }
}
