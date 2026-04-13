//
//  ConversationStore.swift
//  BeagleCore
//
//  Observable conversation model for chat-style interactions.
//  Wraps BeagleClient.chat() with message history and streaming support.
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

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = .now,
        isStreaming: Bool = false,
        model: String? = nil,
        tokensUsed: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.model = model
        self.tokensUsed = tokensUsed
    }
}

// MARK: - Store

@Observable
@MainActor
public final class ConversationStore {

    public private(set) var messages: [ChatMessage] = []
    public private(set) var isStreaming: Bool = false

    private let client = BeagleClient.shared

    public init() {}

    // MARK: - Send

    /// Send a user message and get an assistant response.
    public func sendMessage(_ text: String) async {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        // Create placeholder assistant message
        let assistantId = UUID()
        let placeholder = ChatMessage(id: assistantId, role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        isStreaming = true

        // Call the API
        let result = await client.chat(prompt: text)

        // Update assistant message with response
        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            if let response = result.value {
                let fullText = response.response ?? ""
                messages[idx].model = response.model
                messages[idx].tokensUsed = response.tokensUsed

                // Typing reveal: show characters progressively
                await revealText(fullText, at: idx)

                messages[idx].isStreaming = false
            } else {
                messages[idx].content = result.error ?? "No response received."
                messages[idx].isStreaming = false
            }
        }

        isStreaming = false
    }

    /// Regenerate the last assistant response.
    public func regenerateLastResponse() async {
        // Find the last user message
        guard let lastUserIdx = messages.lastIndex(where: { $0.role == .user }) else { return }
        let prompt = messages[lastUserIdx].content

        // Remove all messages after (and including) the last assistant response
        if let lastAssistantIdx = messages.lastIndex(where: { $0.role == .assistant }) {
            messages.removeSubrange(lastAssistantIdx...)
        }

        // Re-send
        // Remove the user message too — sendMessage will re-add it
        if let userIdx = messages.lastIndex(where: { $0.role == .user && $0.content == prompt }) {
            messages.remove(at: userIdx)
        }

        await sendMessage(prompt)
    }

    /// Clear all messages.
    public func clear() {
        messages.removeAll()
        isStreaming = false
    }

    // MARK: - Derived

    // MARK: - Typing reveal

    /// Progressively reveal text for a typing effect.
    /// Shows ~30 characters per tick at 50ms intervals.
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

    public var isEmpty: Bool { messages.isEmpty }

    public var lastMessage: ChatMessage? { messages.last }
}
