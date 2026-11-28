//
//  ClientReliabilityAndDeepLinkTests.swift
//  BeagleCoreTests
//
//  Deterministic unit tests for:
//  - R1: Safe mutation failover + X-Request-ID propagation in BeagleClient & CockpitClient
//  - R2: Project deep link parsing (host & path forms, agent subpaths) & cold-start pending queue
//  - R4: Redacted diagnostic metadata & non-leaking fallback error formatting
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import BeagleCore

private final class ReliabilityMockURLProtocol: URLProtocol, @unchecked Sendable {
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
        config.protocolClasses = [ReliabilityMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
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

private struct AckResponse: Codable, Sendable, Equatable {
    let ok: Bool
    let id: String
}

private struct EncodedBody: Codable, Sendable {
    let note: String
}

private func makeHTTPResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
}

@Suite("R1: Safe POST/DELETE Failover & X-Request-ID")
struct MutationFailoverReliabilityTests {

    @Test("BeagleClient.post fails over on pre-delivery connection error with identical X-Request-ID")
    func beaglePostFailsOverOnPreDeliveryErrorWithStableRequestID() async {
        let primary = "r1-primary-connect-\(UUID().uuidString.lowercased()).beagle.test"
        let fallback = "r1-fallback-connect-\(UUID().uuidString.lowercased()).beagle.test"
        let seenRequestIDs = Mutex<[String]>([])

        ReliabilityMockURLProtocol.register(host: primary) { req in
            seenRequestIDs.withLock { $0.append(req.value(forHTTPHeaderField: "X-Request-ID") ?? "") }
            throw URLError(.cannotConnectToHost)
        }
        ReliabilityMockURLProtocol.register(host: fallback) { req in
            seenRequestIDs.withLock { $0.append(req.value(forHTTPHeaderField: "X-Request-ID") ?? "") }
            let data = try JSONEncoder().encode(AckResponse(ok: true, id: "fallback-ok"))
            return (makeHTTPResponse(url: req.url!, statusCode: 200), data)
        }
        defer {
            ReliabilityMockURLProtocol.unregister(host: primary)
            ReliabilityMockURLProtocol.unregister(host: fallback)
        }

        let client = BeagleClient(
            session: ReliabilityMockURLProtocol.makeSession(),
            baseURLs: [URL(string: "https://\(primary)")!, URL(string: "https://\(fallback)")!]
        )
        await client.configure(
            baseURLs: [URL(string: "https://\(primary)")!, URL(string: "https://\(fallback)")!],
            consumerId: "test-consumer",
            token: "test-token"
        )

        let result = await client.post(AckResponse.self, path: "/api/test/mutate", body: ["hello": "world"])

        #expect(result.mode == .observed)
        #expect(result.value == AckResponse(ok: true, id: "fallback-ok"))
        #expect(result.source == fallback)

        let ids = seenRequestIDs.withLock { $0 }
        #expect(ids.count == 2)
        #expect(!ids[0].isEmpty)
        #expect(ids[0] == ids[1])
    }

