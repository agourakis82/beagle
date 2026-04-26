import Testing
@testable import BeagleCore
import Foundation

@Test func truthModeValues() {
    #expect(TruthMode.observed.rawValue == "observed")
    #expect(TruthMode.remembered.rawValue == "remembered")
    #expect(TruthMode.declared.rawValue == "declared")
}

@Test func postureCountsInit() {
    let counts = PostureCounts(totalProjects: 5, alwaysOn: 1, warm: 2, cold: 2)
    #expect(counts.totalProjects == 5)
    #expect(counts.alwaysOn == 1)
    #expect(PostureCounts.empty.totalProjects == 0)
}

@Test func agentSessionPhaseMapping() {
    let running = AgentSession(
        kind: "claude-code",
        name: "sounio-claude-code",
        replicas: 1,
        readyReplicas: 1,
        createdAt: nil,
        pods: nil,
        status: "running",
        truthMode: "observed",
        action: nil
    )
    #expect(running.phase == .running)

    let paused = AgentSession(
        kind: "claude-code",
        name: "sounio-claude-code",
        replicas: 0,
        readyReplicas: 0,
        createdAt: nil,
        pods: nil,
        status: "paused",
        truthMode: "observed",
        action: nil
    )
    #expect(paused.phase == .paused)

    let pending = AgentSession(
        kind: "claude-code",
        name: "sounio-claude-code",
        replicas: 1,
        readyReplicas: 0,
        createdAt: nil,
        pods: [AgentPod(name: "pod-1", phase: "Pending", ready: false)],
        status: "creating",
        truthMode: "observed",
        action: "resume"
    )
    #expect(pending.phase == .pending)
}

@Test func beagleBackendErrorPayloadMessageIncludesStructuredFields() throws {
    let payload = BeagleBackendErrorPayload(
        error: "unauthorized",
        reason: "invalid or missing API token",
        truthMode: "stale",
        requestId: "req-123",
        caller: "ios",
        via: "auth-bridge",
        proxiedPath: "/api/auth/beagle-token"
    )

    let message = payload.message(statusCode: 401, fallback: "HTTP 401")

    #expect(message.contains("HTTP 401"))
    #expect(message.contains("unauthorized"))
    #expect(message.contains("invalid or missing API token"))
    #expect(message.contains("truth=stale"))
    #expect(message.contains("requestId=req-123"))
    #expect(message.contains("caller=ios"))
    #expect(message.contains("via=auth-bridge"))
    #expect(message.contains("path=/api/auth/beagle-token"))
}

@Test func cockpitBackendErrorPayloadMessageIncludesRequestId() {
    let payload = CockpitBackendErrorPayload(
        error: "session resume failed",
        reason: nil,
        truthMode: "stale",
        requestId: "resume-42"
    )

    let message = payload.message(statusCode: 503, fallback: "HTTP 503")

    #expect(message.contains("HTTP 503"))
    #expect(message.contains("session resume failed"))
    #expect(message.contains("truth=stale"))
    #expect(message.contains("requestId=resume-42"))
}

