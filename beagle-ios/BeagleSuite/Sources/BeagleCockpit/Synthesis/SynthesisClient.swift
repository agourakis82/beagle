// SynthesisClient.swift — streams POST /api/mobile/v1/synthesize as SSE chunks.
// Reuses BeagleClient's base-URL resolution + cockpit token. Standalone from chat:
// no ConversationStore, no persistence. Part of the deliberate synthesis surface.
import Foundation
import BeagleCore

struct SynthesisClient {
    /// Stream the synthesis. `topic` empty → server falls back to recent mode.
    func stream(topic: String) -> AsyncThrowingStream<SSEChunk, Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                var body: [String: Any] = [:]
                let t = topic.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { body["topic"] = t }
                let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
                var lastError: Error?
                for base in await CockpitClient.shared.mobileBaseURLs {
                    guard let url = URL(string: "/api/mobile/v1/synthesize", relativeTo: base) else { continue }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.setValue(BeagleClient.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                    req.httpBody = payload
                    req.timeoutInterval = 60
                    do {
                        let (bytes, response) = try await URLSession.shared.bytes(for: req)
                        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                            lastError = URLError(.badServerResponse); continue
                        }
                        for try await line in bytes.lines {
                            if Task.isCancelled { continuation.finish(); return }
                            if let chunk = SynthesisSSEParser.parse(line: line) {
                                continuation.yield(chunk)
                                if case .done = chunk { continuation.finish(); return }
                            }
                        }
                        continuation.finish(); return
                    } catch {
                        lastError = error; continue
                    }
                }
                continuation.finish(throwing: lastError ?? URLError(.cannotConnectToHost))
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }
}
