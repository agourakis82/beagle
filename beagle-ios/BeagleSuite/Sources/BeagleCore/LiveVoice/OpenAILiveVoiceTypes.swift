//
//  OpenAILiveVoiceTypes.swift
//  BeagleCore — Modelos puros do protocolo OpenAI GPT-Live (`gpt-live-1.1`)
//

import Foundation

public enum OpenAILiveContextAppendKind: String, Sendable {
    case instructions = "session.instructions.append"
    case thinking = "session.thinking.append"
    case commentary = "session.commentary.append"
}

public struct OpenAILiveTranscriptSegment: Sendable, Equatable {
    public let role: MessageRole
    public var text: String
    public let startMs: Int
    public var endMs: Int

    public init(role: MessageRole, text: String, startMs: Int, endMs: Int) {
        self.role = role
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
    }
}

public struct OpenAILiveDelegationContext: Sendable {
    public let delegationId: String
    public let offsetMs: Int
    public let transcriptWindow: [(role: String, text: String)]
    public let latestUserUtterance: String

    public init(
        delegationId: String,
        offsetMs: Int,
        transcriptWindow: [(role: String, text: String)],
        latestUserUtterance: String
    ) {
        self.delegationId = delegationId
        self.offsetMs = offsetMs
        self.transcriptWindow = transcriptWindow
        self.latestUserUtterance = latestUserUtterance
    }
}

public struct OpenAILiveDelegationOutcome: Sendable {
    public let spokenSummary: String
    public let backgroundFacts: String?
    public let executedTools: [String]

    public init(
        spokenSummary: String,
        backgroundFacts: String? = nil,
        executedTools: [String] = []
    ) {
        self.spokenSummary = spokenSummary
        self.backgroundFacts = backgroundFacts
        self.executedTools = executedTools
    }
}

public enum OpenAILiveServerEvent: Sendable, Equatable {
    case sessionStarted(sessionId: String)
    case outputAudioDelta(pcm16Data: Data)
    case inputTranscriptDelta(delta: String, startMs: Int, endMs: Int)
    case outputTranscriptDelta(delta: String, startMs: Int, endMs: Int)
    case delegationCreated(id: String, target: String, offsetMs: Int)
    case inputAudioMuted(clientEventId: String?)
    case inputAudioUnmuted(clientEventId: String?)
    case contextAppended(eventType: String, clientEventId: String?)
    case sessionClosed
    case error(code: String?, message: String)
    case ignored(type: String)
}
