//
//  ConversationStore.swift
//  BeagleCore
//
//  Observable conversation model for chat-style interactions.
//  Routes between on-device MLX (Tier 0.5) and cloud HERMES (Tier 2+).
//  On-device is preferred when model is loaded; cloud is fallback.
//
//  Cohesive extensions live in `Conversation/`:
//  - `ConversationStore+Streaming.swift`         (auto-routing, Fast FM, Local MLX, MoE, Cloud SSE)
//  - `ConversationStore+Persistence.swift`       (SwiftData, threads, rolling summary, Spotlight, outbox, memory sync)
//  - `ConversationStore+VoiceLive.swift`         (GPT-Live full-duplex voice bubbles & async delegation)
//  - `ConversationStore+OfflineGrounding.swift`  (offline hospital grounding + `BulaTrecho` / `BulaStore`)
//

import Foundation
import Observation
import SwiftData

// MARK: - Message model

public enum MessageRole: String, Sendable, Codable {
    case user
    case assistant
    case system
}

public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public var content: String
    public let timestamp: Date
    public var isStreaming: Bool
    public var model: String?
    public var tokensUsed: Int?
    public var isLocal: Bool
    public var source: String?
    public var agentKind: String?
    public var sessionId: String?
    public var podName: String?
    /// Round Table: voice identity (e.g. "consciousness", "paradox", "quantum")
    public var voiceName: String?
    /// True once this exchange has been auto-imported into the cluster exocortex memory.
    public var savedToMemory: Bool = false
    /// True while this is an instant on-device "presence" acknowledgment (warm pt-BR opener) shown
    /// to bridge the cloud latency — replaced the moment the grounded cloud reply starts streaming.
    public var isProvisional: Bool = false
    /// Normalized JPEG image attached to this turn (nil for text/voice-only turns).
    public var imageData: Data? = nil
    /// Local Apple Vision OCR + classification digest extracted on-device.
    public var imageLocalDigest: String? = nil
    /// True on assistant replies that answered a visual turn.
    public var hadVisualContext: Bool = false
    /// Native iPhone / MCP tool names executed during this assistant turn (for provenance chips).
    public var executedTools: [String] = []

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = .now,
        isStreaming: Bool = false,
        model: String? = nil,
        tokensUsed: Int? = nil,
        isLocal: Bool = false,
        source: String? = nil,
        agentKind: String? = nil,
        sessionId: String? = nil,
        podName: String? = nil,
        voiceName: String? = nil,
        imageData: Data? = nil,
        imageLocalDigest: String? = nil,
        hadVisualContext: Bool = false,
        executedTools: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.model = model
        self.tokensUsed = tokensUsed
        self.isLocal = isLocal
        self.source = source
        self.agentKind = agentKind
        self.sessionId = sessionId
        self.podName = podName
        self.voiceName = voiceName
        self.imageData = imageData
        self.imageLocalDigest = imageLocalDigest
        self.hadVisualContext = hadVisualContext
        self.executedTools = executedTools
    }
}

// MARK: - Store

@Observable
@MainActor
public final class ConversationStore {

    public internal(set) var messages: [ChatMessage] = []
    public internal(set) var isStreaming: Bool = false
    /// Presence LAYER — never the letter. The server writes a presence/phase event at t≈0
    /// of the ~25s wait so the silence reads as listening. It lives outside `messages` on
    /// purpose: server-authored text must never end up in the slot that renders as HIS voice
    /// (desenho 2026-08-02, item 4 vs item 5). Cleared the instant a real token arrives.
    public internal(set) var presenceNote: String? = nil
    public internal(set) var autoImportState: ConversationAutoImportState = .idle

    /// When the user last sent a cloud message — the client owns the thread, so it sends
    /// this so the companion knows how long since they last talked (temporal awareness).
    var lastContactAt: Date?

