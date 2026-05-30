import Foundation

@MainActor
final class SounioWorkspaceStore: ObservableObject {
    @Published private(set) var snapshot: SounioWorkspaceSnapshot = .disconnected
    @Published private(set) var isRefreshing = false
    @Published var endpointText: String

    init() {
        let env = ProcessInfo.processInfo.environment["BEAGLE_COCKPIT_URL"]
        self.endpointText = env?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? env!
            : "http://127.0.0.1:4370"
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let url = try goWorkNowURL()
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }

            let envelope = try JSONDecoder().decode(SounioWorkspaceEnvelope.self, from: data)
            snapshot = SounioWorkspaceSnapshot(envelope: envelope)
        } catch {
            var stale = snapshot
            stale.source = snapshot.source == .live ? .stale : .disconnected
            stale.error = error.localizedDescription
            snapshot = stale
        }
    }

    private func goWorkNowURL() throws -> URL {
        let trimmed = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        let full = base.hasSuffix("/api/projects/sounio/go-work-now?depth=deep")
            ? base
            : "\(base)/api/projects/sounio/go-work-now?depth=deep"
        guard let url = URL(string: full) else {
            throw URLError(.badURL)
        }
        return url
    }
}
