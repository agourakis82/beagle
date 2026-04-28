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
        "last_audit_event_id": "audit-1",
        "memory_governor_status": "healthy",
        "pending_triads": 2,
        "open_contradictions": 1,
        "latest_promotion_decision": "promoted",
        "semantic_backbone_status": "native-semantic-backbone-v2.1",
        "hot_path_mode": "hypermemory_multivector",
        "provisional_hot_path": true,
        "portfolio_truth_gate": "truthset:portfolio:provisional_hot_path"
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: json)

    #expect(snapshot.agentContext?.mcpStatus == "audited")
    #expect(snapshot.agentContext?.lastAgentWrite == "beagle_memory_ingest_chat")
    #expect(snapshot.trustContext?.activeScopes.contains("memory:write") == true)
    #expect(snapshot.trustContext?.toolManifestHash == "sha256:abc")
    #expect(snapshot.trustContext?.memoryGovernorStatus == "healthy")
    #expect(snapshot.trustContext?.pendingTriads == 2)
    #expect(snapshot.trustContext?.openContradictions == 1)
    #expect(snapshot.trustContext?.latestPromotionDecision == "promoted")
    #expect(snapshot.trustContext?.semanticBackboneStatus == "native-semantic-backbone-v2.1")
    #expect(snapshot.trustContext?.hotPathMode == "hypermemory_multivector")
    #expect(snapshot.trustContext?.provisionalHotPath == true)
    #expect(snapshot.trustContext?.portfolioTruthGate?.contains("portfolio") == true)
}

@Test func memoryGovernanceStatusDecodesTriadStrictState() throws {
    let json = """
    {
      "schema_version": "beagle-self-governing-memory-v1.6",
      "status": "healthy",
      "retrieval_policy": "promoted-only-active-search",
      "latest_run": {
        "id": "gov-1",
        "created_at": "2026-04-27T12:00:00Z",
        "schema_version": "beagle-self-governing-memory-v1.6",
        "status": "completed",
        "candidates_evaluated": 3,
        "triad_pending": 1,
        "promoted": 1,
        "rejected": 1,
        "contradictions_found": 1,
        "quality_scores_written": 3,
        "hard_gates": {"triad_strict_required": true},
        "degraded_reason": "none"
      },
      "candidate_count": 4,
      "pending_triads": 1,
      "promoted_count": 2,
      "rejected_count": 1,
      "open_contradictions": 1,
      "latest_promotion_decision": {
        "id": "prom-1",
        "created_at": "2026-04-27T12:01:00Z",
        "candidate_id": "cand-1",
        "quorum_id": "quorum-1",
        "decision": "promoted",
        "status": "promoted",
        "promoted_atom_id": "atom-1",
        "quality_score": {
          "id": "quality-1",
          "created_at": "2026-04-27T12:01:00Z",
          "candidate_id": "cand-1",
          "provenance_score": 1.0,
          "temporal_score": 0.9,
          "critical_score": 0.8,
          "restricted_risk": 0.0,
          "contradiction_risk": 0.0,
          "overall": 0.94,
          "rationale": "complete provenance"
        },
        "rationale": "strict 3/3",
        "reviewer": "triad",
        "evidence_refs": ["cand-1"]
      }
    }
    """.data(using: .utf8)!

    let status = try JSONDecoder().decode(MemoryGovernanceStatus.self, from: json)
    #expect(status.status == "healthy")
    #expect(status.latestRun?.triadPending == 1)
    #expect(status.latestPromotionDecision?.qualityScore?.overall == 0.94)
    #expect(status.openContradictions == 1)
}

