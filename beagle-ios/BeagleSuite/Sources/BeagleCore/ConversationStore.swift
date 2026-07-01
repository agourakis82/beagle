//
//  ConversationStore.swift
//  BeagleCore
//
//  Observable conversation model for chat-style interactions.
//  Routes between on-device MLX (Tier 0.5) and cloud HERMES (Tier 2+).
//  On-device is preferred when model is loaded; cloud is fallback.
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
        voiceName: String? = nil
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
    }
}

// MARK: - Store

@Observable
@MainActor
public final class ConversationStore {

    public private(set) var messages: [ChatMessage] = []
    public private(set) var isStreaming: Bool = false
    public private(set) var autoImportState: ConversationAutoImportState = .idle

    /// When the user last sent a cloud message — the client owns the thread, so it sends
    /// this so the companion knows how long since they last talked (temporal awareness).
    private var lastContactAt: Date?

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

    /// Friendly voice name for the Live Activity — mirrors ChatDepth's labels (BeagleCockpit layer,
    /// not importable from here) so the lock screen says "Sonnet 5" instead of "claude-sonnet-5".
    private func voiceLabel(for model: String?) -> String {
        switch model {
        case "claude-sonnet-5": return "Sonnet 5"
        case "claude-opus-4-8": return "Opus 4.8"
        case "gpt-5.5": return "GPT 5.5"
        case "grok": return "Grok 4.3"
        case "glm-5.2": return "GLM 5.2"
        case "kimi-k2.6": return "Kimi 2.6"
        case "minimax-m3": return "MiniMax M3"
        default: return "Beagle"
        }
    }
    public var modelContext: ModelContext?

