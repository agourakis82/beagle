import Testing
@testable import BeagleCore
import Foundation
import SwiftData

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
        "graph_runtime": "falkordb-graphblas-bakeoff",
        "retrieval_mode": "graphsearch-lite+vector+graph+temporal",
        "last_world_hash": "sha256:world",
        "latest_agent_write": "beagle_work_memory_capture",
        "graph_degraded_reason": "runtime gated by bake-off",
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
    #expect(snapshot.trustContext?.graphRuntime == "falkordb-graphblas-bakeoff")
    #expect(snapshot.trustContext?.lastWorldHash == "sha256:world")
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
      "degraded_reason": "real embedding backend not configured",
      "mode": "graphsearch-lite",
      "graph_runtime": "falkordb-graphblas-bakeoff",
      "evidence_graph": {
        "nodes": [{"id": "atom-1", "label": "GraphRAG++", "node_type": "decision", "score": 0.9, "provenance": {"source": "test"}}],
        "edges": [{"source": "episode-1", "target": "atom-1", "predicate": "contains_atom", "confidence": 0.9, "provenance": {"source": "test"}}],
        "temporary": true,
        "merkle_root": "sha256:graph"
      },
      "community_context": {
        "strategy": "k-core-density-hierarchy",
        "selected_communities": [{"id": "community-1", "label": "beagle", "strategy": "k-core-density-hierarchy", "node_count": 1, "score": 0.8, "summary": "Beagle memory"}],
        "degraded_reason": null
      },
      "retrieval_trace": [{"stage": "question-analysis", "backend": "deterministic-tokenizer", "status": "ok", "items": 2, "latency_ms": 0.0, "notes": ["mode=graphsearch-lite"]}]
    }
    """.data(using: .utf8)!
    let graph = try JSONDecoder().decode(GraphRagQueryResponse.self, from: graphJson)
    #expect(graph.evidence.first?.atomType == "decision")
    #expect(graph.temporalContext.matchedEpisodeCount == 1)
    #expect(graph.graphRuntime == "falkordb-graphblas-bakeoff")
    #expect(graph.evidenceGraph?.nodes.count == 1)
    #expect(graph.communityContext?.selectedCommunities.first?.label == "beagle")

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

@Test func assistedImportFactoryClassifiesRestrictedContent() throws {
    let safe = AssistedImportRequestFactory.capture(
        text: "Decisão: Memory Lens deve mostrar evidência e proveniência.",
        source: "ios-keyboard",
        projectRef: "beagle"
    )
    #expect(safe.privacyClass == "sensitive")
    #expect(safe.sourceSurface == "beagle-ios")
    #expect(safe.tags.contains("graphrag++"))

    let restricted = AssistedImportRequestFactory.capture(
        text: "client_secret=do-not-upload",
        source: "ios-keyboard",
        projectRef: "beagle"
    )
    #expect(restricted.privacyClass == "restricted")
}

@Test func conversationExchangeRequestCarriesGraphRagMetadata() throws {
    let request = AssistedImportRequestFactory.conversationExchange(
        userText: "Vamos continuar o Beagle.",
        assistantText: "Plano: Home, Watch e Memory Lens em paralelo.",
        sourceSurface: "beagle-apple-cloud",
        sessionId: "chat-session-1",
        projectRef: "beagle",
        model: "beagle-core",
        flowState: "FLOW",
        bodySummary: "readiness high",
        agentKind: "codex",
        podName: "agent-pod"
    )
    let encoded = try JSONEncoder().encode(request)
    let payload = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    #expect(payload?["source_platform"] as? String == "beagle-apple")
    #expect(payload?["source_surface"] as? String == "beagle-apple-cloud")
    #expect(payload?["privacy_class"] as? String == "sensitive")
    #expect((payload?["tags"] as? [String])?.contains("auto-import") == true)
}

@Test func memoryGraphRecentResponseDecodes() throws {
    let json = """
    {
      "generated_at": "2026-04-26T17:00:00Z",
      "status": {
        "status": "fresh",
        "schema_version": "beagle-memory-projection-v1.2",
        "episode_count": 1,
        "atom_count": 1,
        "latest_run": null,
        "freshness": "2026-04-26T17:00:00Z",
        "retrieval_mode": "hybrid lexical+graph+temporal",
        "degraded_reason": "real embedding backend not configured"
      },
      "episodes": [{
        "id": "episode-1",
        "created_at": "2026-04-26T17:00:00Z",
        "source": "assisted-import",
        "source_platform": "beagle-apple",
        "session_id": "chat-1",
        "source_ref": "omnimemory:1",
        "content_hash": "sha256:episode",
        "privacy_class": "sensitive",
        "provenance": {"source_surface": "beagle-ios"},
        "tags": ["project:beagle"],
        "title": "Apple chat",
        "linked_chronoself_commits": [],
        "occurred_at": "2026-04-26T17:00:00Z"
      }],
      "atoms": [{
        "id": "atom-1",
        "created_at": "2026-04-26T17:00:00Z",
        "episode_id": "episode-1",
        "atom_type": "decision",
        "text": "Home, Watch e Memory Lens em paralelo.",
        "normalized_text": "home watch memory lens em paralelo",
        "source_refs": ["omnimemory:1"],
        "relations": [],
        "tags": ["project:beagle"],
        "confidence": 0.91,
        "privacy_class": "sensitive",
        "occurred_at": "2026-04-26T17:00:00Z"
      }],
      "relations": [],
      "worlds": [{
        "id": "world-1",
        "created_at": "2026-04-26T17:00:00Z",
        "world_type": "session",
        "source_ref": "omnimemory:1",
        "title": "Apple chat",
        "merkle_root": "sha256:world",
        "valid_from": "2026-04-26T17:00:00Z",
        "valid_until": null,
        "node_count": 2,
        "edge_count": 1,
        "runtime_hint": "falkordb-graphblas-bakeoff",
        "tags": ["project:beagle"],
        "provenance": {"content_addressed": true}
      }],
      "communities": [{
        "id": "community-1",
        "label": "beagle",
        "strategy": "k-core-density-hierarchy",
        "node_count": 1,
        "score": 0.8,
        "summary": "Beagle community"
      }],
      "provenance": {"canonical_store": "/var/lib/beagle/exocortex"}
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(MemoryGraphRecentResponse.self, from: json)
    #expect(response.status.atomCount == 1)
    #expect(response.atoms.first?.text.contains("Memory Lens") == true)
    #expect(response.worlds?.first?.merkleRoot == "sha256:world")
    #expect(response.communities?.first?.strategy == "k-core-density-hierarchy")
}