    /// Whether to prefer on-device model when available.
    public var preferLocal: Bool = true
    public var autoImportsConversationMemory: Bool = true
    public var projectSlug: String
    public var projectFamily: ProjectFamily?
    public var publicationScope: PublicationScope?
    public var discussionProfile: DiscussionProfile = .cluster
    /// Depth gear for the personal-voice path: nil = "Rápido" (server default voice); a model name
    /// (e.g. "glm-5.2" for "Pensar") asks the companion to think with a stronger model. "Fundo" is
    /// handled in the UI by routing to Go-Deeper instead of a chat turn.
    public var voiceModel: String? = nil

    /// Live Activity hooks (set by the view layer, since LiveActivityManager is in BeagleCockpit) —
    /// mirrors the GoDeepStore onResearch* pattern. Lets the user leave the app during the ~14-20s
    /// premium-voice wait (Opus/GPT) and see "pensando…" → the reply resolve on the lock screen.
    public var onCompanionTurnStart: ((String, String) -> Void)?
    public var onCompanionTurnEnd: ((String?) -> Void)?

    /// Async hooks for full-duplex `gpt-live-1.1` deep background delegations (`Modo Fundo` / `Rosalind` / `Síntese Matinal`).
    public var onTriggerAsyncVoiceFollowup: ((String, String?, [String]) async -> Void)?
    public var onVoiceResearchStart: ((String, String, String, Int, String?) -> Void)?
    public var onVoiceResearchUpdate: ((Int, Int, Int, String?, String?, Bool) -> Void)?

    public var modelContext: ModelContext?

    let client: BeagleClient
    /// Sinal de tom do turno que ele acabou de FALAR — ritmo e pausa, derivados no
    /// aparelho. O áudio nunca sai do iPhone.
    ///
    /// Consumido uma vez por turno: sem isso, a mensagem DIGITADA seguinte herdaria
    /// o tom da fala anterior, e o companion falaria de um "agora" que já passou.
    public var sinalDeVozDoTurno: (wpm: Double?, pausa: Double)?

    let llm = LocalLLMEngine.shared
    let assistedImportEncoder = JSONEncoder()
    let conversationImportSessionId = "beagle-apple-chat-\(UUID().uuidString.lowercased())"

    /// The active thread's id. Empty → falls back to the legacy single-thread id so an
    /// existing conversation keeps loading until the user starts/switches a thread.
    public internal(set) var currentConversationId: String = ""
    /// Observable title of the active thread (for the chat top bar). Updates when the thread
    /// is created, switched, or auto-titled from the first user line.
    var hasBackfilledSpotlight: Bool = false
    public internal(set) var currentConversationTitle: String = "Nova conversa"

    /// HRV-aware flow state for routing decisions.
    public var flowState: String? = nil
    /// Last night's sleep quality, 0–1 (deep+REM ratio). Feeds the attuned body-as-story greeting.
    public var sleepQuality01: Double? = nil
    public var physioContext: String? = nil
    public var companionContext: String? = nil
    public var behaviorContext: String? = nil
    public var noteTakingContext: String? = nil
    public var physioPolicy: PhysioConversationPolicy? = nil
    /// Live body + sky, set by the view (same source as the aura/strip). Sent raw so the
    /// server's `## Agora` block matches exactly what the screen shows.
    public var physioSummary: PhysioSummary? = nil
    public var currentSky: SpaceWeatherStore.Snapshot? = nil

    /// Fast on-device responder (Apple Foundation Models), injected by the app layer
    /// (BeagleCore can't reach BeagleCockpit). Light/casual messages route here for an
    /// instant reply; deep ones go to the cloud. Hybrid: on-device for light, cluster for deep.
    public var fastResponder: ((String, [String]) async -> String?)? = nil
    public var fastAvailable: Bool = false
    /// Instant on-device "presence" acknowledgment (Apple Foundation Models). Given the user's
    /// message, returns ONE warm pt-BR opener that bridges the cloud latency — it does NOT answer.
    /// nil/unavailable → the chat just shows the typing indicator as before.
    public var quickAck: ((String) async -> String?)? = nil

