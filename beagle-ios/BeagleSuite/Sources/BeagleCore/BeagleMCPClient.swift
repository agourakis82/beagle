//
//  BeagleMCPClient.swift
//  BeagleCore
//
//  Lightweight Streamable HTTP MCP client for first-party Beagle surfaces.
//  Typed core REST remains the app's primary data path; this client lets the
//  app inspect the public MCP nervous system and make optional audited calls.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum BeagleMCPError: Error, LocalizedError, Sendable {
    case invalidEndpoint
    case missingAccessToken
    case httpStatus(Int, String)
    case rpc(String)
    case missingResult
    case unsupportedSSE

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid MCP endpoint."
        case .missingAccessToken:
            return "Missing MCP OAuth access token."
        case .httpStatus(let status, let body):
            return "MCP HTTP \(status): \(body)"
        case .rpc(let message):
            return "MCP JSON-RPC error: \(message)"
        case .missingResult:
            return "MCP response did not include a result."
        case .unsupportedSSE:
            return "MCP response used SSE without a JSON data frame."
        }
    }
}

public struct MCPToolSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let title: String?
    public let description: String?
    public let inputSchema: ExocortexJSONValue?
    public let annotations: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case description
        case inputSchema = "inputSchema"
        case annotations
    }
}

public struct MCPToolListResult: Codable, Equatable, Sendable {
    public let tools: [MCPToolSummary]
}

public struct MCPResourceSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String { uri }
    public let uri: String
    public let name: String?
    public let title: String?
    public let description: String?
    public let mimeType: String?

    enum CodingKeys: String, CodingKey {
        case uri
        case name
        case title
        case description
        case mimeType = "mimeType"
    }
}

public struct MCPResourceListResult: Codable, Equatable, Sendable {
    public let resources: [MCPResourceSummary]
}

public struct MCPCallToolResult: Codable, Equatable, Sendable {
    public let content: [ExocortexJSONValue]?
    public let structuredContent: ExocortexJSONValue?
    public let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case content
        case structuredContent = "structuredContent"
        case isError = "isError"
    }
}

public struct BeagleMCPPKCERequest: Equatable, Sendable {
    public let authorizationURL: URL
    public let codeVerifier: String
    public let state: String
}

private struct MCPJSONRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: ExocortexJSONValue?
}

private struct MCPJSONRPCError: Decodable {
    let code: Int
    let message: String
}

private struct MCPJSONRPCResponse: Decodable {
    let result: ExocortexJSONValue?
    let error: MCPJSONRPCError?
}

public actor BeagleMCPClient {
    public static let shared = BeagleMCPClient()

    public nonisolated let endpoint: URL
    public nonisolated var endpointHost: String? { endpoint.host }

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var accessToken: String?
    private var nextId = 1

    public init(
        endpoint: URL = URL(string: "https://mcp.agourakis.com/mcp")!,
        accessToken: String? = nil
    ) {
        self.endpoint = endpoint
        self.accessToken = accessToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "Accept": "application/json, text/event-stream",
            "User-Agent": "BeagleAppleMCP/1.0"
        ]
        self.session = URLSession(configuration: config)
    }

    public func configure(accessToken: String?) {
        self.accessToken = accessToken
    }

    public nonisolated static func auth0PKCEAuthorizationURL(
        domain: String,
        clientId: String,
        redirectURI: String,
        audience: String = "https://mcp.agourakis.com/mcp",
        scopes: [String] = [
            "openid",
            "profile",
            "email",
            "offline_access",
            "exocortex:read",
            "memory:write",
            "chronoself:write",
            "research:run",
            "agent:start"
        ],
        state: String = UUID().uuidString
    ) -> BeagleMCPPKCERequest? {
        let verifier = randomCodeVerifier()
        let challenge = codeChallengeS256(verifier)
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/authorize"
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "audience", value: audience),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else { return nil }
        return BeagleMCPPKCERequest(authorizationURL: url, codeVerifier: verifier, state: state)
    }

    @discardableResult
    public func initialize(
        clientName: String = "Beagle Apple App",
        clientVersion: String = "1.0"
    ) async throws -> ExocortexJSONValue {
        try await rpc(
            method: "initialize",
            params: .object([
                "protocolVersion": .string("2025-11-25"),
                "clientInfo": .object([
                    "name": .string(clientName),
                    "version": .string(clientVersion)
                ]),
                "capabilities": .object([:])
            ])
        )
    }

    public func listTools() async throws -> MCPToolListResult {
        let result = try await rpc(method: "tools/list", params: .object([:]))
        return try decodeResult(MCPToolListResult.self, from: result)
    }

    public func listResources() async throws -> MCPResourceListResult {
        let result = try await rpc(method: "resources/list", params: .object([:]))
        return try decodeResult(MCPResourceListResult.self, from: result)
    }

    public func callTool(
        name: String,
        arguments: ExocortexJSONValue = .object([:])
    ) async throws -> MCPCallToolResult {
        let result = try await rpc(
            method: "tools/call",
            params: .object([
                "name": .string(name),
                "arguments": arguments
            ])
        )
        return try decodeResult(MCPCallToolResult.self, from: result)
    }

    private func rpc(method: String, params: ExocortexJSONValue?) async throws -> ExocortexJSONValue {
        let id = nextId
        nextId += 1
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(MCPJSONRPCRequest(id: id, method: method, params: params))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BeagleMCPError.invalidEndpoint
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw BeagleMCPError.httpStatus(http.statusCode, body)
        }

        let payload = try jsonPayload(from: data, contentType: http.value(forHTTPHeaderField: "content-type"))
        let decoded = try decoder.decode(MCPJSONRPCResponse.self, from: payload)
        if let error = decoded.error {
            throw BeagleMCPError.rpc("\(error.code): \(error.message)")
        }
        guard let result = decoded.result else {
            throw BeagleMCPError.missingResult
        }
        return result
    }

    private func jsonPayload(from data: Data, contentType: String?) throws -> Data {
        guard contentType?.contains("text/event-stream") == true else {
            return data
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw BeagleMCPError.unsupportedSSE
        }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { continue }
            if let data = payload.data(using: .utf8) {
                return data
            }
        }
        throw BeagleMCPError.unsupportedSSE
    }

    private func decodeResult<T: Decodable>(_ type: T.Type, from value: ExocortexJSONValue) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(type, from: data)
    }

    private nonisolated static func randomCodeVerifier() -> String {
        let raw = "\(UUID().uuidString)\(UUID().uuidString)\(UUID().uuidString)"
        return raw
            .replacingOccurrences(of: "-", with: "")
            .prefix(96)
            .description
    }

    private nonisolated static func codeChallengeS256(_ verifier: String) -> String {
        let data = Data(verifier.utf8)
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncodedString()
        #else
        return verifier
        #endif
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