    private let client: BeagleClient
    private let llm = LocalLLMEngine.shared
    private let assistedImportEncoder = JSONEncoder()
    private let conversationImportSessionId = "beagle-apple-chat-\(UUID().uuidString.lowercased())"

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
            Task { @MainActor in await self?.flushOutbox() }
        }
    }

    /// The active thread's id. Empty → falls back to the legacy single-thread id so an
    /// existing conversation keeps loading until the user starts/switches a thread.
    public private(set) var currentConversationId: String = ""
    /// Observable title of the active thread (for the chat top bar). Updates when the thread
    /// is created, switched, or auto-titled from the first user line.
    public private(set) var currentConversationTitle: String = "Nova conversa"

    public var persistenceConversationId: String {
        currentConversationId.isEmpty ? "home:\(projectSlug)" : currentConversationId
    }

    // MARK: - Send (auto-routing)

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

    /// Send a message with HRV-gated routing:
    /// FLOW → cloud (deep reasoning worth the latency)
    /// NORMAL → local MLX (balanced)
    /// STRESS → Foundation Models (fast, don't overwhelm)
    public func sendMessage(_ text: String) async {
        // Light, casual messages → instant on-device Apple Intelligence (when available).
        if isLight(text), fastAvailable, fastResponder != nil {
            await sendMessageFast(text)
            return
        }
        // Companion: cloud (rich, grounded, server-side memory ingest) when online; the on-device
        // MLX model when offline — and enqueue the offline turn so the memory spine receives it
        // once connectivity returns. `flowState` still travels in the cloud request body.
        if NetworkMonitor.shared.isOnline {
            await sendMessageCloud(text)
        } else if llm.isReady {
            await sendMessageLocal(text)
            enqueueOffline(userText: text)
        } else {
            await sendMessageCloud(text)
        }
    }

    /// Queue an offline personal turn for later sync to the memory spine (online turns are
    /// ingested server-side during the chat, so only offline ones land here).
    private func enqueueOffline(userText: String) {
        guard let ctx = modelContext else { return }
        let assistant = messages.last(where: { $0.role == .assistant })?.content ?? ""
        OutboxStore(context: ctx).enqueue(
            sessionId: persistenceConversationId,
            userText: userText,
            assistantText: assistant,
            clientTime: ISO8601DateFormatter().string(from: Date()),
            timezone: TimeZone.current.identifier
        )
    }

    /// Drain the offline outbox to the cockpit. Idempotent server-side (content_hash), so a
    /// failed item simply stays queued for the next attempt.
    public func flushOutbox() async {
        guard let ctx = modelContext else { return }
        let store = OutboxStore(context: ctx)
        for item in store.pending() {
            let result = await client.ingestTurn(IngestTurnRequest(
                session_id: item.sessionId, userText: item.userText, assistantText: item.assistantText,
                clientTime: item.clientTime, timezone: item.timezone))
            if result.value != nil { store.delete(item) }
        }
    }

    /// A short, casual message worth answering instantly on-device.
    private func isLight(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count <= 140
    }

    /// Instant on-device reply via the injected fast responder (Apple Foundation Models).
    public func sendMessageFast(_ text: String) async {
        let history = messages.suffix(8).map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        persist(message: userMessage)

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: "", isStreaming: true))
        isStreaming = true

        let reply = await fastResponder?(text, history) ?? nil

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            if let reply, !reply.isEmpty {
                messages[idx].model = "apple-intelligence"
                messages[idx].isLocal = true
                await revealText(reply, for: assistantId)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
            } else {
                // On-device came back empty → hand this turn to the cloud on the same bubble.
                let history2 = messages.dropLast().suffix(10)
                    .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
                    .joined(separator: "\n")
                let prompt = history2.isEmpty ? text : "\(history2)\nUser: \(text)"
                let result = await client.chat(prompt: prompt, system: activeSystemInstruction,
                    projectSlug: projectSlug, projectFamily: projectFamily,
                    publicationScope: publicationScope, discussionProfile: discussionProfile,
                    flowState: flowState, physioPolicy: physioPolicy,
                    hrvMs: physioSummary?.hrvMs, readiness: physioSummary?.readiness.rawValue,
                    sleepHours: physioSummary?.sleepHours,
                    kp: currentSky?.kp, dst: currentSky?.dst,
                    solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz)
                let full = result.value?.response ?? "Tô meio devagar agora — me dá um instante e tenta de novo?"
                messages[idx].source = result.value?.source
                await revealText(full, for: assistantId)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
            }
        }
        isStreaming = false
    }

    private var activeSystemInstruction: String? {
        let contextLines = [companionContext, physioContext, behaviorContext, noteTakingContext]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

        guard !contextLines.isEmpty else { return nil }
        return contextLines.joined(separator: "\n")
    }

    private func contextualizedUserText(_ text: String) -> String {
        guard let activeSystemInstruction else { return text }
        return activeSystemInstruction
            .split(separator: "\n")
            .map { "[\($0)]" }
            .joined(separator: "\n") + "\n" + text
    }

    /// Strip chain-of-thought blocks emitted by reasoning models (hunyuan, phi4-reasoning,
    /// r1, olmo3-think, …) so the chat bubble shows only the answer, not the raw reasoning.
    /// Removes `<think>…</think>` pairs; if a block is left open (truncated), drops from the
    /// last `<think>` onward.
    private func stripReasoning(_ text: String) -> String {
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

    // MARK: - Send via on-device LLM

    /// Send using the on-device MLX model (streaming).
    public func sendMessageLocal(_ text: String) async {
        guard llm.isReady else {
            // Fallback to cloud
            await sendMessageCloud(text)
            return
        }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        persist(message: userMessage)
        let prompt = contextualizedUserText(text)

        let assistantId = UUID()
        let modelName = llm.currentModel?.displayName ?? "local"
        let placeholder = ChatMessage(
            id: assistantId, role: .assistant, content: "",
            isStreaming: true, model: modelName, isLocal: true
        )
        messages.append(placeholder)
        isStreaming = true

        // Stream tokens from on-device model
        do {
            for try await chunk in llm.generate(prompt: prompt) {
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx].content += chunk
                }
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                if messages[idx].content.isEmpty {
                    messages[idx].content = "Local model error: \(error.localizedDescription)"
                }
            }
        }

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            messages[idx].content = stripReasoning(messages[idx].content)
            messages[idx].isStreaming = false
            persist(message: messages[idx])
            await autoImportExchange(
                user: userMessage,
                assistant: messages[idx],
                sourceSurface: "beagle-apple-local"
            )
        }
        isStreaming = false
    }

    // MARK: - Send via cloud (HERMES)

    /// Send using the cloud backend (beagle-core /api/v1/chat).
    public func sendMessageCloud(_ text: String) async {
        // Build history BEFORE appending new user message — pass as STRUCTURED
        // turn-based messages (role+content), NOT a "User: ... Assistant: ..."
        // concatenated string. Smart models (Grok) read concatenated transcripts
        // as text-to-continue and hallucinate the next user line.
        let history: [[String: String]] = messages
            .suffix(10)
            .map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] }
        let contextualPrompt = text

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        persist(message: userMessage)

        let assistantId = UUID()
        let placeholder = ChatMessage(id: assistantId, role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        isStreaming = true

        onCompanionTurnStart?(currentConversationTitle, voiceLabel(for: voiceModel))

        // B-routing: instant on-device "presence". A warm pt-BR opener fills the ~14s cloud
        // latency with the friend's voice instead of typing dots — then the grounded cloud reply
        // replaces it the moment real tokens arrive. Best-effort; skipped if Apple FM is off.
        if let quickAck {
            Task { [assistantId] in
                guard let ack = await quickAck(text)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !ack.isEmpty else { return }
                guard let idx = messages.firstIndex(where: { $0.id == assistantId }),
                      messages[idx].content.isEmpty else { return }   // cloud already streaming → skip
                messages[idx].content = ack
                messages[idx].isProvisional = true
            }
        }

        // Temporal awareness: send the previous contact time (the client owns the thread),
        // then stamp this exchange as the new "last contact" for the next turn. First send →
        // previousContact == nil → the server frames it as a first contact.
        let previousContact = lastContactAt
        lastContactAt = Date()

        // STREAM tokens live from /api/mobile/v1/chat/stream. The user sees the
        // companion typing as the model emits — no more 7-9s frozen wait.
        // Falls back to the buffered /chat endpoint on stream failure so the chat
        // never goes completely dark.
        let stream = client.chatStream(
            prompt: contextualPrompt,
            system: activeSystemInstruction,
            projectSlug: projectSlug,
            projectFamily: projectFamily,
            publicationScope: publicationScope,
            discussionProfile: discussionProfile,
            flowState: flowState,
            physioPolicy: physioPolicy,
            lastContactAt: previousContact,
            history: history,
            hrvMs: physioSummary?.hrvMs, readiness: physioSummary?.readiness.rawValue,
            sleepHours: physioSummary?.sleepHours,
            kp: currentSky?.kp, dst: currentSky?.dst,
            solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz,
            voiceModel: voiceModel
        )

        var streamedText = ""
        var streamErr: Error? = nil
        do {
            for try await token in stream {
                streamedText += token
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    // First real token evicts the provisional on-device ack.
                    if messages[idx].isProvisional { messages[idx].isProvisional = false }
                    messages[idx].content = stripReasoning(streamedText)
                }
            }
        } catch {
            streamErr = error
        }

        if !streamedText.isEmpty {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].content = stripReasoning(streamedText)
                messages[idx].isStreaming = false
                messages[idx].source = "cloud-stream"
                persist(message: messages[idx])
                onCompanionTurnEnd?(messages[idx].content)
                await autoImportExchange(
                    user: userMessage,
                    assistant: messages[idx],
                    sourceSurface: "beagle-apple-cloud"
                )
            }
            isStreaming = false
            return
        }

        // Stream produced nothing (gateway hiccup or 5xx). Fall back to the
        // buffered /chat endpoint so the user always gets a reply.
        let result = await client.chat(
            prompt: contextualPrompt,
            system: activeSystemInstruction,
            projectSlug: projectSlug,
            projectFamily: projectFamily,
            publicationScope: publicationScope,
            discussionProfile: discussionProfile,
            flowState: flowState,
            physioPolicy: physioPolicy,
            lastContactAt: previousContact,
            history: history,
            hrvMs: physioSummary?.hrvMs, readiness: physioSummary?.readiness.rawValue,
            sleepHours: physioSummary?.sleepHours,
            kp: currentSky?.kp, dst: currentSky?.dst,
            solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz,
            voiceModel: voiceModel
        )

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            messages[idx].isProvisional = false   // evict any on-device ack before the real reply
            if let response = result.value {
                let fullText = stripReasoning(response.response ?? "")
                messages[idx].model = response.model
                messages[idx].tokensUsed = response.tokensUsed
                messages[idx].source = response.source
                messages[idx].agentKind = response.agentKind
                messages[idx].sessionId = response.sessionId
                messages[idx].podName = response.podName
                await revealText(fullText, for: assistantId)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
                onCompanionTurnEnd?(messages[idx].content)
                await autoImportExchange(
                    user: userMessage,
                    assistant: messages[idx],
                    sourceSurface: "beagle-apple-cloud"
                )
            } else {
                messages[idx].content = result.error ?? streamErr?.localizedDescription ?? "No response received."
                messages[idx].isStreaming = false
                persist(message: messages[idx])
                onCompanionTurnEnd?(nil)
            }
        }

        isStreaming = false
    }

    // MARK: - Regenerate

    public func regenerateLastResponse() async {
        guard let lastUserIdx = messages.lastIndex(where: { $0.role == .user }) else { return }
        let userId = messages[lastUserIdx].id
        let prompt = messages[lastUserIdx].content

        // Remove the assistant response(s) after the last user message
        if let lastAssistantIdx = messages.lastIndex(where: { $0.role == .assistant }) {
            messages.removeSubrange(lastAssistantIdx...)
        }
        // Remove the user message by id (not content) to avoid matching duplicates
        if let userIdx = messages.lastIndex(where: { $0.id == userId }) {
            messages.remove(at: userIdx)
        }

        await sendMessage(prompt)
    }

    /// Clear all messages.
    public func clear() {
        messages.removeAll()
        isStreaming = false
        guard let modelContext else { return }
        let conversationId = persistenceConversationId
        let descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate<PersistedMessage> { message in
                message.conversationId == conversationId
            }
        )
        if let persisted = try? modelContext.fetch(descriptor) {
            for message in persisted {
                modelContext.delete(message)
            }
            try? modelContext.save()
        }
    }

    // MARK: - Typing reveal (cloud responses)

    private func revealText(_ text: String, for messageId: UUID) async {
        let chars = Array(text)
        let chunkSize = 30
        var pos = 0

        while pos < chars.count {
            // Guard against clear() being called mid-reveal
            guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
            let end = min(pos + chunkSize, chars.count)
            messages[idx].content = String(chars[0..<end])
            pos = end
            if pos < chars.count {
                // Propagate cancellation instead of swallowing it with try?
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(35))
                if Task.isCancelled { return }
            }
        }
    }

    // MARK: - Insert local response (Foundation Models, Mamba, etc.)

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
    public func historyForContext(maxTurns: Int = 20) -> [String] {
        messages.suffix(maxTurns).map { msg in
            "\(msg.role == .user ? "User" : "Beagle"): \(msg.content)"
        }
    }

    // MARK: - Derived

    public var isEmpty: Bool { messages.isEmpty }
    public var lastMessage: ChatMessage? { messages.last }
    public var lastUserMessage: ChatMessage? { messages.last(where: { $0.role == .user }) }
    public var lastAssistantMessage: ChatMessage? { messages.last(where: { $0.role == .assistant }) }
    public var lastUpdatedAt: Date? { messages.last?.timestamp }

    public func loadPersistedConversation() {
        guard let modelContext else { return }
        let conversationId = persistenceConversationId
        let descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate<PersistedMessage> { message in
                message.conversationId == conversationId
            },
            sortBy: [SortDescriptor(\PersistedMessage.sentAt, order: .forward)]
        )

        guard let persisted = try? modelContext.fetch(descriptor) else { return }
        messages = persisted.map { stored in
            ChatMessage(
                role: MessageRole(rawValue: stored.role) ?? .assistant,
                content: stored.content,
                timestamp: stored.sentAt,
                isStreaming: false,
                model: stored.model,
                tokensUsed: stored.tokensUsed,
                isLocal: stored.isLocal,
                source: stored.source,
                agentKind: stored.agentKind,
                sessionId: stored.sessionId,
                podName: stored.podName
            )
        }
        isStreaming = false
        // Backfill a thread record for legacy/un-recorded conversations so they show in the drawer.
        if !messages.isEmpty {
            touchConversationRecord(firstUserText: messages.first(where: { $0.role == .user })?.content)
        }
    }

    // MARK: - Threads (multi-conversation)

    /// All threads for the current project, pinned first then most-recently-updated.
    public func conversations() -> [PersistedConversation] {
        guard let ctx = modelContext else { return [] }
        let slug = projectSlug
        let d = FetchDescriptor<PersistedConversation>(
            predicate: #Predicate<PersistedConversation> { $0.projectSlug == slug },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let all = (try? ctx.fetch(d)) ?? []
        // Bool isn't Comparable for SortDescriptor — partition pinned-first, stable within each group.
        return all.filter { $0.pinned } + all.filter { !$0.pinned }
    }

    /// Start a fresh thread and switch to it (empty in-memory transcript).
    public func newConversation() {
        let id = "conv:\(UUID().uuidString.lowercased())"
        if let ctx = modelContext {
            ctx.insert(PersistedConversation(id: id, projectSlug: projectSlug, lastModel: discussionProfile.rawValue))
            try? ctx.save()
        }
        currentConversationId = id
        currentConversationTitle = "Nova conversa"
        messages = []
        isStreaming = false
        lastContactAt = nil
    }

    /// Switch to an existing thread and load its transcript.
    public func switchTo(conversationId id: String) {
        guard id != persistenceConversationId || messages.isEmpty else { return }
        currentConversationId = id
        loadPersistedConversation()
        refreshCurrentTitle()
        lastContactAt = messages.last(where: { $0.role == .user })?.timestamp
    }

    private func refreshCurrentTitle() {
        guard let ctx = modelContext else { return }
        let id = persistenceConversationId
        let d = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        currentConversationTitle = (try? ctx.fetch(d).first)?.displayTitle ?? "Nova conversa"
    }

    public func renameConversation(_ id: String, title: String) {
        guard let ctx = modelContext else { return }
        let d = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        if let conv = try? ctx.fetch(d).first {
            conv.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            conv.updatedAt = .now
            try? ctx.save()
        }
    }

    public func togglePinned(_ id: String) {
        guard let ctx = modelContext else { return }
        let d = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        if let conv = try? ctx.fetch(d).first {
            conv.pinned.toggle()
            try? ctx.save()
        }
    }

    /// Delete a thread + its messages; if it was current, fall to the most-recent remaining (or a fresh one).
    public func deleteConversation(_ id: String) {
        guard let ctx = modelContext else { return }
        let md = FetchDescriptor<PersistedMessage>(predicate: #Predicate<PersistedMessage> { $0.conversationId == id })
        if let msgs = try? ctx.fetch(md) { for m in msgs { ctx.delete(m) } }
        let cd = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        if let convs = try? ctx.fetch(cd) { for c in convs { ctx.delete(c) } }
        try? ctx.save()
        if persistenceConversationId == id {
            if let next = conversations().first {
                switchTo(conversationId: next.id)
            } else {
                newConversation()
            }
        }
    }

    /// Upsert the thread record (createdif missing, bump updatedAt, set title from the first user
    /// line if still untitled). Auto-title later upgrades to an LLM-generated title.
    private func touchConversationRecord(firstUserText: String?) {
        guard let ctx = modelContext else { return }
        let id = persistenceConversationId
        let slug = projectSlug
        let d = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        if let conv = try? ctx.fetch(d).first {
            conv.updatedAt = .now
            if (conv.title ?? "").isEmpty, let t = firstUserText { conv.title = Self.titleFrom(t) }
            conv.lastModel = discussionProfile.rawValue
        } else {
            let conv = PersistedConversation(id: id, projectSlug: slug, lastModel: discussionProfile.rawValue)
            if let t = firstUserText { conv.title = Self.titleFrom(t) }
            ctx.insert(conv)
        }
        try? ctx.save()
        refreshCurrentTitle()
    }

    private static func titleFrom(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        return String(t.prefix(48))
    }

    public func restoreContext(
        projectSlug: String,
        projectFamily: ProjectFamily?,
        publicationScope: PublicationScope?
    ) {
        self.projectSlug = projectSlug
        self.projectFamily = projectFamily
        self.publicationScope = publicationScope
        loadPersistedConversation()
    }

    public func seedPreviewConversation(_ sampleMessages: [ChatMessage]) {
        clear()
        messages = sampleMessages
        for message in sampleMessages {
            persist(message: message)
        }
        isStreaming = false
    }

    private func persist(message: ChatMessage) {
        guard let modelContext else { return }
        let persisted = PersistedMessage(
            role: message.role.rawValue,
            content: message.content,
            model: message.model,
            tokensUsed: message.tokensUsed,
            isLocal: message.isLocal,
            source: message.source,
            agentKind: message.agentKind,
            sessionId: message.sessionId,
            podName: message.podName,
            conversationId: persistenceConversationId,
            sentAt: message.timestamp
        )
        modelContext.insert(persisted)
        try? modelContext.save()
        // Keep the thread record fresh (updatedAt for ordering; title from the first user line).
        touchConversationRecord(firstUserText: message.role == .user ? message.content : nil)
    }

    private func autoImportExchange(
        user: ChatMessage,
        assistant: ChatMessage,
        sourceSurface: String
    ) async {
        guard autoImportsConversationMemory else { return }
        let assistantText = assistant.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = user.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, !assistantText.isEmpty else { return }

        let request = AssistedImportRequestFactory.conversationExchange(
            userText: userText,
            assistantText: assistantText,
            sourceSurface: sourceSurface,
            sessionId: conversationImportSessionId,
            projectRef: projectSlug,
            model: assistant.model,
            flowState: flowState,
            bodySummary: physioContext,
            agentKind: assistant.agentKind,
            podName: assistant.podName
        )

        if request.privacyClass == "restricted" {
            enqueueAssistedImportOutbox(request, reason: "restricted_privacy_guard")
            autoImportState = ConversationAutoImportState(
                status: "blocked",
                sessionId: request.sessionId,
                queuedCount: queuedOutboxCount(),
                restrictedCount: restrictedOutboxCount(),
                lastError: "Restricted content held locally for explicit review."
            )
            return
        }

        autoImportState = ConversationAutoImportState(
            status: "importing",
            sessionId: request.sessionId,
            queuedCount: queuedOutboxCount(),
            restrictedCount: restrictedOutboxCount()
        )
        let result = await client.assistedImportBatch(request)
        guard let importResult = result.value, importResult.status == "imported" else {
            enqueueAssistedImportOutbox(request, reason: result.error ?? result.value?.reason ?? "auto_import_failed")
            autoImportState = ConversationAutoImportState(
                status: "queued",
                sessionId: request.sessionId,
                queuedCount: queuedOutboxCount(),
                restrictedCount: restrictedOutboxCount(),
                lastError: result.error ?? result.value?.reason
            )
            return
        }
        let atoms = importResult.projection?.atomsCreated ?? 0
        let episodes = importResult.projection?.episodesCreated ?? 0
        // Mark the assistant bubble so the UI can show "✓ Memory" — the idea is now recallable.
        if let i = messages.firstIndex(where: { $0.id == assistant.id }) {
            messages[i].savedToMemory = true
        }
        autoImportState = ConversationAutoImportState(
            status: "imported",
            sessionId: importResult.sessionId,
            lastImportedAt: AssistedImportRequestFactory.isoTimestamp(),
            lastSummary: "\(episodes) episode, \(atoms) atoms",
            queuedCount: queuedOutboxCount(),
            restrictedCount: restrictedOutboxCount()
        )
    }

    private func enqueueAssistedImportOutbox(_ request: AssistedImportBatchRequest, reason: String) {
        guard
            let modelContext,
            let data = try? assistedImportEncoder.encode(request),
            let payload = String(data: data, encoding: .utf8)
        else {
            return
        }
        modelContext.insert(PersistedAssistedImportOutbox(
            payload: payload,
            reason: reason,
            privacyClass: request.privacyClass,
            sourceSurface: request.sourceSurface
        ))
        try? modelContext.save()
    }

    private func queuedOutboxCount() -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<PersistedAssistedImportOutbox>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func restrictedOutboxCount() -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<PersistedAssistedImportOutbox>(
            predicate: #Predicate<PersistedAssistedImportOutbox> { item in
                item.privacyClass == "restricted"
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
}