@Test func memoryContradictionsDecodeForTriadReview() throws {
    let json = """
    {
      "contradictions": [{
        "id": "contradiction-1",
        "created_at": "2026-04-27T12:02:00Z",
        "subject_ref": "memory_candidate:cand-2",
        "conflicting_ref": "memory_atom:atom-old",
        "description": "New candidate says deploy now, old promoted atom says gated deploy.",
        "severity": "medium",
        "evidence_refs": ["atom-old", "cand-2"],
        "status": "open",
        "detected_by": "memory-governor-v1.6"
      }]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(MemoryContradictionListResponse.self, from: json)
    #expect(response.contradictions.first?.subjectRef == "memory_candidate:cand-2")
    #expect(response.contradictions.first?.status == "open")
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
        "memory_engine_status": "healthy",
        "latest_candidate_ref": "candidate-1",
        "latest_quorum_status": "approved",
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
    #expect(snapshot.trustContext?.memoryEngineStatus == "healthy")
    #expect(snapshot.trustContext?.latestCandidateRef == "candidate-1")
    #expect(snapshot.trustContext?.latestQuorumStatus == "approved")
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
      "retrieval_trace": [{"stage": "question-analysis", "backend": "deterministic-tokenizer", "status": "ok", "items": 2, "latency_ms": 0.0, "notes": ["mode=graphsearch-lite"]}],
      "mesh_trace": [{"stage": "federation", "backend": "beagle-memory-engine", "status": "shadow", "items": 1, "latency_ms": 12.5, "notes": ["adaptive shortlist"]}],
      "runtime_votes": [{"runtime": "falkordb", "role": "graphblas-hot-path", "status": "available", "score": 0.88, "notes": ["vector+graph"]}],
      "candidate_refs": ["candidate-1"],
      "runtime_used": "lancedb-multivector+jina-colbert-v2",
      "fallback_chain": ["lancedb-multivector+jina-colbert-v2", "hypermemory", "graphsearch-lite"],
      "semantic_trace": [{"stage": "late-interaction-search", "backend": "LanceDB multivector + jinaai/jina-colbert-v2", "status": "ready", "items": 1, "latency_ms": 0.0, "notes": ["MaxSim"]}],
      "maxsim_scores": [{"atom_id": "atom-1", "score": 0.91}],
      "graph_expansion": {"node_count": 1, "edge_count": 1, "strategy": "MemoryWorld+Hyperedge+Relink-lite"},
      "reranker_scores": [{"atom_id": "atom-1", "score": 0.9, "reranker": "temporal-confidence-provenance"}],
      "truthset_gate_status": {
        "truthset_id": "truth-v20",
        "portfolio_truthset_id": "truthset:portfolio",
        "hot_path_mode": "hypermemory_multivector",
        "provisional_hot_path": true,
        "confirmed_passing": false,
        "required_confirmed_runs": 3,
        "required_margin": 0.05,
        "policy": "provisional"
      },
      "restricted_leak_check": {"restricted_leak_count": 0, "passed": true}
    }
    """.data(using: .utf8)!
    let graph = try JSONDecoder().decode(GraphRagQueryResponse.self, from: graphJson)
    #expect(graph.evidence.first?.atomType == "decision")
    #expect(graph.temporalContext.matchedEpisodeCount == 1)
    #expect(graph.graphRuntime == "falkordb-graphblas-bakeoff")
    #expect(graph.evidenceGraph?.nodes.count == 1)
    #expect(graph.communityContext?.selectedCommunities.first?.label == "beagle")
    #expect(graph.meshTrace.first?.backend == "beagle-memory-engine")
    #expect(graph.runtimeVotes.first?.runtime == "falkordb")
    #expect(graph.candidateRefs == ["candidate-1"])
    #expect(graph.runtimeUsed == "lancedb-multivector+jina-colbert-v2")
    #expect(graph.fallbackChain.contains("hypermemory"))
    #expect(graph.semanticTrace.first?.status == "ready")
    #expect(graph.maxsimScores.count == 1)
    #expect(graph.graphExpansion != nil)
    #expect(graph.rerankerScores.count == 1)
    #expect(graph.truthsetGateStatus?.provisionalHotPath == true)

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

@Test func memoryCandidateListDecodesTriadState() throws {
    let json = """
    {
      "candidates": [{
        "id": "candidate-1",
        "created_at": "2026-04-26T18:00:00Z",
        "candidate_type": "hyperedge",
        "text": "FalkorDB should be promoted only after bake-off gates pass.",
        "normalized_text": "falkordb should be promoted only after bake-off gates pass.",
        "source_refs": ["memory-engine:run-1"],
        "relations": [{"subject": "falkordb", "predicate": "requires", "object": "bakeoff", "confidence": 0.91}],
        "tags": ["candidate", "graphrag++", "v1.5"],
        "provenance": {"runtime": "beagle-memory-engine"},
        "confidence": 0.82,
        "privacy_class": "sensitive",
        "status": "candidate",
        "quorum_ref": "quorum-1",
        "promoted_atom_id": null
      }]
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(MemoryCandidateListResponse.self, from: json)
    #expect(decoded.candidates.first?.candidateType == "hyperedge")
    #expect(decoded.candidates.first?.relations.first?.predicate == "requires")
    #expect(decoded.candidates.first?.quorumRef == "quorum-1")
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

@Test func memoryBenchmarkStatusDecodesCoreAndEngineShapes() throws {
    let coreJson = """
    {
      "generated_at": "2026-04-27T12:00:00Z",
      "schema_version": "beagle-memory-truth-hypermemory-v1.9",
      "status": "passing",
      "latest_run_id": "bench-1",
      "truthset_id": "truth-v19",
      "latest_score": 0.84,
      "query_count": 100,
      "hard_gates": {"restricted_leak_zero": true, "provenance_complete": true},
      "evaluated_modes": ["graphsearch-lite", "hypermemory"],
      "regression_count": 0,
      "artifact_manifest": "/orangefs/beagle-memory-lab/bench-1/manifest.json",
      "hot_path_eligible": true,
      "provisional_hot_path": false,
      "hot_path_mode": "hypermemory_multivector",
      "confirmed_passing_runs": 3,
      "portfolio_truthset_id": "truthset:portfolio",
      "promotion_gate": {
        "baseline_mode": "graphsearch-lite",
        "candidate_mode": "hypermemory",
        "required_margin": 0.05,
        "baseline_score": 0.78,
        "candidate_score": 0.84,
        "consecutive_passing_runs": 3,
        "required_consecutive_runs": 3,
        "hard_gates_passed": true,
        "eligible": true,
        "rationale": "candidate passed"
      }
    }
    """.data(using: .utf8)!

    let coreStatus = try JSONDecoder().decode(MemoryBenchmarkStatus.self, from: coreJson)
    #expect(coreStatus.status == "passing")
    #expect(coreStatus.latestScore == 0.84)
    #expect(coreStatus.evaluatedModes.contains("hypermemory"))
    #expect(coreStatus.truthsetId == "truth-v19")
    #expect(coreStatus.hotPathEligible == true)
    #expect(coreStatus.hotPathMode == "hypermemory_multivector")
    #expect(coreStatus.confirmedPassingRuns == 3)
    #expect(coreStatus.portfolioTruthsetId == "truthset:portfolio")
    #expect(coreStatus.promotionGate?.eligible == true)

    let engineJson = """
    {
      "generated_at": "2026-04-27T12:01:00Z",
      "schema_version": "beagle-federated-memory-engine-v1.9",
      "status": "passing",
      "truthset_id": "truth-v19",
      "latest_score": 0.83,
      "regression_count": 0,
      "evaluated_modes": ["graphsearch-lite", "hypermemory", "adaptive-federation"],
      "hard_gates": {"restricted_leak_zero": true},
      "hot_path_eligible": false,
      "provisional_hot_path": true,
      "hot_path_mode": "hypermemory_multivector",
      "confirmed_passing_runs": 1,
      "portfolio_truthset_id": "truth-v19",
      "promotion_gate": {
        "baseline_mode": "graphsearch-lite",
        "candidate_mode": "hypermemory",
        "required_margin": 0.05,
        "baseline_score": 0.74,
        "candidate_score": 0.83,
        "consecutive_passing_runs": 1,
        "required_consecutive_runs": 3,
        "hard_gates_passed": true,
        "eligible": false,
        "rationale": "needs consecutive runs"
      },
      "latest_run": {
        "id": "bench-2",
        "created_at": "2026-04-27T12:01:00Z",
        "status": "passing",
        "schema_version": "beagle-federated-memory-engine-v1.9",
        "truthset_id": "truth-v19",
        "query_count": 100,
        "domains": ["work-memory"],
        "judge_mode": "truthset-deterministic-plus-blind-llm-ready",
        "baseline_mode": "graphsearch-lite",
        "candidate_modes": ["hypermemory"],
        "hard_gates": {"restricted_leak_zero": true},
        "mode_results": [{
          "mode": "hypermemory",
          "status": "advisory-pass",
          "score": 0.83,
          "metrics": {
            "top_k_hit_rate": 0.82,
            "exact_support": 0.84,
            "multi_hop_correctness": 0.78,
            "temporal_correctness": 0.80,
            "provenance_completeness": 0.88,
            "contradiction_safety": 0.82,
            "implicit_recall": 0.82,
            "restricted_leak_count": 0,
            "p95_latency_ms": 240,
            "blind_judge_depth": 0.81
          },
          "notes": ["cluster-only"]
        }],
        "case_judgments": [{
          "case_id": "case-1",
          "domain": "work-memory",
          "query": "qual foi a última decisão do Codex?",
          "passed": true,
          "score": 0.86,
          "baseline_support": 0.78,
          "candidate_support": 0.86,
          "regression": false,
          "supporting_refs": ["repo", "branch"],
          "notes": ["cluster-only"]
        }],
        "winning_mode": "hypermemory",
        "regression_count": 0,
        "promotion_gate": {
          "baseline_mode": "graphsearch-lite",
          "candidate_mode": "hypermemory",
          "required_margin": 0.05,
          "baseline_score": 0.74,
          "candidate_score": 0.83,
          "consecutive_passing_runs": 1,
          "required_consecutive_runs": 3,
          "hard_gates_passed": true,
          "eligible": false,
          "rationale": "needs consecutive runs"
        },
        "hot_path_eligible": false,
        "artifact_manifest": "/orangefs/beagle-memory-lab/bench-2/manifest.json",
        "degraded_reason": "cluster-only"
      }
    }
    """.data(using: .utf8)!

    let engineStatus = try JSONDecoder().decode(MemoryBenchmarkStatus.self, from: engineJson)
    #expect(engineStatus.latestRun?.modeResults.first?.mode == "hypermemory")
    #expect(engineStatus.latestRun?.modeResults.first?.metrics?.restrictedLeakCount == 0)
    #expect(engineStatus.latestRun?.modeResults.first?.metrics?.exactSupport == 0.84)
    #expect(engineStatus.latestRun?.caseJudgments.first?.domain == "work-memory")
    #expect(engineStatus.promotionGate?.candidateMode == "hypermemory")
    #expect(engineStatus.provisionalHotPath == true)
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
