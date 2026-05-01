//
//  AgentActivityStore.swift
//  BeagleCore
//
//  Observable store for the agent scratchpad — inter-agent communication.
//  Polls the cockpit scratchpad endpoint and shows messages from all agents
//  (remote Claude Code, ChatGPT, web cockpit, iOS itself).
//
//  This enables session continuity: when the remote agent deploys a new
//  endpoint, the iOS agent sees it. When iOS discovers a missing API,
//  it can post a request that the remote agent picks up.
//

import Foundation
import Observation

@Observable
@MainActor
public final class AgentActivityStore {

    public var messages: [AgentMessage] = []
    public var isLoading = false
    public var lastRefresh: Date?

    private let cockpit = CockpitClient.shared
    private let slug: String

    public init(slug: String = "sounio") {
        self.slug = slug
    }

    // MARK: - Refresh

    public func refresh() async {
        isLoading = true
        let result = await cockpit.agentScratchpad(slug: slug)
        if let scratchpad = result.value, let entries = scratchpad.entries {
            messages = entries.map { entry in
                AgentMessage(
                    messageId: entry.entryId,
                    agent: entry.agent,
                    surface: nil,
                    kind: nil,
                    content: entry.text,
                    createdAt: entry.timestamp
                )
            }
        }
        lastRefresh = .now
        isLoading = false
    }

    // MARK: - Post

    /// Post a message from this iOS agent to the shared scratchpad.
    /// When `physio` is provided, the user's physiological snapshot is attached
    /// so downstream consumers can distinguish human-in-flow entries from agent entries.
    public func post(kind: String, content: String, physio: PhysioStore? = nil) async -> Bool {
        let cs: ConsciousnessState? = {
            guard let physio else { return nil }
            let posture = physio.cognitivePosture
            guard posture.hrv != nil || posture.readiness != nil else { return nil }
            let hour = Calendar.current.component(.hour, from: .now)
            let phase: String = switch hour {
            case 5..<8: "dawn"
            case 8..<12: "morning"
            case 12..<16: "peak"
            case 16..<19: "afternoon"
            case 19..<22: "evening"
            default: "night"
            }
            return ConsciousnessState(
                hrvMs: posture.hrv,
                readiness: posture.readiness,
                intensity: posture.suggestedIntensity.rawValue,
                circadianPhase: phase
            )
        }()
        let result = await cockpit.postAgentMessage(
            slug: slug,
            agent: "claude-code-ios",
            text: "[\(kind)] \(content)",
            consciousnessState: cs
        )
        if result.value?.ok == true {
            // Refresh to see our own message + any new ones
            await refresh()
            return true
        }
        return false
    }

    /// Announce what we just did (for other agents to see).
    public func announce(_ content: String) async {
        _ = await post(kind: "completed", content: content)
    }

    /// Request something from other agents.
    public func request(_ content: String) async {
        _ = await post(kind: "needs", content: content)
    }

    // MARK: - Derived

    public var recentMessages: [AgentMessage] {
        Array(messages.prefix(20))
    }

    public var agentNames: [String] {
        Array(Set(messages.compactMap(\.agent))).sorted()
    }

    public var hasMessages: Bool { !messages.isEmpty }
}
