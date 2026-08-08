import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Observation

/// Polls `GET /api/mobile/v1/oficina`. Cheap by design: the cockpit already holds the reading,
/// so this is one small JSON fetch, not a build trigger. Nothing here can start a build — the
/// endpoint is read-only on the server side too.
@MainActor
@Observable
public final class OficinaClient {
    public private(set) var state: OficinaState = .empty
    public private(set) var loading = false
    /// Set when the fetch itself failed (as opposed to the server reporting a stale sweep).
    public private(set) var fetchError: String?

    private let endpoint: FleetEndpoint
    private let session: URLSession
    private var timer: Task<Void, Never>?

    public init(endpoint: FleetEndpoint = FleetEndpoint()) {
        self.endpoint = endpoint
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        #if !canImport(FoundationNetworking)
        // Apple-only: wait for the network instead of failing instantly when the phone is
        // between radios. (On swift-corelibs this property is read-only.)
        cfg.waitsForConnectivity = true
        #endif
        self.session = URLSession(configuration: cfg)
    }

    /// CI verdicts do not change by the second; a slow cadence keeps this honest AND cheap
    /// (perf is a contract: no battery burn for information that moves in minutes).
    public func start(intervalSeconds: UInt64 = 60) {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }

    public func stop() { timer?.cancel(); timer = nil }

    public func refresh() async {
        guard CockpitToken.resolve() != nil else {
            fetchError = CockpitToken.missingReason; return
        }
        guard var req = endpoint.oficinaRequest() else {
            fetchError = "endpoint inválido"; return
        }
        req.httpMethod = "GET"
        loading = true
        defer { loading = false }
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                // Actionable, not a bare code.
                fetchError = http.statusCode == 401
                    ? "Token do cockpit recusado (401). Refazer login da tailnet?"
                    : "O cockpit respondeu \(http.statusCode)."
                return
            }
            guard
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let decoded = OficinaState(envelope: obj)
            else {
                fetchError = "Resposta do cockpit ilegível."
                return
            }
            fetchError = nil
            state = decoded
        } catch {
            // Keep the previous reading: stale-but-labelled beats an empty panel.
            fetchError = "Cockpit não alcançável. Tailnet ativa? (\(error.localizedDescription))"
        }
    }
}