@Test func exocortexHomeDecodesLegacySnapshotWithoutTrustContext() throws {
    let json = """
    {
      "generated_at": "2026-04-25T12:00:00Z",
      "today_brief": "Legacy home",
      "current_self": {
        "id": "v1",
        "label": "Legacy Self",
        "period_start": "2026-04-25T12:00:00Z",
        "period_end": null,
        "dominant_beliefs": [],
        "core_values": [],
        "cognitive_style": "continuity",
        "risk_tolerance": 0.5,
        "source_commit_id": null
      },
      "memory_signals": [],
      "open_loops": [],
      "active_project_ref": "sounio",
      "body_context": null,
      "recommended_next_action": "Continue",
      "cluster_truth": "observed",
      "omnimemory_status": "0 imports indexed",
      "temporal_phase": null
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: json)

    #expect(snapshot.currentSelf.label == "Legacy Self")
    #expect(snapshot.agentContext == nil)
    #expect(snapshot.trustContext == nil)
}

@Test func exocortexHomeDecodesTrustAndAgentContext() throws {
    let json = """
    {
      "generated_at": "2026-04-25T12:00:00Z",
      "today_brief": "Audited home",
      "current_self": {
        "id": "v1",
        "label": "Audited Self",
        "period_start": "2026-04-25T12:00:00Z",
        "period_end": null,
        "dominant_beliefs": [],
        "core_values": [],
        "cognitive_style": "continuity",
        "risk_tolerance": 0.5,
        "source_commit_id": null
      },
      "memory_signals": ["MCP wrote memory"],
      "open_loops": [],
      "active_project_ref": "sounio",
      "body_context": "iPhone 17 Pro Max + Apple Watch Ultra 2",
      "recommended_next_action": "Review audit",
      "cluster_truth": "observed",
      "omnimemory_status": "1 imports indexed",
      "temporal_phase": "Integration",
      "agent_context": {
        "active_sessions": 1,
        "recent_observations": ["Stored memory"],
        "last_agent_write": "beagle_memory_ingest_chat",
        "mcp_status": "audited"
      },
      "trust_context": {
        "mcp_status": "audit-log-observed",
        "active_scopes": ["exocortex:read", "memory:write"],
        "audit_freshness": "2026-04-25T12:00:00Z",
        "destructive_actions": "locked",
        "tool_manifest_hash": "sha256:abc",
        "last_audit_event_id": "audit-1"
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: json)

    #expect(snapshot.agentContext?.mcpStatus == "audited")
    #expect(snapshot.agentContext?.lastAgentWrite == "beagle_memory_ingest_chat")
    #expect(snapshot.trustContext?.activeScopes.contains("memory:write") == true)
    #expect(snapshot.trustContext?.toolManifestHash == "sha256:abc")
}

@Test func exocortexHomeDecodesMemoryProjectionStatus() throws {
    let json = """
    {
      "generated_at": "2026-04-26T16:30:00Z",
      "today_brief": "Projected home",
      "current_self": {
        "id": "v1",
        "label": "GraphRAG Self",
        "period_start": "2026-04-26T16:30:00Z",
        "period_end": null,
        "dominant_beliefs": [],
        "core_values": [],
        "cognitive_style": "continuity",
        "risk_tolerance": 0.5,
        "source_commit_id": null
      },
      "memory_signals": ["decision: GraphRAG++ first"],
      "open_loops": [],
      "active_project_ref": "beagle",
      "body_context": null,
      "recommended_next_action": "Continue",
      "cluster_truth": "observed",
      "omnimemory_status": "1 imports, 1 episodes, 2 atoms projected",
      "temporal_phase": null,
      "trust_context": {
        "mcp_status": "audit-log-observed",
        "active_scopes": ["exocortex:read"],
        "audit_freshness": "2026-04-26T16:30:00Z",
        "destructive_actions": "locked",
        "tool_manifest_hash": "sha256:e633",
        "last_audit_event_id": "audit-1",
        "memory_projection_status": {
          "status": "fresh",
          "schema_version": "beagle-memory-projection-v1.2",
          "episode_count": 1,
          "atom_count": 2,
          "latest_run": {
            "id": "run-1",
            "created_at": "2026-04-26T16:30:00Z",
            "schema_version": "beagle-memory-projection-v1.2",
            "source_count": 1,
            "episodes_created": 1,
            "atoms_created": 2,
            "duplicates": 0,
            "errors": [],
            "projection_hash": "sha256:projection",
            "status": "projected",
            "degraded_reason": "lexical+graph+temporal"
          },
          "freshness": "2026-04-26T16:30:00Z",
          "retrieval_mode": "hybrid lexical+graph+temporal",
          "degraded_reason": "real embedding backend not configured"
        }
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: json)

    #expect(snapshot.trustContext?.memoryProjectionStatus?.atomCount == 2)
    #expect(snapshot.trustContext?.memoryProjectionStatus?.latestRun?.projectionHash == "sha256:projection")
}

@Test func graphRagAndAssistedImportModelsDecodeClusterContracts() throws {
    let graphJson = """
    {
      "summary": "Found 1 GraphRAG++ projected memory match.",
      "evidence": [{
        "atom_id": "atom-1",
        "episode_id": "episode-1",
        "atom_type": "decision",
        "text": "GraphRAG++ persistente primeiro.",
        "score": 0.9,
        "source_refs": ["omnimemory:1"],
        "provenance": {"source_surface": "claude-ios"}
      }],
      "atoms": [],
      "episodes": [],
      "relations": [{"subject": "beagle", "predicate": "has_episode", "object": "episode-1", "confidence": 0.72}],
      "temporal_context": {
        "newest_evidence_at": "2026-04-26T16:30:00Z",
        "oldest_evidence_at": "2026-04-26T16:30:00Z",
        "matched_episode_count": 1
      },
      "provenance": {"retrieval_mode": "hybrid lexical+graph+temporal"},
      "confidence": 0.9,
      "degraded_reason": "real embedding backend not configured"
    }
    """.data(using: .utf8)!
    let graph = try JSONDecoder().decode(GraphRagQueryResponse.self, from: graphJson)
    #expect(graph.evidence.first?.atomType == "decision")
    #expect(graph.temporalContext.matchedEpisodeCount == 1)

    let request = AssistedImportBatchRequest(
        sourcePlatform: "claude",
        sourceSurface: "claude-ios",
        sessionId: "visible-1",
        turns: [AssistedImportTurn(role: "user", content: "Import this visible context")],
        tags: ["surface:claude-ios"]
    )
    let encoded = try JSONEncoder().encode(request)
    let payload = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    #expect(payload?["source_platform"] as? String == "claude")
    #expect(payload?["source_surface"] as? String == "claude-ios")
    #expect(payload?["privacy_class"] as? String == "sensitive")
}

@Test func mcpPKCEURLDoesNotNeedClientSecret() throws {
    let request = try #require(BeagleMCPClient.auth0PKCEAuthorizationURL(
        domain: "beagle-mcp.us.auth0.com",
        clientId: "native-client-id",
        redirectURI: "beagle://auth/callback"
    ))
    let absolute = request.authorizationURL.absoluteString
    #expect(absolute.contains("code_challenge="))
    #expect(absolute.contains("code_challenge_method=S256"))
    #expect(!absolute.contains("client_secret"))
    #expect(request.codeVerifier.count >= 43)
}
