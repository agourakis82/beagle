//
//  BeagleEndpoints.swift
//  BeagleCore
//
//  Single source of truth for Beagle / Cockpit / Physiome / MCP base URLs,
//  path encoding, authentication header injection, and shared connection state.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Canonical endpoint configuration and HTTP auth helpers shared across all Beagle clients.
public enum BeagleEndpoints {

    /// Header name used by the Cockpit mobile boundary (`x-cockpit-token`).
    public static let cockpitTokenHeader = "x-cockpit-token"

    /// Cockpit gateway fallback chain (public HTTPS edge → Tailnet FQDN → Tailnet IP → in-cluster DNS).
    public static let cockpitURLs: [URL] = [
        URL(string: "https://beagle.chiuratto.ai")!,
        URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,
        URL(string: "http://100.107.208.198")!,
        URL(string: "http://project-cockpit.beagle.svc.cluster.local")!
    ]

    /// `beagle-server` fallback chain (public HTTPS gateway → Tailnet → in-cluster pod network).
    public static let beagleServerURLs: [URL] = [
        URL(string: "https://beagle.chiuratto.ai")!,
        URL(string: "http://beagle-core.tail21cbc4.ts.net")!,
        URL(string: "http://beagle-core.beagle.svc.cluster.local:8080")!
    ]

    /// Physiome ingest/telemetry fallback chain (public HTTPS gateway → in-cluster service).
    public static let physiomeURLs: [URL] = [
        URL(string: "https://beagle.chiuratto.ai")!,
        URL(string: "http://physiome-ingest.beagle.svc.cluster.local:8080")!
    ]

    /// Streamable HTTP MCP endpoint for first-party Beagle surfaces.
    public static let mcpEndpoint: URL = URL(string: "https://mcp.agourakis.com/mcp")!

    /// Percent-encodes a single URL path segment (e.g. project slug, agent kind, resource ID).
    public static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Attaches the resolved cockpit token (`x-cockpit-token`) when available.
    /// Resolves across explicit override → bundle `Secrets.plist` → `BEAGLE_COCKPIT_TOKEN` → `~/.beagle/cockpit-token`.
    public static func applyCockpitAuth(to request: inout URLRequest, explicitToken: String? = nil) {
        if let token = CockpitToken.resolve(explicit: explicitToken), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: cockpitTokenHeader)
        }
    }
}

/// Shared lifecycle contract implemented by transport connection state enums
/// (`WebSocketState`, `PTYClient.State`, `FleetStateStore.Link`, `SessionStore.Link`).
public protocol ConnectionStateRepresentable: Sendable, Equatable {
    var isConnected: Bool { get }
    var isConnecting: Bool { get }
    var failureMessage: String? { get }
    var truthMode: TruthMode { get }
}
