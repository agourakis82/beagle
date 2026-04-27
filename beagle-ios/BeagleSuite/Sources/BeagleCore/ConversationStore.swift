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

    /// Whether to prefer on-device model when available.
    public var preferLocal: Bool = true
    public var autoImportsConversationMemory: Bool = true
    public var projectSlug: String
    public var projectFamily: ProjectFamily?
    public var publicationScope: PublicationScope?
    public var discussionProfile: DiscussionProfile = .cluster
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
    }

    public var persistenceConversationId: String {
        "home:\(projectSlug)"
    }

    // MARK: - Send (auto-routing)

    /// HRV-aware flow state for routing decisions.
    public var flowState: String? = nil
    public var physioContext: String? = nil
    public var companionContext: String? = nil
    public var behaviorContext: String? = nil
    public var noteTakingContext: String? = nil
    public var physioPolicy: PhysioConversationPolicy? = nil

    /// Send a message with HRV-gated routing:
    /// FLOW → cloud (deep reasoning worth the latency)
    /// NORMAL → local MLX (balanced)
    /// STRESS → Foundation Models (fast, don't overwhelm)
    public func sendMessage(_ text: String) async {
        switch flowState {
        case "FLOW":
            // Deep focus → use cloud for best reasoning
            await sendMessageCloud(text)
        case "STRESS":
            // Stressed → quick local response
            if llm.isReady {
                await sendMessageLocal(text)
            } else {
                await sendMessageCloud(text)
            }
        default:
            // NORMAL or unknown → prefer local if available
            if preferLocal && llm.isReady {
                await sendMessageLocal(text)
            } else {
                await sendMessageCloud(text)
            }
        }
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
        // Build history BEFORE appending new user message to avoid duplication
        let history = messages
            .suffix(10)
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")
        let contextualPrompt = history.isEmpty ? text : "\(history)\nUser: \(text)"

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        persist(message: userMessage)

        let assistantId = UUID()
        let placeholder = ChatMessage(id: assistantId, role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        isStreaming = true

        let result = await client.chat(
            prompt: contextualPrompt,
            system: activeSystemInstruction,
            projectSlug: projectSlug,
            projectFamily: projectFamily,
            publicationScope: publicationScope,
            discussionProfile: discussionProfile,
            flowState: flowState,
            physioPolicy: physioPolicy
        )

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            if let response = result.value {
                let fullText = response.response ?? ""
                messages[idx].model = response.model
                messages[idx].tokensUsed = response.tokensUsed
                messages[idx].source = response.source
                messages[idx].agentKind = response.agentKind
                messages[idx].sessionId = response.sessionId
                messages[idx].podName = response.podName

                // Typing reveal for cloud responses
                await revealText(fullText, for: assistantId)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
                await autoImportExchange(
                    user: userMessage,
                    assistant: messages[idx],
                    sourceSurface: "beagle-apple-cloud"
                )
            } else {
                messages[idx].content = result.error ?? "No response received."
                messages[idx].isStreaming = false
                persist(message: messages[idx])
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
