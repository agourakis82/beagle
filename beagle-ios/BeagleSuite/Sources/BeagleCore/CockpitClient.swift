//
//  CockpitClient.swift
//  BeagleCore
//
//  Truth-aware HTTP client for the cockpit API.
//  Uses URLSession with Swift 6 async/await.
//  Returns Truthful<T> wrappers preserving epistemic metadata.
//
//  Resolves multiple URLs in preference order
//  (public HTTPS edge → tailnet → internal VIP → cluster service DNS)
//  so the same app works on the public mobile gateway first, while still
//  preserving the old private fallbacks during transition.
//

import Foundation

public actor CockpitClient {

    public static let shared = CockpitClient()

    internal func derivedProjectFamily(slug: String, override: ProjectFamily?) -> ProjectFamily {
        override ?? .fromProjectSlug(slug)
    }

    internal func derivedPublicationScope(
        slug: String,
        projectFamily: ProjectFamily?,
        override: PublicationScope?
    ) -> PublicationScope {
        if let override { return override }
        return .forProjectFamily(derivedProjectFamily(slug: slug, override: projectFamily))
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// URL resolution order — tried in sequence until one responds.
    /// Override via `init(session:baseURLs:)` or `configure(baseURLs:)` from the app/tests.
    private var baseURLs: [URL] = BeagleEndpoints.cockpitURLs

    public init(session: URLSession? = nil, baseURLs: [URL]? = nil) {
        if let baseURLs {
            self.baseURLs = baseURLs
        }
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 12  // Leave room for edge or tailnet fallback
            config.timeoutIntervalForResource = 30
            config.waitsForConnectivity = true
            config.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": "BeagleCockpit/1.0 (iOS/macOS native)"
            ]
            self.session = URLSession(configuration: config)
        }
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    internal static func seg(_ value: String) -> String {
        BeagleEndpoints.pathComponent(value)
    }

    /// Configure the URL resolution order.
    public func configure(baseURLs: [URL]) {
        self.baseURLs = baseURLs
    }

    // MARK: - Core fetch

    /// Fetch a typed response with truth-aware error handling.
    /// Tries each base URL in order; returns the first success.
    public func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        timeout: TimeInterval = 12
    ) async -> Truthful<T> {
        var lastError: String = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.timeoutInterval = timeout
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = "invalid response"
                    continue
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    lastError = formatError(
                        statusCode: httpResponse.statusCode,
                        data: data,
                        fallback: "HTTP \(httpResponse.statusCode)"
                    )
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }

        return .staleError(lastError)
    }

    public func fetchMobile<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        timeout: TimeInterval = 12
    ) async -> Truthful<T> {
        var lastError: String = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.timeoutInterval = timeout
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = "invalid response"
                    continue
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    lastError = formatError(
                        statusCode: httpResponse.statusCode,
                        data: data,
                        fallback: "HTTP \(httpResponse.statusCode)"
                    )
                    continue
                }

                let envelope = try decoder.decode(MobileEnvelope<T>.self, from: data)
                guard envelope.ok != false else {
                    lastError = envelope.error?.message ?? "mobile gateway returned ok=false"
                    continue
                }
                guard let payload = envelope.data else {
                    lastError = envelope.error?.message ?? "mobile gateway returned no data"
                    continue
                }

                let mode = TruthMode(rawValue: envelope.meta?.truthMode ?? "") ?? .observed
                return Truthful(
                    value: payload,
                    mode: mode,
                    observedAt: .now,
                    source: url.host,
                    error: nil
                )
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }

        return .staleError(lastError)
    }

    // MARK: - POST helper

    public func post<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: [String: any Sendable] = [:],
        timeout: TimeInterval = 15
    ) async -> Truthful<T> {
        var lastError = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout

                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = formatError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "HTTP \(statusCode)"
                    )
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        return .staleError(lastError)
    }

    public func postMobile<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: [String: any Sendable] = [:],
        timeout: TimeInterval = 15
    ) async -> Truthful<T> {
        var lastError = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = formatError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "HTTP \(statusCode)"
                    )
                    continue
                }

                let envelope = try decoder.decode(MobileEnvelope<T>.self, from: data)
                guard envelope.ok != false else {
                    lastError = envelope.error?.message ?? "mobile gateway returned ok=false"
                    continue
                }
                guard let payload = envelope.data else {
                    lastError = envelope.error?.message ?? "mobile gateway returned no data"
                    continue
                }

                let mode = TruthMode(rawValue: envelope.meta?.truthMode ?? "") ?? .observed
                return Truthful(
                    value: payload,
                    mode: mode,
                    observedAt: .now,
                    source: url.host,
                    error: nil
                )
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        return .staleError(lastError)
    }

    public func postEncoded<T: Decodable & Sendable, Body: Encodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: Body,
        timeout: TimeInterval = 15
    ) async -> Truthful<T> {
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            return .staleError("Failed to encode request: \(error.localizedDescription)")
        }

        var lastError = "no base URL reachable"
        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout
                request.httpBody = payload

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = formatError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "HTTP \(statusCode)"
                    )
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        return .staleError(lastError)
    }

    public func postMobileEncoded<T: Decodable & Sendable, Body: Encodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: Body,
        timeout: TimeInterval = 15
    ) async -> Truthful<T> {
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            return .staleError("Failed to encode request: \(error.localizedDescription)")
        }

        var lastError = "no base URL reachable"
        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout
                request.httpBody = payload

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = formatError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "HTTP \(statusCode)"
                    )
                    continue
                }

                if let envelope = try? decoder.decode(MobileEnvelope<T>.self, from: data),
                   envelope.ok != false, let unwrapped = envelope.data {
                    let mode = TruthMode(rawValue: envelope.meta?.truthMode ?? "") ?? .observed
                    return Truthful(
                        value: unwrapped,
                        mode: mode,
                        observedAt: .now,
                        source: url.host,
                        error: nil
                    )
                }

                let decoded = try decoder.decode(T.self, from: data)
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        return .staleError(lastError)
    }

    public func deleteMobile<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: [String: any Sendable] = [:]
    ) async -> Truthful<T> {
        var lastError = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.httpMethod = "DELETE"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 15
                if !body.isEmpty {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                }

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = formatError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "HTTP \(statusCode)"
                    )
                    continue
                }

                let envelope = try decoder.decode(MobileEnvelope<T>.self, from: data)
                guard envelope.ok != false else {
                    lastError = envelope.error?.message ?? "mobile gateway returned ok=false"
                    continue
                }
                guard let payload = envelope.data else {
                    lastError = envelope.error?.message ?? "mobile gateway returned no data"
                    continue
                }

                let mode = TruthMode(rawValue: envelope.meta?.truthMode ?? "") ?? .observed
                return Truthful(
                    value: payload,
                    mode: mode,
                    observedAt: .now,
                    source: url.host,
                    error: nil
                )
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        return .staleError(lastError)
    }

    private func formatError(statusCode: Int, data: Data, fallback: String) -> String {
        if let payload = try? decoder.decode(MobileEnvelope<EmptyMobilePayload>.self, from: data) {
            var parts = ["HTTP \(statusCode)"]
            parts.append(payload.error?.message ?? fallback)
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

        if let payload = try? decoder.decode(CockpitBackendErrorPayload.self, from: data) {
            return payload.message(statusCode: statusCode, fallback: fallback)
        }

        let bodyText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bodyText, !bodyText.isEmpty {
            return "HTTP \(statusCode) · \(bodyText)"
        }

        return fallback
    }
}

struct CockpitBackendErrorPayload: Decodable {
    let error: String?
    let reason: String?
    let truthMode: String?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case error
        case reason
        case truthMode
        case requestId
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

        return parts.joined(separator: " · ")
    }
}

private struct EmptyMobilePayload: Decodable, Sendable {}
