import Foundation
import SwiftData

/// Durable queue of offline personal turns awaiting sync to the memory spine.
/// Online turns are ingested server-side during the chat; this carries only the offline ones.
@MainActor
public final class OutboxStore {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    /// Sem `assistantText` isto é uma NOTA AVULSA: ele disse algo e ninguém respondeu.
    /// A guarda antiga exigia os dois lados e descartava a nota em silêncio, aqui, antes
    /// de qualquer rede — o mesmo contrato simétrico que o servidor deixou de exigir.
    /// Nota avulsa é justamente o formato de um auto-relato ("peito apertado", às três
    /// da manhã), que é o substrato da corroboração multimodal.
    public func enqueue(sessionId: String, userText: String, assistantText: String = "",
                        clientTime: String, timezone: String, spoken: Bool = false) {
        let u = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return }
        context.insert(PendingIngest(sessionId: sessionId, userText: u, assistantText: a,
                                     clientTime: clientTime, timezone: timezone,
                                     spoken: spoken ? true : nil))
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
/// `assistantText` é opcional e OMITIDO quando nulo (o Encodable sintetizado usa
/// `encodeIfPresent`): mandar string vazia faria o servidor gravar um turno fantasma
/// do companion no histórico — a voz da máquina entrando onde não deve.
public struct IngestTurnRequest: Encodable, Sendable {
    public let session_id: String
    public let userText: String
    public let assistantText: String?
    public let clientTime: String
    public let timezone: String
    /// Ele FALOU este turno, em vez de digitar. Booleano seco: diz que falou, e nada sobre
    /// COMO — sem ritmo, sem pausa, sem áudio. Omitido (não `false`) quando digitou, porque
    /// a chave só deve existir quando há o que afirmar.
    ///
    /// ⚠️ Falado e digitado são o MESMO canal — auto-relato — em duas formas. Isto serve
    /// para auditar e estratificar, nunca como corroboração: a independência vem do corpo.
    public let spoken: Bool?
    public init(session_id: String, userText: String, assistantText: String?, clientTime: String,
                timezone: String, spoken: Bool? = nil) {
        self.session_id = session_id
        self.userText = userText
        self.assistantText = assistantText
        self.clientTime = clientTime
        self.timezone = timezone
        self.spoken = spoken
    }
}

/// The cockpit acks `{ status: "accepted" }` (unwrapped from the {data} envelope by postEncoded).
public struct IngestTurnResult: Decodable, Sendable {
    public let status: String?
}

