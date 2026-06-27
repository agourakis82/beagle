import Foundation
import SwiftData

/// Durable queue of offline personal turns awaiting sync to the memory spine.
/// Online turns are ingested server-side during the chat; this carries only the offline ones.
@MainActor
public final class OutboxStore {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func enqueue(sessionId: String, userText: String, assistantText: String, clientTime: String, timezone: String) {
        let u = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !a.isEmpty else { return }
        context.insert(PendingIngest(sessionId: sessionId, userText: u, assistantText: a,
                                     clientTime: clientTime, timezone: timezone))
        try? context.save()
    }

    public func pending() -> [PendingIngest] {
        let descriptor = FetchDescriptor<PendingIngest>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func delete(_ item: PendingIngest) {
        context.delete(item)
        try? context.save()
    }
}

/// Body for POST /api/mobile/v1/ingest. Field names match what the cockpit handler reads
/// (session_id, userText, assistantText, clientTime, timezone).
public struct IngestTurnRequest: Encodable, Sendable {
    public let session_id: String
    public let userText: String
    public let assistantText: String
    public let clientTime: String
    public let timezone: String
    public init(session_id: String, userText: String, assistantText: String, clientTime: String, timezone: String) {
        self.session_id = session_id
        self.userText = userText
        self.assistantText = assistantText
        self.clientTime = clientTime
        self.timezone = timezone
    }
}

/// The cockpit acks `{ status: "accepted" }` (unwrapped from the {data} envelope by postEncoded).
public struct IngestTurnResult: Decodable, Sendable {
    public let status: String?
}

