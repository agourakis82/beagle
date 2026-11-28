//
//  LiveActivityModels.swift
//  BeagleCore
//
//  iOS Live Activity attributes for agent sessions, research runs,
//  cognitive state, and companion turns.
//

import Foundation

#if os(iOS)
import ActivityKit

// MARK: - Live Activity Attributes

public struct AgentSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: String
        public var tokensUsed: Int
        public var lastOutputSnippet: String

        public init(status: String, tokensUsed: Int, lastOutputSnippet: String) {
            self.status = status
            self.tokensUsed = tokensUsed
            self.lastOutputSnippet = lastOutputSnippet
        }
    }

    public var agentKind: String
    public var projectSlug: String
    public var sessionId: String

    public init(agentKind: String, projectSlug: String, sessionId: String) {
        self.agentKind = agentKind
        self.projectSlug = projectSlug
        self.sessionId = sessionId
    }
}

public struct ResearchRunAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var stepCurrent: Int
        public var stepTotal: Int
        public var etaSeconds: Int
        public var activeLens: String?
        public var summarySnippet: String?
        public var isCompleted: Bool?

        public init(
            stepCurrent: Int,
            stepTotal: Int,
            etaSeconds: Int,
            activeLens: String? = nil,
            summarySnippet: String? = nil,
            isCompleted: Bool? = nil
        ) {
            self.stepCurrent = stepCurrent
            self.stepTotal = stepTotal
            self.etaSeconds = etaSeconds
            self.activeLens = activeLens
            self.summarySnippet = summarySnippet
            self.isCompleted = isCompleted
        }
    }

    public var runId: String
    public var campaignName: String
    public var projectSlug: String

    public init(runId: String, campaignName: String, projectSlug: String) {
        self.runId = runId
        self.campaignName = campaignName
        self.projectSlug = projectSlug
    }
}

public struct CognitiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var readiness: Double?
        public var intensity: String
        public var hrvMs: Double?
        public var agentCount: Int
        public var activeJobCount: Int
        public var lastThoughtSnippet: String?

        public init(
            readiness: Double? = nil,
            intensity: String = "normal",
            hrvMs: Double? = nil,
            agentCount: Int = 0,
            activeJobCount: Int = 0,
            lastThoughtSnippet: String? = nil
        ) {
            self.readiness = readiness
            self.intensity = intensity
            self.hrvMs = hrvMs
            self.agentCount = agentCount
            self.activeJobCount = activeJobCount
            self.lastThoughtSnippet = lastThoughtSnippet
        }

        public var readinessPercent: Int {
            guard let r = readiness else { return 0 }
            return Int((r * 100).rounded())
        }

        public var intensityLabel: String {
            switch intensity {
            case "minimal":   return "Minimal"
            case "calm":      return "Calm"
            case "normal":    return "Normal"
            case "engaged":   return "Engaged"
            case "challenge": return "Challenge"
            default:          return intensity.capitalized
            }
        }

        public var lockScreenLine: String {
            var parts: [String] = []
            parts.append(intensityLabel)
            if let readiness {
                parts.append("\(Int((readiness * 100).rounded()))%")
            }
            if agentCount > 0 {
                parts.append("\(agentCount) agent\(agentCount == 1 ? "" : "s")")
            }
            return parts.joined(separator: " · ")
        }
    }

    public init() {}
}

/// A single companion chat turn — "pensando" while the voice (Sonnet/Opus/GPT/...) works, then
/// "respondeu" with a snippet once the reply lands. Lets the user leave the app during the ~14-20s
/// premium-voice wait (Opus/GPT) and see it resolve from the lock screen / Dynamic Island.
public struct CompanionTurnAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: String        // "pensando" | "respondeu" | "sem resposta"
        public var voiceLabel: String     // "Sonnet 5", "Opus 4.8", "GLM 5.2", ...
        public var snippet: String        // opening of the reply once available; empty while thinking

        public init(status: String, voiceLabel: String, snippet: String = "") {
            self.status = status
            self.voiceLabel = voiceLabel
            self.snippet = snippet
        }
    }

    public var conversationTitle: String

    public init(conversationTitle: String) {
        self.conversationTitle = conversationTitle
    }
}
#endif
