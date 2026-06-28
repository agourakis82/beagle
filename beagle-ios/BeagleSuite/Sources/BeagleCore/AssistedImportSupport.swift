//
//  AssistedImportSupport.swift
//  BeagleCore
//
//  Shared helpers for turning Apple, agent, and local-client work into
//  cluster-canonical GraphRAG++ Episode+Atom memory.
//

import Foundation

public enum MemoryPrivacyGuard {
    private static let restrictedNeedles = [
        "client_secret",
        "refresh_token",
        "private key",
        "-----begin",
        "bearer ",
        "api_key",
        "password:",
        "passwd",
        "sk-",
        "xoxb-",
        "ghp_"
    ]

    public static func classify(_ texts: [String]) -> String {
        let joined = texts.joined(separator: "\n").lowercased()
        if restrictedNeedles.contains(where: { joined.contains($0) }) {
            return "restricted"
        }
        return "sensitive"
    }

    public static func isRestricted(_ texts: [String]) -> Bool {
        classify(texts) == "restricted"
    }
}

public enum AssistedImportRequestFactory {
    public static func sourceSurface(for source: String) -> String {
        let normalized = source.lowercased()
        if normalized.hasPrefix("beagle-") {
            return normalized
        }
        if normalized.contains("watch") {
            return "beagle-watchos"
        }
        if normalized.contains("siri") || normalized.contains("shortcut") {
            return "beagle-siri"
        }
        if normalized.contains("share") {
            return "beagle-share-extension"
        }
        if normalized.contains("vision") {
            return "beagle-visionos"
        }
        if normalized.contains("mac") {
            return "beagle-macos"
        }
        if normalized.contains("ipad") {
            return "beagle-ipados"
        }
        if normalized.contains("foundation") {
            return "beagle-foundation-models"
        }
        return "beagle-ios"
    }

    public static func capture(
        text: String,
        source: String,
        projectRef: String? = nil,
        bodySummary: String? = nil,
        metadata: [String: ExocortexJSONValue] = [:]
    ) -> AssistedImportBatchRequest {
        let surface = sourceSurface(for: source)
        let sessionId = "\(surface)-\(UUID().uuidString.lowercased())"
        let privacyClass = MemoryPrivacyGuard.classify([text])
        return AssistedImportBatchRequest(
            sourcePlatform: "beagle-apple",
            sourceSurface: surface,
            importScope: "current_conversation",
            sessionId: sessionId,
            projectRef: projectRef,
            turns: [
                AssistedImportTurn(
                    role: "user",
                    content: text,
                    timestamp: isoTimestamp(),
                    model: nil
                )
            ],
            tags: [
                "apple-capture",
                "surface:\(surface)",
                "graphrag++"
            ],
            metadata: .object(commonMetadata(
                source: source,
                surface: surface,
                bodySummary: bodySummary,
                extra: metadata
            )),
            coverage: .object(["visible_turns": .number(1)]),
            privacyClass: privacyClass,
            title: "Apple capture \(sessionId)",
            confidenceScore: privacyClass == "restricted" ? 0.0 : 0.74
        )
    }