    @Test("BeagleClient.post does NOT replay on fallback host after HTTP 500 or HTTP 422")
    func beaglePostDoesNotReplayAfterHTTPResponse() async {
        for statusCode in [500, 422] {
            let primary = "r1-http-\(statusCode)-p-\(UUID().uuidString.lowercased()).beagle.test"
            let fallback = "r1-http-\(statusCode)-f-\(UUID().uuidString.lowercased()).beagle.test"
            let hits = Mutex<[String]>([])

            ReliabilityMockURLProtocol.register(host: primary) { req in
                hits.withLock { $0.append(primary) }
                let data = Data(#"{"error":"server_rejected","requestId":"srv-1"}"#.utf8)
                return (makeHTTPResponse(url: req.url!, statusCode: statusCode), data)
            }
            ReliabilityMockURLProtocol.register(host: fallback) { req in
                hits.withLock { $0.append(fallback) }
                let data = try JSONEncoder().encode(AckResponse(ok: true, id: "must-not-run"))
                return (makeHTTPResponse(url: req.url!, statusCode: 200), data)
            }
            defer {
                ReliabilityMockURLProtocol.unregister(host: primary)
                ReliabilityMockURLProtocol.unregister(host: fallback)
            }

            let client = BeagleClient(
                session: ReliabilityMockURLProtocol.makeSession(),
                baseURLs: [URL(string: "https://\(primary)")!, URL(string: "https://\(fallback)")!]
            )
            await client.configure(
                baseURLs: [URL(string: "https://\(primary)")!, URL(string: "https://\(fallback)")!],
                consumerId: "test-consumer",
                token: "test-token"
            )

            let result = await client.post(AckResponse.self, path: "/api/test/mutate", body: ["k": "v"])

            #expect(result.mode == .stale)
            #expect(result.value == nil)
            #expect(hits.withLock { $0 } == [primary])
        }
    }

    @Test("BeagleClient.postEncoded does NOT replay on fallback host after HTTP 200 decode failure")
    func beaglePostEncodedDoesNotReplayAfterDecodingError() async {
        let primary = "r1-decode-p-\(UUID().uuidString.lowercased()).beagle.test"
        let fallback = "r1-decode-f-\(UUID().uuidString.lowercased()).beagle.test"
        let hits = Mutex<[String]>([])

        ReliabilityMockURLProtocol.register(host: primary) { req in
            hits.withLock { $0.append(primary) }
            // Server committed mutation and returned 200, but schema drifted.
            let data = Data(#"{"unexpected_field":123}"#.utf8)
            return (makeHTTPResponse(url: req.url!, statusCode: 200), data)
        }
        ReliabilityMockURLProtocol.register(host: fallback) { req in
            hits.withLock { $0.append(fallback) }
            let data = try JSONEncoder().encode(AckResponse(ok: true, id: "must-not-duplicate"))
            return (makeHTTPResponse(url: req.url!, statusCode: 200), data)
        }
        defer {
            ReliabilityMockURLProtocol.unregister(host: primary)
            ReliabilityMockURLProtocol.unregister(host: fallback)
        }

        let client = BeagleClient(
            session: ReliabilityMockURLProtocol.makeSession(),
            baseURLs: [URL(string: "https://\(primary)")!, URL(string: "https://\(fallback)")!]
        )
        await client.configure(
            baseURLs: [URL(string: "https://\(primary)")!, URL(string: "https://\(fallback)")!],
            consumerId: "test-consumer",
            token: "test-token"
        )

        let result = await client.postEncoded(
            AckResponse.self,
            path: "/api/test/mutate",
            body: EncodedBody(note: "single-write")
        )

        #expect(result.mode == .stale)
        #expect(hits.withLock { $0 } == [primary])
    }

    @Test("BeagleClient.post does NOT replay on fallback host after ambiguous timeout or connection loss")
    func beaglePostDoesNotReplayAfterAmbiguousTransportError() async {
        for code in [URLError.Code.timedOut, URLError.Code.networkConnectionLost] {
            let primary = "r1-ambig-\(code.rawValue)-p-\(UUID().uuidString.lowercased()).beagle.test"
            let fallback = "r1-ambig-\(code.rawValue)-f-\(UUID().uuidString.lowercased()).beagle.test"
            let hits = Mutex<[String]>([])

            ReliabilityMockURLProtocol.register(host: primary) { _ in
                hits.withLock { $0.append(primary) }
                throw URLError(code)
            }
            ReliabilityMockURLProtocol.register(host: fallback) { req in
                hits.withLock { $0.append(fallback) }
                let data = try JSONEncoder().encode(AckResponse(ok: true, id: "must-not-run"))
                return (makeHTTPResponse(url: req.url!, statusCode: 200), data)
            }
            defer {
                ReliabilityMockURLProtocol.unregister(host: primary)
                ReliabilityMockURLProtocol.unregister(host: fallback)
            }

            let client = BeagleClient(
                session: ReliabilityMockURLProtocol.makeSession(),
                baseURLs: [URL(string: "https://\(primary)")!, URL(string: "https://\(fallback)")!]
            )
            await client.configure(
                baseURLs: [URL(string: "https://\(primary)")!, URL(string: "https://\(fallback)")!],
                consumerId: "test-consumer",
                token: "test-token"
            )

            let result = await client.post(AckResponse.self, path: "/api/test/mutate", body: [:])

            #expect(result.mode == .stale)
            #expect(hits.withLock { $0 } == [primary])
        }
    }

    @Test("CockpitClient mutations propagate explicit X-Request-ID and stop on HTTP 500 or ok=false")
    func cockpitClientMutationIdempotencyAndNoReplay() async {
        let primary = "r1-cockpit-p-\(UUID().uuidString.lowercased()).beagle.test"
        let fallback = "r1-cockpit-f-\(UUID().uuidString.lowercased()).beagle.test"
        let hits = Mutex<[(String, String)]>([])

        // Case 1: Pre-delivery DNS error -> fails over to fallback with same explicit X-Request-ID
        ReliabilityMockURLProtocol.register(host: primary) { req in
            hits.withLock { $0.append((primary, req.value(forHTTPHeaderField: "X-Request-ID") ?? "")) }
            throw URLError(.cannotFindHost)
        }
        ReliabilityMockURLProtocol.register(host: fallback) { req in
            hits.withLock { $0.append((fallback, req.value(forHTTPHeaderField: "X-Request-ID") ?? "")) }
            let data = Data(#"{"ok":true,"data":{"ok":true,"id":"cockpit-fallback"}}"#.utf8)
            return (makeHTTPResponse(url: req.url!, statusCode: 200), data)
        }
        defer {
            ReliabilityMockURLProtocol.unregister(host: primary)
            ReliabilityMockURLProtocol.unregister(host: fallback)
        }

        let client = CockpitClient(
            session: ReliabilityMockURLProtocol.makeSession(),
            baseURLs: [URL(string: "https://\(primary)")!, URL(string: "https://\(fallback)")!]
        )

        let okResult = await client.postMobile(
            AckResponse.self,
            path: "/api/mobile/v1/actions",
            body: ["action": "ping"],
            idempotencyKey: "req-explicit-123"
        )
        #expect(okResult.mode == .observed)
        #expect(okResult.value == AckResponse(ok: true, id: "cockpit-fallback"))
        let recorded = hits.withLock { $0 }
        #expect(recorded.count == 2)
        #expect(recorded[0].1 == "req-explicit-123")
        #expect(recorded[1].1 == "req-explicit-123")

        // Case 2: Primary returns HTTP 200 with ok=false -> MUST NOT replay on fallback
        hits.withLock { $0.removeAll() }
        ReliabilityMockURLProtocol.register(host: primary) { req in
            hits.withLock { $0.append((primary, req.value(forHTTPHeaderField: "X-Request-ID") ?? "")) }
            let data = Data(#"{"ok":false,"error":{"message":"conflict"}}"#.utf8)
            return (makeHTTPResponse(url: req.url!, statusCode: 200), data)
        }

        let deleteResult = await client.deleteMobile(
            AckResponse.self,
            path: "/api/mobile/v1/items/42",
            idempotencyKey: "del-42"
        )
        #expect(deleteResult.mode == .stale)
        #expect(hits.withLock { $0 }.map(\.0) == [primary])
    }
}

@Suite("R2: Project Deep Links & Cold-Start Routing")
struct ProjectDeepLinkRoutingTests {

    @Test("Parses host-form and path-form beagle://project URLs with optional agent kind")
    @MainActor
    func parsesAllProjectDeepLinkForms() {
        let hostOnly = DeepLinkRouter.projectTarget(for: URL(string: "beagle://project/sounio")!)
        #expect(hostOnly == DeepLinkRouter.ProjectLaunchTarget(slug: "sounio", agentKind: nil))

        let pathOnly = DeepLinkRouter.projectTarget(for: URL(string: "beagle:///project/sounio")!)
        #expect(pathOnly == DeepLinkRouter.ProjectLaunchTarget(slug: "sounio", agentKind: nil))

        let hostWithAgent = DeepLinkRouter.projectTarget(for: URL(string: "beagle://project/sounio/agent/claude")!)
        #expect(hostWithAgent == DeepLinkRouter.ProjectLaunchTarget(slug: "sounio", agentKind: "claude"))

        let pathWithAgent = DeepLinkRouter.projectTarget(for: URL(string: "beagle:///project/sounio/agent/codex")!)
        #expect(pathWithAgent == DeepLinkRouter.ProjectLaunchTarget(slug: "sounio", agentKind: "codex"))

        let mixedCase = DeepLinkRouter.projectTarget(for: URL(string: "BEAGLE://PROJECT/beagle-ios/AGENT/gemini")!)
        #expect(mixedCase == DeepLinkRouter.ProjectLaunchTarget(slug: "beagle-ios", agentKind: "gemini"))
    }

    @Test("Rejects malformed project deep links and non-project URLs")
    @MainActor
    func rejectsMalformedProjectDeepLinks() {
        #expect(DeepLinkRouter.projectTarget(for: URL(string: "beagle://project")!) == nil)
        #expect(DeepLinkRouter.projectTarget(for: URL(string: "beagle://project/")!) == nil)
        #expect(DeepLinkRouter.projectTarget(for: URL(string: "beagle:///project/")!) == nil)
        #expect(DeepLinkRouter.projectTarget(for: URL(string: "https://project/sounio")!) == nil)
        #expect(DeepLinkRouter.projectTarget(for: URL(string: "beagle://frota")!) == nil)
    }

    @Test("DeepLinkRouter.open parks pendingProject for cold start and consumes exactly once")
    @MainActor
    func openParksAndConsumesProjectTarget() {
        let router = DeepLinkRouter.shared
        _ = router.consumeProject()
        defer { _ = router.consumeProject() }

        let handled = router.open(URL(string: "beagle://project/sounio/agent/claude")!)
        #expect(handled == true)
        #expect(router.pendingProject == DeepLinkRouter.ProjectLaunchTarget(slug: "sounio", agentKind: "claude"))

        let firstConsume = router.consumeProject()
        #expect(firstConsume == DeepLinkRouter.ProjectLaunchTarget(slug: "sounio", agentKind: "claude"))
        #expect(router.pendingProject == nil)
        #expect(router.consumeProject() == nil)
    }
}

@Suite("R4: Response Body Log & Error Redaction")
struct ResponseRedactionTests {

    @Test("BeagleClient.redactedDiagnosticSummary reports structural metadata without leaking payload text")
    func diagnosticSummaryIsRedacted() {
        let secretPayload = #"{"patient":"Demetrios","cortisol":24.5}"#
        let decodeError: Error
        do {
            _ = try JSONDecoder().decode(AckResponse.self, from: Data(secretPayload.utf8))
            Issue.record("Expected DecodingError")
            return
        } catch {
            decodeError = error
        }

        let summary = BeagleClient.redactedDiagnosticSummary(
            statusCode: 200,
            byteCount: secretPayload.utf8.count,
            requestID: "req-abc",
            error: decodeError
        )

        #expect(summary.contains("status=200"))
        #expect(summary.contains("bytes=\(secretPayload.utf8.count)"))
        #expect(summary.contains("requestId=req-abc"))
        #expect(summary.contains("decodingError=keyNotFound("))
        #expect(!summary.contains("Demetrios"))
        #expect(!summary.contains("cortisol"))
    }

    @Test("formatError never leaks raw unstructured body text while preserving structured backend errors")
    func formatErrorRedactsUnstructuredPayloads() async {
        let client = BeagleClient(
            session: ReliabilityMockURLProtocol.makeSession(),
            baseURLs: [URL(string: "https://redaction.beagle.test")!]
        )
        let cockpit = CockpitClient(
            session: ReliabilityMockURLProtocol.makeSession(),
            baseURLs: [URL(string: "https://redaction.beagle.test")!]
        )

        let rawSensitiveBody = Data("Sensitive clinical note: patient XYZ".utf8)
        let beagleUnstructured = await client.formatError(statusCode: 502, data: rawSensitiveBody, fallback: "HTTP 502")
        let beagleMobileUnstructured = await client.formatMobileError(statusCode: 502, data: rawSensitiveBody, fallback: "HTTP 502")
        let cockpitUnstructured = await cockpit.formatError(statusCode: 502, data: rawSensitiveBody, fallback: "HTTP 502")

        #expect(beagleUnstructured == "HTTP 502")
        #expect(beagleMobileUnstructured == "HTTP 502")
        #expect(cockpitUnstructured == "HTTP 502")
        #expect(!beagleUnstructured.contains("Sensitive"))
        #expect(!cockpitUnstructured.contains("Sensitive"))

        // Structured backend error payloads remain intact
        let structuredBody = Data(#"{"error":"rate_limited","reason":"retry after 5s","requestId":"req-9"}"#.utf8)
        let beagleStructured = await client.formatError(statusCode: 429, data: structuredBody, fallback: "HTTP 429")
        let cockpitStructured = await cockpit.formatError(statusCode: 429, data: structuredBody, fallback: "HTTP 429")

        #expect(beagleStructured.contains("rate_limited"))
        #expect(beagleStructured.contains("requestId=req-9"))
        #expect(cockpitStructured.contains("rate_limited"))
        #expect(cockpitStructured.contains("requestId=req-9"))
    }
}
