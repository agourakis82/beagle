//
//  BeagleClient.swift
//  BeagleCore
//
//  HTTP client for the beagle-server (Rust/Axum) scientific endpoints.
//  Mirrors CockpitClient pattern: multi-URL fallback, Truthful<T> responses.
//
//  Endpoints:
//   - /dev/chat, /dev/debate — exocortex conversation + Triad
//   - /api/jobs/science/* — Julia scientific pipelines
//   - /api/hrv — Apple Watch HRV ingest
//   - /api/v1/cognitive/state — aggregated cognitive dashboard
//   - /api/v1/hyperedges — knowledge graph
//   - /api/v1/feedback — learning loop
//

import Foundation

public actor BeagleClient {

    /// Shared secret gating the project-cockpit's `/api/mobile/v1/*` surface — that API is
    /// reachable on the public internet (beagle.chiuratto.ai), so every request must prove
    /// physical possession of this build. Personal single-user app: a compiled-in constant
    /// matches this app's existing trust model (device possession = access), same as the
    /// other hardcoded endpoints/UAs already in this file. Rotate by regenerating + rebuilding.
    // internal (module-visible), not fileprivate: PhysiomeUploader (same BeagleCore module)
    // also needs it — its own token-bridge + ingest requests were missed in the original
    // cockpit-auth pass (a duplicate refreshPhysiomeToken() implementation, not routed
    // through this actor).
    // public, not just internal: BeagleCockpit-module screens (e.g. CognitiveRecall.swift)
    // also need it — BeagleCore and BeagleCockpit are separate modules, so `internal` isn't
    // enough.
    /// Token do cockpit, lido do bundle — NUNCA de um literal no código.
    ///
    /// Este valor ficou hardcoded aqui e a branch é publicada: de 01-jul a
    /// 06-ago-2026 qualquer pessoa podia baixar o arquivo do GitHub sem
    /// autenticação, conversar com o companion como ele e puxar 19 KB da
    /// biografia dele por /companion/grounding. Verificado, não suposto.
    ///
    /// Agora vem de Secrets.plist, que é gitignored. Secrets.example.plist tem o
    /// modelo e diz como obter o valor real do cluster.
    ///
    /// Vazio quando o arquivo falta: o app compila e as chamadas falham com 401,
    /// que é ruído honesto — melhor que um token de exemplo parecendo funcionar.
    /// Resolved cockpit mobile token, delegating to `CockpitToken.resolve()`
    /// (bundle `Secrets.plist` → `BEAGLE_COCKPIT_TOKEN` → `~/.beagle/cockpit-token`).
    /// Returns `""` when unconfigured so requests fail honestly with HTTP 401.
    public static var cockpitMobileToken: String {
        CockpitToken.resolve() ?? ""
    }

    public static let shared = BeagleClient()

    internal let session: URLSession
    internal let decoder: JSONDecoder
    internal let encoder: JSONEncoder

    /// beagle-server URLs — tried in sequence.
    internal var baseURLs: [URL] = BeagleEndpoints.beagleServerURLs

    /// Auth token for beagle-core consumer API.
    /// Obtained via cockpit auth bridge: GET /api/auth/beagle-token
    private var consumerToken: String?
    private var consumerId: String?
    private var tokenFetched = false
    internal var authBootstrapError: String?

    public init(session: URLSession? = nil, baseURLs: [URL]? = nil) {
        if let baseURLs {
            self.baseURLs = baseURLs
        }
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 120 // Triad can be slow
            config.waitsForConnectivity = true
            config.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": "BeagleCockpit/1.0 (iOS exocortex)"
            ]
            self.session = URLSession(configuration: config)
        }
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func configure(baseURLs: [URL], consumerId: String? = nil, token: String? = nil) {
        self.baseURLs = baseURLs
        if let consumerId { self.consumerId = consumerId }
        if let token {
            self.consumerToken = token
            self.tokenFetched = !token.isEmpty
            self.tokenFetchedAt = token.isEmpty ? nil : Date()
            if !token.isEmpty {
                self.authBootstrapError = nil
            }
        }
    }

    internal static func pathComponent(_ value: String) -> String {
        BeagleEndpoints.pathComponent(value)
    }

    /// Whether beagle-server is reachable (quick health check).
    /// Minimal decode of GET /health. The server returns a MIXED-type object
    /// ({"status":"ok","safe_mode":true,...}); decoding it as [String: Bool] (the old
    /// shape) always failed on the string fields, so isReachable() returned false — which
    /// silently gated every CognitiveStore.refresh(), so a triggered fractal/Φ (or any
    /// cognitive refresh) never surfaced in the UI. A permissive struct just confirms the
    /// server answered with parseable JSON.
    private struct HealthProbe: Decodable { let status: String? }

    public func isReachable() async -> Bool {
        let result = await fetch(HealthProbe.self, path: "/health", requiresAuth: false)
        return result.mode == .observed
    }

    // MARK: - Core fetch (GET)

    public func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        timeout: TimeInterval = 15,
        requiresAuth: Bool = true
    ) async -> Truthful<T> {
        if requiresAuth {
            let authReady = await ensureAuth()
            guard authReady else {
                let authError = authBootstrapError ?? "Auth bootstrap failed"
                print("[BeagleClient] [\(type)] GET \(path) auth blocked: \(authError)")
                return .staleError(authError)
            }
        }
        var lastError = "beagle-server unreachable"
        let debugLabel = "[\(type)] GET \(path)"
        print("[BeagleClient] \(debugLabel) starting...")

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else {
                print("[BeagleClient] \(debugLabel) failed to construct URL with base: \(base)")
                continue
            }
            var responseData: Data?
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = timeout
                applyAuth(&request)
                print("[BeagleClient] \(debugLabel) requesting: \(url)")
                let (data, response) = try await session.data(for: request)
                responseData = data

                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                    lastError = formatError(statusCode: statusCode, data: data, fallback: "HTTP \(statusCode)")
                    print("[BeagleClient] \(debugLabel) ❌ HTTP \(statusCode)")
                    print("[BeagleClient] Response body: \(bodyText.prefix(300))")
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                print("[BeagleClient] \(debugLabel) ✅ success")
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                let bodyText: String
                if let data = responseData {
                    bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                } else {
                    bodyText = "<no response data>"
                }
                print("[BeagleClient] \(debugLabel) ❌ error: \(error.localizedDescription)")
                print("[BeagleClient] Response body: \(bodyText.prefix(300))")
                continue
            }
        }
        print("[BeagleClient] \(debugLabel) all URLs failed: \(lastError)")
        return .staleError(lastError)
    }

    // MARK: - Core POST

    public func post<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: [String: any Sendable] = [:],
        timeout: TimeInterval = 120,
        requiresAuth: Bool = true
    ) async -> Truthful<T> {
        if requiresAuth {
            let authReady = await ensureAuth()
            guard authReady else {
                let authError = authBootstrapError ?? "Auth bootstrap failed"
                print("[BeagleClient] [\(type)] POST \(path) auth blocked: \(authError)")
                return .staleError(authError)
            }
        }
        var lastError = "beagle-server unreachable"
        let debugLabel = "[\(type)] POST \(path)"
        print("[BeagleClient] \(debugLabel) starting...")

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else {
                print("[BeagleClient] \(debugLabel) failed to construct URL with base: \(base)")
                continue
            }
            var responseData: Data?
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout
                applyAuth(&request)
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                print("[BeagleClient] \(debugLabel) requesting: \(url)")
                let (data, response) = try await session.data(for: request)
                responseData = data

                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                    lastError = formatError(statusCode: statusCode, data: data, fallback: "HTTP \(statusCode)")
                    print("[BeagleClient] \(debugLabel) ❌ HTTP \(statusCode)")
                    print("[BeagleClient] Response body: \(bodyText.prefix(300))")
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                print("[BeagleClient] \(debugLabel) ✅ success")
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                let bodyText: String
                if let data = responseData {
                    bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                } else {
                    bodyText = "<no response data>"
                }
                print("[BeagleClient] \(debugLabel) ❌ error: \(error.localizedDescription)")
                print("[BeagleClient] Response body: \(bodyText.prefix(300))")
                continue
            }
        }
        print("[BeagleClient] \(debugLabel) all URLs failed: \(lastError)")
        return .staleError(lastError)
    }

    public func postEncoded<T: Decodable & Sendable, Body: Encodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: Body,
        timeout: TimeInterval = 120,
        requiresAuth: Bool = true
    ) async -> Truthful<T> {
        if requiresAuth {
            let authReady = await ensureAuth()
            guard authReady else {
                let authError = authBootstrapError ?? "Auth bootstrap failed"
                print("[BeagleClient] [\(type)] POST \(path) auth blocked: \(authError)")
                return .staleError(authError)
            }
        }

        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            return .staleError("Failed to encode request: \(error.localizedDescription)")
        }

        var lastError = "beagle-server unreachable"
        let debugLabel = "[\(type)] POST \(path)"
        print("[BeagleClient] \(debugLabel) starting...")

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else {
                print("[BeagleClient] \(debugLabel) failed to construct URL with base: \(base)")
                continue
            }
            var responseData: Data?
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout
                applyAuth(&request)
                request.httpBody = payload

                print("[BeagleClient] \(debugLabel) requesting: \(url)")
                let (data, response) = try await session.data(for: request)
                responseData = data

                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                    lastError = formatError(statusCode: statusCode, data: data, fallback: "HTTP \(statusCode)")
                    print("[BeagleClient] \(debugLabel) ❌ HTTP \(statusCode)")
                    print("[BeagleClient] Response body: \(bodyText.prefix(300))")
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                print("[BeagleClient] \(debugLabel) ✅ success")
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                let bodyText: String
                if let data = responseData {
                    bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                } else {
                    bodyText = "<no response data>"
                }
                print("[BeagleClient] \(debugLabel) ❌ error: \(error.localizedDescription)")
                print("[BeagleClient] Response body: \(bodyText.prefix(300))")
                continue
            }
        }
        print("[BeagleClient] \(debugLabel) all URLs failed: \(lastError)")
        return .staleError(lastError)
    }

    /// Fetch auth token from cockpit bridge (zero hardcode).
    /// Re-fetches when token is older than 4 minutes (server TTL is 5min).
    private var tokenFetchedAt: Date?
    private let tokenRefreshInterval: TimeInterval = 4 * 60 // 4 minutes

    public func ensureAuth() async -> Bool {
        if tokenFetched,
           let fetchedAt = tokenFetchedAt,
           Date().timeIntervalSince(fetchedAt) < tokenRefreshInterval {
            return true
        }
        print("[BeagleClient] ensureAuth starting...")
        // GET /api/auth/beagle-token from the public Cockpit boundary first,
        // with older private paths left as fallback during transition.
        let cockpitURLs = BeagleEndpoints.cockpitURLs
        var lastFailure = "Auth bridge unreachable"
        for base in cockpitURLs {
            guard let url = URL(string: "/api/auth/beagle-token", relativeTo: base) else {
                print("[BeagleClient] ensureAuth failed to construct URL")
                lastFailure = "Auth bridge URL construction failed"
                continue
            }
            do {
                var request = URLRequest(url: url)
                BeagleEndpoints.applyCockpitAuth(to: &request)
                print("[BeagleClient] ensureAuth requesting: \(url)")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastFailure = formatError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "Auth bridge HTTP \(statusCode)"
                    )
                    print("[BeagleClient] ensureAuth ❌ HTTP \(statusCode)")
                    continue
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let rawToken = json["token"] as? String
                    let authHeaderValue = json["auth_header_value"] as? String
                    let consumerHeaderName = json["consumer_header_name"] as? String
                    let consumerHeaderValue = json["consumer_header_value"] as? String

                    if let rawToken, !rawToken.isEmpty {
                        consumerToken = rawToken
                    } else if
                        let authHeaderValue,
                        authHeaderValue.hasPrefix("Bearer "),
                        authHeaderValue.count > "Bearer ".count
                    {
                        consumerToken = String(authHeaderValue.dropFirst("Bearer ".count))
                    } else {
                        consumerToken = nil
                    }

                    if consumerHeaderName == "X-Beagle-Consumer", let consumerHeaderValue, !consumerHeaderValue.isEmpty {
                        consumerId = consumerHeaderValue
                    } else {
                        consumerId = json["consumer"] as? String ?? "beagle-operator"
                    }
                    guard
                        let consumerToken,
                        !consumerToken.isEmpty,
                        let consumerId,
                        !consumerId.isEmpty
                    else {
                        lastFailure = "Auth bridge returned incomplete credentials"
                        print("[BeagleClient] ensureAuth ❌ incomplete credentials")
                        continue
                    }
                    print("[BeagleClient] ensureAuth ✅ token acquired: \(consumerId)")
                    // Update base URL if provided
                    let beagleURLString = (json["beagle_url"] as? String) ?? (json["beagleServerUrl"] as? String)
                    if let urlStr = beagleURLString, let serverUrl = URL(string: urlStr),
                       !baseURLs.contains(serverUrl) {
                        print("[BeagleClient] ensureAuth updating base URL: \(serverUrl)")
                        baseURLs.insert(serverUrl, at: 0)
                    }
                    tokenFetched = true
                    tokenFetchedAt = Date()
                    authBootstrapError = nil
                    return true
                }
                lastFailure = "Auth bridge returned malformed JSON"
            } catch {
                lastFailure = error.localizedDescription
                print("[BeagleClient] ensureAuth ❌ error: \(error.localizedDescription)")
                continue
            }
        }
        authBootstrapError = lastFailure
        print("[BeagleClient] ensureAuth failed: \(lastFailure)")
        return false
    }

    /// Returns the current bearer token after ensuring auth, for use by first-party
    /// WebSocket clients (e.g. MoshiSessionManager) that cannot use applyAuth directly.
    /// Falls back to empty string if auth is unavailable.
    public func resolvedBearerToken() async -> String {
        if !tokenFetched { _ = await ensureAuth() }
        return consumerToken ?? ""
    }

    public func authBootstrapStatus() -> Truthful<String> {
        if tokenFetched {
            return .observed(consumerId ?? "token ready", source: "cockpit-auth-bridge")
        }
        if let authBootstrapError {
            return .staleError(authBootstrapError, source: "cockpit-auth-bridge")
        }
        return .declared("auth not attempted", source: "cockpit-auth-bridge")
    }

    internal func applyAuth(_ request: inout URLRequest) {
        if let consumerId {
            request.setValue(consumerId, forHTTPHeaderField: "X-Beagle-Consumer")
            print("[BeagleClient] applyAuth: X-Beagle-Consumer = \(consumerId)")
        } else {
            print("[BeagleClient] applyAuth: ⚠️  consumerId is nil")
        }
        if let consumerToken {
            request.setValue("Bearer \(consumerToken)", forHTTPHeaderField: "Authorization")
            print("[BeagleClient] applyAuth: Authorization header set (redacted)")
        } else {
            print("[BeagleClient] applyAuth: ⚠️  consumerToken is nil")
        }
    }

    internal func formatError(statusCode: Int, data: Data, fallback: String) -> String {
        if let payload = try? decoder.decode(BeagleBackendErrorPayload.self, from: data) {
            return payload.message(statusCode: statusCode, fallback: fallback)
        }

        let bodyText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bodyText, !bodyText.isEmpty {
            return "HTTP \(statusCode) · \(bodyText)"
        }

        return fallback
    }

    internal func formatMobileError(statusCode: Int, data: Data, fallback: String) -> String {
        if let payload = try? decoder.decode(MobileEnvelope<ChatResponse>.self, from: data) {
            var parts = ["HTTP \(statusCode)"]
            if let message = payload.error?.message, !message.isEmpty {
                parts.append(message)
            } else {
                parts.append(fallback)
            }
            if let reason = payload.error?.reason, !reason.isEmpty {
                parts.append(reason)
            }
            if let code = payload.error?.code, !code.isEmpty {
                parts.append("code=\(code)")
            }
            if let truthMode = payload.meta?.truthMode, !truthMode.isEmpty {
                parts.append("truth=\(truthMode)")
            }
            if let requestId = payload.meta?.requestId, !requestId.isEmpty {
                parts.append("requestId=\(requestId)")
            }
            return parts.joined(separator: " · ")
        }

        let bodyText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bodyText, !bodyText.isEmpty {
            return "HTTP \(statusCode) · \(bodyText)"
        }

        return fallback
    }

}