    public static func conversationExchange(
        userText: String,
        assistantText: String,
        sourceSurface: String,
        sessionId: String,
        projectRef: String,
        model: String?,
        flowState: String?,
        bodySummary: String?,
        agentKind: String?,
        podName: String?
    ) -> AssistedImportBatchRequest {
        let privacyClass = MemoryPrivacyGuard.classify([userText, assistantText])
        var metadata = commonMetadata(
            source: "conversation",
            surface: sourceSurface,
            bodySummary: bodySummary,
            extra: [
                "project_slug": .string(projectRef),
                "auto_import": .bool(true)
            ]
        )
        if let flowState, !flowState.isEmpty {
            metadata["flow_state"] = .string(flowState)
        }
        if let agentKind, !agentKind.isEmpty {
            metadata["agent_kind"] = .string(agentKind)
        }
        if let podName, !podName.isEmpty {
            metadata["pod_name"] = .string(podName)
        }

        return AssistedImportBatchRequest(
            sourcePlatform: "beagle-apple",
            sourceSurface: sourceSurface,
            importScope: "current_conversation",
            sessionId: sessionId,
            projectRef: projectRef,
            turns: [
                AssistedImportTurn(role: "user", content: userText, timestamp: isoTimestamp(), model: nil),
                AssistedImportTurn(role: "assistant", content: assistantText, timestamp: isoTimestamp(), model: model)
            ],
            tags: [
                "apple-chat",
                "surface:\(sourceSurface)",
                "project:\(projectRef)",
                "graphrag++",
                "auto-import"
            ],
            metadata: .object(metadata),
            coverage: .object(["visible_turns": .number(2)]),
            privacyClass: privacyClass,
            title: "Apple conversation \(projectRef)",
            confidenceScore: privacyClass == "restricted" ? 0.0 : 0.82
        )
    }

    public static func workMemory(
        _ snapshot: AgentWorkMemorySnapshot,
        toolManifestHash: String? = nil
    ) -> AssistedImportBatchRequest {
        let parts = [
            snapshot.objective.map { "Objective: \($0)" },
            snapshot.planSummary.map { "Plan: \($0)" },
            snapshot.diffSummary.map { "Diff: \($0)" },
            snapshot.testsSummary.map { "Tests: \($0)" },
            snapshot.decisionSummary.map { "Decision: \($0)" }
        ].compactMap { $0 }
        let content = parts.isEmpty ? "Agent work memory event." : parts.joined(separator: "\n")
        let privacyClass = MemoryPrivacyGuard.classify([content])
        var metadata: [String: ExocortexJSONValue] = [
            "principal": .string(snapshot.agentKind),
            "source": .string("agent-work-memory"),
            "surface_claimed": .string(snapshot.agentKind),
            "surface_observed": .string("local_tailnet_full"),
            "project_slug": .string(snapshot.projectSlug),
            "session_id": .string(snapshot.sessionId),
            "repo": snapshot.repo.map(ExocortexJSONValue.string) ?? .null,
            "branch": snapshot.branch.map(ExocortexJSONValue.string) ?? .null
        ]
        if let toolManifestHash, !toolManifestHash.isEmpty {
            metadata["tool_manifest_hash"] = .string(toolManifestHash)
        }
        return AssistedImportBatchRequest(
            sourcePlatform: "beagle-work-memory",
            sourceSurface: snapshot.agentKind,
            importScope: "agent_work_session",
            sessionId: snapshot.sessionId,
            projectRef: snapshot.projectSlug,
            turns: [
                AssistedImportTurn(
                    role: "system",
                    content: content,
                    timestamp: snapshot.createdAt,
                    model: snapshot.agentKind
                )
            ],
            tags: [
                "work-memory",
                "agent:\(snapshot.agentKind)",
                "project:\(snapshot.projectSlug)",
                "graphrag++"
            ],
            metadata: .object(metadata),
            coverage: .object(["visible_turns": .number(1)]),
            privacyClass: privacyClass,
            title: "Work memory \(snapshot.agentKind) \(snapshot.projectSlug)",
            originalDate: snapshot.createdAt,
            confidenceScore: privacyClass == "restricted" ? 0.0 : 0.86
        )
    }

    public static func isoTimestamp(_ date: Date = .now) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func commonMetadata(
        source: String,
        surface: String,
        bodySummary: String?,
        extra: [String: ExocortexJSONValue]
    ) -> [String: ExocortexJSONValue] {
        var metadata: [String: ExocortexJSONValue] = [
            "principal": .string("beagle-apple-app"),
            "source": .string(source),
            "surface_claimed": .string(surface),
            "surface_observed": .string("beagle-apple-client")
        ]
        if let bodySummary, !bodySummary.isEmpty {
            metadata["body_summary"] = .string(bodySummary)
        }
        for (key, value) in extra {
            metadata[key] = value
        }
        return metadata
    }
}
