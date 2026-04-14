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

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = .now,
        isStreaming: Bool = false,
        model: String? = nil,
        tokensUsed: Int? = nil,
        isLocal: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.model = model
        self.tokensUsed = tokensUsed
        self.isLocal = isLocal
    }
}

// MARK: - Store

@Observable
@MainActor
public final class ConversationStore {

    public private(set) var messages: [ChatMessage] = []
    public private(set) var isStreaming: Bool = false

    /// Whether to prefer on-device model when available.
    public var preferLocal: Bool = true

    private let client: BeagleClient
    private let llm = LocalLLMEngine.shared

    public init(client: BeagleClient = .shared) {
        self.client = client
    }

    // MARK: - Send (auto-routing)

    /// HRV-aware flow state for routing decisions.
    public var flowState: String? = nil

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
            for try await chunk in llm.generate(prompt: text) {
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
        }
        isStreaming = false
    }

    // MARK: - Send via cloud (HERMES)

    /// Send using the cloud backend (beagle-core /api/v1/chat).
    public func sendMessageCloud(_ text: String) async {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        let assistantId = UUID()
        let placeholder = ChatMessage(id: assistantId, role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        isStreaming = true

        // Build conversation history (last 10 turns) for context
        let history = messages
            .filter { $0.id != assistantId }  // exclude placeholder
            .suffix(10)
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")
        let contextualPrompt = history.isEmpty ? text : "\(history)\nUser: \(text)"
        let result = await client.chat(prompt: contextualPrompt)

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            if let response = result.value {
                let fullText = response.response ?? ""
                messages[idx].model = response.model
                messages[idx].tokensUsed = response.tokensUsed

                // Typing reveal for cloud responses
                await revealText(fullText, at: idx)
                messages[idx].isStreaming = false
            } else {
                messages[idx].content = result.error ?? "No response received."
                messages[idx].isStreaming = false
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
    }

    // MARK: - Typing reveal (cloud responses)

    private func revealText(_ text: String, at index: Int) async {
        let chars = Array(text)
        let chunkSize = 30
        var pos = 0

        while pos < chars.count {
            let end = min(pos + chunkSize, chars.count)
            messages[index].content = String(chars[0..<end])
            pos = end
            if pos < chars.count {
                try? await Task.sleep(for: .milliseconds(35))
            }
        }
    }

    // MARK: - Derived

    public var isEmpty: Bool { messages.isEmpty }
    public var lastMessage: ChatMessage? { messages.last }
}