@Test func memoryGraphStatusDecodesBakeoffAndWorlds() throws {
    let json = """
    {
      "generated_at": "2026-04-26T18:00:00Z",
      "schema_version": "beagle-graphrag-runtime-v1.4",
      "graph_runtime": "falkordb-graphblas-bakeoff",
      "runtime_status": "bakeoff-design-only",
      "retrieval_mode": "lexical+jsonl+temporal+evidence-graph",
      "canonical_store": "/var/lib/beagle/exocortex",
      "projection_status": {
        "status": "fresh",
        "schema_version": "beagle-memory-projection-v1.2",
        "episode_count": 1,
        "atom_count": 1,
        "latest_run": null,
        "freshness": "2026-04-26T18:00:00Z",
        "retrieval_mode": "hybrid lexical+graph+temporal",
        "degraded_reason": "fallback"
      },
      "latest_bakeoff": {
        "id": "bakeoff-1",
        "created_at": "2026-04-26T18:00:00Z",
        "status": "completed",
        "schema_version": "beagle-graphrag-runtime-v1.4",
        "dataset": {"golden_queries": 20},
        "candidates": [{
          "name": "FalkorDB GraphBLAS",
          "runtime_kind": "graphblas-native-graph-vector",
          "status": "candidate",
          "score": 0.86,
          "metrics": {
            "p95_query_ms": 85,
            "ingest_latency_ms": 120,
            "top5_hit_rate": 0.86,
            "multi_hop_accuracy": 0.82,
            "provenance_quality": 0.92,
            "rebuild_seconds": 18,
            "operational_complexity": 0.34
          },
          "strengths": ["GraphBLAS"],
          "risks": ["needs smoke"],
          "promotion_notes": ["promote after golden queries"]
        }],
        "winner": "FalkorDB GraphBLAS",
        "baseline": "Neo4j+Qdrant baseline",
        "report_ref": "docs/research/beagle_graphrag_runtime_bakeoff.md",
        "degraded_reason": "design metrics"
      },
      "latest_index_run": null,
      "world_count": 3,
      "degraded_reason": "No live graph runtime configured"
    }
    """.data(using: .utf8)!

    let status = try JSONDecoder().decode(MemoryGraphStatus.self, from: json)
    #expect(status.schemaVersion == "beagle-graphrag-runtime-v1.4")
    #expect(status.latestBakeoff?.winner == "FalkorDB GraphBLAS")
    #expect(status.latestBakeoff?.candidates.first?.metrics.top5HitRate == 0.86)
}

@Test func persistenceContainerIncludesAssistedImportOutbox() throws {
    let schema = Schema([
        PersistedThought.self,
        PersistedMessage.self,
        PersistedDeepSession.self,
        PersistedExocortexHomeSnapshot.self,
        PersistedAssistedImportOutbox.self,
    ])
    let container = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let context = ModelContext(container)
    context.insert(PersistedAssistedImportOutbox(
        payload: "{}",
        reason: "restricted_privacy_guard",
        privacyClass: "restricted",
        sourceSurface: "beagle-ios"
    ))
    try context.save()
    let count = try context.fetchCount(FetchDescriptor<PersistedAssistedImportOutbox>())
    #expect(count == 1)
}
