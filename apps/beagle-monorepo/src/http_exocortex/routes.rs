//! exocortex route table — extracted from the god-file (plan #16).
//! Maps every /api/exocortex/v1/* path to its handler (handlers live in mod.rs/siblings,
//! reachable here via `use super::*` since they are pub(crate)).

use super::*;
use crate::http::AppState;
use axum::{
    routing::{get, post},
    Router,
};

pub fn exocortex_routes() -> Router<AppState> {
    Router::new()
        .route("/api/exocortex/v1/home", get(exocortex_home_handler))
        .route(
            "/api/exocortex/v1/chronoself/current",
            get(chronoself_current_handler),
        )
        .route(
            "/api/exocortex/v1/chronoself/commits",
            get(chronoself_commits_handler).post(chronoself_create_commit_handler),
        )
        .route(
            "/api/exocortex/v1/omnimemory/imports",
            post(omnimemory_import_handler),
        )
        .route(
            "/api/exocortex/v1/memory/assisted-import",
            post(memory_assisted_import_handler),
        )
        .route("/api/exocortex/v1/write/probe", post(write_probe_handler))
        .route(
            "/api/exocortex/v1/failed-writes",
            get(failed_writes_handler).post(failed_write_record_handler),
        )
        .route(
            "/api/exocortex/v1/failed-writes/rescue",
            post(failed_write_rescue_handler),
        )
        .route(
            "/api/exocortex/v1/capture/sessions",
            post(capture_session_start_handler),
        )
        .route(
            "/api/exocortex/v1/capture/sessions/{session_id}",
            get(capture_session_status_handler),
        )
        .route(
            "/api/exocortex/v1/capture/sessions/{session_id}/events",
            post(capture_session_event_handler),
        )
        .route(
            "/api/exocortex/v1/capture/visual/artifacts",
            post(capture_visual_artifact_handler),
        )
        .route(
            "/api/exocortex/v1/capture/visual/analyze",
            post(capture_visual_analyze_handler),
        )
        .route(
            "/api/exocortex/v1/capture/review",
            post(capture_review_handler),
        )
        .route(
            "/api/exocortex/v1/context/compile",
            post(context_compile_handler),
        )
        .route(
            "/api/exocortex/v1/context/packs/{pack_id}",
            get(context_pack_get_handler),
        )
        .route(
            "/api/exocortex/v1/memory/effectiveness/events",
            post(memory_effectiveness_event_handler),
        )
        .route(
            "/api/exocortex/v1/memory/policy/status",
            get(memory_policy_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/dreamcycle/run",
            post(memory_dreamcycle_run_handler),
        )
        .route(
            "/api/exocortex/v1/memory/dreamcycle/status",
            get(memory_dreamcycle_status_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/programs/check",
            post(sounio_program_check_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/claims/check",
            post(sounio_claim_check_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/moments/type",
            post(sounio_moment_type_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/moments/recent",
            get(sounio_moments_recent_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/moments/{moment_id}/review",
            post(sounio_moment_review_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/workday/status",
            get(sounio_workday_status_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns",
            post(sounio_paperrun_start_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/{paper_run_id}",
            get(sounio_paperrun_get_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/{paper_run_id}/approve-step",
            post(sounio_paperrun_approve_step_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/{paper_run_id}/artifacts",
            get(sounio_paperrun_artifacts_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/{paper_run_id}/claims",
            post(sounio_paperrun_add_claim_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/{paper_run_id}/claims/{claim_id}/review",
            post(sounio_claim_review_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/{paper_run_id}/theatre",
            get(sounio_paperrun_theatre_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/{paper_run_id}/public-digest",
            get(sounio_paperrun_public_digest_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/trace",
            get(sounio_trace_query_handler),
        )
        .route(
            "/api/exocortex/v1/memory/export",
            post(memory_export_handler),
        )
        .route(
            "/api/exocortex/v1/memory/truthsets",
            post(memory_truthset_create_handler),
        )
        .route(
            "/api/exocortex/v1/memory/truthsets/{truthset_id}",
            get(memory_truthset_get_handler),
        )
        .route(
            "/api/exocortex/v1/memory/truthsets/{truthset_id}/cases",
            post(memory_truthset_case_create_handler),
        )
        .route(
            "/api/exocortex/v1/memory/truthsets/{truthset_id}/review",
            post(memory_truthset_review_handler),
        )
        .route(
            "/api/exocortex/v1/memory/candidates",
            get(memory_candidates_handler).post(memory_candidate_create_handler),
        )
        .route(
            "/api/exocortex/v1/memory/candidates/{candidate_id}/quorum",
            post(memory_candidate_quorum_handler),
        )
        .route(
            "/api/exocortex/v1/memory/candidates/{candidate_id}/promote",
            post(memory_candidate_promote_handler),
        )
        .route(
            "/api/exocortex/v1/memory/governance/run",
            post(memory_governance_run_handler),
        )
        .route(
            "/api/exocortex/v1/memory/governance/status",
            get(memory_governance_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/contradictions",
            get(memory_contradictions_handler),
        )
        .route(
            "/api/exocortex/v1/temporal/analyze",
            post(temporal_analyze_handler),
        )
        .route(
            "/api/exocortex/v1/audit/events",
            get(audit_events_handler).post(audit_event_create_handler),
        )
        .route(
            "/api/exocortex/v1/memory/events",
            get(memory_events_handler).post(memory_event_create_handler),
        )
        .route(
            "/api/exocortex/v1/memory/project",
            post(memory_project_handler),
        )
        .route(
            "/api/exocortex/v1/memory/projection/status",
            get(memory_projection_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/graph/status",
            get(memory_graph_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/bench/status",
            get(memory_bench_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/graph/bakeoff",
            post(memory_graph_bakeoff_handler),
        )
        .route(
            "/api/exocortex/v1/memory/graph/bakeoff/status",
            get(memory_graph_bakeoff_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/index-graph",
            post(memory_index_graph_handler),
        )
        .route(
            "/api/exocortex/v1/memory/graph/recent",
            get(memory_graph_recent_handler),
        )
        .route(
            "/api/exocortex/v1/memory/worlds/recent",
            get(memory_worlds_recent_handler),
        )
        .route(
            "/api/exocortex/v1/spatial/worlds/marble",
            post(spatial_world_marble_handler),
        )
        .route(
            "/api/exocortex/v1/spatial/worlds/{world_id}",
            get(spatial_world_get_handler),
        )
        .route(
            "/api/exocortex/v1/spatial/worlds/{world_id}/assets",
            get(spatial_world_assets_handler),
        )
        .route(
            "/api/exocortex/v1/spatial/projects/{slug}/control-room",
            get(spatial_control_room_handler),
        )
        .route(
            "/api/exocortex/v1/spatial/worlds/{world_id}/sounio/evidence",
            post(spatial_sounio_evidence_handler),
        )
        .route("/api/exocortex/v1/mind-palace", get(mind_palace_handler))
        .route(
            "/api/exocortex/v1/mind-palace/rooms",
            get(mind_palace_rooms_handler),
        )
        .route(
            "/api/exocortex/v1/mind-palace/desk",
            get(mind_palace_desk_handler),
        )
        .route(
            "/api/exocortex/v1/mind-palace/next-best-place",
            get(mind_palace_next_best_place_handler),
        )
        .route(
            "/api/exocortex/v1/mind-palace/action-menu",
            get(mind_palace_action_menu_handler),
        )
        .route(
            "/api/exocortex/v1/conversation-portals",
            post(conversation_portal_create_handler),
        )
        .route(
            "/api/exocortex/v1/conversation-portals/{portal_id}/promote",
            post(conversation_portal_promote_handler),
        )
        .route(
            "/api/exocortex/v1/focus-coach/status",
            get(focus_coach_status_handler),
        )
        .route(
            "/api/exocortex/v1/focus-coach/events",
            post(focus_coach_event_handler),
        )
        .route(
            "/api/exocortex/v1/graphrag/query",
            post(graphrag_query_handler),
        )
        .route(
            "/api/exocortex/v1/recall/answer",
            post(recall_answer_handler),
        )
        // Alias: the iOS cockpit (CognitiveRecall.swift) POSTs the un-prefixed
        // `/api/recall/answer`. Map it to the same handler so the shipped app build
        // stops 404ing (and rendering the HTML error page into the answer card)
        // before the client path fix lands.
        .route("/api/recall/answer", post(recall_answer_handler))
        // Recall "Next" mode: the fleet proposes next steps (LLM, grounded in recall) +
        // accept logs to the proposals board. Canonical exocortex path (the public gateway
        // already routes /api/exocortex/* → beagle-core) + the un-prefixed aliases the
        // shipped client currently uses.
        .route("/api/exocortex/v1/propose", post(propose_handler))
        .route("/api/propose", post(propose_handler))
        .route("/api/exocortex/v1/propose/accept", post(accept_handler))
        .route("/api/propose/accept", post(accept_handler))
        // Cognitive playground — the iOS cockpit's un-prefixed calls, now real:
        // deep-think via the TieredRouter, fractal.recurse + exocortex/process (Φ) via
        // Sounio verbs on the inference service, hyperedges via the live memory graph.
        .route("/api/cognitive/deep-think", post(deep_think_handler))
        .route("/api/fractal/recurse", post(fractal_recurse_handler))
        .route("/api/exocortex/process", post(exocortex_process_handler))
        .route(
            "/api/hyperedges",
            get(hyperedges_list_handler).post(hyperedges_create_handler),
        )
        .route(
            "/api/exocortex/v1/projects/active",
            get(active_projects_handler),
        )
        // Orchestration layer (BeagleCockpit A+B+C)
        .route("/api/exocortex/v1/verify", post(verify_handler))
        .route(
            "/api/orchestration/plan/confirm",
            post(confirm_plan_handler),
        )
        .route("/api/moshi/v1/session", get(moshi_session_handler))
}
