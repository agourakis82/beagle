//
//  Persistence.swift
//  BeagleCore
//
//  SwiftData models for local cache and transient outbox.
//  Canonical exocortex memory lives on the cluster GraphRAG++ append-only logs.
//
//  Models:
//   - PersistedThought: raw + refined text, source, timestamps
//   - PersistedMessage: conversation messages with model/tokens
//   - PersistedDeepSession: Go Deeper session with all modality results
//   - UserPreferences: model choice, last tab, settings
//

import Foundation
import SwiftData

// MARK: - Persisted Thought

@Model
public final class PersistedThought {
    public var rawText: String
    public var refinedText: String?
    public var source: String
    public var capturedAt: Date
    public var syncedToServer: Bool
    public var nodeId: String?
    /// English translation if the original thought was in Portuguese.
    public var translatedText: String?
    /// Detected language code (BCP-47), e.g. "pt", "en".
    public var originalLanguage: String?

    public init(rawText: String, refinedText: String? = nil, source: String = "ios", capturedAt: Date = .now) {
        self.rawText = rawText
        self.refinedText = refinedText
        self.source = source
        self.capturedAt = capturedAt
        self.syncedToServer = false
    }

    /// The best available text (refined if available, otherwise raw).
    public var displayText: String {
        refinedText ?? rawText
    }

    /// Whether HERMES has refined this thought.
    public var isRefined: Bool {
        refinedText != nil
    }
}

// MARK: - Persisted Message

@Model
public final class PersistedMessage {
    public var role: String              // "user" or "assistant"
    public var content: String
    public var model: String?
    public var tokensUsed: Int?
    public var isLocal: Bool
    public var source: String?
    public var agentKind: String?
    public var sessionId: String?
    public var podName: String?
    public var conversationId: String    // groups messages into conversations
    public var sentAt: Date

    public init(
        role: String, content: String, model: String? = nil,
        tokensUsed: Int? = nil, isLocal: Bool = false,
        source: String? = nil, agentKind: String? = nil,
        sessionId: String? = nil, podName: String? = nil,
        conversationId: String = "default", sentAt: Date = .now
    ) {
        self.role = role
        self.content = content
        self.model = model
        self.tokensUsed = tokensUsed
        self.isLocal = isLocal
        self.source = source
        self.agentKind = agentKind
        self.sessionId = sessionId
        self.podName = podName
        self.conversationId = conversationId
        self.sentAt = sentAt
    }
}

// MARK: - Persisted Conversation (multi-thread)

/// One chat thread. Messages link to it by `PersistedMessage.conversationId == id`. Lets the
/// chat hold many conversations (history drawer) instead of a single home thread.
@Model
public final class PersistedConversation {
    @Attribute(.unique) public var id: String   // == conversationId on its messages
    public var projectSlug: String
    public var title: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var pinned: Bool
    public var lastModel: String?

    public init(
        id: String, projectSlug: String, title: String? = nil,
        createdAt: Date = .now, updatedAt: Date = .now, pinned: Bool = false, lastModel: String? = nil
    ) {
        self.id = id
        self.projectSlug = projectSlug
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.lastModel = lastModel
    }

    /// Title to show in the history drawer when none was set yet.
    public var displayTitle: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Nova conversa" : t
    }
}

// MARK: - Persisted Deep Session

@Model
public final class PersistedDeepSession {
    public var prompt: String
    public var startedAt: Date
    public var completedAt: Date?
    public var synthesisText: String?
    public var modalityResults: String?   // JSON-encoded modality summaries
    public var modalityCount: Int

    public init(prompt: String, startedAt: Date = .now, modalityCount: Int = 0) {
        self.prompt = prompt
        self.startedAt = startedAt
        self.modalityCount = modalityCount
    }

    public var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    public var isComplete: Bool { completedAt != nil }
}

// MARK: - Persisted Exocortex Home Snapshot Cache

@Model
public final class PersistedExocortexHomeSnapshot {
    public var payload: String
    public var capturedAt: Date

    public init(payload: String, capturedAt: Date = .now) {
        self.payload = payload
        self.capturedAt = capturedAt
    }
}

// MARK: - Assisted Import Outbox

@Model
public final class PersistedAssistedImportOutbox {
    public var id: String
    public var payload: String
    public var reason: String
    public var privacyClass: String
    public var sourceSurface: String
    public var createdAt: Date
    public var lastAttemptAt: Date?
    public var attemptCount: Int

    public init(
        id: String = UUID().uuidString,
        payload: String,
        reason: String,
        privacyClass: String,
        sourceSurface: String,
        createdAt: Date = .now,
        lastAttemptAt: Date? = nil,
        attemptCount: Int = 0
    ) {
        self.id = id
        self.payload = payload
        self.reason = reason
        self.privacyClass = privacyClass
        self.sourceSurface = sourceSurface
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = attemptCount
    }
}

/// A personal-space companion turn captured offline, awaiting sync to the memory spine.
@Model
public final class PendingIngest {
    @Attribute(.unique) public var id: UUID
    public var sessionId: String
    public var userText: String
    public var assistantText: String
    public var clientTime: String
    public var timezone: String
    public var createdAt: Date

    public init(id: UUID = UUID(), sessionId: String, userText: String, assistantText: String,
                clientTime: String, timezone: String, createdAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.userText = userText
        self.assistantText = assistantText
        self.clientTime = clientTime
        self.timezone = timezone
        self.createdAt = createdAt
    }
}

// MARK: - Container Configuration

public enum PersistenceConfig {
    public static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            PersistedThought.self,
            PersistedMessage.self,
            PersistedConversation.self,
            PersistedDeepSession.self,
            PersistedExocortexHomeSnapshot.self,
            PersistedAssistedImportOutbox.self,
            PendingIngest.self,
        ])
        let config = ModelConfiguration(
            "BeagleExocortex",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
