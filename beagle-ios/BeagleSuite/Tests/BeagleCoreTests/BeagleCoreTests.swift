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

@Test func workspaceAgentAuthorityDecodesBackwardCompatibly() throws {
    let json = """
    {
      "projectSlug": "sounio",
      "authority": {
        "authority": "workspace-agent",
        "fallback": "cockpit-local",
        "persistence": "workspace-pvc",
        "workbenchDir": "/workspace/.beagle/workbench",
        "workspaceRoot": "/workspace/sounio",
        "protocol": "beagle-terminal-v1",
        "bridgeVersion": "beagle-warp-bridge-v0.2",
        "supervisor": {
          "status": "healthy",
          "runtime": "beagle-pty-supervisor-v1",
          "panes": 1,
          "url": "http://127.0.0.1:4372",
          "updatedAt": "2026-04-30T20:00:00Z"
        },
        "updatedAt": "2026-04-30T20:00:00Z"
      },
      "sessions": [{
        "id": "wb-test",
        "projectSlug": "sounio",
        "title": "Sounio Workbench",
        "status": "active",
        "layout": "notebook",
        "createdAt": "2026-04-30T20:00:00Z",
        "updatedAt": "2026-04-30T20:00:00Z",
        "lastAttachedAt": "2026-04-30T20:00:01Z",
        "lastMemoryStatus": null,
        "sourceModel": "beagle",
        "bridgeVersion": "beagle-warp-bridge-v0.2",
        "sessionHash": "sha256:test",
        "rendererHint": "beagle-terminal-v1",
        "authorityStatus": {
          "authority": "workspace-agent",
          "persistence": "workspace-pvc",
          "supervisor": { "status": "healthy", "runtime": "beagle-pty-supervisor-v1", "panes": 1 }
        },
        "panes": [{
          "id": "pane-main",
          "title": "Shell",
          "kind": "human",
          "status": "attached",
          "createdAt": "2026-04-30T20:00:00Z",
          "lastAttachedAt": "2026-04-30T20:00:01Z",
          "cwd": "/workspace/sounio",
          "reconnectState": "attached",
          "agent": null
        }]
      }]
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(WorkspaceSessionListResponse.self, from: json)

    #expect(decoded.authority?.authority == "workspace-agent")
    #expect(decoded.authority?.supervisor?.runtime == "beagle-pty-supervisor-v1")
    #expect(decoded.sessions.first?.authorityStatus?.supervisor?.status == "healthy")
    #expect(decoded.sessions.first?.panes.first?.reconnectState == "attached")
}

@Test func workspaceLegacySessionStillDecodesWithoutAuthority() throws {
    let json = """
    {
      "projectSlug": "sounio",
      "sessions": [{
        "id": "wb-legacy",
        "projectSlug": "sounio",
        "title": "Legacy Workbench",
        "status": "active",
        "layout": "notebook",
        "createdAt": "",
        "updatedAt": "",
        "lastAttachedAt": "",
        "lastMemoryStatus": null,
        "panes": [{
          "id": "pane-main",
          "title": "Shell",
          "kind": "human",
          "status": "idle",
          "createdAt": "",
          "lastAttachedAt": "",
          "cwd": "",
          "agent": null
        }]
      }]
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(WorkspaceSessionListResponse.self, from: json)

    #expect(decoded.authority == nil)
    #expect(decoded.sessions.first?.authorityStatus == nil)
    #expect(decoded.sessions.first?.panes.first?.reconnectState == nil)
}

@Test func originLineageLocalSeedIsSanitizedAndClaimOnly() {
    let seed = OriginLineageSnapshot.localSeed

    #expect(seed.nodes.map(\.title) == ["RAG++", "Darwin", "Beagle", "Sounio"])
    #expect(seed.edges.count == 3)
    #expect(seed.evidenceRefs.count == 4)
    #expect(seed.tensions.count == 4)
    #expect(seed.claimSeeds.count == 4)
    #expect(seed.sourcePolicy.contains("sanitized_local_seed"))

    let promotedStatuses = seed.claimSeeds.compactMap(\.epistemicStatus).filter {
        $0 == "knowledge" || $0 == "robust"
    }
    #expect(promotedStatuses.isEmpty)
    #expect(seed.claimSeeds.allSatisfy { $0.publicationReadiness == "not_ready" })
    #expect(seed.claimSeeds.allSatisfy { $0.privacyClass == "sensitive" })

    let joinedSeedText = (
        seed.nodes.flatMap { [$0.title, $0.subtitle, $0.sourceFamily, $0.tension, $0.nextAction] }
            + seed.evidenceRefs.flatMap { [$0.id, $0.label, $0.sourceFamily, $0.visibility] }
            + seed.claimSeeds.flatMap { [$0.claimText, $0.rationale ?? ""] }
    ).joined(separator: "\n")

    #expect(!joinedSeedText.contains("/Users/"))
    #expect(!joinedSeedText.localizedCaseInsensitiveContains("client_secret"))
    #expect(!joinedSeedText.localizedCaseInsensitiveContains("raw transcript"))
}

@Test func exocortexHomeDecodesFutureOriginLineageSnapshot() throws {
    let json = """
    {
      "generated_at": "2026-04-28T12:00:00Z",
      "today_brief": "Origin-aware home",
      "current_self": {
        "id": "v1",
        "label": "Origin Self",
        "period_start": "2026-04-28T12:00:00Z",
        "period_end": null,
        "dominant_beliefs": [],
        "core_values": [],
        "cognitive_style": "continuity",
        "risk_tolerance": 0.5,
        "source_commit_id": null
      },
      "memory_signals": ["RAG++ became Darwin"],
      "open_loops": [],
      "active_project_ref": "beagle",
      "body_context": null,
      "recommended_next_action": "Review origin claims",
      "cluster_truth": "observed",
      "omnimemory_status": "origin lineage projected",
      "temporal_phase": "origin archaeology",
      "origin_lineage": {
        "generated_at": "2026-04-28T12:00:00Z",
        "source_policy": "cluster_canonical_origin_lineage",
        "nodes": [{
          "id": "ragpp-mestrado",
          "title": "RAG++",
          "subtitle": "Mestrado",
          "state": "origin",
          "first_known_at": "2025-08-30",
          "source_family": "ChatGPT export digest",
          "tension": "retrieval had to become memory",
          "next_action": "Attach reviewed evidence",
          "evidence_refs": ["origin:cluster:ragpp"],
          "claim_seed_id": "claim-origin-ragpp"
        }],
        "edges": [],
        "evidence_refs": [{
          "id": "origin:cluster:ragpp",
          "label": "Reviewed RAG++ origin digest",
          "source_family": "cluster-origin-lineage",
          "visibility": "sanitized_digest_ok",
          "first_observed_at": "2026-04-28"
        }],
        "tensions": [{
          "id": "tension-rag-exocortex",
          "title": "RAG vs exocortex",
          "detail": "RAG alone did not preserve identity continuity.",
          "status": "active"
        }],
        "claim_seeds": [{
          "id": "claim-origin-ragpp",
          "claim_text": "Beagle began as RAG++ memory archaeology.",
          "subject": "Beagle origin",
          "value_type": "Claim<T>",
          "epistemic_status": "belief",
          "evidence_refs": ["origin:cluster:ragpp"],
          "provenance": {"source": "cluster_origin_lineage"},
          "confidence": 0.65,
          "contestation": {},
          "review_state": "seeded",
          "promotion_rule": "requires_human_review",
          "publication_readiness": "not_ready",
          "section_id": "origin",
          "agent_refs": [],
          "contract_refs": [],
          "artifact_refs": [],
          "chronoself_commit_refs": [],
          "privacy_class": "sensitive",
          "rationale": "Cluster-provided but still candidate-only."
        }]
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: json)

    #expect(snapshot.originLineage?.sourcePolicy == "cluster_canonical_origin_lineage")
    #expect(snapshot.originLineage?.nodes.first?.title == "RAG++")
    #expect(snapshot.originLineage?.evidenceRefs.first?.visibility == "sanitized_digest_ok")
    #expect(snapshot.originLineage?.tensions.first?.title == "RAG vs exocortex")
    #expect(snapshot.originLineage?.claimSeeds.first?.epistemicStatus == "belief")
    #expect(snapshot.originLineage?.claimSeeds.first?.publicationReadiness == "not_ready")
}

@Test func exocortexHomeDecodesFutureContinuityContext() throws {
    let json = """
    {
      "generated_at": "2026-04-29T12:00:00Z",
      "today_brief": "Living home",
      "current_self": {
        "id": "v1",
        "label": "Living Self",
        "period_start": "2026-04-29T12:00:00Z",
        "period_end": null,
        "dominant_beliefs": [],
        "core_values": [],
        "cognitive_style": "continuity",
        "risk_tolerance": 0.5,
        "source_commit_id": null
      },
      "memory_signals": [],
      "open_loops": [],
      "active_project_ref": "beagle",
      "body_context": null,
      "recommended_next_action": "Open Memory Lens",
      "cluster_truth": "observed",
      "omnimemory_status": "projected",
      "temporal_phase": "Home Viva",
      "continuity_context": {
        "generated_at": "2026-04-29T12:00:00Z",
        "mode": "live",
        "changed_since_last_open": [{
          "id": "latest-agent-write",
          "title": "Agent wrote memory",
          "detail": "codex summary",
          "kind": "agent_write",
          "source_surface": "codex",
          "observed_at": "2026-04-29T12:00:00Z",
          "truth_mode": "observed",
          "provenance_refs": ["audit-1"]
        }],
        "latest_surface_write": {
          "id": "latest-agent-write",
          "title": "Agent wrote memory",
          "detail": "codex summary",
          "kind": "agent_write",
          "source_surface": "codex",
          "observed_at": "2026-04-29T12:00:00Z",
          "truth_mode": "observed",
          "provenance_refs": ["audit-1"]
        },
        "active_thread": "beagle",
        "primary_next_action": {
          "id": "open-memory-lens",
          "title": "Open Memory Lens",
          "detail": "Agent wrote memory",
          "action": "open_memory_lens",
          "system_image": "point.3.connected.trianglepath.dotted",
          "reason": "Inspect fresh provenance.",
          "priority": 70,
          "target": "beagle"
        },
        "alternative_next_actions": [],
        "why_this_now": "Fresh agent write.",
        "confidence": 0.91,
        "source_mode": "cluster"
      }
    }
    """.data(using: .utf8)!

    let snapshot = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: json)

    #expect(snapshot.continuityContext?.mode == .live)
    #expect(snapshot.continuityContext?.changedSinceLastOpen.first?.kind == "agent_write")
    #expect(snapshot.continuityContext?.latestSurfaceWrite?.sourceSurface == "codex")
    #expect(snapshot.continuityContext?.primaryNextAction.action == "open_memory_lens")
    #expect(snapshot.continuityContext?.sourceMode == "cluster")
}

@Test func homeContinuityContextSynthesizesAgentWriteDeterministically() throws {
    let json = """
    {
      "generated_at": "2026-04-29T12:00:00Z",
      "today_brief": "Audited living home",
      "current_self": {
        "id": "v1",
        "label": "Audited Self",
        "period_start": "2026-04-29T12:00:00Z",
        "period_end": null,
        "dominant_beliefs": [],
        "core_values": [],
        "cognitive_style": "continuity",
        "risk_tolerance": 0.5,
        "source_commit_id": null
      },
      "memory_signals": ["Codex work memory stored"],
      "open_loops": [],
      "active_project_ref": "beagle",
      "body_context": "Watch summary available",
      "recommended_next_action": "Inspect the latest write",
      "cluster_truth": "observed",
      "omnimemory_status": "projected",
      "temporal_phase": "implementation",
      "agent_context": {
        "active_sessions": 1,
        "recent_observations": ["Stored memory"],
        "last_agent_write": "codex summary captured",
        "mcp_status": "audited"
      },
      "trust_context": {
        "mcp_status": "audit-log-observed",
        "active_scopes": ["exocortex:read", "memory:write"],
        "audit_freshness": "2026-04-29T12:00:00Z",
        "destructive_actions": "locked",
        "last_audit_event_id": "audit-1",
        "apple_capture_freshness": "watch capture fresh"
      }
    }
    """.data(using: .utf8)!
    let snapshot = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: json)

    let first = HomeContinuityContext.synthesized(home: snapshot, truthMode: .observed)
    let second = HomeContinuityContext.synthesized(home: snapshot, truthMode: .observed)

    #expect(first == second)
    #expect(first.mode == .live)
    #expect(first.latestSurfaceWrite?.kind == "agent_write")
    #expect(first.primaryNextAction.action == "open_memory_lens")
    #expect(first.changedSinceLastOpen.contains { $0.kind == "apple_capture" })
    #expect(first.sourceMode == "local_synthesis")
}

@Test func homeContinuityContextSynthesizesOfflineAndClaimReviewStates() throws {
    let offline = HomeContinuityContext.synthesized(
        home: .bootstrap,
        truthMode: .stale,
        previousHome: .bootstrap
    )
    #expect(offline.mode == .offline)
    #expect(offline.primaryNextAction.action == "inspect_trust")
    #expect(offline.changedSinceLastOpen.first?.kind == "cache")

    let reviewJSON = """
    {
      "generated_at": "2026-04-29T12:05:00Z",
      "today_brief": "Review home",
      "current_self": {
        "id": "v1",
        "label": "Review Self",
        "period_start": "2026-04-29T12:05:00Z",
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
      "recommended_next_action": "Review claim",
      "cluster_truth": "observed",
      "omnimemory_status": "projected",
      "temporal_phase": null,
      "trust_context": {
        "mcp_status": "audit-log-observed",
        "active_scopes": ["exocortex:read"],
        "audit_freshness": "2026-04-29T12:05:00Z",
        "destructive_actions": "locked",
        "pending_triads": 2,
        "sounio_pending_approval": "claim-review"
      }
    }
    """.data(using: .utf8)!
    let reviewSnapshot = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: reviewJSON)
    let review = HomeContinuityContext.synthesized(home: reviewSnapshot, truthMode: .observed)

    #expect(review.mode == .review)
    #expect(review.primaryNextAction.action == "review_claim")
    #expect(review.whyThisNow.localizedCaseInsensitiveContains("claim"))
}

@Test func homeContinuityContextSynthesizesGrokImportSignalWithoutRestricted() throws {
    let graphJSON = """
    {
      "generated_at": "2026-04-29T12:10:00Z",
      "status": {
        "status": "fresh",
        "schema_version": "beagle-memory-projection-v1.2",
        "episode_count": 2,
        "atom_count": 1,
        "latest_run": null,
        "freshness": "fresh",
        "retrieval_mode": "lexical+graph+temporal",
        "degraded_reason": ""
      },
      "episodes": [{
        "id": "episode-grok",
        "created_at": "2026-04-29T12:09:00Z",
        "source": "assisted-import",
        "source_platform": "grok",
        "session_id": "grok-import",
        "source_ref": "omnimemory:grok",
        "content_hash": "sha256:grok",
        "privacy_class": "sensitive",
        "provenance": null,
        "tags": ["grok", "graphrag++"],
        "title": "Grok conversations imported",
        "linked_chronoself_commits": [],
        "occurred_at": "2026-04-29T12:09:00Z"
      }, {
        "id": "episode-restricted",
        "created_at": "2026-04-29T12:09:30Z",
        "source": "assisted-import",
        "source_platform": "grok",
        "session_id": "restricted",
        "source_ref": "omnimemory:restricted",
        "content_hash": "sha256:restricted",
        "privacy_class": "restricted",
        "provenance": null,
        "tags": ["grok"],
        "title": "restricted should not surface",
        "linked_chronoself_commits": [],
        "occurred_at": "2026-04-29T12:09:30Z"
      }],
      "atoms": [],
      "relations": [],
      "worlds": [],
      "communities": [],
      "provenance": null
    }
    """.data(using: .utf8)!
    let graph = try JSONDecoder().decode(MemoryGraphRecentResponse.self, from: graphJSON)
    let context = HomeContinuityContext.synthesized(
        home: .bootstrap,
        truthMode: .observed,
        recentGraph: graph
    )

    #expect(context.changedSinceLastOpen.contains { $0.kind == "grok_import" })
    #expect(!context.changedSinceLastOpen.contains { $0.detail.localizedCaseInsensitiveContains("restricted") })
}

@Test func memoryLensReportSynthesizesLivingReportAndFiltersRestricted() throws {
    let homeJSON = """
    {
      "generated_at": "2026-04-29T13:00:00Z",
      "today_brief": "Living Memory Lens",
      "current_self": {
        "id": "v1",
        "label": "Beagle UI",
        "period_start": "2026-04-29T13:00:00Z",
        "period_end": null,
        "dominant_beliefs": [],
        "core_values": [],
        "cognitive_style": "Apple Lab",
        "risk_tolerance": 0.5,
        "source_commit_id": null
      },
      "memory_signals": ["Grok import active"],
      "open_loops": [],
      "active_project_ref": "beagle",
      "body_context": null,
      "recommended_next_action": "Open Memory Lens",
      "cluster_truth": "observed",
      "omnimemory_status": "projected",
      "temporal_phase": "UI",
      "trust_context": {
        "mcp_status": "audit-log-observed",
        "active_scopes": ["exocortex:read"],
        "audit_freshness": "2026-04-29T13:00:00Z",
        "destructive_actions": "locked",
        "latest_agent_write": "codex implemented Living Home",
        "hot_path_mode": "hypermemory_multivector"
      }
    }
    """.data(using: .utf8)!
    let graphJSON = """
    {
      "generated_at": "2026-04-29T13:01:00Z",
      "status": {
        "status": "fresh",
        "schema_version": "beagle-memory-projection-v1.2",
        "episode_count": 2,
        "atom_count": 3,
        "latest_run": null,
        "freshness": "fresh",
        "retrieval_mode": "hypermemory_multivector",
        "degraded_reason": ""
      },
      "episodes": [{
        "id": "episode-grok",
        "created_at": "2026-04-29T13:01:00Z",
        "source": "assisted-import",
        "source_platform": "grok",
        "session_id": "grok-import",
        "source_ref": "omnimemory:grok",
        "content_hash": "sha256:grok",
        "privacy_class": "sensitive",
        "provenance": null,
        "tags": ["grok"],
        "title": "Grok conversations imported",
        "linked_chronoself_commits": [],
        "occurred_at": "2026-04-29T13:01:00Z"
      }],
      "atoms": [{
        "id": "atom-codex",
        "created_at": "2026-04-29T13:01:00Z",
        "episode_id": "episode-codex",
        "atom_type": "decision",
        "text": "Memory Lens should open as a living report.",
        "normalized_text": "memory lens living report",
        "source_refs": ["omnimemory:codex"],
        "relations": [],
        "tags": ["work-memory", "codex"],
        "confidence": 0.92,
        "privacy_class": "sensitive",
        "occurred_at": "2026-04-29T13:01:00Z"
      }, {
        "id": "atom-restricted",
        "created_at": "2026-04-29T13:01:30Z",
        "episode_id": "episode-restricted",
        "atom_type": "secret",
        "text": "restricted local-only content",
        "normalized_text": "restricted",
        "source_refs": ["omnimemory:restricted"],
        "relations": [],
        "tags": ["restricted"],
        "confidence": 0.99,
        "privacy_class": "restricted",
        "occurred_at": "2026-04-29T13:01:30Z"
      }],
      "relations": [],
      "worlds": [],
      "communities": [],
      "provenance": null
    }
    """.data(using: .utf8)!
    let home = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: homeJSON)
    let graph = try JSONDecoder().decode(MemoryGraphRecentResponse.self, from: graphJSON)
    let report = MemoryLensReport.synthesized(home: home, homeTruthMode: .observed, recentGraph: graph)

    #expect(report.mode == .report)
    #expect(report.headline.localizedCaseInsensitiveContains("memória viva"))
    #expect(report.presets.map(\.id) == [
        "latest-beagle-decision",
        "claude-codex-changes",
        "sounio-paperrun-now",
        "grok-claude-imports",
        "next-move"
    ])
    #expect(report.changedSignals.contains { $0.localizedCaseInsensitiveContains("codex") })
    #expect(report.changedSignals.contains { $0.localizedCaseInsensitiveContains("grok") })
    #expect(report.evidenceFrontier.contains { $0.id == "atom-codex" })
    #expect(!report.evidenceFrontier.contains { $0.detail.localizedCaseInsensitiveContains("restricted") })
    #expect(report.restrictedContentFiltered)
}

@Test func spatialControlRoomModelsDecodeMarbleManifestAndEvidence() throws {
    let json = """
    {
      "id": "control-room-sounio",
      "generated_at": "2026-05-01T12:00:00Z",
      "schema_version": "beagle-spatial-control-room-v3.6",
      "project_slug": "sounio",
      "spatial_world": {
        "id": "spatial-world",
        "created_at": "2026-05-01T12:00:00Z",
        "updated_at": "2026-05-01T12:01:00Z",
        "schema_version": "beagle-spatial-control-room-v3.6",
        "project_slug": "sounio",
        "world_id": "world-sounio",
        "operation_id": "op-sounio",
        "display_name": "Sounio Control Room",
        "status": "ready",
        "world_marble_url": "https://marble.worldlabs.ai/worlds/world-sounio",
        "assets": {
          "pano_url": "https://assets.example/pano.png",
          "collider_mesh_url": "https://assets.example/collider.glb",
          "hq_mesh_urls": [],
          "spz_urls": {"low_res": "https://assets.example/low.spz"},
          "ply_urls": {},
          "coordinate_system": "opencv:+x-left,+y-down,+z-forward",
          "coordinate_transform": "opencv_to_opengl:scale_yz_minus_one",
          "asset_root": "/orangefs/beagle-spatial-worlds/world-sounio",
          "degraded_reason": null
        },
        "model": "marble-1.1",
        "permission": "private",
        "prompt_hash": "sha256:prompt",
        "prompt_summary": "sanitized control room",
        "privacy_policy": "cluster-private derived artifact",
        "tags": ["spatial-control-room"],
        "provenance": {"sanitized_prompt_only": true}
      },
      "memory_worlds": [],
      "agent_lanes": ["Builder: Claude/Codex"],
      "pods_wall": ["beagle-core"],
      "incident_corridor": ["failed-write rescue"],
      "compiler_map": ["Sounio IR"],
      "evidence_refs": ["spatial-evidence:1"],
      "provenance": {"surface": "visionOS"}
    }
    """.data(using: .utf8)!
    let snapshot = try JSONDecoder().decode(ControlRoomSnapshot.self, from: json)
    #expect(snapshot.projectSlug == "sounio")
    #expect(snapshot.spatialWorld?.assets.spzUrls["low_res"] == "https://assets.example/low.spz")
    #expect(snapshot.spatialWorld?.assets.coordinateTransform == "opencv_to_opengl:scale_yz_minus_one")
    #expect(snapshot.spatialWorld?.permission == "private")

    let request = CreateSpatialWorldRequest(
        promptSummary: "sanitized",
        sanitizedPrompt: "sanitized",
        approved: true
    )
    let encoded = try JSONEncoder().encode(request)
    let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    #expect(object?["project_slug"] as? String == "sounio")
    #expect(object?["sanitized_prompt"] as? String == "sanitized")
    #expect(object?["approved"] as? Bool == true)
}

@Test func memoryLensReportUsesLastQueryAsEvidenceFrontierAndProof() throws {
    let queryJSON = """
    {
      "summary": "Beagle chose Memory Lens as the second magical UI moment.",
      "evidence": [{
        "atom_id": "atom-memory-lens",
        "episode_id": "episode-ui",
        "atom_type": "decision",
        "text": "Memory Lens becomes a living laboratory report.",
        "score": 0.94,
        "source_refs": ["omnimemory:ui"],
        "provenance": {"surface": "codex"}
      }, {
        "atom_id": "atom-hidden",
        "episode_id": "episode-restricted",
        "atom_type": "secret",
        "text": "restricted evidence should not display",
        "score": 0.99,
        "source_refs": ["omnimemory:restricted"],
        "provenance": null
      }],
      "atoms": [],
      "episodes": [],
      "relations": [],
      "temporal_context": {
        "newest_evidence_at": "2026-04-29T13:05:00Z",
        "oldest_evidence_at": "2026-04-29T13:00:00Z",
        "matched_episode_count": 1
      },
      "provenance": {"query": "memory lens"},
      "confidence": 0.91,
      "degraded_reason": null,
      "mode": "hypermemory_multivector",
      "runtime_used": "hypermemory_multivector",
      "fallback_chain": ["hypermemory_multivector", "hypermemory"],
      "retrieval_trace": [{
        "stage": "direct",
        "backend": "lancedb",
        "status": "ok",
        "items": 4,
        "latency_ms": 42,
        "notes": ["late interaction"]
      }],
      "semantic_trace": [],
      "runtime_trace": []
    }
    """.data(using: .utf8)!
    let query = try JSONDecoder().decode(GraphRagQueryResponse.self, from: queryJSON)
    let report = MemoryLensReport.synthesized(lastQuery: query, activeProjectSlug: "beagle")

    #expect(report.mode == .evidence)
    #expect(report.summary.contains("second magical UI"))
    #expect(report.evidenceFrontier.count == 1)
    #expect(report.evidenceFrontier.first?.proof.traceLines.first?.contains("lancedb") == true)
    #expect(report.proof.sourceRefs == ["omnimemory:ui"])
    #expect(report.runtime == "hypermemory_multivector")
    #expect(report.restrictedContentFiltered)
}

@Test func memoryLensReportSurfacesPaperRunAndContradictionSignals() throws {
    let homeJSON = """
    {
      "generated_at": "2026-04-29T13:10:00Z",
      "today_brief": "Sounio claim review",
      "current_self": {
        "id": "v1",
        "label": "Sounio",
        "period_start": "2026-04-29T13:10:00Z",
        "period_end": null,
        "dominant_beliefs": [],
        "core_values": [],
        "cognitive_style": "epistemic",
        "risk_tolerance": 0.5,
        "source_commit_id": null
      },
      "memory_signals": [],
      "open_loops": [],
      "active_project_ref": "sounio",
      "body_context": null,
      "recommended_next_action": "Review claim",
      "cluster_truth": "observed",
      "omnimemory_status": "projected",
      "temporal_phase": "claim-review",
      "trust_context": {
        "mcp_status": "audit-log-observed",
        "active_scopes": ["exocortex:read"],
        "audit_freshness": "2026-04-29T13:10:00Z",
        "destructive_actions": "locked",
        "sounio_paperrun_status": "human_approval_pending",
        "sounio_pending_approval": "claim-42"
      }
    }
    """.data(using: .utf8)!
    let contradictionsJSON = """
    {
      "contradictions": [{
        "id": "contradiction-1",
        "created_at": "2026-04-29T13:10:00Z",
        "subject_ref": "claim-42",
        "conflicting_ref": "evidence-7",
        "description": "Claim requires stronger provenance.",
        "severity": "medium",
        "evidence_refs": ["evidence-7"],
        "status": "open",
        "detected_by": "critical"
      }]
    }
    """.data(using: .utf8)!
    let home = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: homeJSON)
    let contradictions = try JSONDecoder().decode(MemoryContradictionListResponse.self, from: contradictionsJSON)
    let report = MemoryLensReport.synthesized(home: home, contradictions: contradictions, activeProjectSlug: "sounio")

    #expect(report.changedSignals.contains { $0.localizedCaseInsensitiveContains("PaperRun") })
    #expect(report.changedSignals.contains { $0.localizedCaseInsensitiveContains("approval") })
    #expect(report.changedSignals.contains { $0.localizedCaseInsensitiveContains("contradiction") })
    #expect(report.presets.first?.scopeHint == "sounio")
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
        "portfolio_truth_gate": "truthset:portfolio:provisional_hot_path",
        "sounio_paperrun_status": "human_approval_pending",
        "sounio_temporal_status": "dry_run_not_started",
        "sounio_pending_approval": "human_approval",
        "sounio_latest_artifact": "/orangefs/beagle-memory-lab/paperruns/run-1/manuscript.md"
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
    #expect(snapshot.trustContext?.sounioPaperRunStatus == "human_approval_pending")
    #expect(snapshot.trustContext?.sounioTemporalStatus == "dry_run_not_started")
    #expect(snapshot.trustContext?.sounioPendingApproval == "human_approval")
    #expect(snapshot.trustContext?.sounioLatestArtifact?.contains("/orangefs/") == true)
}

@Test func sounioPaperRunModelsDecodeClusterContracts() throws {
    let runJSON = """
    {
      "id": "run-1",
      "created_at": "2026-04-28T12:00:00Z",
      "updated_at": "2026-04-28T12:01:00Z",
      "schema_version": "beagle-sounio-paperrun-v2.4",
      "paper_id": "beagle-self-writing-systems-paper",
      "title": "Beagle: A Self-Governing Exocortex",
      "status": "human_approval_pending",
      "temporal_workflow_id": "sounio-paperrun-run-1",
      "temporal_namespace": "beagle",
      "temporal_task_queue": "sounio-paperrun",
      "temporal_status": "dry_run_not_started",
      "sounio_program_id": "program-1",
      "sounio_program_hash": "sha256:abc",
      "manuscript_version": "draft-0.1",
      "section_status": {"Architecture": "planned"},
      "claim_registry": [{"id": "claim-1", "status": "needs_evidence"}],
      "citation_registry": [{"id": "mcp-spec"}],
      "approval_state": "waiting_for_human",
      "pending_approval_step": "human_approval",
      "context_pack_id": "context-pack-1",
      "artifact_refs": ["/orangefs/beagle-memory-lab/paperruns/run-1/manuscript.md"],
      "provenance": {"canonical_source": "/var/lib/beagle/exocortex"}
    }
    """.data(using: .utf8)!

    let run = try JSONDecoder().decode(PaperRun.self, from: runJSON)
    #expect(run.id == "run-1")
    #expect(run.pendingApprovalStep == "human_approval")
    #expect(run.artifactRefs.first?.contains("/orangefs/") == true)

    let traceJSON = """
    {
      "events": [
        {
          "id": "trace-1",
          "created_at": "2026-04-28T12:00:00Z",
          "paper_run_id": "run-1",
          "program_id": "program-1",
          "step_id": "paperrun_start",
          "event_type": "workflow_start_requested",
          "status": "dry_run_not_started",
          "summary": "PaperRun created",
          "context_pack_id": "context-pack-1",
          "provenance": {"temporal_workflow_id": "sounio-paperrun-run-1"},
          "artifact_refs": []
        }
      ]
    }
    """.data(using: .utf8)!

    let trace = try JSONDecoder().decode(SounioTraceListResponse.self, from: traceJSON)
    #expect(trace.events.first?.eventType == "workflow_start_requested")

    let artifactsJSON = """
    {
      "paper_run_id": "run-1",
      "generated_at": "2026-04-28T12:02:00Z",
      "manuscript_markdown": "# Beagle\\n",
      "provenance_pack": {"restricted_policy": "exclude"},
      "artifact_refs": ["/orangefs/beagle-memory-lab/paperruns/run-1/manuscript.md"]
    }
    """.data(using: .utf8)!

    let artifacts = try JSONDecoder().decode(PaperRunArtifactsResponse.self, from: artifactsJSON)
    #expect(artifacts.manuscriptMarkdown.contains("Beagle"))
}

@Test func sounioClaimAndTheatreModelsDecodeEpistemicPaperRun() throws {
    let json = """
    {
      "paper_run_id": "run-1",
      "generated_at": "2026-04-28T13:00:00Z",
      "schema_version": "beagle-sounio-paperrun-theatre-v2.5",
      "paper_run": {
        "id": "run-1",
        "created_at": "2026-04-28T12:00:00Z",
        "updated_at": "2026-04-28T12:30:00Z",
        "schema_version": "beagle-sounio-paperrun-v2.4",
        "paper_id": "beagle-self-writing-systems-paper",
        "title": "Beagle: A Self-Governing Exocortex",
        "status": "human_approval_pending",
        "temporal_workflow_id": "sounio-paperrun-run-1",
        "temporal_namespace": "beagle",
        "temporal_task_queue": "sounio-paperrun",
        "temporal_status": "dry_run_not_started",
        "sounio_program_id": "program-1",
        "sounio_program_hash": "sha256:abc",
        "manuscript_version": "draft-0.1",
        "section_status": {"Sounio IR": "drafting"},
        "claim_registry": [{"id": "claim-sedenion", "status": "knowledge"}],
        "citation_registry": [],
        "approval_state": "waiting_for_human",
        "pending_approval_step": "human_approval",
        "context_pack_id": "context-pack-1",
        "artifact_refs": ["/orangefs/beagle-memory-lab/paperruns/run-1/manuscript.md"],
        "provenance": {"canonical_source": "/var/lib/beagle/exocortex"},
        "interaction_summary": "1 claim tracked.",
        "claim_lifecycle_status": {"claim-sedenion": "knowledge"},
        "public_digest_status": "stale_after_claim_review",
        "current_stage": "claim_review"
      },
      "manuscript_markdown": "# Beagle\\n",
      "claim_graph": {
        "paper_run_id": "run-1",
        "generated_at": "2026-04-28T13:00:00Z",
        "schema_version": "sounio-claim-epistemic-v0.1",
        "claims": [{
          "id": "claim-sedenion",
          "created_at": "2026-04-28T12:10:00Z",
          "updated_at": "2026-04-28T12:20:00Z",
          "paper_run_id": "run-1",
          "section_id": "Sounio IR",
          "claim_text": "Sedenion SSM is the first strong Sounio demonstration.",
          "subject": "sedenion_ssm_arc",
          "value_type": "Claim<T>",
          "epistemic_status": "knowledge",
          "evidence_refs": ["artifact:sedenion_ssm_arc"],
          "provenance": {"source": "beagle-apple", "human_review": true},
          "confidence": 0.84,
          "contestation": {},
          "review_state": "approved",
          "promotion_rule": "Knowledge<T> requires evidence+provenance.",
          "publication_readiness": "section_ready_with_provenance",
          "agent_refs": ["beagle-app"],
          "contract_refs": [],
          "artifact_refs": ["/orangefs/beagle-memory-lab/paperruns/run-1/sedenion_ssm_public_case.json"],
          "chronoself_commit_refs": [],
          "privacy_class": "sensitive",
          "rationale": "Human reviewed."
        }],
        "edges": [{"from": "claim-sedenion", "to": "artifact:sedenion_ssm_arc", "kind": "supported_by"}],
        "status_counts": {"knowledge": 1},
        "unsupported_claim_ids": [],
        "robust_claim_ids": []
      },
      "trace_events": [],
      "agent_contributions": [],
      "approvals": [],
      "evidence_table": [],
      "sounio_score": {"score": 1.0},
      "current_stage": "claim_review",
      "next_action": "Generate public digest.",
      "public_digest_status": "stale_after_claim_review",
      "private_trace_ref": "/orangefs/beagle-memory-lab/paperruns/run-1/private_trace_pack.jsonl"
    }
    """.data(using: .utf8)!

    let theatre = try JSONDecoder().decode(PaperRunTheatreSnapshot.self, from: json)
    #expect(theatre.paperRun.currentStage == "claim_review")
    #expect(theatre.claimGraph.claims.first?.epistemicStatus == "knowledge")
    #expect(theatre.claimGraph.statusCounts["knowledge"] == 1)
    #expect(theatre.privateTraceRef.contains("/orangefs/"))

    let digestJSON = """
    {
      "paper_run_id": "run-1",
      "generated_at": "2026-04-28T13:05:00Z",
      "schema_version": "beagle-sounio-public-digest-v2.5",
      "title": "Beagle: A Self-Governing Exocortex",
      "thesis": "Beagle observes; Sounio types.",
      "sanitized_claims": [{"id": "claim-sedenion", "epistemic_status": "knowledge"}],
      "sedenion_ssm_case": {"case_id": "sedenion-ssm-arc"},
      "public_trace_digest": [],
      "disclosure": "Agents are instruments, not authors.",
      "excluded_private_trace_policy": "Private traces stay cluster-only.",
      "manuscript_excerpt": "# Beagle"
    }
    """.data(using: .utf8)!

    let digest = try JSONDecoder().decode(PublicDigestArtifact.self, from: digestJSON)
    #expect(digest.thesis.contains("Sounio"))
    #expect(digest.excludedPrivateTracePolicy.contains("cluster-only"))
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

@Test func sounioWorkdayModelsDecodeAmbientMomentAndHomeContext() throws {
    let json = """
    {
      "generated_at": "2026-04-29T22:10:00Z",
      "schema_version": "beagle-sounio-workday-v2.9",
      "project_slug": "sounio",
      "status": "active-review-needed",
      "latest_moment": {
        "id": "sounio-moment:1",
        "created_at": "2026-04-29T22:09:00Z",
        "updated_at": "2026-04-29T22:09:00Z",
        "schema_version": "sounio-ambient-moment-v2.9",
        "project_slug": "sounio",
        "moment_type": "work_memory",
        "intent": "Implement ambient typed Sounio loop.",
        "summary": "Codex connected Sounio Workday to the Apple Home.",
        "source_platform": "codex",
        "source_surface": "codex-local",
        "session_id": "codex-session-1",
        "source_event_refs": ["memory_event:1"],
        "evidence_refs": ["memory_event:1"],
        "claim_seeds": [{
          "id": "claim-1",
          "created_at": "2026-04-29T22:09:00Z",
          "updated_at": "2026-04-29T22:09:00Z",
          "claim_text": "Sounio types ambient work moments conservatively.",
          "subject": "sounio",
          "value_type": "Claim<T>",
          "epistemic_status": "belief",
          "evidence_refs": ["memory_event:1"],
          "provenance": {"source": "test"},
          "confidence": 0.62,
          "contestation": {},
          "review_state": "unreviewed",
          "promotion_rule": "requires evidence",
          "publication_readiness": "not_ready",
          "agent_refs": ["codex"],
          "contract_refs": [],
          "artifact_refs": [],
          "chronoself_commit_refs": [],
          "privacy_class": "sensitive"
        }],
        "decision_seeds": ["Ambient Typed Life is the v2.9 demo."],
        "next_action": "Review the moment on iPhone.",
        "privacy_class": "sensitive",
        "review_state": "unreviewed",
        "restricted_leak_check": "passed:no_restricted_payload_typed",
        "provenance": {"source": "test"},
        "tags": ["sounio", "codex"]
      },
      "moments": [],
      "claim_seeds": [],
      "decision_seeds": ["Ambient Typed Life is the v2.9 demo."],
      "evidence_refs": ["memory_event:1"],
      "tensions": ["typing vs certainty"],
      "agents": ["codex"],
      "next_action": "Review the moment on iPhone.",
      "review_queue_count": 1,
      "restricted_leak_check": "passed:restricted_filtered_from_workday",
      "provenance": {"cluster_only": true}
    }
    """.data(using: .utf8)!

    let workday = try JSONDecoder().decode(SounioWorkdaySnapshot.self, from: json)
    #expect(workday.latestMoment?.momentType == "work_memory")
    #expect(workday.latestMoment?.claimSeeds.first?.epistemicStatus == "belief")
    #expect(workday.reviewQueueCount == 1)

    let homeJson = """
    {
      "generated_at": "2026-04-29T22:11:00Z",
      "today_brief": "Sounio Workday active.",
      "current_self": {
        "id": "self-1",
        "label": "Beagle",
        "period_start": "2026-04-29T00:00:00Z",
        "dominant_beliefs": [],
        "core_values": [],
        "cognitive_style": "exocortex",
        "risk_tolerance": 0.5
      },
      "memory_signals": ["Sounio now"],
      "open_loops": [],
      "active_project_ref": "sounio",
      "recommended_next_action": "Review the moment on iPhone.",
      "cluster_truth": "observed",
      "omnimemory_status": "projected",
      "trust_context": {
        "mcp_status": "audit-log-observed",
        "active_scopes": ["exocortex:read"],
        "audit_freshness": "now",
        "destructive_actions": "locked",
        "sounio_workday_status": "sounio:active-review-needed",
        "sounio_latest_moment": "work_memory:Codex connected Sounio Workday",
        "sounio_pending_moment_review": "1 pending"
      },
      "sounio_workday_context": \(String(data: json, encoding: .utf8)!)
    }
    """.data(using: .utf8)!

    let home = try JSONDecoder().decode(ExocortexHomeSnapshot.self, from: homeJson)
    #expect(home.sounioWorkdayContext?.status == "active-review-needed")
    #expect(home.trustContext?.sounioPendingMomentReview == "1 pending")
    let now = SounioNowContext.synthesized(from: home)
    #expect(now.reviewQueueCount == 1)
    #expect(now.claimLine?.contains("belief") == true)
}

@Test func workspaceNotebookTerminalModelsDecode() throws {
    let sessionJson = """
    {
      "session": {
        "id": "wb-test",
        "projectSlug": "sounio",
        "title": "Sounio Workbench",
        "status": "active",
        "layout": "notebook",
        "createdAt": "2026-04-30T10:00:00Z",
        "updatedAt": "2026-04-30T10:01:00Z",
        "lastAttachedAt": "2026-04-30T10:02:00Z",
        "sourceModel": "beagle",
        "bridgeVersion": "beagle-warp-bridge-v0.2",
        "sessionHash": "sha256:session",
        "rendererHint": "beagle-terminal-v1",
        "lastMemoryStatus": {
          "blockId": "block-1",
          "status": "remembered",
          "memoryEventId": "memory-1",
          "auditEventId": "audit-1",
          "sourceModel": "beagle",
          "bridgeVersion": "beagle-warp-bridge-v0.2"
        },
        "panes": [{
          "id": "pane-main",
          "title": "Shell",
          "kind": "human",
          "status": "attached",
          "createdAt": "2026-04-30T10:00:00Z",
          "lastAttachedAt": "2026-04-30T10:02:00Z",
          "cwd": "/workspace/sounio"
        }]
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(WorkspaceSessionResponse.self, from: sessionJson)
    #expect(decoded.session.id == "wb-test")
    #expect(decoded.session.layout == .notebook)
    #expect(decoded.session.panes.first?.id == "pane-main")
    #expect(decoded.session.lastMemoryStatus?.status == "remembered")
    #expect(decoded.session.sourceModel == "beagle")
    #expect(decoded.session.bridgeVersion == "beagle-warp-bridge-v0.2")
    #expect(decoded.session.sessionHash == "sha256:session")
}

@Test func terminalBlockDecodesMemoryState() throws {
    let blocksJson = """
    {
      "projectSlug": "sounio",
      "sessionId": "wb-test",
      "blocks": [{
        "id": "block-1",
        "sessionId": "wb-test",
        "paneId": "pane-main",
        "kind": "command",
        "title": "swift test",
        "command": "swift test",
        "outputPreview": "Test Suite passed",
        "outputByteCount": 17,
        "startedAt": "2026-04-30T10:00:00Z",
        "finishedAt": "2026-04-30T10:01:00Z",
        "durationMs": 60000,
        "exitCode": 0,
        "status": "finished",
        "privacyClass": "sensitive",
        "memoryStatus": "not_saved",
        "tags": ["workbench", "terminal-block", "project:sounio"],
        "sourceModel": "beagle",
        "bridgeVersion": "beagle-warp-bridge-v0.2",
        "blockHash": "sha256:block",
        "sessionHash": "sha256:session",
        "rendererHint": "beagle-terminal-v1"
      }]
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(WorkspaceBlocksResponse.self, from: blocksJson)
    #expect(decoded.blocks.first?.title == "swift test")
    #expect(decoded.blocks.first?.privacyClass == "sensitive")
    #expect(decoded.blocks.first?.memoryStatus == "not_saved")
    #expect(decoded.blocks.first?.sourceModel == "beagle")
    #expect(decoded.blocks.first?.blockHash == "sha256:block")
}

@Test func mindPalaceSnapshotDecodesSpatialDeskPortalsAndFocusCoach() throws {
    let json = """
    {
      "id": "mind-palace-v37",
      "generated_at": "2026-05-01T12:00:00Z",
      "schema_version": "beagle-spatial-desk-mind-palace-v3.7",
      "rooms": [{
        "id": "parallel-work",
        "title": "Parallel Workbench",
        "room_type": "workspace",
        "state": "active",
        "project_slug": "sounio",
        "source_family": "agent work memory",
        "tension": "Many agents can make progress while conversation continues elsewhere.",
        "next_action": "Open the Workbench drawer.",
        "freshness": "fresh",
        "truth_mode": "observed",
        "priority": 0.91,
        "desk_item_refs": [],
        "evidence_refs": ["memory_event:1"],
        "tags": ["workbench"]
      }],
      "desk": {
        "id": "spatial-desk",
        "generated_at": "2026-05-01T12:00:00Z",
        "schema_version": "beagle-spatial-desk-mind-palace-v3.7",
        "active_items": [{
          "id": "desk-1",
          "kind": "conversation_portal",
          "title": "Claude Desktop idea thread",
          "detail": "Promote explicit clips only.",
          "state": "reference_only",
          "priority": 0.78,
          "room_id": "conversation-portals",
          "source_ref": "conversation_portal:1",
          "actions": ["promote_clip"]
        }],
        "pinned_room_ids": ["parallel-work"],
        "portals": [{
          "id": "portal-1",
          "created_at": "2026-05-01T12:00:00Z",
          "updated_at": "2026-05-01T12:01:00Z",
          "schema_version": "beagle-conversation-portal-v3.7",
          "title": "Claude Desktop idea thread",
          "provider": "claude-desktop",
          "surface": "desktop-portal",
          "status": "reference_only",
          "source_mode": "portal+promote",
          "privacy_class": "sensitive",
          "source_ref": "external-window:claude",
          "promoted_clip_refs": [],
          "tags": ["conversation-portal"]
        }],
        "agent_lanes": ["Primary Builder: Claude/Codex"],
        "focus_strip": ["Water + posture check"],
        "proof_panels": ["Memory provenance"]
      },
      "next_best_place": {
        "id": "next-1",
        "generated_at": "2026-05-01T12:00:00Z",
        "room_id": "parallel-work",
        "title": "Parallel Workbench",
        "reason": "Continuity says this room is live.",
        "source_mode": "continuity+readiness",
        "confidence": 0.83,
        "candidate_room_ids": ["parallel-work"],
        "readiness_context": {"focus_mode": "focused"}
      },
      "action_menu": {
        "id": "actions",
        "generated_at": "2026-05-01T12:00:00Z",
        "mode": "parallel-spaces",
        "actions": [{
          "id": "open-workbench",
          "title": "Open Workbench",
          "kind": "open_workbench",
          "target_ref": "workspace:sounio",
          "reason": "Keep coding agents visible.",
          "enabled": true
        }]
      },
      "focus_coach": {
        "id": "focus",
        "generated_at": "2026-05-01T12:00:00Z",
        "schema_version": "beagle-focus-coach-v3.7",
        "mode": "focused",
        "active_session": null,
        "interventions": [{
          "id": "hydrate",
          "kind": "hydration",
          "title": "Water + posture check",
          "reason": "Gentle upkeep.",
          "priority": 0.72,
          "status": "suggested",
          "actions": ["drink_water"]
        }],
        "hydration_due": true,
        "calendar_nudge": "Keep commitments visible.",
        "session_minutes": 42,
        "can_override": true
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(MindPalaceSnapshot.self, from: json)
    #expect(decoded.schemaVersion == "beagle-spatial-desk-mind-palace-v3.7")
    #expect(decoded.rooms.first?.id == "parallel-work")
    #expect(decoded.desk.portals.first?.provider == "claude-desktop")
    #expect(decoded.nextBestPlace.roomId == "parallel-work")
    #expect(decoded.actionMenu.actions.first?.id == "open-workbench")
    #expect(decoded.focusCoach.hydrationDue == true)
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