struct BeagleBackendErrorPayload: Decodable {
    let error: String?
    let reason: String?
    let truthMode: String?
    let requestId: String?
    let caller: String?
    let via: String?
    let proxiedPath: String?

    enum CodingKeys: String, CodingKey {
        case error
        case reason
        case truthMode
        case requestId
        case caller
        case via
        case proxiedPath = "proxied_path"
    }

    func message(statusCode: Int, fallback: String) -> String {
        var parts = ["HTTP \(statusCode)"]

        if let error, !error.isEmpty {
            parts.append(error)
        } else {
            parts.append(fallback)
        }
        if let reason, !reason.isEmpty {
            parts.append(reason)
        }
        if let truthMode, !truthMode.isEmpty {
            parts.append("truth=\(truthMode)")
        }
        if let requestId, !requestId.isEmpty {
            parts.append("requestId=\(requestId)")
        }
        if let caller, !caller.isEmpty {
            parts.append("caller=\(caller)")
        }
        if let via, !via.isEmpty {
            parts.append("via=\(via)")
        }
        if let proxiedPath, !proxiedPath.isEmpty {
            parts.append("path=\(proxiedPath)")
        }

        return parts.joined(separator: " · ")
    }
}

// MARK: - Triad streaming (SSE)

/// One event from the streaming debate endpoint.
public enum TriadStreamEvent: Sendable {
    /// Incremental text from an agent (agent name when the frame identifies one).
    case delta(agent: String?, text: String)
    /// Final consolidated review; the stream ends after this.
    case final(TriadResult)
    /// Stream-level failure (auth/network/unreachable).
    case error(String)
}

/// A single SSE delta frame from `/dev/debate?stream=true`.
struct TriadStreamDelta: Decodable, Sendable {
    let agent: String?
    let text: String?
    let content: String?
}

// MARK: - Wave 2: capture/refine (real LLM thought refinement)

public struct ThoughtRefineResponse: Codable, Sendable {
    public let refinedText: String
    public let model: String?
    public let tier: String?
    enum CodingKeys: String, CodingKey {
        case refinedText = "refined_text"
        case model
        case tier
    }
}

struct ThoughtRefineRequest: Encodable, Sendable {
    let rawText: String
    let projectSlug: String?
    let sourceSurface: String?
    /// BCP-47 hint (e.g. "pt-BR") so refinement keeps the user's language.
    let languageHint: String?
    /// Explicit flag instructing the backend never to translate the refined text.
    let preserveLanguage: Bool
    enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
        case projectSlug = "project_slug"
        case sourceSurface = "source_surface"
        case languageHint = "language_hint"
        case preserveLanguage = "preserve_language"
    }
}