    public init(
        client: BeagleClient = .shared,
        preferLocal: Bool = true,
        projectSlug: String = "sounio",
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil
    ) {
        self.client = client
        self.preferLocal = preferLocal
        self.projectSlug = projectSlug
        self.projectFamily = projectFamily
        self.publicationScope = publicationScope
        // Drain the offline outbox to the memory spine the moment connectivity returns.
        NetworkMonitor.shared.onReconnect = { [weak self] in
            Task { @MainActor in
                await self?.flushOutbox()
                // Voltou a rede: a nuvem responde e os 4,29 GB viram só risco.
                LocalLLMEngine.shared.unload()
            }
        }
        // Aquece o modelo local na abertura, se os pesos já estiverem aqui.
        // Carregar 8B leva dezenas de segundos; pagar isso quando a rede já caiu
        // é pagar no pior momento possível.
        print(String(format: "[Beagle] RAM fisica: %.2f GB", LocalLLMEngine.ramGBMedida))
        // Carregar o modelo na ABERTURA matava o app: o iOS mata em
        // per-process-limit ~6,45 GB e os pesos sozinhos são 4,29 GB. Online ele
        // não precisa do modelo — então só carrega quando a rede cai, e devolve
        // a memória quando ela volta.
        NetworkMonitor.shared.onDisconnect = {
            Task { @MainActor in await LocalLLMEngine.shared.restaurarUltimoModelo() }
        }
    }

    public var persistenceConversationId: String {
        currentConversationId.isEmpty ? "home:\(projectSlug)" : currentConversationId
    }

    var activeSystemInstruction: String? {
        let contextLines = [companionContext, physioContext, behaviorContext, noteTakingContext]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

        guard !contextLines.isEmpty else { return nil }
        return contextLines.joined(separator: "\n")
    }

    // MARK: - Derived

    public var isEmpty: Bool { messages.isEmpty }
    public var lastMessage: ChatMessage? { messages.last }
    public var lastUserMessage: ChatMessage? { messages.last(where: { $0.role == .user }) }
    public var lastAssistantMessage: ChatMessage? { messages.last(where: { $0.role == .assistant }) }
    public var lastUpdatedAt: Date? { messages.last?.timestamp }

    // MARK: - Seed & Local Insertion

    /// Demo seed for screenshots/previews — a warm, attuned sample exchange. No-op if the
    /// conversation already has messages.
    public func seedDemoConversation() {
        guard messages.isEmpty else { return }
        messages = [
            ChatMessage(role: .user, content: "Acordei meio pra baixo hoje, não sei bem por quê."),
            ChatMessage(role: .assistant,
                content: "Faz sentido. Você dormiu leve e o coração andou tenso essa noite — às vezes o corpo sente antes da gente entender. Quer me contar como foi a noite?",
                source: "physiome"),
            ChatMessage(role: .user, content: "Acho que foi a apresentação de amanhã martelando na cabeça."),
            ChatMessage(role: .assistant,
                content: "A gente já passou por isso antes — e você costuma chegar mais inteiro do que imagina. Quer ensaiar o começo comigo agora, ou prefere só descarregar um pouco?",
                source: "exocortex"),
        ]
    }

    public func seedPreviewConversation(_ sampleMessages: [ChatMessage]) {
        clear()
        messages = sampleMessages
        for message in sampleMessages {
            persist(message: message)
        }
        isStreaming = false
    }

    /// Insert a locally-generated response into the conversation and persist it.
    /// Used when Foundation Models or other on-device models produce a response
    /// outside of the normal send flow.
    public func insertUserMessage(_ text: String) {
        let msg = ChatMessage(role: .user, content: text, isLocal: true)
        messages.append(msg)
        persist(message: msg)
    }

