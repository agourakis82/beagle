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
    public func post(kind: String, content: String) async -> Bool {
        let result = await cockpit.postAgentMessage(
            slug: slug,
            agent: "claude-code-ios",
            text: "[\(kind)] \(content)"
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