    public func insertLocalResponse(content: String, source: String = "foundation-models", model: String? = nil) {
        let msg = ChatMessage(
            role: .assistant,
            content: content,
            model: model ?? source,
            isLocal: true,
            source: source
        )
        messages.append(msg)
        persist(message: msg)
        if let user = messages.dropLast().last(where: { $0.role == .user }) {
            Task {
                await self.autoImportExchange(
                    user: user,
                    assistant: msg,
                    sourceSurface: AssistedImportRequestFactory.sourceSurface(for: source)
                )
            }
        }
    }

    /// Build conversation history as strings for seeding an LLM context.
    public func historyForContext(maxTurns: Int = 60) -> [String] {
        var result: [String] = []
        if let summary = currentRollingSummary(), !summary.isEmpty {
            result.append("[Resumo episódico anterior: \(summary)]")
        }
        result.append(contentsOf: messages.suffix(maxTurns).map { msg in
            "\(msg.role == .user ? "User" : "Beagle"): \(msg.content)"
        })
        return result
    }

    // MARK: - Regenerate

    public func regenerateLastResponse() async {
        guard let lastUserIdx = messages.lastIndex(where: { $0.role == .user }) else { return }
        let userId = messages[lastUserIdx].id
        let prompt = messages[lastUserIdx].content
        let attachedImage = messages[lastUserIdx].imageData

        // Remove the assistant response(s) after the last user message
        if let lastAssistantIdx = messages.lastIndex(where: { $0.role == .assistant }) {
            messages.removeSubrange(lastAssistantIdx...)
        }
        // Remove the user message by id (not content) to avoid matching duplicates
        if let userIdx = messages.lastIndex(where: { $0.id == userId }) {
            messages.remove(at: userIdx)
        }

        await sendMessage(prompt, imageData: attachedImage)
    }

    // MARK: - Shared Formatting & Reasoning Helpers

    static func composeUserBubbleContent(text: String, document: ChatDocumentPayload?) -> String {
        guard let document else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Analisa este documento PDF comigo." {
            return "📄 \(document.summaryBadge)"
        }
        return "📄 \(document.summaryBadge)\n\(text)"
    }

    static func composePersistedAttachmentDigest(
        vision: ChatVisionPayload?,
        document: ChatDocumentPayload?,
        webBlock: String? = nil
    ) -> String? {
        var parts: [String] = []
        if let doc = document {
            let excerpt = String(doc.extractedText.prefix(2_400))
            if excerpt.isEmpty {
                parts.append("PDF anexado: \(doc.summaryBadge)")
            } else {
                parts.append("PDF anexado (\(doc.summaryBadge)):\n\(excerpt)")
            }
        }
        if let v = vision?.localDigest, !v.isEmpty {
            parts.append(v)
        }
        if let w = webBlock, !w.isEmpty {
            parts.append(String(w.prefix(1_600)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func mergeUniqueTools(_ groups: [[String]]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for g in groups {
            for item in g where seen.insert(item).inserted {
                out.append(item)
            }
        }
        return out
    }

    /// Strip chain-of-thought blocks emitted by reasoning models (hunyuan, phi4-reasoning,
    /// r1, olmo3-think, …) so the chat bubble shows only the answer, not the raw reasoning.
    /// Removes `<think>…</think>` pairs; if a block is left open (truncated), drops from the
    /// last `<think>` onward.
    /// Exposto e nonisolated para poder ser testado: o caso que quebrou não foi o
    /// bloco fechado, foi o PARCIAL durante o streaming.
    nonisolated static func semRaciocinio(_ text: String) -> String {
        var s = text
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        // Handle an unclosed <think> (model still reasoning / output truncated).
        if let open = s.range(of: "<think>", options: .caseInsensitive), !s.localizedCaseInsensitiveContains("</think>") {
            s = String(s[..<open.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stripReasoning(_ text: String) -> String { Self.semRaciocinio(text) }
}
