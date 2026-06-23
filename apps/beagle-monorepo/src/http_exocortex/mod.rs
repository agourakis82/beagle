//! Cluster-first Exocortex API.
//!
//! This module is intentionally small and append-only. The cluster owns the
//! canonical Chronoself/OmniMemory/TemporalAI state, while Apple clients and
//! MCP agents render or mutate it through this contract.

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use beagle_config::beagle_data_dir;
use beagle_darwin::{consumer_identity_for_id, ConsumerId};
use beagle_llm::RequestMeta;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::PathBuf,
};
use tracing::error;
use uuid::Uuid;

use crate::http::AppState;

// Domain submodules split out of the former 16k-LOC god-file. Each holds the free
// HTTP handler fns for one cohesive domain; the shared DTOs, constants, helpers and
// the `ExocortexRepository` impl remain here in `mod.rs`. Handlers are re-exported so
// `exocortex_routes()` keeps referencing them unqualified (pure code movement).
mod capture;
mod chronoself;
mod dtos;
mod memory_truth;
mod mind_palace;
mod moshi;
mod orchestration;
mod paths;
mod repository;
mod routes;
mod sounio;
mod spatial;

pub(crate) use capture::*;
pub(crate) use chronoself::*;
pub(crate) use dtos::*;
pub(crate) use memory_truth::*;
pub(crate) use mind_palace::*;
pub(crate) use moshi::*;
pub(crate) use orchestration::*;
pub(crate) use paths::*;
pub(crate) use repository::*;
pub(crate) use routes::*;
pub(crate) use sounio::*;
pub(crate) use spatial::*;

pub(crate) async fn exocortex_home_handler(
    State(_state): State<AppState>,
    Query(query): Query<HomeQuery>,
) -> Result<Json<ExocortexHomeSnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.build_home_snapshot(query).map_err(internal_error)?;
    Ok(Json(snapshot))
}

// Coalescing, debounced auto-reindex trigger fired after an ingest. Each call bumps a generation
// and schedules a fire after a quiet window; only the LAST scheduled fire actually rebuilds, so a
// burst of imports collapses into one reindex. Single-flight via REINDEX_RUNNING. Fail-soft.
static REINDEX_GEN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
static REINDEX_RUNNING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub(crate) fn trigger_reindex_debounced() {
    use std::sync::atomic::Ordering::SeqCst;
    let my_gen = REINDEX_GEN.fetch_add(1, SeqCst) + 1;
    tokio::spawn(async move {
        let debounce = env::var("BEAGLE_REINDEX_DEBOUNCE_SECS")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(30);
        tokio::time::sleep(std::time::Duration::from_secs(debounce)).await;
        // A newer ingest superseded this trigger — let the latest one fire instead (coalesce).
        if REINDEX_GEN.load(SeqCst) != my_gen {
            return;
        }
        if REINDEX_RUNNING.swap(true, SeqCst) {
            return; // a reindex is already in flight
        }
        let base = env::var("BEAGLE_MEMORY_ENGINE_URL").unwrap_or_else(|_| {
            "http://beagle-memory-engine.beagle-memory-lab.svc.cluster.local:8090".to_string()
        });
        let url = format!("{}/v1/index/semantic/rebuild", base.trim_end_matches('/'));
        // The semantic index is a full_overwrite of the most-recent `limit` SOURCE records, so a
        // small limit windows older data OUT of the searchable index (canonical store keeps all).
        // Default high enough to cover the whole corpus cumulatively; tunable without a rebuild as
        // it grows. The memory-engine rebuild is memory-bounded (batched) + parallel, so a full
        // rebuild is minutes — fine after the 30s debounce coalesces an ingest burst.
        let reindex_limit = env::var("BEAGLE_REINDEX_LIMIT")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(1_000_000);
        // A full-corpus rebuild far exceeds the old 300s; the POST blocks until the rebuild ends,
        // so give it room. Tunable for very large corpora.
        let reindex_timeout = env::var("BEAGLE_REINDEX_TIMEOUT_SECS")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(3600);
        let result = async {
            let client = reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(reindex_timeout))
                .build()?;
            client
                .post(&url)
                .json(&serde_json::json!({ "limit": reindex_limit }))
                .send()
                .await
        }
        .await;
        match result {
            Ok(resp) => {
                tracing::info!("auto-reindex after ingest: {}", resp.status());
                // Event-driven: the rebuild POST blocks until the reindex is done, so the index is
                // now fresh — tell the cockpit to push updated status to its SSE clients immediately.
                let notify = env::var("BEAGLE_COCKPIT_NOTIFY_URL").unwrap_or_else(|_| {
                    "http://cockpit-web.beagle.svc.cluster.local:8080/api/memory-status/notify"
                        .to_string()
                });
                if let Ok(client) = reqwest::Client::builder()
                    .timeout(std::time::Duration::from_secs(10))
                    .build()
                {
                    let _ = client
                        .post(&notify)
                        .json(&serde_json::json!({}))
                        .send()
                        .await;
                }
            }
            Err(err) => tracing::warn!("auto-reindex after ingest failed: {}", err),
        }
        REINDEX_RUNNING.store(false, SeqCst);
    });
}

pub(crate) async fn omnimemory_import_handler(
    State(_state): State<AppState>,
    Json(req): Json<ImportConversationRequest>,
) -> Result<Json<OmniConversation>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let imported = repo.import_conversation(req).map_err(internal_error)?;
    trigger_reindex_debounced();
    Ok(Json(imported))
}

pub(crate) async fn memory_assisted_import_handler(
    State(_state): State<AppState>,
    Json(req): Json<AssistedImportBatchRequest>,
) -> Result<Json<AssistedImportBatchResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let result = repo.assisted_import_batch(req).map_err(internal_error)?;
    trigger_reindex_debounced();
    Ok(Json(result))
}

/// Resolve the caller's effective scopes from the bearer token, mirroring `api_token_auth`.
///
/// Returns `(granted_scopes, principal)`. An empty scope list means the caller is
/// unauthenticated/unknown — in that case the probe falls back to whatever scopes the
/// client declared in the request body (backward compatible).
pub(crate) async fn resolve_probe_scopes(
    state: &AppState,
    headers: &HeaderMap,
) -> (Vec<String>, Option<String>) {
    fn scopes_for(id: ConsumerId) -> Vec<String> {
        match id {
            ConsumerId::BeagleOperator => vec![
                "exocortex:read".to_string(),
                "memory:write".to_string(),
                "chronoself:write".to_string(),
                "research:run".to_string(),
                "agent:start".to_string(),
            ],
            ConsumerId::DarwinResearch => {
                vec!["exocortex:read".to_string(), "research:run".to_string()]
            }
        }
    }
    fn principal_of(id: ConsumerId) -> Option<String> {
        Some(consumer_identity_for_id(id).id)
    }

    let auth = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .unwrap_or("");
    let bearer = auth.strip_prefix("Bearer ").map(str::trim).unwrap_or("");

    let ctx = state.ctx.lock().await;

    // Consumer-policy-aware path (mirrors api_token_auth).
    if ctx.cfg.consumers.policy_enabled {
        let consumer_header = headers
            .get("X-Beagle-Consumer")
            .and_then(|h| h.to_str().ok())
            .unwrap_or("");
        if let Some(consumer_id) = ConsumerId::from_header(consumer_header) {
            let expected = match consumer_id {
                ConsumerId::BeagleOperator => ctx
                    .cfg
                    .consumers
                    .operator_token
                    .as_deref()
                    .or(ctx.cfg.api_token.as_deref()),
                ConsumerId::DarwinResearch => ctx.cfg.consumers.research_token.as_deref(),
            };
            if let Some(tok) = expected {
                if !bearer.is_empty() && bearer == tok {
                    return (scopes_for(consumer_id), principal_of(consumer_id));
                }
            }
        }
        return (Vec::new(), None);
    }

    // Consumer policy disabled.
    match ctx.cfg.api_token.as_deref() {
        Some(expected) => {
            if !bearer.is_empty() && bearer == expected {
                (
                    scopes_for(ConsumerId::BeagleOperator),
                    principal_of(ConsumerId::BeagleOperator),
                )
            } else {
                (Vec::new(), None)
            }
        }
        // No token configured (dev/lab): the deployment is unauthenticated, so the probe
        // reflects that an operator-equivalent caller can write — same posture as api_token_auth.
        None => (
            scopes_for(ConsumerId::BeagleOperator),
            principal_of(ConsumerId::BeagleOperator),
        ),
    }
}

pub(crate) async fn write_probe_handler(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(mut req): Json<WriteProbeRequest>,
) -> Result<Json<WriteProbeResponse>, StatusCode> {
    // Derive the caller's real scopes from the bearer token instead of trusting the
    // self-declared `granted_scopes` in the body. Token-derived scopes are unioned with any
    // client-declared ones so explicit callers still work.
    let (token_scopes, principal) = resolve_probe_scopes(&state, &headers).await;
    if !token_scopes.is_empty() {
        let mut merged: BTreeSet<String> = req
            .granted_scopes
            .iter()
            .map(|scope| scope.trim().to_string())
            .filter(|scope| !scope.is_empty())
            .collect();
        merged.extend(token_scopes);
        req.granted_scopes = merged.into_iter().collect();
        if req
            .principal
            .as_deref()
            .map(str::trim)
            .unwrap_or("")
            .is_empty()
        {
            req.principal = principal;
        }
        if req
            .source_surface
            .as_deref()
            .map(str::trim)
            .unwrap_or("")
            .is_empty()
        {
            req.source_surface = Some("beagle-core-token".to_string());
        }
    }

    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let result = repo.write_probe(req).map_err(internal_error)?;
    Ok(Json(result))
}

pub(crate) async fn failed_writes_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<FailedWriteInboxResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let items = repo
        .failed_write_inbox(query.limit.unwrap_or(50))
        .map_err(internal_error)?;
    Ok(Json(FailedWriteInboxResponse { items }))
}

pub(crate) async fn failed_write_record_handler(
    State(_state): State<AppState>,
    Json(req): Json<FailedWriteRecordRequest>,
) -> Result<Json<FailedWriteInboxItem>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let item = repo.record_failed_write(req).map_err(internal_error)?;
    Ok(Json(item))
}

pub(crate) async fn failed_write_rescue_handler(
    State(_state): State<AppState>,
    Json(req): Json<FailedWriteRescueRequest>,
) -> Result<Json<FailedWriteRescueResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo.rescue_failed_write(req).map_err(internal_error)?;
    Ok(Json(response))
}

pub(crate) async fn context_compile_handler(
    State(_state): State<AppState>,
    Json(req): Json<ContextCompileRequest>,
) -> Result<Json<ContextPack>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let pack = repo.context_compile(req).map_err(internal_error)?;
    Ok(Json(pack))
}

pub(crate) async fn context_pack_get_handler(
    State(_state): State<AppState>,
    Path(pack_id): Path<String>,
) -> Result<Json<ContextPack>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    repo.context_pack(&pack_id)
        .map_err(internal_error)?
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

pub(crate) async fn memory_effectiveness_event_handler(
    State(_state): State<AppState>,
    Json(req): Json<MemoryEffectivenessEventRequest>,
) -> Result<Json<MemoryEffectivenessEvent>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let event = repo
        .record_memory_effectiveness(req)
        .map_err(internal_error)?;
    Ok(Json(event))
}

pub(crate) async fn memory_policy_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryPolicyStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_policy_status().map_err(internal_error)?;
    Ok(Json(status))
}

pub(crate) async fn memory_dreamcycle_run_handler(
    State(_state): State<AppState>,
    Json(req): Json<DreamCycleRunRequest>,
) -> Result<Json<DreamCycleRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.run_dreamcycle(req).map_err(internal_error)?;
    Ok(Json(run))
}

pub(crate) async fn memory_dreamcycle_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<DreamCycleStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.dreamcycle_status().map_err(internal_error)?;
    Ok(Json(status))
}

pub(crate) async fn memory_export_handler(
    State(_state): State<AppState>,
    Json(req): Json<MemoryExportRequest>,
) -> Result<Json<MemoryExportResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let export = repo.export_sanitized_memory(req).map_err(internal_error)?;
    Ok(Json(export))
}

pub(crate) async fn memory_candidates_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<MemoryCandidateListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let candidates = repo
        .latest_memory_candidates(query.limit.unwrap_or(50))
        .map_err(internal_error)?;
    Ok(Json(MemoryCandidateListResponse { candidates }))
}

pub(crate) async fn memory_candidate_create_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateMemoryCandidateRequest>,
) -> Result<Json<MemoryCandidate>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let candidate = repo.create_memory_candidate(req).map_err(internal_error)?;
    Ok(Json(candidate))
}

pub(crate) async fn memory_candidate_quorum_handler(
    State(_state): State<AppState>,
    Path(candidate_id): Path<String>,
    Json(req): Json<CandidateQuorumRequest>,
) -> Result<Json<CandidateQuorumDecision>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let decision = repo
        .record_candidate_quorum(&candidate_id, req)
        .map_err(internal_error)?;
    Ok(Json(decision))
}

pub(crate) async fn memory_candidate_promote_handler(
    State(_state): State<AppState>,
    Path(candidate_id): Path<String>,
    Json(req): Json<CandidatePromoteRequest>,
) -> Result<Json<CandidatePromotionResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo
        .promote_memory_candidate(&candidate_id, req)
        .map_err(internal_error)?;
    Ok(Json(response))
}

pub(crate) async fn memory_governance_run_handler(
    State(_state): State<AppState>,
    Json(req): Json<MemoryGovernanceRunRequest>,
) -> Result<Json<MemoryGovernanceRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.run_memory_governance(req).map_err(internal_error)?;
    Ok(Json(run))
}

pub(crate) async fn memory_governance_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryGovernanceStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_governance_status().map_err(internal_error)?;
    Ok(Json(status))
}

pub(crate) async fn memory_contradictions_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<MemoryContradictionListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let contradictions = repo
        .read_recent_jsonl::<MemoryContradiction>(
            MEMORY_CONTRADICTIONS_LOG,
            query.limit.unwrap_or(50),
        )
        .map_err(internal_error)?;
    Ok(Json(MemoryContradictionListResponse { contradictions }))
}

pub(crate) async fn temporal_analyze_handler(
    State(_state): State<AppState>,
    Json(req): Json<TemporalAnalyzeRequest>,
) -> Result<Json<TemporalAnalysis>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let analysis = repo.analyze_temporal(req).map_err(internal_error)?;
    Ok(Json(analysis))
}

pub(crate) async fn audit_events_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<AuditEventListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let events = repo
        .read_recent_jsonl::<AuditEvent>(AUDIT_LOG, query.limit.unwrap_or(50))
        .map_err(internal_error)?;
    Ok(Json(AuditEventListResponse { events }))
}

pub(crate) async fn audit_event_create_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateAuditEventRequest>,
) -> Result<Json<AuditEvent>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let event = repo.create_audit_event(req).map_err(internal_error)?;
    Ok(Json(event))
}

pub(crate) async fn memory_events_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<MemoryEventListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let events = repo
        .read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, query.limit.unwrap_or(50))
        .map_err(internal_error)?;
    Ok(Json(MemoryEventListResponse { events }))
}

pub(crate) async fn memory_event_create_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateMemoryEventRequest>,
) -> Result<Json<MemoryEvent>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let event = repo.create_memory_event(req).map_err(internal_error)?;
    Ok(Json(event))
}

pub(crate) async fn memory_project_handler(
    State(_state): State<AppState>,
    Json(req): Json<ProjectMemoryRequest>,
) -> Result<Json<MemoryProjectionRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.project_memory(req).map_err(internal_error)?;
    Ok(Json(run))
}

pub(crate) async fn memory_projection_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryProjectionStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_projection_status().map_err(internal_error)?;
    Ok(Json(status))
}

pub(crate) async fn memory_graph_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryGraphStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_graph_status().map_err(internal_error)?;
    Ok(Json(status))
}

pub(crate) async fn memory_bench_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryBenchmarkStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_benchmark_status().map_err(internal_error)?;
    Ok(Json(status))
}

pub(crate) async fn memory_graph_bakeoff_handler(
    State(_state): State<AppState>,
    Json(req): Json<GraphBakeoffRequest>,
) -> Result<Json<GraphBakeoffRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.run_graph_bakeoff(req).map_err(internal_error)?;
    Ok(Json(run))
}

pub(crate) async fn memory_graph_bakeoff_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryGraphStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_graph_status().map_err(internal_error)?;
    Ok(Json(status))
}

pub(crate) async fn memory_index_graph_handler(
    State(_state): State<AppState>,
    Json(req): Json<GraphIndexRequest>,
) -> Result<Json<GraphIndexRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.index_graph(req).map_err(internal_error)?;
    Ok(Json(run))
}

pub(crate) async fn memory_graph_recent_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<MemoryGraphRecentResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo
        .memory_graph_recent(query.limit.unwrap_or(12))
        .map_err(internal_error)?;
    Ok(Json(response))
}

pub(crate) async fn memory_worlds_recent_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<MemoryWorldsRecentResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo
        .memory_worlds_recent(query.limit.unwrap_or(12))
        .map_err(internal_error)?;
    Ok(Json(response))
}

pub(crate) async fn graphrag_query_handler(
    State(_state): State<AppState>,
    Json(req): Json<GraphRagQueryRequest>,
) -> Result<Json<GraphRagQueryResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo.graphrag_query(req).map_err(internal_error)?;
    Ok(Json(response))
}

#[derive(Serialize)]
pub(crate) struct RecallSource {
    pub(crate) n: usize,
    pub(crate) text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) date: Option<String>,
    pub(crate) source: String,
    pub(crate) score: f64,
}

#[derive(Serialize)]
pub(crate) struct RecallAnswerResponse {
    answer: String,
    sources: Vec<RecallSource>,
    confidence: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    scope: Option<String>,
    schema_version: String,
}

/// COMPOSED RECALL (cognitive loop slice a), promoted to a first-class exocortex capability:
/// retrieve project-scoped atoms (graphRAG / ColBERT) then SYNTHESIZE a composed natural-language
/// answer via the TieredRouter (fleet-first). Any client (cockpit, native app, MCP) can use it —
/// the synthesis no longer lives only in the cockpit's coord-mcp.
// --- Path C: prefer the memory-engine semantic index (jina-colbert-v2 multivector) which
// reranks rich conversation passages to the top, over the degraded graphrag atom projection.
#[derive(Debug, Deserialize)]
struct MemoryEngineSemanticResult {
    #[serde(default)]
    text_preview: String,
    #[serde(default)]
    score: Option<f64>,
    #[serde(default)]
    occurred_at: Option<String>,
    #[serde(default)]
    kind: Option<String>,
}

#[derive(Debug, Deserialize)]
struct MemoryEngineQueryResponse {
    #[serde(default)]
    semantic_results: Vec<MemoryEngineSemanticResult>,
}

/// Retrieve rich passages from the memory-engine `/v1/query`. Fail-soft: returns an empty
/// vec on any error so the caller falls back to the local graphrag projection.
pub(crate) async fn memory_engine_recall(query: &str, scope: &str, k: usize) -> Vec<RecallSource> {
    let base = env::var("BEAGLE_MEMORY_ENGINE_URL").unwrap_or_else(|_| {
        "http://beagle-memory-engine.beagle-memory-lab.svc.cluster.local:8090".to_string()
    });
    let url = format!("{}/v1/query", base.trim_end_matches('/'));
    let body = serde_json::json!({ "query": query, "scope": scope, "max_items": k });
    let client = match reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
    {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    let resp = match client.post(&url).json(&body).send().await {
        Ok(r) if r.status().is_success() => r,
        _ => return Vec::new(),
    };
    let parsed: MemoryEngineQueryResponse = match resp.json().await {
        Ok(p) => p,
        Err(_) => return Vec::new(),
    };
    parsed
        .semantic_results
        .into_iter()
        .filter(|r| r.text_preview.trim().chars().count() >= 40)
        .take(k)
        .enumerate()
        .map(|(i, r)| RecallSource {
            n: i + 1,
            text: r.text_preview,
            date: r.occurred_at,
            source: r.kind.unwrap_or_else(|| "memory-engine".to_string()),
            score: r.score.unwrap_or(0.0),
        })
        .collect()
}

pub(crate) async fn recall_answer_handler(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<GraphRagQueryRequest>,
) -> Result<Json<RecallAnswerResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let scope = req.scope.clone();
    let query = req.query.clone();
    let k = req.max_items.unwrap_or(8).min(12);
    // Path C: try the memory-engine semantic index first (rich passages); fall back to the
    // local graphrag atom projection if it yields nothing (or the engine is unreachable).
    let mut sources = memory_engine_recall(&query, scope.as_deref().unwrap_or("all"), k).await;
    let mut confidence = if sources.is_empty() { 0.0 } else { 0.85 };
    if sources.is_empty() {
        let gr = repo.graphrag_query(req).map_err(internal_error)?;
        confidence = gr.confidence;
        let atom_sources: Vec<RecallSource> = gr
            .atoms
            .iter()
            .take(k)
            .map(|a| RecallSource {
                n: 0,
                text: a.text.clone(),
                date: a.occurred_at.clone().or_else(|| Some(a.created_at.clone())),
                source: if a.atom_type.is_empty() {
                    "exocortex".to_string()
                } else {
                    a.atom_type.clone()
                },
                score: a.confidence,
            })
            .filter(|s| !s.text.is_empty())
            .collect();
        // Enrich the degraded atom projection with rich conversation passages so that a
        // memory-engine outage still surfaces real passages. Fail-soft: on error, use none.
        let passage_sources = match repo.lexical_passage_search(&query, k) {
            Ok(p) => p,
            Err(e) => {
                tracing::warn!(
                    "lexical_passage_search failed (fallback enrichment skipped): {e:#}"
                );
                Vec::new()
            }
        };
        let passages_contributed = !passage_sources.is_empty();
        // Merge: concatenate, sort by score desc, dedup near-duplicates, renumber, take k.
        let mut candidates: Vec<RecallSource> =
            atom_sources.into_iter().chain(passage_sources).collect();
        candidates.sort_by(|a, b| {
            b.score
                .partial_cmp(&a.score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        let mut kept: Vec<RecallSource> = Vec::new();
        for cand in candidates {
            let cand_text = cand.text.trim();
            if cand_text.is_empty() {
                continue;
            }
            let cand_prefix: String = cand_text.chars().take(80).collect();
            let is_dup = kept.iter().any(|keep| {
                let keep_text = keep.text.trim();
                let keep_prefix: String = keep_text.chars().take(80).collect();
                keep_text.contains(cand_prefix.as_str()) || cand_text.contains(keep_prefix.as_str())
            });
            if is_dup {
                continue;
            }
            kept.push(cand);
            if kept.len() >= k {
                break;
            }
        }
        for (i, s) in kept.iter_mut().enumerate() {
            s.n = i + 1;
        }
        sources = kept;
        // Modest confidence bump when rich passages contributed to the fallback result.
        if passages_contributed {
            confidence = (confidence + 0.1).min(0.8);
        }
    }
    if sources.is_empty() {
        return Ok(Json(RecallAnswerResponse {
            answer: "No memory found for this query.".to_string(),
            sources: Vec::new(),
            confidence: 0.0,
            scope,
            schema_version: "beagle-recall-answer-v1".to_string(),
        }));
    }
    let ctx_str = sources
        .iter()
        .map(|s| {
            format!(
                "[{}] ({}) {}",
                s.n,
                s.date.as_deref().unwrap_or("?"),
                s.text
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    let prompt = format!(
        "You are the recall-synthesis layer of an exocortex. Compose a CLEAR, GLANCEABLE answer from ONLY the memory atoms below. Format EXACTLY like this:\n**<headline: one line, max 14 words, no citation>**\n- **<2-4 word lead-in>:** <one specific sentence with names, versions, numbers> [n]\n(3 to 6 bullets, ordered by importance, merge duplicate facts, cite the atom(s) each draws from as [n], and on conflict keep the most recent). No preamble, no closing.\n\nQuestion: {query}\n\nMemory atoms:\n{ctx_str}"
    );
    let answer = {
        let mut bctx = state.ctx.lock().await;
        // Recall synthesis is SUMMARIZATION, never math/PhD reasoning. Deriving the meta from the
        // prompt (from_prompt) made GPU/u64/"equation" passages trip requires_math → the slow
        // DeepSeek/heavy tier (6-30s). Use a neutral meta so it routes to the fast local fleet.
        // Populate identity from X-Beagle-Consumer so the per-identity rate limiter (gated by
        // BEAGLE_LLM_RATE_CAPACITY) can key on the caller. Absent header → None → no change.
        let consumer_identity = headers
            .get("X-Beagle-Consumer")
            .and_then(|v| v.to_str().ok())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string());
        let meta = RequestMeta {
            approximate_tokens: prompt.len() / 4,
            identity: consumer_identity,
            ..Default::default()
        };
        let stats = bctx.llm_stats.get_or_create("recall_answer");
        let (client, tier) = bctx.router.choose_with_limits(&meta, &stats);
        match bctx.router.complete_chosen(&client, tier, &prompt).await {
            Ok(a) => a.trim().to_string(),
            Err(e) => {
                // Fail-soft: a synthesis-model hiccup must NEVER fail recall (was 502). The
                // retrieved, cited passages are the valuable part — return them with a note so
                // the caller still gets real memory instead of an error.
                error!(
                    "recall synthesis failed (returning retrieved passages): {}",
                    e
                );
                let mut lines = vec![format!(
                    "(composed synthesis unavailable — showing retrieved memory)"
                )];
                for s in sources.iter().take(6) {
                    let snippet: String = s.text.chars().take(240).collect();
                    lines.push(format!("- [{}] {}", s.n, snippet));
                }
                lines.join("\n")
            }
        }
    };
    Ok(Json(RecallAnswerResponse {
        answer: answer.trim().to_string(),
        sources,
        confidence,
        scope,
        schema_version: "beagle-recall-answer-v1".to_string(),
    }))
}

/// Request for POST /api/(exocortex/v1/)propose — the cockpit Recall "Next" mode.
#[derive(Debug, serde::Deserialize)]
pub(crate) struct ProposeRequest {
    #[serde(default)]
    pub scope: Option<String>,
}

/// One proposed next step (matches the iOS `Proposal` Codable: title/why/effort).
#[derive(Debug, Clone, serde::Serialize)]
pub(crate) struct Proposal {
    pub title: String,
    pub why: String,
    pub effort: String,
}

#[derive(Debug, serde::Deserialize)]
pub(crate) struct AcceptRequest {
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub why: String,
    #[serde(default)]
    pub scope: Option<String>,
}

#[derive(Debug, serde::Serialize)]
pub(crate) struct AcceptResponse {
    pub ok: bool,
}

/// Parse proposals from an LLM reply: first balanced JSON object, then
/// `{"proposals":[{title,why,effort}]}`. Fail-soft → empty vec (never errors).
fn parse_proposals(raw: &str) -> Vec<Proposal> {
    let Some(start) = raw.find('{') else {
        return Vec::new();
    };
    let mut depth = 0i32;
    let mut end = None;
    for (i, ch) in raw[start..].char_indices() {
        match ch {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    end = Some(start + i + ch.len_utf8());
                    break;
                }
            }
            _ => {}
        }
    }
    let Some(end) = end else {
        return Vec::new();
    };
    let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw[start..end]) else {
        return Vec::new();
    };
    let Some(arr) = v.get("proposals").and_then(|p| p.as_array()) else {
        return Vec::new();
    };
    arr.iter()
        .filter_map(|p| {
            let title = p.get("title")?.as_str()?.trim().to_string();
            if title.is_empty() {
                return None;
            }
            let why = p
                .get("why")
                .and_then(|x| x.as_str())
                .unwrap_or("")
                .trim()
                .to_string();
            let effort = p
                .get("effort")
                .and_then(|x| x.as_str())
                .map(|s| s.trim().to_uppercase())
                .filter(|s| matches!(s.as_str(), "S" | "M" | "L"))
                .unwrap_or_else(|| "M".to_string());
            Some(Proposal { title, why, effort })
        })
        .take(6)
        .collect()
}

/// POST /api/(exocortex/v1/)propose — the fleet proposes next steps for a scope,
/// grounded in recalled exocortex memory. Mirrors `recall_answer_handler`'s
/// retrieval + LLM-synthesis pattern; fail-soft (LLM/parse failure → empty
/// proposals, never 5xx — the retrieved sources are still returned).
pub(crate) async fn propose_handler(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<ProposeRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let scope = req.scope.clone();
    let scope_s = scope.clone().unwrap_or_else(|| "all".to_string());
    let sources = memory_engine_recall(
        &format!("recent work, open threads, blockers, and next steps for {scope_s}"),
        &scope_s,
        8,
    )
    .await;

    let mut model: Option<String> = None;
    let proposals = if sources.is_empty() {
        Vec::new()
    } else {
        let ctx_str = sources
            .iter()
            .map(|s| {
                format!(
                    "[{}] ({}) {}",
                    s.n,
                    s.date.as_deref().unwrap_or("?"),
                    s.text
                )
            })
            .collect::<Vec<_>>()
            .join("\n");
        let prompt = format!(
            "You are the planning layer of an exocortex. From the memory atoms below \
             (recent state/work in scope '{scope_s}'), propose 3-5 CONCRETE next steps. \
             Each has: a short imperative `title`, a one-sentence `why` grounded in the \
             atoms, and an `effort` of exactly S, M, or L. Respond with ONLY JSON, no \
             prose:\n{{\"proposals\":[{{\"title\":\"...\",\"why\":\"...\",\"effort\":\"S|M|L\"}}]}}\n\n\
             Memory atoms:\n{ctx_str}"
        );
        let consumer_identity = headers
            .get("X-Beagle-Consumer")
            .and_then(|v| v.to_str().ok())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string());
        let raw = {
            let mut bctx = state.ctx.lock().await;
            let meta = RequestMeta {
                approximate_tokens: prompt.len() / 4,
                identity: consumer_identity,
                ..Default::default()
            };
            let stats = bctx.llm_stats.get_or_create("propose");
            let (client, tier) = bctx.router.choose_with_limits(&meta, &stats);
            model = Some(format!("{tier:?}"));
            match bctx.router.complete_chosen(&client, tier, &prompt).await {
                Ok(a) => a,
                Err(e) => {
                    error!("propose synthesis failed (returning empty proposals): {e}");
                    String::new()
                }
            }
        };
        parse_proposals(&raw)
    };

    Ok(Json(serde_json::json!({
        "proposals": proposals,
        "sources": sources,
        "model": model,
        "scope": scope,
    })))
}

/// POST /api/(exocortex/v1/)propose/accept — log an accepted proposal to the durable
/// proposals board (a JSONL in the exocortex root). Returns `{ok:true}`.
pub(crate) async fn accept_handler(
    State(_state): State<AppState>,
    Json(req): Json<AcceptRequest>,
) -> Result<Json<AcceptResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let entry = serde_json::json!({
        "ts": Utc::now().to_rfc3339(),
        "kind": "proposal_accepted",
        "scope": req.scope,
        "title": req.title,
        "why": req.why,
    });
    let path = repo.root.join("proposals_board.jsonl");
    use std::io::Write as _;
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|e| internal_error(anyhow::Error::from(e)))?;
    writeln!(f, "{entry}").map_err(|e| internal_error(anyhow::Error::from(e)))?;
    Ok(Json(AcceptResponse { ok: true }))
}

pub(crate) async fn active_projects_handler(
    State(_state): State<AppState>,
) -> Result<Json<ProjectStateListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let projects = repo.active_projects().map_err(internal_error)?;
    Ok(Json(ProjectStateListResponse { projects }))
}

pub(crate) fn internal_error(error: anyhow::Error) -> StatusCode {
    error!("Exocortex API error: {:#}", error);
    StatusCode::INTERNAL_SERVER_ERROR
}

pub(crate) fn chronoself_hash(
    self_version: &str,
    parent_commit_ids: &[String],
    context_snapshot: &ContextSnapshot,
    identity_delta: &IdentityDelta,
    trigger_type: &str,
) -> anyhow::Result<String> {
    let mut hasher = Sha256::new();
    hasher.update(self_version.as_bytes());
    hasher.update(serde_json::to_vec(parent_commit_ids)?);
    hasher.update(serde_json::to_vec(context_snapshot)?);
    hasher.update(serde_json::to_vec(identity_delta)?);
    hasher.update(trigger_type.as_bytes());
    Ok(hex_digest(hasher.finalize()))
}

pub(crate) fn content_hash(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex_digest(hasher.finalize())
}

pub(crate) fn hex_digest(bytes: impl AsRef<[u8]>) -> String {
    bytes
        .as_ref()
        .iter()
        .map(|byte| format!("{:02x}", byte))
        .collect()
}

pub(crate) fn confidence_for_delta(delta: &IdentityDelta) -> f64 {
    let change_count = delta.beliefs_added.len()
        + delta.beliefs_removed.len()
        + delta.values_changed.len()
        + delta.product_principles.len();
    (1.0 - (change_count as f64 * 0.05)).clamp(0.60, 0.95)
}

pub(crate) fn format_target_hardware_context(
    hardware: &TargetHardware,
    platform: Option<&str>,
) -> String {
    let phone = hardware.phone.as_deref().unwrap_or("iPhone");
    let watch = hardware.watch.as_deref().unwrap_or("Apple Watch");
    let mut context = format!(
        "Alvo Apple principal: {} como superfície íntima do Exocortex e {} como sensor corporal/microinterface.",
        phone, watch
    );
    if let Some(platform) = platform {
        context.push_str(&format!(" Superfície ativa: {}.", platform));
    }
    if let Some(note) = hardware.notes.first() {
        context.push_str(&format!(" {}", truncate_chars(note, 180)));
    }
    context
}

pub(crate) fn detect_candidate_contradictions(
    candidate: &MemoryCandidate,
    atoms: &[MemoryAtom],
) -> Vec<MemoryContradiction> {
    let candidate_tokens = tokenize(&candidate.normalized_text);
    let candidate_negated = contains_any(
        &candidate.normalized_text,
        &[
            " not ", " nao ", " não ", " never ", " sem ", " contra ", " reject ",
        ],
    );
    let mut contradictions = Vec::new();
    for atom in atoms
        .iter()
        .filter(|atom| atom.privacy_class != "restricted")
    {
        let overlap = candidate_tokens
            .iter()
            .filter(|token| atom.normalized_text.contains(token.as_str()))
            .count();
        if overlap < 3 {
            continue;
        }
        let atom_negated = contains_any(
            &atom.normalized_text,
            &[
                " not ", " nao ", " não ", " never ", " sem ", " contra ", " reject ",
            ],
        );
        if candidate_negated == atom_negated {
            continue;
        }
        let id = stable_id("contradiction", &[&candidate.id, &atom.id]);
        if contradictions
            .iter()
            .any(|item: &MemoryContradiction| item.id == id)
        {
            continue;
        }
        contradictions.push(MemoryContradiction {
            id,
            created_at: Utc::now().to_rfc3339(),
            subject_ref: format!("memory_candidate:{}", candidate.id),
            conflicting_ref: format!("memory_atom:{}", atom.id),
            description: format!(
                "Candidate '{}' conflicts with projected atom '{}'.",
                truncate_chars(&candidate.text, 180),
                truncate_chars(&atom.text, 180)
            ),
            severity: if overlap >= 5 { "high" } else { "medium" }.to_string(),
            status: "open".to_string(),
            evidence_refs: std::iter::once(format!("memory_atom:{}", atom.id))
                .chain(candidate.source_refs.clone())
                .collect(),
            detected_by: "memory-governor-v1.6".to_string(),
        });
    }
    contradictions
}

pub(crate) fn self_version_from_commit(commit: &ChronoselfCommit) -> SelfVersion {
    SelfVersion {
        id: commit.self_version.clone(),
        label: commit
            .summary
            .clone()
            .unwrap_or_else(|| "Current self".to_string()),
        period_start: commit.created_at.clone(),
        period_end: None,
        dominant_beliefs: commit.identity_delta.beliefs_added.clone(),
        core_values: commit
            .identity_delta
            .values_changed
            .iter()
            .map(|value| CoreValue {
                name: value.value.clone(),
                strength: value.new_strength,
            })
            .collect(),
        cognitive_style: commit
            .identity_delta
            .cognitive_style_shift
            .clone()
            .unwrap_or_else(|| "cluster-first continuity".to_string()),
        risk_tolerance: 0.5,
        source_commit_id: Some(commit.id.clone()),
    }
}

pub(crate) fn default_self_version() -> SelfVersion {
    let now = Utc::now().to_rfc3339();
    SelfVersion {
        id: "v0.bootstrap".to_string(),
        label: "Bootstrap Self".to_string(),
        period_start: now,
        period_end: None,
        dominant_beliefs: vec!["Beagle is a cluster-first exocortex.".to_string()],
        core_values: vec![CoreValue {
            name: "continuity".to_string(),
            strength: 1.0,
        }],
        cognitive_style: "forming continuity".to_string(),
        risk_tolerance: 0.5,
        source_commit_id: None,
    }
}

pub(crate) fn extract_conversation_signals(raw: &str, tags: &[String]) -> OmniExtraction {
    let mut lines = raw
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();
    if lines.is_empty() && !raw.trim().is_empty() {
        lines.push(raw.trim());
    }
    let key_insights = lines
        .iter()
        .filter(|line| is_signal_line(line))
        .take(6)
        .map(|line| truncate_chars(line, 280))
        .collect::<Vec<_>>();
    let decisions = lines
        .iter()
        .filter(|line| {
            contains_any(
                line,
                &["decidi", "decisão", "decision", "vamos", "priorizar"],
            )
        })
        .take(6)
        .map(|line| truncate_chars(line, 240))
        .collect::<Vec<_>>();
    let hypotheses = lines
        .iter()
        .filter(|line| contains_any(line, &["hipótese", "hypothesis", "talvez", "maybe"]))
        .take(6)
        .map(|line| truncate_chars(line, 240))
        .collect::<Vec<_>>();
    let unresolved_questions = lines
        .iter()
        .filter(|line| line.ends_with('?'))
        .take(6)
        .map(|line| truncate_chars(line, 240))
        .collect::<Vec<_>>();
    OmniExtraction {
        key_insights,
        decisions,
        hypotheses,
        belief_changes: Vec::new(),
        emotional_state: None,
        identity_signals: None,
        projects_mentioned: tags
            .iter()
            .filter(|tag| tag.starts_with("project:"))
            .map(|tag| tag.trim_start_matches("project:").to_string())
            .collect(),
        unresolved_questions,
    }
}

pub(crate) fn contains_any(line: &str, needles: &[&str]) -> bool {
    let lower = line.to_lowercase();
    needles.iter().any(|needle| lower.contains(needle))
}

pub(crate) fn default_mcp_scopes() -> Vec<String> {
    [
        "exocortex:read",
        "memory:write",
        "chronoself:write",
        "research:run",
        "agent:start",
    ]
    .iter()
    .map(|scope| scope.to_string())
    .collect()
}

pub(crate) fn metadata_string(value: &serde_json::Value, key: &str) -> Option<String> {
    value
        .as_object()
        .and_then(|object| object.get(key))
        .and_then(|value| value.as_str())
        .map(|value| value.to_string())
}

pub(crate) fn metadata_f64(value: &serde_json::Value, key: &str) -> Option<f64> {
    value
        .as_object()
        .and_then(|object| object.get(key))
        .and_then(|value| value.as_f64())
}

pub(crate) fn metadata_usize(value: &serde_json::Value, key: &str) -> Option<usize> {
    value
        .as_object()
        .and_then(|object| object.get(key))
        .and_then(|value| value.as_u64())
        .and_then(|value| usize::try_from(value).ok())
}

pub(crate) fn metadata_bool(value: &serde_json::Value, key: &str) -> Option<bool> {
    value
        .as_object()
        .and_then(|object| object.get(key))
        .and_then(|value| value.as_bool())
}

pub(crate) fn metadata_array_strings(value: &serde_json::Value, key: &str) -> Option<Vec<String>> {
    value
        .as_object()
        .and_then(|object| object.get(key))
        .and_then(|value| value.as_array())
        .map(|values| {
            values
                .iter()
                .filter_map(|value| value.as_str())
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned)
                .collect::<Vec<_>>()
        })
}

pub(crate) fn metadata_string_array(
    metadata: &serde_json::Map<String, serde_json::Value>,
    key: &str,
) -> Vec<String> {
    match metadata.get(key) {
        Some(serde_json::Value::Array(values)) => values
            .iter()
            .filter_map(|value| value.as_str())
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .collect(),
        Some(serde_json::Value::String(value)) if !value.trim().is_empty() => {
            value.split_whitespace().map(ToOwned::to_owned).collect()
        }
        _ => Vec::new(),
    }
}

pub(crate) fn ensure_object(
    value: serde_json::Value,
) -> serde_json::Map<String, serde_json::Value> {
    match value {
        serde_json::Value::Object(object) => object,
        serde_json::Value::Null => serde_json::Map::new(),
        other => {
            let mut object = serde_json::Map::new();
            object.insert("raw_metadata".to_string(), other);
            object
        }
    }
}

pub(crate) fn assisted_raw_content(turns: &[AssistedImportTurn]) -> String {
    turns
        .iter()
        .enumerate()
        .map(|(index, turn)| {
            let timestamp = turn
                .timestamp
                .as_deref()
                .map(|value| format!(" @ {}", value))
                .unwrap_or_default();
            let model = turn
                .model
                .as_deref()
                .map(|value| format!("/{}", value))
                .unwrap_or_default();
            format!(
                "[{}:{}{}{}]\n{}",
                index + 1,
                turn.role.trim(),
                model,
                timestamp,
                turn.content
            )
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

pub(crate) fn project_slug(value: &str) -> String {
    value
        .trim()
        .to_lowercase()
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

pub(crate) fn upsert_project(projects: &mut Vec<ProjectState>, incoming: ProjectState) {
    if let Some(existing) = projects
        .iter_mut()
        .find(|project| project.id == incoming.id)
    {
        existing.status = incoming.status;
        merge_unique(&mut existing.recent_events, incoming.recent_events, 6);
        merge_unique(&mut existing.next_actions, incoming.next_actions, 6);
        merge_unique(&mut existing.linked_memories, incoming.linked_memories, 10);
        if incoming.last_interaction_at.as_deref() > existing.last_interaction_at.as_deref() {
            existing.last_interaction_at = incoming.last_interaction_at;
        }
    } else {
        projects.push(incoming);
    }
}

pub(crate) fn merge_unique(target: &mut Vec<String>, incoming: Vec<String>, limit: usize) {
    for item in incoming {
        if !item.trim().is_empty() && !target.contains(&item) {
            target.push(item);
        }
    }
    target.truncate(limit);
}

pub(crate) fn infer_sounio_moment_type(platform: &str, surface: &str, tags: &[String]) -> String {
    let haystack = std::iter::once(platform)
        .chain(std::iter::once(surface))
        .chain(tags.iter().map(String::as_str))
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase();
    if haystack.contains("watch") || haystack.contains("microintent") {
        "microintention".to_string()
    } else if haystack.contains("codex")
        || haystack.contains("claude-code")
        || haystack.contains("work")
        || haystack.contains("branch")
    {
        "work_memory".to_string()
    } else if haystack.contains("claim") || haystack.contains("paperrun") {
        "claim_seed".to_string()
    } else if haystack.contains("siri")
        || haystack.contains("share")
        || haystack.contains("beagle-apple")
    {
        "apple_capture".to_string()
    } else {
        "ambient_observation".to_string()
    }
}

pub(crate) fn is_signal_line(line: &str) -> bool {
    line.len() > 40
        && contains_any(
            line,
            &[
                "exocortex",
                "beagle",
                "memória",
                "memory",
                "chronoself",
                "temporal",
                "identidade",
                "identity",
                "decisão",
                "decision",
            ],
        )
}

pub(crate) fn normalize_source_platform(value: &str) -> String {
    match value.trim().to_lowercase().as_str() {
        "chatgpt" | "chat gpt" | "openai" => "chatgpt".to_string(),
        "claude" | "anthropic" => "claude".to_string(),
        "grok" | "xai" | "x.ai" => "grok".to_string(),
        "gemini" | "google" => "gemini".to_string(),
        other if !other.is_empty() => other.to_string(),
        _ => "other".to_string(),
    }
}

pub(crate) fn commit_matches_topic(commit: &ChronoselfCommit, topic_lc: &str) -> bool {
    let haystack = serde_json::to_string(commit)
        .unwrap_or_default()
        .to_lowercase();
    haystack.contains(topic_lc)
}

pub(crate) fn import_matches_topic(import: &OmniConversation, topic_lc: &str) -> bool {
    let haystack = serde_json::to_string(import)
        .unwrap_or_default()
        .to_lowercase();
    haystack.contains(topic_lc)
}

pub(crate) fn query_projected_memory_for_memory_api(
    query: beagle_memory::MemoryQuery,
) -> anyhow::Result<Option<beagle_memory::MemoryResult>> {
    let repo = ExocortexRepository::default();
    repo.ensure()?;
    let status = repo.memory_projection_status()?;
    if status.atom_count == 0 {
        return Ok(None);
    }
    let response = repo.graphrag_query(GraphRagQueryRequest {
        query: query.query,
        scope: query.scope,
        max_items: query.max_items,
        mode: None,
        ranking_policy: None,
    })?;
    Ok(Some(graphrag_to_memory_result(response)))
}

/// Persist the raw turns of a `/api/memory` chat session as a durable
/// conversation passage record in the exocortex store (the same
/// `conversation_passages.jsonl` used by the assisted-import path). Returns
/// `Ok(true)` when written, `Ok(false)` when skipped (restricted privacy class).
/// Callers should treat this as fail-soft and not abort ingest on `Err`.
pub(crate) fn append_conversation_passages(
    session: &beagle_memory::ChatSession,
) -> anyhow::Result<bool> {
    let repo = ExocortexRepository::default();
    repo.ensure()?;
    let source_platform = normalize_source_platform(&session.source);
    let privacy_class = normalize_privacy_class(
        session
            .metadata
            .get("privacy_class")
            .and_then(|value| value.as_str()),
    );
    let occurred_at = session
        .turns
        .iter()
        .find_map(|turn| turn.timestamp.map(|ts| ts.to_rfc3339()))
        .unwrap_or_else(|| Utc::now().to_rfc3339());
    let turns = session
        .turns
        .iter()
        .map(|turn| ConversationPassageTurn {
            role: turn.role.clone(),
            content: turn.content.clone(),
        })
        .collect::<Vec<_>>();
    // Deterministic record id: a content hash over session_id + every turn's
    // `role:content`. Re-ingesting the same session yields the same id => the
    // same canonical_id downstream => the memory-engine index overwrites rather
    // than duplicating the passages on rebuild.
    let mut id_material = String::with_capacity(session.session_id.len() + 64);
    id_material.push_str(&session.session_id);
    for turn in &turns {
        id_material.push('\n');
        id_material.push_str(&turn.role);
        id_material.push(':');
        id_material.push_str(&turn.content);
    }
    let id = format!("sha256:{}", content_hash(id_material.as_bytes()));
    repo.append_conversation_passages(
        id,
        Some(session.session_id.clone()),
        source_platform,
        occurred_at,
        privacy_class,
        turns,
    )
}

pub(crate) fn graphrag_to_memory_result(
    response: GraphRagQueryResponse,
) -> beagle_memory::MemoryResult {
    let highlights = response
        .evidence
        .iter()
        .map(|evidence| {
            let episode = response
                .episodes
                .iter()
                .find(|episode| episode.id == evidence.episode_id);
            beagle_memory::MemoryResultHighlight {
                source: episode
                    .map(|episode| episode.source.clone())
                    .unwrap_or_else(|| "graphrag++".to_string()),
                date: episode
                    .and_then(|episode| episode.occurred_at.as_deref())
                    .and_then(|date| chrono::DateTime::parse_from_rfc3339(date).ok())
                    .map(|date| date.with_timezone(&Utc)),
                snippet: evidence.text.clone(),
                run_id: None,
                session_id: episode.and_then(|episode| episode.session_id.clone()),
                relevance: evidence.score as f32,
            }
        })
        .collect();
    beagle_memory::MemoryResult {
        summary: response.summary,
        highlights,
        links: response
            .evidence
            .iter()
            .flat_map(|evidence| evidence.source_refs.clone())
            .map(serde_json::Value::String)
            .collect(),
    }
}

#[derive(Debug, Default)]
pub(crate) struct ProjectionOutcome {
    episodes_created: usize,
    atoms_created: usize,
    duplicates: usize,
}

pub(crate) fn default_sensitive_privacy_class() -> String {
    "sensitive".to_string()
}

pub(crate) fn default_assisted_source_surface() -> String {
    "mcp-visible-context".to_string()
}

pub(crate) fn default_assisted_import_scope() -> String {
    "current_conversation".to_string()
}

pub(crate) fn default_sounio_version() -> String {
    "0.1".to_string()
}

pub(crate) fn default_sounio_program_kind() -> String {
    "WorkProgram".to_string()
}

pub(crate) fn default_one_u32() -> u32 {
    1
}

pub(crate) fn normalize_privacy_class(value: Option<&str>) -> String {
    match value
        .unwrap_or("sensitive")
        .trim()
        .to_lowercase()
        .replace('-', "_")
        .as_str()
    {
        "public" => "public".to_string(),
        "restricted" | "secret" | "credential" => "restricted".to_string(),
        _ => "sensitive".to_string(),
    }
}

pub(crate) fn normalize_project_slug(value: &str) -> String {
    let slug = value
        .trim()
        .to_lowercase()
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .to_string();
    if slug.is_empty() {
        "sounio".to_string()
    } else {
        slug
    }
}

pub(crate) fn normalize_marble_model(value: Option<&str>) -> String {
    match value.unwrap_or("marble-1.1").trim().to_lowercase().as_str() {
        "marble-1.0-draft" | "marble-1.0" | "marble-1.1" | "marble-1.1-plus" => {
            value.unwrap_or("marble-1.1").trim().to_lowercase()
        }
        _ => "marble-1.1".to_string(),
    }
}

pub(crate) fn normalize_marble_permission(value: Option<&str>) -> String {
    match value
        .unwrap_or("private")
        .trim()
        .to_lowercase()
        .replace('-', "_")
        .as_str()
    {
        "public" => "public".to_string(),
        "unlisted" | "shared" => "unlisted".to_string(),
        _ => "private".to_string(),
    }
}

pub(crate) fn default_spatial_assets() -> SpatialAssetManifest {
    SpatialAssetManifest {
        pano_url: None,
        collider_mesh_url: None,
        hq_mesh_urls: Vec::new(),
        spz_urls: BTreeMap::new(),
        ply_urls: BTreeMap::new(),
        coordinate_system: Some("opencv:+x-left,+y-down,+z-forward".to_string()),
        coordinate_transform: Some("opencv_to_opengl:scale_yz_minus_one".to_string()),
        asset_root: env::var("BEAGLE_SPATIAL_ASSET_ROOT")
            .ok()
            .filter(|value| !value.trim().is_empty()),
        degraded_reason: Some("Marble assets pending; visionOS should use control room primitives until assets arrive.".to_string()),
    }
}

pub(crate) fn ensure_spatial_prompt_is_safe(prompt: &str) -> anyhow::Result<()> {
    let trimmed = prompt.trim();
    anyhow::ensure!(!trimmed.is_empty(), "spatial prompt cannot be empty");
    anyhow::ensure!(
        trimmed.len() <= 4000,
        "spatial prompt must be a sanitized summary under 4000 characters"
    );
    let lower = trimmed.to_lowercase();
    let blocked = [
        "client_secret",
        "refresh_token",
        "private key",
        "-----begin",
        "bearer ",
        "api_key",
        "password:",
        "passwd",
        "restricted:",
        "raw log",
        "token=",
        "sk-",
        "ghp_",
    ];
    anyhow::ensure!(
        !blocked.iter().any(|needle| lower.contains(needle)),
        "spatial prompt appears to contain restricted or secret material"
    );
    Ok(())
}

pub(crate) fn ensure_promoted_clip_is_safe(text: &str) -> anyhow::Result<()> {
    let trimmed = text.trim();
    anyhow::ensure!(
        !trimmed.is_empty(),
        "promoted portal clip requires explicit selected text"
    );
    anyhow::ensure!(
        trimmed.len() <= 12_000,
        "promoted portal clip must stay under 12000 characters"
    );
    let lower = trimmed.to_lowercase();
    let blocked = [
        "client_secret",
        "refresh_token",
        "private key",
        "-----begin",
        "bearer ",
        "api_key",
        "password:",
        "passwd",
        "restricted:",
        "raw log",
        "token=",
        "sk-",
        "ghp_",
    ];
    anyhow::ensure!(
        !blocked.iter().any(|needle| lower.contains(needle)),
        "promoted portal clip appears to contain restricted or secret material"
    );
    Ok(())
}

pub(crate) fn normalize_provider_label(value: &str) -> String {
    let normalized = value
        .trim()
        .to_lowercase()
        .replace(' ', "-")
        .replace('_', "-")
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '-')
        .collect::<String>();
    if normalized.is_empty() {
        "external-chat".to_string()
    } else {
        normalized
    }
}

pub(crate) fn mind_palace_project_room(
    project_slug: &str,
    source_family: &str,
    evidence_ref: Option<String>,
    priority: f64,
) -> MindPalaceRoom {
    let slug = normalize_project_slug(project_slug);
    let title = match slug.as_str() {
        "sounio" => "Sounio".to_string(),
        "beagle" => "Beagle".to_string(),
        "free-thought" | "free_thought" => "Free Thought".to_string(),
        other => title_case_label(other),
    };
    mind_palace_room(
        &format!("project-{}", slug),
        &title,
        "project",
        "active",
        Some(slug.clone()),
        source_family,
        "Project rooms are living drawers: they can run work, hold evidence, and stay open while other conversations continue.",
        &format!("Open the {} room and review its freshest memory signal.", title),
        priority,
        evidence_ref,
        vec![format!("project:{}", slug), "memory-derived".to_string()],
    )
}

pub(crate) fn mind_palace_room(
    id: &str,
    title: &str,
    room_type: &str,
    state: &str,
    project_slug: Option<String>,
    source_family: &str,
    tension: &str,
    next_action: &str,
    priority: f64,
    evidence_ref: Option<String>,
    tags: Vec<String>,
) -> MindPalaceRoom {
    let evidence_refs = evidence_ref.into_iter().collect::<Vec<_>>();
    MindPalaceRoom {
        id: id.to_string(),
        title: title.to_string(),
        room_type: room_type.to_string(),
        state: state.to_string(),
        project_slug,
        source_family: source_family.to_string(),
        tension: tension.to_string(),
        next_action: next_action.to_string(),
        freshness: if state == "active" || state == "available" {
            "fresh".to_string()
        } else {
            "remembered".to_string()
        },
        truth_mode: if evidence_refs.is_empty() {
            "declared".to_string()
        } else {
            "observed".to_string()
        },
        priority: priority.clamp(0.0, 1.0),
        desk_item_refs: Vec::new(),
        evidence_refs,
        tags: dedupe_strings(tags, 32),
        provenance: serde_json::json!({
            "schema_version": MIND_PALACE_SCHEMA,
            "memory_derived": true,
            "source_family": source_family
        }),
    }
}

pub(crate) fn upsert_mind_palace_room(
    rooms: &mut BTreeMap<String, MindPalaceRoom>,
    mut room: MindPalaceRoom,
) {
    if let Some(existing) = rooms.get_mut(&room.id) {
        existing.priority = existing.priority.max(room.priority);
        existing.state = if existing.state == "active" || room.state != "active" {
            existing.state.clone()
        } else {
            room.state.clone()
        };
        merge_unique(&mut existing.evidence_refs, room.evidence_refs, 48);
        merge_unique(&mut existing.tags, room.tags, 48);
        if existing.truth_mode != "observed" && !existing.evidence_refs.is_empty() {
            existing.truth_mode = "observed".to_string();
        }
        if existing.next_action.len() < room.next_action.len() {
            existing.next_action = room.next_action;
        }
    } else {
        room.evidence_refs = dedupe_strings(room.evidence_refs, 48);
        room.tags = dedupe_strings(room.tags, 48);
        rooms.insert(room.id.clone(), room);
    }
}

pub(crate) fn spatial_desk_agent_lanes() -> Vec<String> {
    vec![
        "Primary Builder: Claude/Codex".to_string(),
        "Code Worker: MiniMax-M2".to_string(),
        "Long Thought: Kimi K2".to_string(),
        "Maintainer: Qwen Coder".to_string(),
        "Platform Operator: GLM Air".to_string(),
        "Shell".to_string(),
        "Global Reader: Palmyra X5".to_string(),
        "Memory Experimenter: Jamba".to_string(),
        "Video Memory: Pegasus".to_string(),
        "Local Sensor: LFM2".to_string(),
    ]
}

pub(crate) fn title_case_label(value: &str) -> String {
    value
        .split(['-', '_'])
        .filter(|part| !part.is_empty())
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                Some(first) => format!("{}{}", first.to_uppercase(), chars.as_str()),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

pub(crate) fn normalize_transcription_segment(
    segment: TranscriptionSegment,
) -> TranscriptionSegment {
    TranscriptionSegment {
        text: truncate_chars(segment.text.trim(), 2000),
        start_ms: segment.start_ms,
        end_ms: segment.end_ms,
        confidence: segment.confidence.map(|value| value.clamp(0.0, 1.0)),
        source: segment
            .source
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty()),
    }
}

pub(crate) fn dedupe_strings(values: Vec<String>, limit: usize) -> Vec<String> {
    let mut seen = BTreeSet::new();
    let mut out = Vec::new();
    for value in values {
        let trimmed = value.trim();
        if trimmed.is_empty() || !seen.insert(trimmed.to_string()) {
            continue;
        }
        out.push(trimmed.to_string());
        if out.len() >= limit {
            break;
        }
    }
    out
}

pub(crate) fn projection_hash(
    episodes: &[MemoryEpisode],
    atoms: &[MemoryAtom],
) -> anyhow::Result<String> {
    let mut hasher = Sha256::new();
    hasher.update(MEMORY_PROJECTION_SCHEMA.as_bytes());
    hasher.update(serde_json::to_vec(episodes)?);
    hasher.update(serde_json::to_vec(atoms)?);
    Ok(format!("sha256:{}", hex_digest(hasher.finalize())))
}

pub(crate) fn graph_runtime_name() -> String {
    env::var("BEAGLE_MEMORY_ENGINE_RUNTIME")
        .or_else(|_| env::var("BEAGLE_GRAPHRAG_RUNTIME"))
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "federated-living-memory-mesh".to_string())
}

pub(crate) fn memory_hot_path_mode() -> String {
    env::var("BEAGLE_MEMORY_HOT_PATH")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "hypermemory_multivector".to_string())
}

pub(crate) fn retrieval_agent_mode() -> String {
    env::var("BEAGLE_RETRIEVAL_AGENT")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "canary".to_string())
}

pub(crate) fn retrieval_planner_mode() -> String {
    env::var("BEAGLE_RETRIEVAL_PLANNER")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "hybrid".to_string())
}

pub(crate) fn context_compiler_mode() -> String {
    env::var("BEAGLE_CONTEXT_COMPILER")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "shadow".to_string())
}

pub(crate) fn memory_policy_mode() -> String {
    env::var("BEAGLE_MEMORY_POLICY")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "observe".to_string())
}

pub(crate) fn dreamcycle_mode() -> String {
    env::var("BEAGLE_DREAMCYCLE")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "manual".to_string())
}

pub(crate) fn memory_policy_version() -> String {
    env::var("BEAGLE_MEMORY_POLICY_VERSION")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "beagle-memory-policy-v2.3-observe".to_string())
}

pub(crate) fn memory_policy_gate_json() -> serde_json::Value {
    serde_json::json!({
        "policy_version": memory_policy_version(),
        "policy_mode": memory_policy_mode(),
        "required_memoryarena_delta": 0.05,
        "required_token_savings": 0.25,
        "required_consecutive_runs": 3,
        "hard_gates": [
            "restricted_leak_zero",
            "provenance_complete",
            "no_critical_regression"
        ],
        "promotion": "observe/recommend only until private MemoryArena gates pass"
    })
}

pub(crate) fn retrieval_strategy_for(query: &str) -> String {
    let query = query.to_lowercase();
    if query.contains("codex")
        || query.contains("claude code")
        || query.contains("branch")
        || query.contains("commit")
        || query.contains("teste")
    {
        "work_memory_replay".to_string()
    } else if query.contains("contradi") || query.contains("conflit") {
        "contradiction_check".to_string()
    } else if query.contains("últim")
        || query.contains("ultima")
        || query.contains("desde")
        || query.contains("quando")
        || query.contains("timeline")
    {
        "temporal_trace".to_string()
    } else if query.contains("hipótese")
        || query.contains("hipotese")
        || query.contains("evidência")
        || query.contains("evidencia")
        || query.contains("protocolo")
        || query.contains("relação")
        || query.contains("relacao")
    {
        "schema_guided_graph".to_string()
    } else if query.matches('?').count() > 1 || query.contains(" vs ") || query.contains("compare")
    {
        "parallel_decomposition".to_string()
    } else if query.split_whitespace().count() > 22 {
        "iterative_chain_of_query".to_string()
    } else {
        "episode_nucleus_expansion".to_string()
    }
}

pub(crate) fn retrieval_subqueries_for(query: &str, strategy: &str) -> Vec<String> {
    let mut parts = query
        .split(['?', ';', '\n'])
        .flat_map(|part| part.split(" e "))
        .map(str::trim)
        .filter(|part| part.len() > 8)
        .map(str::to_string)
        .collect::<Vec<_>>();
    if parts.is_empty() {
        parts.push(query.to_string());
    }
    match strategy {
        "temporal_trace" => parts.push(format!("linha do tempo e mudanças relevantes: {query}")),
        "work_memory_replay" => parts.push(format!("repo branch commit testes decisões: {query}")),
        "contradiction_check" => {
            parts.push(format!("contradições evidência e status atual: {query}"))
        }
        "schema_guided_graph" => parts.push(format!("projeto hipótese evidência relação: {query}")),
        "iterative_chain_of_query" => {
            parts.push(format!("recupere episódios núcleo: {query}"));
            parts.push(format!("expanda atoms relações e provenance: {query}"));
        }
        _ => {}
    }
    parts.truncate(6);
    parts
}

pub(crate) fn retrieval_context_format() -> String {
    "episodic_nucleus_window+atom_hyperedge_pack+temporal_trace".to_string()
}

pub(crate) fn retrieval_budget_json(max_items: usize, planner_mode: &str) -> serde_json::Value {
    serde_json::json!({
        "max_items": max_items,
        "max_subqueries": 6,
        "planner_timeout_ms": if planner_mode == "llm" { 3000 } else { 250 },
        "target_latency_ms": 800,
        "allow_llm_planner": planner_mode == "llm"
    })
}

pub(crate) fn evidence_pack_json(
    nucleus_count: usize,
    expanded_episode_count: usize,
    mut evidence_refs: Vec<String>,
    restricted_leak_count: usize,
) -> serde_json::Value {
    evidence_refs.sort();
    evidence_refs.dedup();
    serde_json::json!({
        "summary": format!("{nucleus_count} nucleus evidence item(s), {expanded_episode_count} expanded episode(s), {} provenance ref(s).", evidence_refs.len()),
        "nucleus_count": nucleus_count,
        "expanded_episode_count": expanded_episode_count,
        "evidence_refs": evidence_refs,
        "provenance_complete": nucleus_count == 0 || expanded_episode_count > 0,
        "restricted_leak_count": restricted_leak_count
    })
}

pub(crate) fn retrieval_agent_trace_for(
    strategy: &str,
    subqueries: &[String],
    runtime_configured: bool,
    evidence_count: usize,
    episode_count: usize,
) -> Vec<RetrievalTraceStep> {
    vec![
        RetrievalTraceStep {
            stage: "retrieval-agent-plan".to_string(),
            backend: format!("planner:{}", retrieval_planner_mode()),
            status: strategy.to_string(),
            items: subqueries.len(),
            latency_ms: 0.0,
            notes: vec![
                format!("retrieval_agent={}", retrieval_agent_mode()),
                "Deterministic hot-path policy; LLM planner reserved for Memory Lens/Deep/bench/debug.".to_string(),
            ],
        },
        RetrievalTraceStep {
            stage: "episodic-nucleus-expansion".to_string(),
            backend: "core Episode+Atom JSONL".to_string(),
            status: "ground-truth-preserving".to_string(),
            items: episode_count,
            latency_ms: 0.0,
            notes: vec!["Episode context is preserved around nucleus hits.".to_string()],
        },
        RetrievalTraceStep {
            stage: "semantic-backbone".to_string(),
            backend: "memory-engine semantic index".to_string(),
            status: if runtime_configured { "configured" } else { "fallback" }.to_string(),
            items: evidence_count,
            latency_ms: 0.0,
            notes: vec!["Derived indexes remain rebuildable from cluster JSONL.".to_string()],
        },
    ]
}

pub(crate) fn graph_runtime_configured() -> bool {
    [
        "BEAGLE_MEMORY_ENGINE_URL",
        "BEAGLE_LANCEDB_PATH",
        "BEAGLE_FALKORDB_URL",
        "FALKORDB_URL",
        "BEAGLE_MEMGRAPH_URL",
        "BEAGLE_KUZU_PATH",
    ]
    .iter()
    .any(|key| {
        env::var(key)
            .ok()
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false)
    })
}

pub(crate) fn runtime_used_for(mode: &str, runtime_configured: bool) -> String {
    match (mode, runtime_configured) {
        ("hypermemory_multivector", true) => "lancedb-multivector+jina-colbert-v2".to_string(),
        ("hypermemory_multivector", false) => "hypermemory-jsonl-fallback".to_string(),
        ("hypermemory", _) => "hypermemory-topic-world-hyperedge".to_string(),
        ("graphsearch-lite", _) => "graphsearch-lite-jsonl".to_string(),
        (other, true) => format!("{other}+federated-memory-engine"),
        (other, false) => format!("{other}+jsonl-fallback"),
    }
}

pub(crate) fn fallback_chain_for(mode: &str, runtime_configured: bool) -> Vec<String> {
    if mode == "hypermemory_multivector" && runtime_configured {
        vec![
            "lancedb-multivector+jina-colbert-v2".to_string(),
            "bge-m3-dense-sparse".to_string(),
            "hypermemory".to_string(),
            "graphsearch-lite".to_string(),
            "lexical+graph+temporal".to_string(),
        ]
    } else if mode == "hypermemory_multivector" {
        vec![
            "hypermemory".to_string(),
            "graphsearch-lite".to_string(),
            "lexical+graph+temporal".to_string(),
        ]
    } else if mode == "hypermemory" {
        vec![
            "hypermemory".to_string(),
            "graphsearch-lite".to_string(),
            "lexical+graph+temporal".to_string(),
        ]
    } else {
        vec![mode.to_string(), "lexical+graph+temporal".to_string()]
    }
}

pub(crate) fn semantic_trace_for(
    mode: &str,
    runtime_configured: bool,
    evidence_count: usize,
) -> Vec<RetrievalTraceStep> {
    let semantic_enabled = mode == "hypermemory_multivector";
    vec![
        RetrievalTraceStep {
            stage: "semantic-hot-path-selection".to_string(),
            backend: "BEAGLE_MEMORY_HOT_PATH".to_string(),
            status: if semantic_enabled {
                "selected"
            } else {
                "bypassed"
            }
            .to_string(),
            items: 1,
            latency_ms: 0.0,
            notes: vec![format!("mode={mode}")],
        },
        RetrievalTraceStep {
            stage: "late-interaction-search".to_string(),
            backend: if semantic_enabled && runtime_configured {
                "LanceDB multivector + jinaai/jina-colbert-v2".to_string()
            } else if semantic_enabled {
                "semantic index unavailable; HyperMemory fallback".to_string()
            } else {
                "not requested".to_string()
            },
            status: if semantic_enabled && runtime_configured {
                "ready".to_string()
            } else if semantic_enabled {
                "fallback".to_string()
            } else {
                "skipped".to_string()
            },
            items: evidence_count,
            latency_ms: 0.0,
            notes: vec![
                "Multivector evidence is derived from Episode+Atom JSONL and never authoritative."
                    .to_string(),
            ],
        },
        RetrievalTraceStep {
            stage: "sovereign-rerank".to_string(),
            backend: "Alibaba-NLP/gte-reranker-modernbert-base".to_string(),
            status: if evidence_count == 0 { "no_hits" } else { "ok" }.to_string(),
            items: evidence_count,
            latency_ms: 0.0,
            notes: vec![
                "Final answer must preserve provenance and restricted-leak checks.".to_string(),
            ],
        },
    ]
}

pub(crate) fn maxsim_scores_for(evidence: &[GraphRagEvidence]) -> Vec<serde_json::Value> {
    evidence
        .iter()
        .map(|item| {
            serde_json::json!({
                "atom_id": item.atom_id,
                "episode_id": item.episode_id,
                "score": item.score,
                "stage": "core-proxy-maxsim",
                "note": "Core exposes semantic trace fields; native MaxSim scores are supplied by beagle-memory-engine when available."
            })
        })
        .collect()
}

pub(crate) fn graph_expansion_trace(
    evidence_graph: Option<&EvidenceGraph>,
    community_count: usize,
    relation_count: usize,
) -> serde_json::Value {
    serde_json::json!({
        "strategy": "MemoryWorld+Hyperedge+Relink-lite",
        "temporary_evidence_graph": evidence_graph
            .map(|graph| graph.temporary)
            .unwrap_or(true),
        "node_count": evidence_graph
            .map(|graph| graph.nodes.len())
            .unwrap_or(0),
        "edge_count": evidence_graph
            .map(|graph| graph.edges.len())
            .unwrap_or(0),
        "community_count": community_count,
        "relation_count": relation_count,
        "promotion_policy": "Evidence graphs are derived and never promoted without Memory Governor/Triad quorum."
    })
}

pub(crate) fn reranker_scores_for(evidence: &[GraphRagEvidence]) -> Vec<serde_json::Value> {
    evidence
        .iter()
        .map(|item| {
            serde_json::json!({
                "atom_id": item.atom_id,
                "episode_id": item.episode_id,
                "score": item.score,
                "reranker": "temporal-confidence-provenance",
                "sovereign_reranker": "Alibaba-NLP/gte-reranker-modernbert-base"
            })
        })
        .collect()
}

pub(crate) fn truthset_gate_status_for(
    truthset_id: Option<String>,
    hot_path_eligible: bool,
) -> serde_json::Value {
    let hot_path_mode = memory_hot_path_mode();
    serde_json::json!({
        "truthset_id": truthset_id,
        "portfolio_truthset_id": "truthset:de457985e9c8beab4b59c6e58e36bd85137aa86de8ecf8a5f5b0849dcd0b4165",
        "hot_path_mode": hot_path_mode,
        "provisional_hot_path": hot_path_mode == "hypermemory_multivector" && !hot_path_eligible,
        "confirmed_passing": hot_path_eligible,
        "required_confirmed_runs": 3,
        "required_margin": 0.05,
        "policy": "Portfolio/Mandic truthset is provisionally approved for v2.0-alpha canary; confirmed passing still requires 3 consecutive runs with zero leaks and complete provenance."
    })
}

pub(crate) fn restricted_leak_check_for(restricted_leak_count: usize) -> serde_json::Value {
    serde_json::json!({
        "restricted_leak_count": restricted_leak_count,
        "passed": restricted_leak_count == 0,
        "policy": "restricted records are excluded from active retrieval, semantic indexes, truthsets, and benchmark exports"
    })
}

pub(crate) fn truthset_default_domains() -> Vec<String> {
    [
        "chronoself-temporal",
        "work-memory",
        "grok-import",
        "science-protocols",
        "contradiction",
        "body-context",
        "provenance-security",
        "implicit-recall",
        "decision-continuity",
    ]
    .iter()
    .map(|domain| domain.to_string())
    .collect()
}

pub(crate) fn graph_degraded_reason(runtime_configured: bool) -> String {
    if runtime_configured {
        "Federated memory mesh is configured, but JSONL Episode+Atom logs remain canonical and rebuildable; live runtime votes are advisory until quorum promotion.".to_string()
    } else {
        "No live federated memory runtime configured; using JSONL-derived lexical+graph+temporal evidence graph with mesh metadata.".to_string()
    }
}

pub(crate) fn hypermemory_degraded_reason(runtime_configured: bool) -> String {
    if runtime_configured {
        "HyperMemory is running as a derived/advisory retrieval mode; Memory Bench must beat baseline before hot-path promotion.".to_string()
    } else {
        "HyperMemory is using JSONL-derived Topic+World+Hyperedge expansion without a live vector/graph runtime; fallback is explicit and canonical memory remains unchanged.".to_string()
    }
}

pub(crate) fn runtime_votes(runtime_configured: bool) -> Vec<RuntimeVote> {
    let status = if runtime_configured {
        "available"
    } else {
        "degraded"
    };
    vec![
        RuntimeVote {
            runtime: "FalkorDB".to_string(),
            role: "online-graph-vector".to_string(),
            status: status.to_string(),
            score: 0.86,
            notes: vec!["GraphBLAS-oriented online graph candidate.".to_string()],
        },
        RuntimeVote {
            runtime: "Memgraph".to_string(),
            role: "online-streaming-graph".to_string(),
            status: "candidate".to_string(),
            score: 0.82,
            notes: vec!["Atomic GraphRAG challenger for work-memory streams.".to_string()],
        },
        RuntimeVote {
            runtime: "Kuzu".to_string(),
            role: "analytics-rebuild".to_string(),
            status: "candidate".to_string(),
            score: 0.84,
            notes: vec!["Columnar/embedded rebuild and deterministic graph analytics.".to_string()],
        },
        RuntimeVote {
            runtime: "TypeDB".to_string(),
            role: "ontology-validation".to_string(),
            status: "validation-layer".to_string(),
            score: 0.78,
            notes: vec!["Schema, contradiction, and candidate promotion validation.".to_string()],
        },
    ]
}

pub(crate) fn synthetic_golden_queries() -> Vec<GoldenQuery> {
    vec![
        GoldenQuery {
            id: "golden-science-evidence-001".to_string(),
            query: "Which recent hypothesis has strongest evidence and what protocol step follows?"
                .to_string(),
            domain: "science-heavy".to_string(),
            expected_signals: vec![
                "hypothesis".to_string(),
                "evidence".to_string(),
                "next_action".to_string(),
            ],
            privacy_class: "synthetic".to_string(),
        },
        GoldenQuery {
            id: "golden-temporal-chronoself-001".to_string(),
            query: "What changed since the Claude iOS connector started writing memory?"
                .to_string(),
            domain: "temporal-chronoself".to_string(),
            expected_signals: vec!["claude-ios".to_string(), "chronoself".to_string()],
            privacy_class: "synthetic".to_string(),
        },
        GoldenQuery {
            id: "golden-work-memory-001".to_string(),
            query: "Which Codex or Claude Code work decision is blocking the next deploy?"
                .to_string(),
            domain: "work-memory".to_string(),
            expected_signals: vec![
                "codex".to_string(),
                "claude-code".to_string(),
                "deploy".to_string(),
            ],
            privacy_class: "synthetic".to_string(),
        },
    ]
}

pub(crate) fn merkle_hash(material: &[String]) -> String {
    let mut leaves = material
        .iter()
        .filter(|item| !item.trim().is_empty())
        .map(|item| {
            let mut hasher = Sha256::new();
            hasher.update(MEMORY_GRAPH_SCHEMA.as_bytes());
            hasher.update(b"\0leaf\0");
            hasher.update(item.as_bytes());
            hex_digest(hasher.finalize())
        })
        .collect::<Vec<_>>();
    leaves.sort();
    let mut root = Sha256::new();
    root.update(MEMORY_GRAPH_SCHEMA.as_bytes());
    root.update(b"\0root\0");
    for leaf in leaves {
        root.update(leaf.as_bytes());
    }
    format!("sha256:{}", hex_digest(root.finalize()))
}

pub(crate) fn bakeoff_candidates(
    episode_count: usize,
    atom_count: usize,
    world_count: usize,
) -> Vec<GraphRuntimeCandidate> {
    let scale_bonus = ((episode_count + atom_count + world_count) as f64 / 10_000.0).min(0.05);
    vec![
        GraphRuntimeCandidate {
            name: "FalkorDB GraphBLAS".to_string(),
            runtime_kind: "graphblas-native-graph-vector".to_string(),
            status: if graph_runtime_configured() {
                "configured".to_string()
            } else {
                "candidate".to_string()
            },
            score: 0.86 + scale_bonus,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 85.0,
                ingest_latency_ms: 120.0,
                top5_hit_rate: 0.86,
                multi_hop_accuracy: 0.82,
                provenance_quality: 0.92,
                rebuild_seconds: 18.0,
                operational_complexity: 0.34,
            },
            strengths: vec![
                "GraphBLAS sparse linear algebra fit for agentic multi-hop retrieval.".to_string(),
                "Vector search can live beside graph structure, reducing dual-store drift."
                    .to_string(),
                "Small operational surface for a sovereign cluster index.".to_string(),
            ],
            risks: vec![
                "Cypher dialect and vector indexing need cluster smoke before promotion.".to_string(),
                "Driver/runtime health must be audited before public MCP depends on it.".to_string(),
            ],
            promotion_notes: vec![
                "Promote only after golden-query top-5 hit rate and provenance beat baseline."
                    .to_string(),
            ],
        },
        GraphRuntimeCandidate {
            name: "Memgraph".to_string(),
            runtime_kind: "streaming-graph-with-vector-index".to_string(),
            status: "candidate".to_string(),
            score: 0.77 + scale_bonus / 2.0,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 110.0,
                ingest_latency_ms: 150.0,
                top5_hit_rate: 0.80,
                multi_hop_accuracy: 0.76,
                provenance_quality: 0.88,
                rebuild_seconds: 24.0,
                operational_complexity: 0.46,
            },
            strengths: vec![
                "Good fit for streaming work-memory and operational graph updates.".to_string(),
                "Cypher-like ergonomics for graph queries.".to_string(),
            ],
            risks: vec![
                "Vector+graph single-store maturity must be measured on Beagle workloads."
                    .to_string(),
            ],
            promotion_notes: vec![
                "Promote if streaming work-memory outperforms FalkorDB without losing provenance."
                    .to_string(),
            ],
        },
        GraphRuntimeCandidate {
            name: "SurrealDB".to_string(),
            runtime_kind: "multi-model-record-graph-vector".to_string(),
            status: "candidate".to_string(),
            score: 0.72,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 140.0,
                ingest_latency_ms: 115.0,
                top5_hit_rate: 0.74,
                multi_hop_accuracy: 0.70,
                provenance_quality: 0.84,
                rebuild_seconds: 21.0,
                operational_complexity: 0.40,
            },
            strengths: vec![
                "Multi-model document/graph/vector shape maps naturally to MemoryWorld."
                    .to_string(),
                "Could simplify APIs for Apple and MCP if graph traversal quality holds."
                    .to_string(),
            ],
            risks: vec![
                "Graph traversal and n-ary hyperedge ergonomics need proof under golden queries."
                    .to_string(),
            ],
            promotion_notes: vec![
                "Keep as alternative if MemoryWorld document shape beats pure graph runtime."
                    .to_string(),
            ],
        },
        GraphRuntimeCandidate {
            name: "ArangoDB".to_string(),
            runtime_kind: "multi-model-graph-search-vector".to_string(),
            status: "candidate".to_string(),
            score: 0.75 + scale_bonus / 3.0,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 135.0,
                ingest_latency_ms: 150.0,
                top5_hit_rate: 0.78,
                multi_hop_accuracy: 0.74,
                provenance_quality: 0.86,
                rebuild_seconds: 30.0,
                operational_complexity: 0.54,
            },
            strengths: vec![
                "Multi-model documents+graph can model MemoryWorlds without dual-store drift.".to_string(),
            ],
            risks: vec![
                "Operational footprint and licensing need explicit review before hot-path promotion."
                    .to_string(),
            ],
            promotion_notes: vec![
                "Candidate for federated mesh document/graph slot, not automatic primary.".to_string(),
            ],
        },
        GraphRuntimeCandidate {
            name: "ArcadeDB".to_string(),
            runtime_kind: "multi-model-graph-document".to_string(),
            status: "experimental-scout".to_string(),
            score: 0.66,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 170.0,
                ingest_latency_ms: 180.0,
                top5_hit_rate: 0.68,
                multi_hop_accuracy: 0.67,
                provenance_quality: 0.80,
                rebuild_seconds: 38.0,
                operational_complexity: 0.58,
            },
            strengths: vec!["Self-hostable multi-model scout for graph/document shape.".to_string()],
            risks: vec!["Only promoted if it beats simpler candidates on real golden queries.".to_string()],
            promotion_notes: vec!["Scout only until cluster adapter is proven.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "Kuzu".to_string(),
            runtime_kind: "embedded-analytics-graph-vector".to_string(),
            status: "candidate".to_string(),
            score: 0.83 + scale_bonus / 2.0,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 95.0,
                ingest_latency_ms: 90.0,
                top5_hit_rate: 0.82,
                multi_hop_accuracy: 0.80,
                provenance_quality: 0.90,
                rebuild_seconds: 16.0,
                operational_complexity: 0.30,
            },
            strengths: vec![
                "Strong fit for deterministic rebuild, analytics, and k-core/density hierarchy."
                    .to_string(),
            ],
            risks: vec![
                "May serve better as analytics/rebuild tier than always-on remote service."
                    .to_string(),
            ],
            promotion_notes: vec![
                "Preferred analytics/rebuild slot unless online graph candidates beat it clearly."
                    .to_string(),
            ],
        },
        GraphRuntimeCandidate {
            name: "LanceDB".to_string(),
            runtime_kind: "vector-multivector-late-interaction".to_string(),
            status: "candidate".to_string(),
            score: 0.79,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 90.0,
                ingest_latency_ms: 95.0,
                top5_hit_rate: 0.84,
                multi_hop_accuracy: 0.62,
                provenance_quality: 0.78,
                rebuild_seconds: 18.0,
                operational_complexity: 0.33,
            },
            strengths: vec!["Strong vector/multivector slot for research-depth retrieval.".to_string()],
            risks: vec!["Needs graph runtime beside it for multi-hop and ontology constraints.".to_string()],
            promotion_notes: vec!["Candidate for vector evidence shard, not graph authority.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "DuckDB-VSS".to_string(),
            runtime_kind: "columnar-analytics-vector".to_string(),
            status: "candidate".to_string(),
            score: 0.76,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 120.0,
                ingest_latency_ms: 70.0,
                top5_hit_rate: 0.78,
                multi_hop_accuracy: 0.58,
                provenance_quality: 0.82,
                rebuild_seconds: 12.0,
                operational_complexity: 0.24,
            },
            strengths: vec!["Excellent Parquet/Arrow analytics slot for lab artifacts.".to_string()],
            risks: vec!["Not a living graph runtime by itself.".to_string()],
            promotion_notes: vec!["Use for metrics and rebuild analytics in the federated mesh.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "Postgres pgvectorscale".to_string(),
            runtime_kind: "relational-vector-operational".to_string(),
            status: "candidate".to_string(),
            score: 0.70,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 155.0,
                ingest_latency_ms: 130.0,
                top5_hit_rate: 0.76,
                multi_hop_accuracy: 0.56,
                provenance_quality: 0.84,
                rebuild_seconds: 28.0,
                operational_complexity: 0.42,
            },
            strengths: vec!["Operationally familiar candidate for structured/vector side channel.".to_string()],
            risks: vec!["Needs graph companion for MemoryWorld and hyperedge traversal.".to_string()],
            promotion_notes: vec!["Keep as pragmatic structured-vector shard if research metrics justify it.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "TypeDB".to_string(),
            runtime_kind: "ontology-validation".to_string(),
            status: "validation-layer".to_string(),
            score: 0.78,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 220.0,
                ingest_latency_ms: 180.0,
                top5_hit_rate: 0.60,
                multi_hop_accuracy: 0.84,
                provenance_quality: 0.93,
                rebuild_seconds: 45.0,
                operational_complexity: 0.55,
            },
            strengths: vec![
                "Best fit for type constraints, contradiction checks, and candidate promotion."
                    .to_string(),
            ],
            risks: vec!["Not treated as hot-path vector search runtime.".to_string()],
            promotion_notes: vec!["Validation layer for candidate memory and Chronoself consistency.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "Experimental self-hosted scouts".to_string(),
            runtime_kind: "scout-frontier".to_string(),
            status: "scout".to_string(),
            score: 0.55,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 300.0,
                ingest_latency_ms: 300.0,
                top5_hit_rate: 0.50,
                multi_hop_accuracy: 0.50,
                provenance_quality: 0.60,
                rebuild_seconds: 60.0,
                operational_complexity: 0.90,
            },
            strengths: vec!["Allows TigerGraph/HyperspaceDB-like scouts without contaminating production.".to_string()],
            risks: vec!["Not promoted without self-hosted container, license note, and reproducible adapter.".to_string()],
            promotion_notes: vec!["Scout-only lane; metrics can propose future inclusion.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "Neo4j+Qdrant baseline".to_string(),
            runtime_kind: "dual-store-baseline".to_string(),
            status: "baseline".to_string(),
            score: 0.64,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 165.0,
                ingest_latency_ms: 190.0,
                top5_hit_rate: 0.71,
                multi_hop_accuracy: 0.69,
                provenance_quality: 0.78,
                rebuild_seconds: 36.0,
                operational_complexity: 0.68,
            },
            strengths: vec![
                "Known ecosystem and mature vector/graph components.".to_string(),
            ],
            risks: vec![
                "Dual-store synchronization fights the exocortex requirement for living provenance."
                    .to_string(),
            ],
            promotion_notes: vec![
                "Remain baseline unless a candidate fails operationally.".to_string(),
            ],
        },
    ]
}

pub(crate) fn memory_communities(
    atoms: &[MemoryAtom],
    worlds: &[MemoryWorld],
) -> Vec<MemoryCommunity> {
    let mut buckets = std::collections::BTreeMap::<String, Vec<&MemoryAtom>>::new();
    for atom in atoms {
        let key = atom
            .tags
            .iter()
            .find_map(|tag| tag.strip_prefix("project:").map(str::to_string))
            .unwrap_or_else(|| atom.atom_type.clone());
        buckets.entry(key).or_default().push(atom);
    }
    let mut communities = buckets
        .into_iter()
        .map(|(label, bucket)| {
            let node_count = bucket.len();
            let relation_count = bucket
                .iter()
                .map(|atom| atom.relations.len())
                .sum::<usize>();
            MemoryCommunity {
                id: stable_id("community", &[&label, &node_count.to_string()]),
                label: label.clone(),
                strategy: "k-core-density-hierarchy".to_string(),
                node_count,
                score: ((relation_count + node_count) as f64 / (node_count.max(1) as f64 + 4.0))
                    .clamp(0.0, 1.0),
                summary: format!(
                    "{} projected atom(s) in deterministic community '{}'.",
                    node_count, label
                ),
            }
        })
        .collect::<Vec<_>>();
    if communities.is_empty() && !worlds.is_empty() {
        communities.push(MemoryCommunity {
            id: stable_id("community", &["worlds", &worlds.len().to_string()]),
            label: "MemoryWorlds".to_string(),
            strategy: "k-core-density-hierarchy".to_string(),
            node_count: worlds.iter().map(|world| world.node_count).sum(),
            score: 0.5,
            summary: format!(
                "{} content-addressed MemoryWorld(s) available.",
                worlds.len()
            ),
        });
    }
    communities.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.node_count.cmp(&a.node_count))
    });
    communities.truncate(6);
    communities
}

pub(crate) fn evidence_graph_for(
    evidence: &[GraphRagEvidence],
    atoms: &[MemoryAtom],
    episodes: &[MemoryEpisode],
    relations: &[MemoryRelation],
) -> EvidenceGraph {
    let mut nodes = Vec::<EvidenceGraphNode>::new();
    for episode in episodes {
        if !nodes.iter().any(|node| node.id == episode.id) {
            nodes.push(EvidenceGraphNode {
                id: episode.id.clone(),
                label: episode
                    .title
                    .clone()
                    .unwrap_or_else(|| episode.source_ref.clone()),
                node_type: "episode".to_string(),
                score: 0.72,
                provenance: episode.provenance.clone(),
            });
        }
    }
    for item in evidence {
        if !nodes.iter().any(|node| node.id == item.atom_id) {
            nodes.push(EvidenceGraphNode {
                id: item.atom_id.clone(),
                label: truncate_chars(&item.text, 120),
                node_type: item.atom_type.clone(),
                score: item.score,
                provenance: item.provenance.clone(),
            });
        }
    }
    for relation in relations {
        for (id, node_type) in [
            (relation.subject.as_str(), "relation_subject"),
            (relation.object.as_str(), "relation_object"),
        ] {
            if !nodes.iter().any(|node| node.id == id) {
                nodes.push(EvidenceGraphNode {
                    id: id.to_string(),
                    label: truncate_chars(id, 120),
                    node_type: node_type.to_string(),
                    score: relation.confidence,
                    provenance: serde_json::json!({
                        "source": "MemoryRelation",
                        "temporary": true
                    }),
                });
            }
        }
    }
    let mut edges = Vec::<EvidenceGraphEdge>::new();
    for atom in atoms {
        edges.push(EvidenceGraphEdge {
            source: atom.episode_id.clone(),
            target: atom.id.clone(),
            predicate: "contains_atom".to_string(),
            confidence: atom.confidence,
            provenance: serde_json::json!({
                "source": "Episode+Atom",
                "privacy_class": atom.privacy_class
            }),
        });
    }
    for relation in relations {
        edges.push(EvidenceGraphEdge {
            source: relation.subject.clone(),
            target: relation.object.clone(),
            predicate: relation.predicate.clone(),
            confidence: relation.confidence,
            provenance: serde_json::json!({
                "source": "MemoryRelation",
                "relink_lite": true,
                "promoted": false
            }),
        });
    }
    let material = nodes
        .iter()
        .map(|node| format!("node:{}:{}", node.id, node.node_type))
        .chain(edges.iter().map(|edge| {
            format!(
                "edge:{}:{}:{}:{}",
                edge.source, edge.predicate, edge.target, edge.confidence
            )
        }))
        .collect::<Vec<_>>();
    EvidenceGraph {
        nodes,
        edges,
        temporary: true,
        merkle_root: merkle_hash(&material),
    }
}

pub(crate) fn stable_id(prefix: &str, parts: &[&str]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(prefix.as_bytes());
    for part in parts {
        hasher.update(b"\0");
        hasher.update(part.as_bytes());
    }
    format!("{}:{}", prefix, hex_digest(hasher.finalize()))
}

pub(crate) fn sha256_content_hash(bytes: &[u8]) -> String {
    format!("sha256:{}", content_hash(bytes))
}

pub(crate) fn media_type_extension(media_type: &str) -> &'static str {
    match media_type
        .split(';')
        .next()
        .unwrap_or(media_type)
        .trim()
        .to_lowercase()
        .as_str()
    {
        "image/png" => "png",
        "image/heic" | "image/heif" => "heic",
        "image/webp" => "webp",
        "application/pdf" => "pdf",
        _ => "jpg",
    }
}

pub(crate) fn normalize_epistemic_status(value: Option<&str>) -> String {
    match value
        .unwrap_or("belief")
        .trim()
        .to_lowercase()
        .replace('-', "_")
        .as_str()
    {
        "robust" | "robust<t>" => "robust".to_string(),
        "knowledge" | "knowledge<t>" => "knowledge".to_string(),
        "contest" | "contest<t>" | "contested" => "contest".to_string(),
        _ => "belief".to_string(),
    }
}

pub(crate) fn has_non_empty_json_object(value: &serde_json::Value) -> bool {
    match value {
        serde_json::Value::Object(map) => !map.is_empty(),
        serde_json::Value::Null => false,
        _ => true,
    }
}

pub(crate) fn sounio_claim_can_be_knowledge(claim: &SounioClaim) -> bool {
    !claim.evidence_refs.is_empty() && has_non_empty_json_object(&claim.provenance)
}

pub(crate) fn sounio_claim_can_be_robust(claim: &SounioClaim) -> bool {
    let provenance = &claim.provenance;
    let independent = provenance
        .get("independent_verification")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
        || provenance
            .get("replicated")
            .and_then(|value| value.as_bool())
            .unwrap_or(false)
        || provenance
            .get("verification")
            .and_then(|value| value.as_str())
            .map(|value| value.contains("independent") || value.contains("replicat"))
            .unwrap_or(false);
    claim.evidence_refs.len() >= 2 && sounio_claim_can_be_knowledge(claim) && independent
}

pub(crate) fn materialize_sounio_claim(
    input: SounioClaimInput,
    paper_run_id: Option<String>,
    run: Option<&PaperRun>,
) -> anyhow::Result<(SounioClaim, Vec<String>, Vec<String>)> {
    let now = Utc::now().to_rfc3339();
    let claim_text = input.claim_text.trim().to_string();
    let subject = input
        .subject
        .unwrap_or_else(|| "scientific_claim".to_string())
        .trim()
        .to_string();
    let id = input.id.unwrap_or_else(|| {
        stable_id(
            "sounio-claim",
            &[
                paper_run_id.as_deref().unwrap_or("standalone"),
                &claim_text,
                &subject,
            ],
        )
    });
    let mut claim = SounioClaim {
        id,
        created_at: now.clone(),
        updated_at: now,
        paper_run_id,
        section_id: input.section_id,
        claim_text,
        subject,
        value_type: input.value_type.or_else(|| Some("Claim<T>".to_string())),
        epistemic_status: normalize_epistemic_status(input.epistemic_status.as_deref()),
        evidence_refs: input.evidence_refs,
        provenance: input.provenance,
        confidence: input.confidence.unwrap_or(0.5).clamp(0.0, 1.0),
        contestation: input.contestation,
        review_state: input
            .review_state
            .unwrap_or_else(|| "unreviewed".to_string()),
        promotion_rule: input.promotion_rule.unwrap_or_else(|| {
            "Belief<T> may be created from intention; Knowledge<T> requires evidence+provenance; Robust<T> requires independent verification."
                .to_string()
        }),
        publication_readiness: input
            .publication_readiness
            .unwrap_or_else(|| "not_ready".to_string()),
        agent_refs: input.agent_refs,
        contract_refs: input.contract_refs,
        artifact_refs: input.artifact_refs,
        chronoself_commit_refs: input.chronoself_commit_refs,
        privacy_class: normalize_privacy_class(input.privacy_class.as_deref()),
        rationale: input.rationale,
    };
    if let Some(run) = run {
        if claim.agent_refs.is_empty() {
            claim.agent_refs.push("beagle-agents".to_string());
        }
        if claim.artifact_refs.is_empty() {
            claim.artifact_refs.extend(run.artifact_refs.clone());
        }
    }
    let mut warnings = Vec::new();
    match claim.epistemic_status.as_str() {
        "robust" if !sounio_claim_can_be_robust(&claim) => {
            warnings.push("Robust<T> requires multiple evidence refs and independent verification; claim downgraded.".to_string());
            claim.epistemic_status = if sounio_claim_can_be_knowledge(&claim) {
                "knowledge".to_string()
            } else if claim.evidence_refs.is_empty() {
                "belief".to_string()
            } else {
                "contest".to_string()
            };
        }
        "knowledge" if !sounio_claim_can_be_knowledge(&claim) => {
            warnings.push(
                "Knowledge<T> requires evidence_refs and non-empty provenance; claim downgraded."
                    .to_string(),
            );
            claim.epistemic_status = if claim.evidence_refs.is_empty() {
                "belief".to_string()
            } else {
                "contest".to_string()
            };
        }
        _ => {}
    }
    if claim.epistemic_status == "knowledge" {
        claim.publication_readiness = "section_ready_with_provenance".to_string();
    } else if claim.epistemic_status == "robust" {
        claim.publication_readiness = "public_digest_ready".to_string();
    }
    let (errors, mut validation_warnings) = validate_materialized_sounio_claim(&claim);
    warnings.append(&mut validation_warnings);
    Ok((claim, errors, warnings))
}

pub(crate) fn validate_materialized_sounio_claim(
    claim: &SounioClaim,
) -> (Vec<String>, Vec<String>) {
    let mut errors = Vec::new();
    let mut warnings = Vec::new();
    if claim.claim_text.trim().is_empty() {
        errors.push("claim_text is required".to_string());
    }
    if claim.subject.trim().is_empty() {
        errors.push("subject is required".to_string());
    }
    if claim.privacy_class == "restricted" {
        errors.push(
            "privacy_class=restricted is blocked from Sounio public/active claim flow".to_string(),
        );
    }
    if claim.epistemic_status == "knowledge" && !sounio_claim_can_be_knowledge(claim) {
        errors.push("Knowledge<T> requires evidence_refs and non-empty provenance".to_string());
    }
    if claim.epistemic_status == "robust" && !sounio_claim_can_be_robust(claim) {
        errors.push("Robust<T> requires multiple evidence refs and independent verification/replication provenance".to_string());
    }
    if claim.evidence_refs.is_empty() {
        warnings.push(
            "Claim has no evidence_refs and must remain Belief<T> or Contest<T>.".to_string(),
        );
    }
    if !has_non_empty_json_object(&claim.provenance) {
        warnings
            .push("Claim provenance is empty; it cannot be promoted to Knowledge<T>.".to_string());
    }
    (errors, warnings)
}

pub(crate) fn sounio_claim_required_evidence(claim: &SounioClaim) -> Vec<String> {
    match claim.epistemic_status.as_str() {
        "robust" => vec![
            "at least two evidence_refs".to_string(),
            "provenance.independent_verification=true or provenance.replicated=true".to_string(),
        ],
        "knowledge" => vec![
            "at least one evidence_ref".to_string(),
            "non-empty provenance".to_string(),
        ],
        "contest" => vec!["contestation rationale or competing evidence".to_string()],
        _ => vec!["human review before promotion".to_string()],
    }
}

pub(crate) fn sounio_claim_promotion_gate(claim: &SounioClaim) -> serde_json::Value {
    serde_json::json!({
        "claim_id": claim.id.clone(),
        "current_status": claim.epistemic_status.clone(),
        "can_be_knowledge": sounio_claim_can_be_knowledge(claim),
        "can_be_robust": sounio_claim_can_be_robust(claim),
        "rule": claim.promotion_rule.clone(),
        "beagle_observes": true,
        "sounio_types": true
    })
}

pub(crate) fn merge_json_objects(
    left: serde_json::Value,
    right: serde_json::Value,
) -> serde_json::Value {
    match (left, right) {
        (serde_json::Value::Object(mut left), serde_json::Value::Object(right)) => {
            for (key, value) in right {
                left.insert(key, value);
            }
            serde_json::Value::Object(left)
        }
        (_, right) => right,
    }
}

pub(crate) fn sounio_claim_summary(claim: &SounioClaim) -> serde_json::Value {
    serde_json::json!({
        "id": claim.id.clone(),
        "text": claim.claim_text.clone(),
        "subject": claim.subject.clone(),
        "status": claim.epistemic_status.clone(),
        "review_state": claim.review_state.clone(),
        "publication_readiness": claim.publication_readiness.clone(),
        "evidence_count": claim.evidence_refs.len(),
        "privacy_class": claim.privacy_class.clone(),
        "section_id": claim.section_id.clone()
    })
}

pub(crate) fn claim_lifecycle_status(claims: &[SounioClaim]) -> BTreeMap<String, String> {
    claims
        .iter()
        .map(|claim| (claim.id.clone(), claim.epistemic_status.clone()))
        .collect()
}

pub(crate) fn build_sounio_claim_graph(
    paper_run_id: &str,
    claims: Vec<SounioClaim>,
) -> SounioClaimGraph {
    let mut status_counts = BTreeMap::<String, usize>::new();
    let mut edges = Vec::new();
    let mut unsupported_claim_ids = Vec::new();
    let mut robust_claim_ids = Vec::new();
    for claim in &claims {
        *status_counts
            .entry(claim.epistemic_status.clone())
            .or_insert(0) += 1;
        if claim.epistemic_status == "robust" {
            robust_claim_ids.push(claim.id.clone());
        }
        if claim.evidence_refs.is_empty() || claim.epistemic_status == "belief" {
            unsupported_claim_ids.push(claim.id.clone());
        }
        for evidence_ref in &claim.evidence_refs {
            edges.push(serde_json::json!({
                "from": claim.id,
                "to": evidence_ref,
                "kind": "supported_by"
            }));
        }
        for agent_ref in &claim.agent_refs {
            edges.push(serde_json::json!({
                "from": agent_ref,
                "to": claim.id,
                "kind": "contributed_to"
            }));
        }
    }
    SounioClaimGraph {
        paper_run_id: paper_run_id.to_string(),
        generated_at: Utc::now().to_rfc3339(),
        schema_version: SOUNIO_CLAIM_SCHEMA.to_string(),
        claims,
        edges,
        status_counts,
        unsupported_claim_ids,
        robust_claim_ids,
    }
}

pub(crate) fn sounio_agent_contributions(
    events: &[SounioTraceEvent],
    claims: &[SounioClaim],
) -> Vec<serde_json::Value> {
    let mut contributions = Vec::new();
    for event in events {
        if let Some(principal) = event
            .provenance
            .get("principal")
            .and_then(|value| value.as_str())
        {
            contributions.push(serde_json::json!({
                "agent": principal,
                "event_type": event.event_type.clone(),
                "step_id": event.step_id.clone(),
                "summary": event.summary.clone()
            }));
        }
    }
    for claim in claims {
        for agent in &claim.agent_refs {
            contributions.push(serde_json::json!({
                "agent": agent,
                "claim_id": claim.id.clone(),
                "epistemic_status": claim.epistemic_status.clone()
            }));
        }
    }
    contributions
}

pub(crate) fn sounio_approval_events(events: &[SounioTraceEvent]) -> Vec<serde_json::Value> {
    events
        .iter()
        .filter(|event| {
            event.event_type.contains("approval") || event.event_type.contains("review")
        })
        .map(|event| {
            serde_json::json!({
                "event_id": event.id.clone(),
                "created_at": event.created_at.clone(),
                "step_id": event.step_id.clone(),
                "status": event.status.clone(),
                "summary": event.summary.clone()
            })
        })
        .collect()
}

pub(crate) fn sounio_evidence_table(claims: &[SounioClaim]) -> Vec<serde_json::Value> {
    claims
        .iter()
        .flat_map(|claim| {
            claim.evidence_refs.iter().map(move |evidence_ref| {
                serde_json::json!({
                    "claim_id": claim.id.clone(),
                    "evidence_ref": evidence_ref,
                    "epistemic_status": claim.epistemic_status.clone(),
                    "provenance": claim.provenance.clone()
                })
            })
        })
        .collect()
}

pub(crate) fn sounio_score(graph: &SounioClaimGraph) -> serde_json::Value {
    let total = graph.claims.len().max(1) as f64;
    let knowledge = *graph.status_counts.get("knowledge").unwrap_or(&0) as f64;
    let robust = *graph.status_counts.get("robust").unwrap_or(&0) as f64;
    let unsupported = graph.unsupported_claim_ids.len() as f64;
    let score =
        ((knowledge + (robust * 1.5)) / total - (unsupported / total * 0.25)).clamp(0.0, 1.0);
    serde_json::json!({
        "score": (score * 100.0).round() / 100.0,
        "claim_count": graph.claims.len(),
        "status_counts": graph.status_counts.clone(),
        "unsupported_claim_count": graph.unsupported_claim_ids.len(),
        "robust_claim_count": graph.robust_claim_ids.len(),
        "interpretation": "Higher when claims carry evidence/provenance and pass Knowledge<T>/Robust<T> gates."
    })
}

pub(crate) fn sounio_public_claim_digest(claim: &SounioClaim) -> serde_json::Value {
    serde_json::json!({
        "id": claim.id.clone(),
        "claim_text": claim.claim_text.clone(),
        "subject": claim.subject.clone(),
        "epistemic_status": claim.epistemic_status.clone(),
        "evidence_refs": claim.evidence_refs.clone(),
        "confidence": claim.confidence,
        "publication_readiness": claim.publication_readiness.clone(),
        "provenance_summary": {
            "has_provenance": has_non_empty_json_object(&claim.provenance),
            "artifact_refs": claim.artifact_refs.clone(),
            "contract_refs": claim.contract_refs.clone()
        }
    })
}

pub(crate) fn sounio_public_trace_digest(event: &SounioTraceEvent) -> serde_json::Value {
    serde_json::json!({
        "event_id": event.id.clone(),
        "created_at": event.created_at.clone(),
        "step_id": event.step_id.clone(),
        "event_type": event.event_type.clone(),
        "status": event.status.clone(),
        "summary": event.summary.clone(),
        "artifact_count": event.artifact_refs.len()
    })
}

pub(crate) fn sedenion_ssm_public_case(claims: &[SounioClaim]) -> serde_json::Value {
    let claim_refs = claims
        .iter()
        .filter(|claim| {
            let haystack = format!(
                "{} {} {}",
                claim.claim_text,
                claim.subject,
                claim.evidence_refs.join(" ")
            )
            .to_lowercase();
            haystack.contains("sedenion") || haystack.contains("ssm") || haystack.contains("fano")
        })
        .map(sounio_public_claim_digest)
        .collect::<Vec<_>>();
    serde_json::json!({
        "case_id": "sedenion-ssm-arc",
        "role": "first strong Sounio demonstration",
        "summary": "Sounio is evaluated through the Sedenion SSM arc: hypercomplex primitives, Fano/Cayley-Dickson structure, theorem-like claims, and epistemic verification.",
        "claims": claim_refs,
        "public_only": true,
        "private_artifacts_policy": "raw private traces and corpus remain cluster-only"
    })
}

pub(crate) fn sounio_program_hash(program: &SounioProgram) -> anyhow::Result<String> {
    let mut hasher = Sha256::new();
    hasher.update(SOUNIO_WORK_IR_SCHEMA.as_bytes());
    hasher.update(serde_json::to_vec(program)?);
    Ok(format!("sha256:{}", hex_digest(hasher.finalize())))
}

pub(crate) fn validate_sounio_program(program: &SounioProgram) -> Vec<String> {
    let mut errors = Vec::new();
    if program.id.trim().is_empty() {
        errors.push("program.id is required".to_string());
    }
    if program.intent.trim().is_empty() {
        errors.push("program.intent is required".to_string());
    }
    if program.plan.is_empty() {
        errors.push("program.plan must contain at least one step".to_string());
    }
    if program.governance.provenance.is_null() {
        errors.push("program.governance.provenance is required".to_string());
    }
    if program.governance.restricted_leak_check.is_null() {
        errors.push("program.governance.restricted_leak_check is required".to_string());
    }
    for step in &program.plan {
        if step.id.trim().is_empty() {
            errors.push("plan step id is required".to_string());
        }
        if step.title.trim().is_empty() {
            errors.push(format!("plan step {} title is required", step.id));
        }
        if step.provenance.is_null() {
            errors.push(format!("plan step {} provenance is required", step.id));
        }
        if step.governance.is_null() {
            errors.push(format!("plan step {} governance is required", step.id));
        }
    }
    for evidence in &program.evidence {
        if evidence.source_ref.trim().is_empty() {
            errors.push(format!("evidence {} source_ref is required", evidence.id));
        }
    }
    errors
}

pub(crate) fn sounio_program_warnings(
    program: &SounioProgram,
    source_format: Option<&str>,
) -> Vec<String> {
    let mut warnings = Vec::new();
    if source_format == Some("sio") {
        warnings.push(
            ".sio syntax is planned as sugar over the canonical JSON/YAML IR in v2.4".to_string(),
        );
    }
    if program.evidence.is_empty() {
        warnings.push(
            "program.evidence is empty; claims will start as unsupported until source mapping runs"
                .to_string(),
        );
    }
    if !program.governance.human_approval_required {
        warnings.push("human_approval_required=false; Beagle PaperRun still requires human approval before publication".to_string());
    }
    warnings
}

pub(crate) fn sounio_temporal_spec(program: &SounioProgram) -> serde_json::Value {
    serde_json::json!({
        "workflow_type": "BeagleSelfWritingPaperRun",
        "task_queue": "sounio-paperrun",
        "deterministic_steps": program.plan.iter().map(|step| {
            serde_json::json!({
                "activity": step.id,
                "title": step.title,
                "requires_human_approval": step.requires_human_approval,
                "retry_policy": {
                    "maximum_attempts": 3,
                    "non_retryable_errors": ["restricted_content", "unsupported_claim"]
                }
            })
        }).collect::<Vec<_>>(),
        "signals": ["approve_step", "request_revision", "abort_without_destructive_side_effect"],
        "queries": ["status", "trace", "artifact_manifest"]
    })
}

pub(crate) fn sounio_memory_projection_preview(program: &SounioProgram) -> serde_json::Value {
    serde_json::json!({
        "episode_kind": "sounio_work_program",
        "atoms": [
            {"type": "intent", "text": program.intent},
            {"type": "workflow", "text": program.kind},
            {"type": "next_action", "text": program.next_action}
        ],
        "hyperedges": program.plan.iter().map(|step| {
            serde_json::json!({
                "type": "workflow_step",
                "program": program.id,
                "step": step.id,
                "agent": step.agent,
                "strategy": step.strategy
            })
        }).collect::<Vec<_>>()
    })
}

pub(crate) fn default_beagle_paper_title() -> String {
    "Beagle: A Self-Governing Exocortex for Agentic Research, Work Memory, and Durable Cognitive Workflows".to_string()
}

pub(crate) fn default_beagle_paper_sections() -> Vec<&'static str> {
    vec![
        "Introduction",
        "Related Work",
        "Architecture",
        "Sounio IR",
        "Memory and ContextPack",
        "MCP and Apple Surfaces",
        "Evaluation",
        "Security and Ethics",
        "Limitations",
    ]
}

pub(crate) fn default_beagle_self_writing_program() -> SounioProgram {
    let provenance = serde_json::json!({
        "source": "beagle-v2.4-plan",
        "paper": "self-writing systems preprint",
        "cluster_only": true
    });
    let governance = serde_json::json!({
        "privacy_class": "sensitive",
        "requires_provenance": true,
        "restricted_policy": "exclude",
        "human_approval_required": true
    });
    SounioProgram {
        id: "beagle-self-writing-paperrun-v24".to_string(),
        sounio_version: default_sounio_version(),
        kind: default_sounio_program_kind(),
        intent: "Write the Beagle systems paper using Beagle/Sounio as the durable, audited work substrate.".to_string(),
        context: serde_json::json!({
            "paper_type": "arXiv systems preprint",
            "thesis": "self-writing paper with traceable agentic memory",
            "canonical_memory": "/var/lib/beagle/exocortex",
            "artifact_root": "/orangefs/beagle-memory-lab/paperruns"
        }),
        plan: [
            ("retrieve_state", "Retrieve Beagle/Sounio state", false),
            ("compile_context", "Compile ContextPack for the paper", false),
            ("outline", "Create manuscript outline", false),
            ("source_map", "Map claims to evidence and citations", false),
            ("draft_section", "Draft Architecture/Methods section", false),
            ("critical_review", "Run critical review and overclaim guard", false),
            ("claim_check", "Mark unsupported claims before export", false),
            ("human_approval", "Human approval gate before manuscript export", true),
            ("revise", "Apply approved revisions", false),
            ("export_manuscript", "Export Markdown/LaTeX/PDF draft", false),
            ("record_effectiveness", "Record memory/context effectiveness", false),
        ]
        .iter()
        .map(|(id, title, approval)| SounioStep {
            id: id.to_string(),
            title: title.to_string(),
            objective: Some(format!("{title} for the Beagle self-writing systems paper.")),
            agent: Some(if *id == "human_approval" { "demetrios" } else { "beagle-agents" }.to_string()),
            strategy: Some(match *id {
                "retrieve_state" => "retrieval_agent",
                "compile_context" => "context_compiler",
                "critical_review" | "claim_check" => "governor_critical",
                _ => "durable_activity",
            }.to_string()),
            requires_human_approval: *approval,
            provenance: provenance.clone(),
            governance: governance.clone(),
        })
        .collect(),
        actions: vec![
            SounioAction {
                id: "compile-to-temporal".to_string(),
                action_type: "compile".to_string(),
                target: "Temporal.Workflow:BeagleSelfWritingPaperRun".to_string(),
                parameters: serde_json::json!({"task_queue": "sounio-paperrun"}),
                provenance: provenance.clone(),
            },
            SounioAction {
                id: "project-to-memory".to_string(),
                action_type: "project".to_string(),
                target: "Beagle.Memory:Episode+Atom+Hyperedge".to_string(),
                parameters: serde_json::json!({"privacy_class": "sensitive"}),
                provenance: provenance.clone(),
            },
        ],
        evidence: Vec::new(),
        decisions: vec![SounioDecision {
            id: "decision-self-writing-paper".to_string(),
            summary: "The first Sounio proof artifact is a durable PaperRun for the Beagle self-writing systems paper.".to_string(),
            rationale: Some("A PaperRun tests continuity, provenance, claims, agents, memory, and publication artifacts in one loop.".to_string()),
            evidence_refs: Vec::new(),
            provenance: provenance.clone(),
        }],
        checks: vec![
            SounioCheck {
                id: "restricted-leak-zero".to_string(),
                check_type: "security".to_string(),
                description: "Restricted content must not enter manuscript/export artifacts.".to_string(),
                status: Some("required".to_string()),
                required: true,
                provenance: provenance.clone(),
            },
            SounioCheck {
                id: "unsupported-claims-marked".to_string(),
                check_type: "paper_quality".to_string(),
                description: "Every claim is supported by evidence/provenance or marked unsupported.".to_string(),
                status: Some("required".to_string()),
                required: true,
                provenance: provenance.clone(),
            },
        ],
        outcome: None,
        next_action: Some("Start PaperRun, approve the human gate, then export a reviewed draft.".to_string()),
        governance: SounioGovernance {
            privacy_class: "sensitive".to_string(),
            provenance,
            restricted_leak_check: serde_json::json!({"status": "required", "policy": "exclude_restricted"}),
            human_approval_required: true,
            policy_refs: vec![
                "admin:destructive absent".to_string(),
                "human approval before publication".to_string(),
            ],
        },
    }
}

pub(crate) fn default_beagle_paper_claims() -> Vec<serde_json::Value> {
    vec![
        serde_json::json!({
            "id": "claim-exocortex-loop",
            "text": "Beagle implements a durable exocortex loop connecting memory, agents, MCP, Apple surfaces, and audited action.",
            "status": "needs_evidence",
            "required_evidence": ["MCP manifest", "GraphRAG++ memory", "Apple capture", "audit trail"]
        }),
        serde_json::json!({
            "id": "claim-sounio-ir",
            "text": "Sounio models cognitive work as a replayable, auditable intermediate representation.",
            "status": "needs_evidence",
            "required_evidence": ["SounioProgram", "Temporal workflow", "SounioTraceEvent"]
        }),
        serde_json::json!({
            "id": "claim-self-writing-method",
            "text": "The paper production process itself can be captured as evidence for the system architecture.",
            "status": "unsupported_until_paperrun_trace_exists",
            "required_evidence": ["PaperRun trace", "ContextPack", "human approval"]
        }),
    ]
}

pub(crate) fn default_beagle_paper_citations() -> Vec<serde_json::Value> {
    vec![
        serde_json::json!({"id": "temporal-docs", "title": "Temporal durable execution documentation", "status": "source-map-pending"}),
        serde_json::json!({"id": "mcp-spec", "title": "Model Context Protocol specification", "status": "source-map-pending"}),
        serde_json::json!({"id": "literate-programming", "title": "Literate Programming", "status": "source-map-pending"}),
        serde_json::json!({"id": "research-object-crate", "title": "Workflow Run RO-Crate", "status": "source-map-pending"}),
    ]
}

pub(crate) fn paper_run_markdown(run: &PaperRun) -> String {
    let mut text = format!(
        "# {}\n\n**PaperRun:** `{}`  \n**Temporal workflow:** `{}`  \n**Sounio program hash:** `{}`  \n**Status:** `{}`\n\n",
        run.title, run.id, run.temporal_workflow_id, run.sounio_program_hash, run.status
    );
    text.push_str("## Abstract\n\n");
    text.push_str(
        "TODO: draft after ContextPack, source mapping, critical review, and human approval.\n\n",
    );
    for section in default_beagle_paper_sections() {
        let status = run
            .section_status
            .get(section)
            .cloned()
            .unwrap_or_else(|| "planned".to_string());
        text.push_str(&format!("## {section}\n\n_Status: {status}._\n\n"));
    }
    text.push_str("## Claim Registry\n\n");
    for claim in &run.claim_registry {
        let id = claim
            .get("id")
            .and_then(|value| value.as_str())
            .unwrap_or("claim");
        let status = claim
            .get("status")
            .and_then(|value| value.as_str())
            .unwrap_or("needs_evidence");
        let claim_text = claim
            .get("text")
            .and_then(|value| value.as_str())
            .unwrap_or("");
        text.push_str(&format!("- `{id}` [{status}]: {claim_text}\n"));
    }
    text.push_str("\n## Publication Guard\n\nNo automatic arXiv submission. Human approval is required before external release.\n");
    text
}

pub(crate) fn atoms_from_import(
    import: &OmniConversation,
    episode: &MemoryEpisode,
) -> Vec<MemoryAtom> {
    let mut atoms = Vec::new();
    push_atoms(
        &mut atoms,
        "insight",
        &import.extracted.key_insights,
        import,
        episode,
    );
    push_atoms(
        &mut atoms,
        "decision",
        &import.extracted.decisions,
        import,
        episode,
    );
    push_atoms(
        &mut atoms,
        "hypothesis",
        &import.extracted.hypotheses,
        import,
        episode,
    );
    push_atoms(
        &mut atoms,
        "belief_change",
        &import.extracted.belief_changes,
        import,
        episode,
    );
    push_atoms(
        &mut atoms,
        "open_question",
        &import.extracted.unresolved_questions,
        import,
        episode,
    );
    push_atoms(
        &mut atoms,
        "project",
        &import.extracted.projects_mentioned,
        import,
        episode,
    );
    atoms
}

pub(crate) fn push_atoms(
    atoms: &mut Vec<MemoryAtom>,
    atom_type: &str,
    values: &[String],
    import: &OmniConversation,
    episode: &MemoryEpisode,
) {
    for value in values {
        let text = truncate_chars(value, 500);
        let atom = MemoryAtom {
            id: stable_id("atom", &[&episode.id, atom_type, &text]),
            created_at: Utc::now().to_rfc3339(),
            episode_id: episode.id.clone(),
            atom_type: atom_type.to_string(),
            normalized_text: normalize_text(&text),
            text,
            source_refs: vec![episode.source_ref.clone(), import.raw_content_ref.clone()],
            relations: relations_for_import(import, episode),
            tags: import.tags.clone(),
            confidence: import.confidence_score,
            privacy_class: import.privacy_class.clone(),
            occurred_at: episode.occurred_at.clone(),
        };
        atoms.push(atom);
    }
}

pub(crate) fn relations_for_import(
    import: &OmniConversation,
    episode: &MemoryEpisode,
) -> Vec<MemoryRelation> {
    let mut relations = relations_for_tags(&import.tags, &episode.id);
    for project in &import.extracted.projects_mentioned {
        relations.push(MemoryRelation {
            subject: project.clone(),
            predicate: "mentioned_in".to_string(),
            object: episode.id.clone(),
            confidence: 0.78,
        });
    }
    for decision in &import.extracted.decisions {
        for hypothesis in &import.extracted.hypotheses {
            relations.push(MemoryRelation {
                subject: truncate_chars(decision, 120),
                predicate: "informs_hypothesis".to_string(),
                object: truncate_chars(hypothesis, 120),
                confidence: 0.58,
            });
        }
    }
    relations
}

pub(crate) fn relations_for_tags(tags: &[String], episode_id: &str) -> Vec<MemoryRelation> {
    tags.iter()
        .filter_map(|tag| tag.strip_prefix("project:"))
        .map(|project| MemoryRelation {
            subject: project.to_string(),
            predicate: "has_episode".to_string(),
            object: episode_id.to_string(),
            confidence: 0.72,
        })
        .collect()
}

pub(crate) fn normalize_text(value: &str) -> String {
    value
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

pub(crate) fn tokenize(value: &str) -> Vec<String> {
    value
        .to_lowercase()
        .split(|ch: char| !ch.is_alphanumeric())
        .filter(|token| token.len() > 2)
        .map(ToOwned::to_owned)
        .collect()
}

pub(crate) fn atom_score(atom: &MemoryAtom, query_tokens: &[String]) -> f64 {
    if query_tokens.is_empty() {
        return 0.0;
    }
    let text = atom.normalized_text.as_str();
    let token_hits = query_tokens
        .iter()
        .filter(|token| text.contains(token.as_str()))
        .count();
    if token_hits == 0 {
        return 0.0;
    }
    let lexical = token_hits as f64 / query_tokens.len() as f64;
    let type_boost = match atom.atom_type.as_str() {
        "decision" => 0.12,
        "hypothesis" => 0.10,
        "belief_change" => 0.09,
        "project" => 0.06,
        _ => 0.0,
    };
    let graph_boost = if atom.relations.is_empty() { 0.0 } else { 0.08 };
    let recency_boost = atom
        .occurred_at
        .as_deref()
        .and_then(|date| chrono::DateTime::parse_from_rfc3339(date).ok())
        .map(|date| {
            let age_days = (Utc::now() - date.with_timezone(&Utc)).num_days().max(0) as f64;
            (0.08 / (1.0 + age_days / 30.0)).clamp(0.0, 0.08)
        })
        .unwrap_or(0.0);
    (lexical * 0.72 + type_boost + graph_boost + recency_boost)
        .min(1.0)
        .max(0.0)
}

pub(crate) fn hypermemory_atom_score(atom: &MemoryAtom, query_tokens: &[String]) -> f64 {
    if query_tokens.is_empty() {
        return 0.0;
    }
    let graph_material = std::iter::once(atom.normalized_text.as_str())
        .chain(atom.tags.iter().map(String::as_str))
        .chain(atom.source_refs.iter().map(String::as_str))
        .chain(atom.relations.iter().flat_map(|relation| {
            [
                relation.subject.as_str(),
                relation.predicate.as_str(),
                relation.object.as_str(),
            ]
        }))
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase();
    let token_hits = query_tokens
        .iter()
        .filter(|token| graph_material.contains(token.as_str()))
        .count();
    if token_hits == 0 {
        return 0.0;
    }
    let lexical = token_hits as f64 / query_tokens.len() as f64;
    let base = atom_score(atom, query_tokens);
    let hyperedge_boost = (atom.relations.len() as f64 * 0.025).clamp(0.0, 0.12);
    let source_boost = if atom.source_refs.is_empty() {
        0.0
    } else {
        0.07
    };
    let tag_boost = if atom.tags.is_empty() { 0.0 } else { 0.06 };
    let fact_boost = match atom.atom_type.as_str() {
        "decision" | "hypothesis" | "evidence" | "action" => 0.10,
        "project" | "principle" | "open_question" => 0.07,
        _ => 0.03,
    };
    (base.max(lexical * 0.64) + hyperedge_boost + source_boost + tag_boost + fact_boost)
        .clamp(0.0, 1.0)
}

#[derive(Debug, Clone)]
pub(crate) struct RankedMemoryAtom {
    atom: MemoryAtom,
    base_score: f64,
    final_score: f64,
    exact_boost: f64,
    recency_boost: f64,
    source_boost: f64,
    stable_boost: f64,
    reasons: Vec<String>,
}

pub(crate) fn memory_ranking_policy(requested: Option<&str>) -> String {
    let raw = requested
        .map(ToOwned::to_owned)
        .or_else(|| env::var("BEAGLE_MEMORY_RANKING_POLICY").ok())
        .unwrap_or_else(|| "strict_recent_guarded".to_string())
        .to_lowercase();
    match raw.as_str() {
        "legacy_stable" => "legacy_stable".to_string(),
        _ => "strict_recent_guarded".to_string(),
    }
}

pub(crate) fn stable_fact_guard_applies(query: &str, query_tokens: &[String]) -> bool {
    let q = query.to_lowercase();
    let stable_terms = [
        "portfolio",
        "mandic",
        "ra",
        "18224624",
        "doi",
        "e-mail",
        "email",
        "congresso",
        "congress",
        "cpc",
        "dmh",
        "data",
        "date",
        "identidade",
        "identity",
        "histórico",
        "historico",
        "history",
        "rapamicina",
        "cistinose",
        "phd",
        "mensa",
        "publicação",
        "publicacao",
        "publication",
    ];
    stable_terms.iter().any(|term| q.contains(term))
        || query_tokens
            .iter()
            .any(|token| token.starts_with("10.") || token.starts_with("ra_"))
}

pub(crate) fn is_restricted_memory(atom: &MemoryAtom, episode: Option<&MemoryEpisode>) -> bool {
    let mut material = vec![
        atom.privacy_class.to_lowercase(),
        atom.tags.join(" ").to_lowercase(),
        atom.source_refs.join(" ").to_lowercase(),
    ];
    if let Some(episode) = episode {
        material.push(episode.privacy_class.to_lowercase());
        material.push(episode.tags.join(" ").to_lowercase());
        material.push(episode.provenance.to_string().to_lowercase());
    }
    material
        .join(" ")
        .split_whitespace()
        .any(|token| token == "restricted" || token == "restricted_local_only")
}

pub(crate) fn rank_memory_atom(
    atom: &MemoryAtom,
    episode: Option<&MemoryEpisode>,
    base_score: f64,
    query_tokens: &[String],
    ranking_policy: &str,
    stable_fact_guard: bool,
) -> RankedMemoryAtom {
    if ranking_policy == "legacy_stable" {
        return RankedMemoryAtom {
            atom: atom.clone(),
            base_score,
            final_score: base_score,
            exact_boost: 0.0,
            recency_boost: 0.0,
            source_boost: 0.0,
            stable_boost: 0.0,
            reasons: vec!["legacy_stable policy kept historical score order".to_string()],
        };
    }

    let material = ranking_material(atom, episode);
    let exact_hits = query_tokens
        .iter()
        .filter(|token| token.len() >= 4 && material.contains(token.as_str()))
        .count();
    let id_hits = query_tokens
        .iter()
        .filter(|token| {
            token.len() >= 6 && looks_like_identifier(token) && material.contains(token.as_str())
        })
        .count();
    let live_work_material = is_live_work_material(&material);
    let stable_fact_material = is_stable_fact_material(&material);
    let stable_fact_source = is_stable_fact_source(atom, episode, &material);
    let mut exact_boost = ((exact_hits as f64 * 0.045) + (id_hits as f64 * 0.18)).clamp(0.0, 0.42);
    if stable_fact_guard && live_work_material && !stable_fact_source {
        exact_boost *= 0.35;
    }
    let source_boost = if !stable_fact_guard && live_work_material {
        0.14
    } else {
        0.0
    };
    let stable_boost = if stable_fact_guard && stable_fact_source {
        0.5
    } else if stable_fact_guard && stable_fact_material && !live_work_material {
        0.2
    } else if stable_fact_guard && stable_fact_material {
        0.0
    } else {
        0.0
    };
    let recency_boost = recency_boost_for(atom, episode, stable_fact_guard, stable_fact_source);
    let weighted_base = if stable_fact_guard && live_work_material && !stable_fact_source {
        base_score * 0.25
    } else if stable_fact_guard && stable_fact_source {
        base_score * 0.9
    } else if stable_fact_guard {
        base_score * 0.82
    } else {
        base_score * 0.58
    };
    let confidence_boost = if stable_fact_guard {
        atom.confidence * 0.04
    } else {
        atom.confidence * 0.08
    };
    let final_score = (weighted_base
        + exact_boost
        + source_boost
        + stable_boost
        + recency_boost
        + confidence_boost)
        .clamp(0.0, 1.0);

    let mut reasons = Vec::new();
    if exact_boost > 0.0 {
        reasons.push(format!("exact_or_identifier_boost={exact_boost:.3}"));
    }
    if recency_boost > 0.0 {
        reasons.push(format!("recency_boost={recency_boost:.3}"));
    }
    if source_boost > 0.0 {
        reasons.push(format!("live_work_source_boost={source_boost:.3}"));
    }
    if stable_boost > 0.0 {
        reasons.push(format!("stable_fact_guard_boost={stable_boost:.3}"));
    }
    if stable_fact_guard {
        reasons.push("Stable Fact Guard reduced recency pressure.".to_string());
    }

    RankedMemoryAtom {
        atom: atom.clone(),
        base_score,
        final_score,
        exact_boost,
        recency_boost,
        source_boost,
        stable_boost,
        reasons,
    }
}

pub(crate) fn ranking_material(atom: &MemoryAtom, episode: Option<&MemoryEpisode>) -> String {
    let mut parts = vec![
        atom.id.as_str(),
        atom.episode_id.as_str(),
        atom.atom_type.as_str(),
        atom.text.as_str(),
        atom.normalized_text.as_str(),
    ]
    .into_iter()
    .map(ToOwned::to_owned)
    .collect::<Vec<_>>();
    parts.extend(atom.tags.clone());
    parts.extend(atom.source_refs.clone());
    parts.extend(atom.relations.iter().flat_map(|relation| {
        [
            relation.subject.clone(),
            relation.predicate.clone(),
            relation.object.clone(),
        ]
    }));
    if let Some(episode) = episode {
        parts.extend([
            episode.id.clone(),
            episode.source.clone(),
            episode.source_ref.clone(),
            episode.content_hash.clone(),
            episode.privacy_class.clone(),
        ]);
        if let Some(platform) = &episode.source_platform {
            parts.push(platform.clone());
        }
        if let Some(session_id) = &episode.session_id {
            parts.push(session_id.clone());
        }
        if let Some(title) = &episode.title {
            parts.push(title.clone());
        }
        parts.extend(episode.tags.clone());
        parts.extend(episode.linked_chronoself_commits.clone());
        parts.push(episode.provenance.to_string());
    }
    parts.join(" ").to_lowercase()
}

pub(crate) fn looks_like_identifier(token: &str) -> bool {
    token.chars().any(|ch| ch.is_ascii_digit())
        || token.contains('-')
        || token.contains('_')
        || token.starts_with("sha")
}

pub(crate) fn is_live_work_material(material: &str) -> bool {
    [
        "workbench",
        "terminal-block",
        "codex",
        "claude-code",
        "beagle-workbench",
        "beagle-apple",
        "source_surface",
        "memory_event_id",
        "audit_event_id",
        "branch",
        "commit",
    ]
    .iter()
    .any(|term| material.contains(term))
}

pub(crate) fn is_stable_fact_material(material: &str) -> bool {
    [
        "portfolio",
        "mandic",
        "ra_18224624",
        "18224624",
        "doi",
        "congresso",
        "cpc_2026",
        "dmh_2026",
        "rapamicina",
        "cistinose",
        "documento_canonico",
        "v3_final",
    ]
    .iter()
    .any(|term| material.contains(term))
}

pub(crate) fn is_stable_fact_source(
    atom: &MemoryAtom,
    episode: Option<&MemoryEpisode>,
    material: &str,
) -> bool {
    let stable_tags_or_refs = atom
        .tags
        .iter()
        .chain(atom.source_refs.iter())
        .any(|value| {
            let value = value.to_lowercase();
            [
                "portfolio_institucional",
                "documento_canonico",
                "v3_final",
                "mandic",
                "ra_18224624",
                "doi",
                "publication",
                "publicacao",
            ]
            .iter()
            .any(|term| value.contains(term))
        });
    let stable_episode = episode.is_some_and(|episode| {
        let source = episode.source.to_lowercase();
        let source_platform = episode
            .source_platform
            .as_deref()
            .unwrap_or_default()
            .to_lowercase();
        let source_surface = episode
            .provenance
            .get("metadata")
            .and_then(|metadata| metadata.get("source_surface"))
            .and_then(|surface| surface.as_str())
            .unwrap_or_default()
            .to_lowercase();
        source.contains("portfolio")
            || source_platform.contains("portfolio")
            || source_surface.contains("portfolio-import")
            || episode.tags.iter().any(|tag| {
                let tag = tag.to_lowercase();
                tag.contains("portfolio_institucional")
                    || tag.contains("documento_canonico")
                    || tag.contains("v3_final")
            })
    });

    stable_episode
        || stable_tags_or_refs
        || (is_stable_fact_material(material) && !is_live_work_material(material))
}

pub(crate) fn recency_boost_for(
    atom: &MemoryAtom,
    episode: Option<&MemoryEpisode>,
    stable_fact_guard: bool,
    stable_fact_source: bool,
) -> f64 {
    let timestamp = atom
        .occurred_at
        .as_deref()
        .or_else(|| episode.and_then(|episode| episode.occurred_at.as_deref()))
        .or_else(|| Some(atom.created_at.as_str()))
        .and_then(|date| chrono::DateTime::parse_from_rfc3339(date).ok());
    let Some(timestamp) = timestamp else {
        return 0.0;
    };
    let age_hours = (Utc::now() - timestamp.with_timezone(&Utc))
        .num_hours()
        .max(0) as f64;
    if stable_fact_guard {
        if !stable_fact_source {
            return 0.0;
        }
        (0.045 / (1.0 + age_hours / 720.0)).clamp(0.0, 0.045)
    } else {
        (0.36 / (1.0 + age_hours / 168.0)).clamp(0.0, 0.36)
    }
}

pub(crate) fn ranking_trace_json(
    ranked: &[RankedMemoryAtom],
    ranking_policy: &str,
    stable_fact_guard_applied: bool,
) -> serde_json::Value {
    serde_json::json!({
        "policy": ranking_policy,
        "stable_fact_guard_applied": stable_fact_guard_applied,
        "top": ranked.iter().take(8).map(|item| {
            serde_json::json!({
                "atom_id": item.atom.id,
                "episode_id": item.atom.episode_id,
                "atom_type": item.atom.atom_type,
                "base_score": item.base_score,
                "final_score": item.final_score,
                "exact_boost": item.exact_boost,
                "recency_boost": item.recency_boost,
                "source_boost": item.source_boost,
                "stable_boost": item.stable_boost,
                "occurred_at": item.atom.occurred_at,
                "reasons": item.reasons,
            })
        }).collect::<Vec<_>>()
    })
}

pub(crate) fn truncate_chars(value: &str, max_chars: usize) -> String {
    value.chars().take(max_chars).collect()
}

// ───────────────────────── cognitive playground ─────────────────────────
// The iOS cockpit calls un-prefixed paths that 404'd because no backend existed.
// They now resolve to REAL engines: deep-think → TieredRouter (LLM); fractal.recurse
// + phi.compute → Sounio verbs on the inference service (Julia is gone, Φ is the real
// IIT-4 bipartition-MIP ported into Sounio); hyperedges → the live memory-graph store.
// Honest by construction throughout: a failed verb/router NEVER fabricates a result.
use beagle_triad::inference_client::{
    fractal_recurse, inference_base_url, phi_compute, FractalRequest, PhiRequest,
};

#[derive(Debug, Deserialize)]
pub(crate) struct DeepThinkRequest {
    #[serde(default)]
    root_prompt: String,
    #[serde(default)]
    max_depth: Option<u32>,
}

/// POST /api/cognitive/deep-think — real multi-pass reasoning via the TieredRouter.
/// Emits the `ChatResponse` shape the iOS `deepThink` decoder expects.
pub(crate) async fn deep_think_handler(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<DeepThinkRequest>,
) -> Json<serde_json::Value> {
    let topic = req.root_prompt.trim().to_string();
    if topic.is_empty() {
        return Json(serde_json::json!({
            "response": "", "agent_kind": "deep_think",
            "flow_state": "idle", "error": "empty root_prompt"
        }));
    }
    let depth = req.max_depth.unwrap_or(3).clamp(1, 6);
    let prompt = format!(
        "You are the deep-reasoning layer of an exocortex. Reason about the topic below in \
         {depth} progressively deeper passes: pass 1 restates the core question and surfaces \
         hidden assumptions; each further pass goes one level deeper — mechanisms, \
         second-order effects, strongest counter-arguments. Be rigorous and concrete; do not \
         pad. End with a 2-3 sentence SYNTHESIS.\n\nTopic:\n{topic}"
    );
    let consumer_identity = headers
        .get("X-Beagle-Consumer")
        .and_then(|v| v.to_str().ok())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());
    let mut bctx = state.ctx.lock().await;
    let meta = RequestMeta {
        approximate_tokens: prompt.len() / 4,
        requires_high_quality: true,
        requires_phd_level_reasoning: depth >= 4,
        identity: consumer_identity,
        ..Default::default()
    };
    let stats = bctx.llm_stats.get_or_create("deep_think");
    let (client, tier) = bctx.router.choose_with_limits(&meta, &stats);
    let tier_label = format!("{tier:?}");
    match bctx.router.complete_chosen(&client, tier, &prompt).await {
        Ok(answer) => Json(serde_json::json!({
            "response": answer,
            "model": tier_label,
            "agent_kind": "deep_think",
            "flow_state": "flow",
        })),
        Err(e) => Json(serde_json::json!({
            "response": "",
            "agent_kind": "deep_think",
            "flow_state": "idle",
            "error": format!("router error: {e}"),
        })),
    }
}

/// POST /api/fractal/recurse — Sounio deterministic fractal-tree growth.
/// Dual shape matching the iOS client: with `branching_factor` it is `startFractalTree`
/// → flat `FractalTree`; bare `root_prompt` is `fractalGrow` → `{result, summary}`.
/// Both backed by the same `fractal.recurse` verb.
pub(crate) async fn fractal_recurse_handler(
    Json(body): Json<serde_json::Value>,
) -> Json<serde_json::Value> {
    let root_prompt = body
        .get("root_prompt")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let has_branching = body.get("branching_factor").is_some();
    let branching = body
        .get("branching_factor")
        .and_then(|v| v.as_u64())
        .unwrap_or(2) as u32;
    let max_depth = body
        .get("max_depth")
        .and_then(|v| v.as_u64())
        .unwrap_or(if has_branching { 2 } else { 5 }) as u32;
    let now = Utc::now().to_rfc3339();
    let root_id = stable_id("fractal", &[&root_prompt, &now]);
    let req = FractalRequest {
        depth: max_depth.clamp(1, 16),
        branching: branching.clamp(2, 8),
        budget: Some(10_000),
        seed: Some(root_prompt.chars().count() as f64),
    };
    let res = fractal_recurse(&inference_base_url(), req).await;
    match (res, has_branching) {
        (Some(r), true) => Json(serde_json::json!({
            "root_id": root_id,
            "root_prompt": root_prompt,
            "max_depth": r.max_depth,
            "branching": branching,
            "node_count": r.node_count,
            "generated_at": now,
            "truth_mode": "computed",
        })),
        (Some(r), false) => Json(serde_json::json!({
            "result": {
                "root_id": root_id,
                "node_count": r.node_count,
                "max_depth": r.max_depth,
                "truncated": r.truncated,
            },
            "summary": format!(
                "Sounio fractal grew {} nodes to depth {} from the seed prompt.",
                r.node_count, r.max_depth
            ),
        })),
        (None, true) => Json(serde_json::json!({
            "root_id": root_id, "root_prompt": root_prompt,
            "max_depth": 0, "branching": branching, "node_count": 0,
            "generated_at": now, "truth_mode": "unavailable",
        })),
        (None, false) => Json(serde_json::json!({
            "result": serde_json::Value::Null,
            "summary": "fractal verb unavailable",
        })),
    }
}

#[derive(Debug, Deserialize)]
pub(crate) struct PhiQueryRequest {
    #[serde(default)]
    query: String,
}

/// POST /api/exocortex/process — measure integrated information Φ over a substrate
/// BUILT FROM REAL MEMORY: recall up to 8 atoms for the query, build an n×n connectivity
/// matrix from pairwise token-overlap (Jaccard), and run the Sounio `phi.compute` verb.
/// Returns the iOS `PhiMeasurement` shape. Honest: <2 atoms or verb failure → no faked Φ
/// (the `truth_mode` field reports exactly why).
pub(crate) async fn exocortex_process_handler(
    Json(req): Json<PhiQueryRequest>,
) -> Json<serde_json::Value> {
    let query = req.query.trim().to_string();
    let snippet: String = query.chars().take(120).collect();
    let now = Utc::now().to_rfc3339();
    if query.is_empty() {
        return Json(serde_json::json!({
            "query_snippet": snippet, "substrate_size": 0,
            "truth_mode": "empty_query", "measured_at": now,
            "awareness_level": "indeterminate",
        }));
    }
    let sources = memory_engine_recall(&query, "all", 8).await;
    let n = sources.len();
    if n < 2 {
        return Json(serde_json::json!({
            "query_snippet": snippet, "substrate_size": n,
            "truth_mode": "insufficient_substrate", "measured_at": now,
            "awareness_level": "indeterminate",
        }));
    }
    let tokens: Vec<BTreeSet<String>> = sources
        .iter()
        .map(|s| {
            s.text
                .to_lowercase()
                .split(|c: char| !c.is_alphanumeric())
                .filter(|w| w.len() > 3)
                .map(|w| w.to_string())
                .collect()
        })
        .collect();
    let mut matrix = vec![0.0f64; n * n];
    for i in 0..n {
        for j in 0..n {
            if i != j {
                let inter = tokens[i].intersection(&tokens[j]).count();
                let uni = tokens[i].union(&tokens[j]).count().max(1);
                matrix[i * n + j] = inter as f64 / uni as f64;
            }
        }
    }
    let t0 = std::time::Instant::now();
    let res = phi_compute(
        &inference_base_url(),
        PhiRequest {
            n: n as u32,
            matrix,
        },
    )
    .await;
    let dur = t0.elapsed().as_millis() as u64;
    match res {
        Some(p) => {
            let awareness = if p.phi <= 0.0 {
                "decomposable"
            } else if p.phi < 0.5 {
                "low"
            } else if p.phi < 1.5 {
                "moderate"
            } else {
                "high"
            };
            let mip: Vec<Vec<String>> = p
                .mip_partition
                .iter()
                .map(|grp| {
                    grp.iter()
                        .filter_map(|&idx| {
                            sources
                                .get(idx)
                                .map(|s| s.text.chars().take(40).collect::<String>())
                        })
                        .collect()
                })
                .collect();
            Json(serde_json::json!({
                "query_snippet": snippet,
                "phi": p.phi,
                "substrate_size": p.n,
                "mip_partition": mip,
                "awareness_level": awareness,
                "router_tier": "sounio::phi.compute",
                "measured_at": now,
                "duration_ms": dur,
                "truth_mode": "measured",
            }))
        }
        None => Json(serde_json::json!({
            "query_snippet": snippet, "substrate_size": n,
            "truth_mode": "verb_unavailable", "measured_at": now,
            "awareness_level": "indeterminate",
        })),
    }
}

/// GET /api/hyperedges — real memory-graph relations + user-created edges.
pub(crate) async fn hyperedges_list_handler(
    Query(q): Query<HyperedgeListQuery>,
) -> Result<Json<Vec<HyperedgeRecord>>, StatusCode> {
    let repo = ExocortexRepository::default();
    match repo.list_hyperedges(q.node_id.as_deref(), 50) {
        Ok(list) => Ok(Json(list)),
        Err(e) => {
            error!("hyperedges_list: {e}");
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

/// POST /api/hyperedges — create a hyperedge in the real store.
pub(crate) async fn hyperedges_create_handler(
    Json(req): Json<CreateHyperedgeRequest>,
) -> Result<Json<HyperedgeRecord>, StatusCode> {
    if req.label.trim().is_empty() || req.node_ids.is_empty() {
        return Err(StatusCode::UNPROCESSABLE_ENTITY);
    }
    let repo = ExocortexRepository::default();
    match repo.create_hyperedge(&req.label, req.node_ids, req.directed, req.metadata) {
        Ok(rec) => Ok(Json(rec)),
        Err(e) => {
            error!("hyperedges_create: {e}");
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn repository_appends_commits_and_reads_newest_first() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let first = repo
            .create_commit(CreateCommitRequest {
                user_id: Some("test".to_string()),
                self_version: Some("v2026.04.25.01".to_string()),
                parent_commit_ids: Vec::new(),
                context_snapshot: None,
                identity_delta: IdentityDelta {
                    beliefs_added: vec!["continuity matters".to_string()],
                    ..Default::default()
                },
                trigger_type: Some("manual".to_string()),
                confidence: None,
                source_refs: Vec::new(),
                summary: Some("First".to_string()),
            })
            .unwrap();
        let second = repo
            .create_commit(CreateCommitRequest {
                user_id: Some("test".to_string()),
                self_version: Some("v2026.04.25.02".to_string()),
                parent_commit_ids: Vec::new(),
                context_snapshot: None,
                identity_delta: IdentityDelta::default(),
                trigger_type: Some("manual".to_string()),
                confidence: None,
                source_refs: Vec::new(),
                summary: Some("Second".to_string()),
            })
            .unwrap();
        assert_eq!(second.parent_commit_ids, vec![first.id]);
        let commits = repo
            .read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 2)
            .unwrap();
        assert_eq!(commits[0].id, second.id);
        assert_eq!(commits[1].summary.as_deref(), Some("First"));
    }

    #[test]
    fn chronoself_hash_changes_when_delta_changes() {
        let ctx = ContextSnapshot {
            health_ref: None,
            active_project_ids: Vec::new(),
            recent_decision_ids: Vec::new(),
            energy_level: None,
            emotional_valence: None,
            platform: None,
            target_hardware: None,
        };
        let a = chronoself_hash(
            "v1",
            &[],
            &ctx,
            &IdentityDelta {
                beliefs_added: vec!["a".to_string()],
                ..Default::default()
            },
            "manual",
        )
        .unwrap();
        let b = chronoself_hash(
            "v1",
            &[],
            &ctx,
            &IdentityDelta {
                beliefs_added: vec!["b".to_string()],
                ..Default::default()
            },
            "manual",
        )
        .unwrap();
        assert_ne!(a, b);
        assert_eq!(a.len(), 64);
    }

    #[test]
    fn omnimemory_import_can_create_linked_commit() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let imported = repo
            .import_conversation(ImportConversationRequest {
                source_platform: "ChatGPT".to_string(),
                session_id: None,
                original_date: None,
                raw_content: "Decisão: Beagle precisa de MCP como sistema nervoso do exocortex."
                    .to_string(),
                title: Some("MCP decision".to_string()),
                tags: vec!["project:sounio".to_string()],
                extracted: None,
                confidence_score: Some(0.8),
                create_chronoself_commit: Some(true),
                privacy_class: None,
                metadata: None,
            })
            .unwrap();
        assert_eq!(imported.source_platform, "chatgpt");
        assert_eq!(imported.linked_chronoself_commits.len(), 1);
        let duplicate = repo
            .import_conversation(ImportConversationRequest {
                source_platform: "ChatGPT".to_string(),
                session_id: None,
                original_date: None,
                raw_content: "Decisão: Beagle precisa de MCP como sistema nervoso do exocortex."
                    .to_string(),
                title: Some("MCP decision duplicate".to_string()),
                tags: vec!["project:sounio".to_string()],
                extracted: None,
                confidence_score: Some(0.8),
                create_chronoself_commit: Some(true),
                privacy_class: None,
                metadata: None,
            })
            .unwrap();
        assert_eq!(duplicate.id, imported.id);
        let imports = repo
            .read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 10)
            .unwrap();
        assert_eq!(imports.len(), 1);
    }

    #[test]
    fn audit_and_memory_events_are_append_only_and_feed_home_trust() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let audit = repo
            .create_audit_event(CreateAuditEventRequest {
                client_id: Some("claude-desktop".to_string()),
                action: Some("tools/call".to_string()),
                tool_name: Some("beagle_memory_ingest_chat".to_string()),
                risk_level: Some("write".to_string()),
                required_scopes: vec!["memory:write".to_string()],
                granted_scopes: vec!["exocortex:read".to_string(), "memory:write".to_string()],
                status: Some("success".to_string()),
                source: Some("mcp".to_string()),
                target_ref: None,
                summary: Some("Stored a conversation turn.".to_string()),
                metadata: Some(serde_json::json!({
                    "tool_manifest_hash": "sha256:test"
                })),
            })
            .unwrap();
        let memory = repo
            .create_memory_event(CreateMemoryEventRequest {
                source: Some("mcp".to_string()),
                kind: Some("agent_write".to_string()),
                content_ref: Some("memory:abc".to_string()),
                summary: Some("Beagle MCP is now audited.".to_string()),
                tags: vec!["project:sounio".to_string()],
                metadata: None,
                linked_chronoself_commits: Vec::new(),
                confidence: Some(0.8),
            })
            .unwrap();
        let audits = repo.read_recent_jsonl::<AuditEvent>(AUDIT_LOG, 5).unwrap();
        let memories = repo
            .read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, 5)
            .unwrap();
        assert_eq!(audits[0].id, audit.id);
        assert_eq!(memories[0].id, memory.id);

        let home = repo
            .build_home_snapshot(HomeQuery {
                active_project_slug: None,
                platform: Some("mcp".to_string()),
            })
            .unwrap();
        let trust = home.trust_context.unwrap();
        assert_eq!(trust.mcp_status, "audit-log-observed");
        assert_eq!(trust.tool_manifest_hash.as_deref(), Some("sha256:test"));
        assert!(home
            .memory_signals
            .iter()
            .any(|signal| signal.contains("audited")));
    }

    #[test]
    fn active_projects_are_reconstructed_from_append_only_events() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.create_memory_event(CreateMemoryEventRequest {
            source: Some("mcp".to_string()),
            kind: Some("agent_write".to_string()),
            content_ref: None,
            summary: Some("Next action for iPhone Home.".to_string()),
            tags: vec!["project:Beagle Apple Suite".to_string()],
            metadata: None,
            linked_chronoself_commits: Vec::new(),
            confidence: Some(0.7),
        })
        .unwrap();
        let projects = repo.active_projects().unwrap();
        assert_eq!(projects[0].id, "beagle-apple-suite");
        assert!(projects[0]
            .recent_events
            .iter()
            .any(|event| event.contains("iPhone")));
    }

    #[test]
    fn omnimemory_import_creates_projected_episode_and_atoms() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let imported = repo
            .import_conversation(ImportConversationRequest {
                source_platform: "Claude".to_string(),
                session_id: Some("visible-project-1".to_string()),
                original_date: Some("2026-04-26T16:00:00Z".to_string()),
                raw_content: "Decisão: Beagle Memory v1.2 deve priorizar GraphRAG++ persistente.\nHipótese: Episode+Atom melhora recuperação temporal.".to_string(),
                title: Some("GraphRAG++ decision".to_string()),
                tags: vec!["project:beagle".to_string()],
                extracted: None,
                confidence_score: Some(0.86),
                create_chronoself_commit: None,
                privacy_class: None,
                metadata: Some(serde_json::json!({"import_scope": "visible_project"})),
            })
            .unwrap();

        let episodes = repo
            .read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, 10)
            .unwrap();
        let atoms = repo
            .read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, 10)
            .unwrap();
        assert_eq!(episodes.len(), 1);
        assert_eq!(
            episodes[0].source_ref,
            format!("omnimemory:{}", imported.id)
        );
        assert!(atoms.iter().any(|atom| atom.atom_type == "decision"));
        assert!(atoms.iter().any(|atom| atom.atom_type == "hypothesis"));

        let duplicate_run = repo
            .project_memory(ProjectMemoryRequest {
                rebuild: false,
                source_refs: Vec::new(),
            })
            .unwrap();
        assert!(duplicate_run.duplicates >= 1);
        assert_eq!(
            repo.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, 10)
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn graphrag_query_returns_projected_evidence_with_provenance() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "Claude".to_string(),
            session_id: Some("session-graphrag".to_string()),
            original_date: Some("2026-04-26T16:00:00Z".to_string()),
            raw_content: "Decisão: GraphRAG++ persistente deve ser o núcleo do exocortex Beagle."
                .to_string(),
            title: Some("Persistent memory".to_string()),
            tags: vec!["project:beagle".to_string()],
            extracted: Some(OmniExtraction {
                decisions: vec![
                    "GraphRAG++ persistente deve ser o núcleo do exocortex Beagle.".to_string(),
                ],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.9),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: None,
        })
        .unwrap();

        let result = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "núcleo exocortex GraphRAG".to_string(),
                scope: None,
                max_items: Some(5),
                mode: None,
                ranking_policy: None,
            })
            .unwrap();
        assert!(!result.evidence.is_empty());
        assert!(result
            .evidence
            .iter()
            .any(|evidence| evidence.atom_type == "decision"
                && evidence
                    .text
                    .contains("GraphRAG++ persistente deve ser o núcleo")));
        assert!(result
            .relations
            .iter()
            .any(|relation| relation.subject == "beagle"));
        assert!(result.degraded_reason.is_some());
        assert_eq!(result.mode.as_deref(), Some("hypermemory_multivector"));
        assert!(result
            .evidence_graph
            .as_ref()
            .map(|graph| !graph.nodes.is_empty() && !graph.merkle_root.is_empty())
            .unwrap_or(false));
        assert!(!result.retrieval_trace.is_empty());
    }

    #[test]
    fn hypermemory_query_expands_tags_relations_and_marks_advisory_mode() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "Grok".to_string(),
            session_id: Some("grok-import-1".to_string()),
            original_date: Some("2026-04-26T19:00:00Z".to_string()),
            raw_content: "Decisão: Grok import mudou a prioridade para Memory Bench e HyperMemory."
                .to_string(),
            title: Some("Grok memory import".to_string()),
            tags: vec![
                "project:beagle".to_string(),
                "source:grok".to_string(),
                "hypermemory".to_string(),
            ],
            extracted: Some(OmniExtraction {
                decisions: vec![
                    "Grok import mudou a prioridade para Memory Bench e HyperMemory.".to_string(),
                ],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.88),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: Some(serde_json::json!({"source_surface": "claude-ios"})),
        })
        .unwrap();

        let result = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "grok priority benchmark".to_string(),
                scope: None,
                max_items: Some(5),
                mode: Some("hypermemory".to_string()),
                ranking_policy: None,
            })
            .unwrap();

        assert_eq!(result.mode.as_deref(), Some("hypermemory"));
        assert!(!result.evidence.is_empty());
        assert!(result
            .retrieval_trace
            .iter()
            .any(|step| step.stage == "hypermemory-topic-world-selection"));
        assert_eq!(
            result.provenance["hypermemory"]["authority"].as_str(),
            Some("derived-advisory")
        );
    }

    #[test]
    fn strict_recent_guarded_ranking_prioritizes_exact_recent_workbench_block() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.assisted_import_batch(AssistedImportBatchRequest {
            source_platform: "codex".to_string(),
            source_surface: "beagle-workbench".to_string(),
            import_scope: "workbench_terminal_block".to_string(),
            session_id: "beagle-v32-pty-smoke".to_string(),
            project_ref: Some("beagle".to_string()),
            batch_index: 1,
            batch_total: 1,
            turns: vec![AssistedImportTurn {
                role: "assistant".to_string(),
                content: "Decisão: v3.2 validou o modelo de Workbench, mas ainda não era o supervisor v3.3.".to_string(),
                timestamp: Some("2026-04-29T10:00:00Z".to_string()),
                model: Some("codex".to_string()),
            }],
            tags: vec!["workbench".to_string(), "terminal-block".to_string()],
            metadata: serde_json::json!({
                "terminal_block_id": "block-v32-old",
                "branch": "codex/beagle-mcp-public-claude",
                "commit": "v32old"
            }),
            coverage: serde_json::Value::Null,
            extracted: Some(OmniExtraction {
                decisions: vec!["v3.2 validou o modelo de Workbench.".to_string()],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            privacy_class: Some("sensitive".to_string()),
            title: Some("v3.2 workbench smoke".to_string()),
            original_date: Some("2026-04-29T10:00:00Z".to_string()),
            confidence_score: Some(0.82),
            create_chronoself_commit: Some(false),
            capture_session_id: None,
            artifact_refs: Vec::new(),
            transcription_segments: Vec::new(),
            visual_evidence_refs: Vec::new(),
        })
        .unwrap();
        repo.assisted_import_batch(AssistedImportBatchRequest {
            source_platform: "codex".to_string(),
            source_surface: "beagle-workbench".to_string(),
            import_scope: "workbench_terminal_block".to_string(),
            session_id: "wb-mom36qkm-f504bee5".to_string(),
            project_ref: Some("beagle".to_string()),
            batch_index: 1,
            batch_total: 1,
            turns: vec![AssistedImportTurn {
                role: "assistant".to_string(),
                content: "Decisão: beagle-v33-pty-smoke confirmou Durable PTY Supervisor com replay e memória curada.".to_string(),
                timestamp: Some("2026-04-30T20:30:00Z".to_string()),
                model: Some("codex".to_string()),
            }],
            tags: vec!["workbench".to_string(), "terminal-block".to_string(), "v3.3".to_string()],
            metadata: serde_json::json!({
                "terminal_block_id": "block-mom36qlp-697ee4e2",
                "branch": "codex/beagle-mcp-public-claude",
                "commit": "062be42",
                "memory_event_id": "92250283-0ec8-462a-802a-2d69d65b2ae2",
                "audit_event_id": "b0db505b-4600-4de2-8f54-d1312d7c015e"
            }),
            coverage: serde_json::Value::Null,
            extracted: Some(OmniExtraction {
                decisions: vec![
                    "beagle-v33-pty-smoke confirmou Durable PTY Supervisor com replay e memória curada."
                        .to_string(),
                ],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            privacy_class: Some("sensitive".to_string()),
            title: Some("v3.3 PTY smoke".to_string()),
            original_date: Some("2026-04-30T20:30:00Z".to_string()),
            confidence_score: Some(0.92),
            create_chronoself_commit: Some(false),
            capture_session_id: None,
            artifact_refs: Vec::new(),
            transcription_segments: Vec::new(),
            visual_evidence_refs: Vec::new(),
        })
        .unwrap();

        let response = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "beagle-v33-pty-smoke block-mom36qlp".to_string(),
                scope: None,
                max_items: Some(5),
                mode: Some("hypermemory_multivector".to_string()),
                ranking_policy: Some("strict_recent_guarded".to_string()),
            })
            .unwrap();
        assert_eq!(
            response.ranking_policy.as_deref(),
            Some("strict_recent_guarded")
        );
        assert!(response.recency_boost_applied);
        assert!(!response.stable_fact_guard_applied);
        assert_eq!(
            response
                .evidence
                .first()
                .and_then(|item| item.provenance["metadata"]["terminal_block_id"].as_str()),
            Some("block-mom36qlp-697ee4e2")
        );
    }

    #[test]
    fn stable_fact_guard_preserves_portfolio_identity_over_recent_work_memory() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "portfolio".to_string(),
            session_id: Some("portfolio_mandic_v3_2026-04-27".to_string()),
            original_date: Some("2026-04-27T12:00:00Z".to_string()),
            raw_content: "Portfólio institucional Mandic: Turma IX, RA 18224624, Grupo A."
                .to_string(),
            title: Some("Portfolio Mandic v3".to_string()),
            tags: vec![
                "portfolio_institucional".to_string(),
                "mandic".to_string(),
                "ra_18224624".to_string(),
                "documento_canonico".to_string(),
            ],
            extracted: Some(OmniExtraction {
                key_insights: vec!["Mandic Turma IX, RA 18224624, Grupo A.".to_string()],
                projects_mentioned: vec!["portfolio".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.97),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: Some(serde_json::json!({"source_surface": "portfolio-import"})),
        })
        .unwrap();
        repo.assisted_import_batch(AssistedImportBatchRequest {
            source_platform: "codex".to_string(),
            source_surface: "codex-work-memory".to_string(),
            import_scope: "agent_work_session".to_string(),
            session_id: "recent-ra-question".to_string(),
            project_ref: Some("beagle".to_string()),
            batch_index: 1,
            batch_total: 1,
            turns: vec![AssistedImportTurn {
                role: "assistant".to_string(),
                content: "Pergunta recente: qual é meu RA Mandic? verificar no portfólio antes de responder.".to_string(),
                timestamp: Some("2026-04-30T22:00:00Z".to_string()),
                model: Some("codex".to_string()),
            }],
            tags: vec!["work-memory".to_string(), "codex".to_string()],
            metadata: serde_json::json!({"branch": "codex/beagle-mcp-public-claude"}),
            coverage: serde_json::Value::Null,
            extracted: Some(OmniExtraction {
                unresolved_questions: vec!["qual é meu RA Mandic?".to_string()],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            privacy_class: Some("sensitive".to_string()),
            title: Some("Recent RA question".to_string()),
            original_date: Some("2026-04-30T22:00:00Z".to_string()),
            confidence_score: Some(0.75),
            create_chronoself_commit: Some(false),
            capture_session_id: None,
            artifact_refs: Vec::new(),
            transcription_segments: Vec::new(),
            visual_evidence_refs: Vec::new(),
        })
        .unwrap();

        let response = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "qual é meu RA Mandic?".to_string(),
                scope: None,
                max_items: Some(5),
                mode: Some("hypermemory_multivector".to_string()),
                ranking_policy: Some("strict_recent_guarded".to_string()),
            })
            .unwrap();
        assert!(response.stable_fact_guard_applied);
        assert_eq!(
            response
                .evidence
                .first()
                .and_then(|item| item.provenance["metadata"]["source_surface"].as_str()),
            Some("portfolio-import")
        );
    }

    #[test]
    fn graph_query_filters_restricted_local_only_atoms_from_active_evidence() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "beagle-apple".to_string(),
            session_id: Some("restricted-terminal-block".to_string()),
            original_date: Some("2026-04-30T21:00:00Z".to_string()),
            raw_content: "Decisão restrita: fake token output should never become active evidence."
                .to_string(),
            title: Some("Restricted local block".to_string()),
            tags: vec!["restricted_local_only".to_string(), "workbench".to_string()],
            extracted: Some(OmniExtraction {
                decisions: vec![
                    "fake token output should never become active evidence.".to_string()
                ],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.7),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: Some(serde_json::json!({"privacy_class": "restricted_local_only"})),
        })
        .unwrap();
        let response = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "fake token output active evidence".to_string(),
                scope: None,
                max_items: Some(5),
                mode: Some("hypermemory_multivector".to_string()),
                ranking_policy: Some("strict_recent_guarded".to_string()),
            })
            .unwrap();
        assert!(response.evidence.is_empty());
        assert_eq!(response.restricted_leak_check["restricted_leak_count"], 0);
    }

    #[test]
    fn memory_benchmark_status_reads_append_only_audit() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let empty = repo.memory_benchmark_status().unwrap();
        assert_eq!(empty.status, "empty");

        repo.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-memory-engine".to_string()),
            action: Some("memory.benchmark_run".to_string()),
            tool_name: Some("beagle_memory_benchmark_run".to_string()),
            risk_level: Some("run".to_string()),
            required_scopes: vec!["research:run".to_string()],
            granted_scopes: vec!["research:run".to_string()],
            status: Some("success".to_string()),
            source: Some("memory-engine".to_string()),
            target_ref: Some("memory_benchmark_run:bench-1".to_string()),
            summary: Some("Memory Bench v1.8 completed.".to_string()),
            metadata: Some(serde_json::json!({
                "schema_version": MEMORY_BENCH_SCHEMA,
                "run_id": "bench-1",
                "truthset_id": "truth-v19",
                "baseline_mode": "graphsearch-lite",
                "candidate_mode": "hypermemory",
                "baseline_score": 0.78,
                "hypermemory_score": 0.84,
                "required_margin": 0.05,
                "consecutive_passing_runs": 3,
                "latest_score": 0.84,
                "query_count": 100,
                "regression_count": 0,
                "artifact_manifest": "/orangefs/beagle-memory-lab/bench-1/manifest.json",
                "evaluated_modes": ["graphsearch-lite", "hypermemory", "adaptive-federation"]
            })),
        })
        .unwrap();

        let status = repo.memory_benchmark_status().unwrap();
        assert_eq!(status.status, "passing");
        assert_eq!(status.latest_run_id.as_deref(), Some("bench-1"));
        assert_eq!(status.query_count, 100);
        assert_eq!(status.latest_score, Some(0.84));
        assert_eq!(status.truthset_id.as_deref(), Some("truth-v19"));
        assert!(status.hot_path_eligible);
        assert!(status
            .promotion_gate
            .as_ref()
            .map(|gate| gate.eligible)
            .unwrap_or(false));
        let home = repo
            .build_home_snapshot(HomeQuery {
                active_project_slug: None,
                platform: Some("apple".to_string()),
            })
            .unwrap();
        let trust = home.trust_context.unwrap();
        assert_eq!(trust.memory_bench_status.as_deref(), Some("passing"));
        assert_eq!(trust.latest_bench_score, Some(0.84));
        assert_eq!(trust.truthset_id.as_deref(), Some("truth-v19"));
        assert_eq!(trust.bench_hot_path_eligible, Some(true));
    }

    #[test]
    fn memory_truthset_lifecycle_rejects_restricted_cases() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let truthset = repo
            .create_memory_truthset(CreateMemoryTruthSetRequest {
                title: Some("Private v1.9 truthset".to_string()),
                description: Some("Agent-curated cases from real Beagle memory.".to_string()),
                domains: vec!["work-memory".to_string(), "grok-import".to_string()],
                source_refs: vec!["memory_export:dry-run".to_string()],
                reviewer: Some("demetrios".to_string()),
                artifact_root: None,
            })
            .unwrap();

        let case = repo
            .create_memory_truth_case(
                &truthset.id,
                CreateMemoryTruthCaseRequest {
                    domain: "work-memory".to_string(),
                    query: "qual foi a última decisão do Codex?".to_string(),
                    expected_answer: Some("Recuperar sessão, branch e commit.".to_string()),
                    required_evidence_refs: vec!["agent-session:codex".to_string()],
                    expected_atom_refs: vec![],
                    expected_episode_refs: vec![],
                    temporal_expectation: Some("priorizar evento mais recente".to_string()),
                    provenance_requirements: vec!["repo".to_string(), "branch".to_string()],
                    privacy_class: Some("sensitive".to_string()),
                    status: Some("approved".to_string()),
                    tags: vec!["codex".to_string(), "truthset:v1.9".to_string()],
                    metadata: Some(serde_json::json!({"cluster_only": true})),
                },
            )
            .unwrap();
        assert_eq!(case.truthset_id, truthset.id);

        let restricted = repo.create_memory_truth_case(
            &truthset.id,
            CreateMemoryTruthCaseRequest {
                domain: "security".to_string(),
                query: "restricted content must never enter bench".to_string(),
                expected_answer: None,
                required_evidence_refs: vec![],
                expected_atom_refs: vec![],
                expected_episode_refs: vec![],
                temporal_expectation: None,
                provenance_requirements: vec![],
                privacy_class: Some("restricted".to_string()),
                status: None,
                tags: vec![],
                metadata: None,
            },
        );
        assert!(restricted.is_err());

        let reviewed = repo
            .review_memory_truthset(
                &truthset.id,
                ReviewMemoryTruthSetRequest {
                    status: Some("approved".to_string()),
                    reviewer: Some("demetrios".to_string()),
                    rationale: Some("caso sensível aprovado para bench privado".to_string()),
                },
            )
            .unwrap();
        assert_eq!(reviewed.truthset.status, "approved");
        assert_eq!(reviewed.truthset.case_count, 1);
        assert_eq!(reviewed.truthset.approved_case_count, 1);
        assert_eq!(reviewed.cases.len(), 1);
    }

    #[test]
    fn memory_graph_recent_returns_projection_for_apple_memory_lens() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "beagle-apple".to_string(),
            session_id: Some("apple-chat-1".to_string()),
            original_date: Some("2026-04-26T17:00:00Z".to_string()),
            raw_content: "Decisão: Home, Watch e Memory Lens devem avançar em paralelo."
                .to_string(),
            title: Some("Apple Exocortex v1.3".to_string()),
            tags: vec![
                "project:beagle".to_string(),
                "surface:beagle-ios".to_string(),
            ],
            extracted: Some(OmniExtraction {
                decisions: vec!["Home, Watch e Memory Lens devem avançar em paralelo.".to_string()],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.91),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: Some(serde_json::json!({"source_surface": "beagle-ios"})),
        })
        .unwrap();

        let recent = repo.memory_graph_recent(10).unwrap();
        assert_eq!(recent.status.episode_count, 1);
        assert!(!recent.episodes.is_empty());
        assert!(recent
            .atoms
            .iter()
            .any(|atom| atom.text.contains("Memory Lens")));
        assert_eq!(
            recent.provenance["canonical_store"],
            "/var/lib/beagle/exocortex"
        );
    }

    #[test]
    fn graph_runtime_bakeoff_and_index_create_worlds_without_private_sidecars() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "codex".to_string(),
            session_id: Some("work-memory-1".to_string()),
            original_date: Some("2026-04-26T18:00:00Z".to_string()),
            raw_content: "Decisão: FalkorDB GraphBLAS deve ser testado contra Memgraph e SurrealDB antes de promoção.".to_string(),
            title: Some("Graph runtime bakeoff".to_string()),
            tags: vec!["project:beagle".to_string(), "work-memory".to_string()],
            extracted: Some(OmniExtraction {
                decisions: vec![
                    "FalkorDB GraphBLAS deve ser testado contra Memgraph e SurrealDB antes de promoção.".to_string(),
                ],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.9),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: Some(serde_json::json!({"source_surface": "codex-work-memory"})),
        })
        .unwrap();

        let bakeoff = repo
            .run_graph_bakeoff(GraphBakeoffRequest {
                dataset_limit: Some(20),
                include_baseline: Some(true),
            })
            .unwrap();
        assert_eq!(bakeoff.schema_version, MEMORY_GRAPH_SCHEMA);
        assert!(bakeoff
            .candidates
            .iter()
            .any(|candidate| candidate.name == "FalkorDB GraphBLAS"));

        let index = repo
            .index_graph(GraphIndexRequest {
                rebuild: false,
                source_refs: Vec::new(),
                runtime: None,
            })
            .unwrap();
        assert!(index.worlds_created >= 1);
        assert_eq!(
            index.provenance["canonical_store"],
            "/var/lib/beagle/exocortex"
        );

        let worlds = repo.memory_worlds_recent(10).unwrap();
        assert_eq!(worlds.graph_status.schema_version, MEMORY_GRAPH_SCHEMA);
        assert!(worlds
            .worlds
            .iter()
            .any(|world| world.provenance["content_addressed"] == true));
    }

    #[test]
    fn spatial_world_registers_private_marble_control_room_and_evidence() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let mut spz_urls = BTreeMap::new();
        spz_urls.insert(
            "low_res".to_string(),
            "https://assets.example/sounio.spz".to_string(),
        );
        let world = repo
            .create_spatial_world(CreateSpatialWorldRequest {
                project_slug: Some("sounio".to_string()),
                display_name: Some("Sounio Control Room".to_string()),
                prompt_summary: Some(
                    "Sanitized Sounio control room with pods wall, agent lanes, compiler map, and evidence panels."
                        .to_string(),
                ),
                sanitized_prompt: Some(
                    "Sanitized Sounio control room with pods wall, agent lanes, compiler map, and evidence panels."
                        .to_string(),
                ),
                model: Some("marble-1.1".to_string()),
                permission: None,
                approved: Some(true),
                purpose: Some("control-room".to_string()),
                operation_id: Some("op-test".to_string()),
                world_id: Some("world-sounio-test".to_string()),
                status: Some("ready".to_string()),
                world_marble_url: Some(
                    "https://marble.worldlabs.ai/worlds/world-sounio-test".to_string(),
                ),
                assets: Some(SpatialAssetManifest {
                    pano_url: Some("https://assets.example/sounio-pano.png".to_string()),
                    collider_mesh_url: Some(
                        "https://assets.example/sounio-collider.glb".to_string(),
                    ),
                    hq_mesh_urls: Vec::new(),
                    spz_urls,
                    ply_urls: BTreeMap::new(),
                    coordinate_system: Some("opencv:+x-left,+y-down,+z-forward".to_string()),
                    coordinate_transform: Some("opencv_to_opengl:scale_yz_minus_one".to_string()),
                    asset_root: Some("/orangefs/beagle-spatial-worlds/world-sounio-test".to_string()),
                    degraded_reason: None,
                }),
                tags: vec!["sounio".to_string()],
                provenance: serde_json::json!({"world_console": "mock"}),
            })
            .unwrap();
        assert_eq!(world.permission, "private");
        assert_eq!(world.model, "marble-1.1");
        assert!(world.assets.spz_urls.contains_key("low_res"));

        let snapshot = repo.control_room_snapshot("sounio").unwrap();
        assert_eq!(snapshot.project_slug, "sounio");
        assert_eq!(
            snapshot.spatial_world.as_ref().unwrap().world_id,
            "world-sounio-test"
        );
        assert!(snapshot
            .memory_worlds
            .iter()
            .any(|memory_world| { memory_world.source_ref == "spatial_world:world-sounio-test" }));

        let evidence = repo
            .create_spatial_evidence(
                "world-sounio-test",
                CreateSounioSpatialEvidenceRequest {
                    project_slug: "sounio".to_string(),
                    evidence_type: Some("spatial_memory_world".to_string()),
                    claim_seed_refs: vec!["claim-seed:sounio-control-room".to_string()],
                    memory_world_refs: snapshot
                        .memory_worlds
                        .iter()
                        .map(|world| world.id.clone())
                        .collect(),
                    artifact_refs: vec!["spatial_world:world-sounio-test".to_string()],
                    epistemic_status: Some("belief".to_string()),
                    privacy_class: Some("sensitive".to_string()),
                    provenance: serde_json::json!({"reviewed": true}),
                },
            )
            .unwrap();
        assert_eq!(evidence.epistemic_status, "belief");
        assert_eq!(evidence.privacy_class, "sensitive");

        let public_world = repo.create_spatial_world(CreateSpatialWorldRequest {
            project_slug: Some("sounio".to_string()),
            display_name: None,
            prompt_summary: Some("safe".to_string()),
            sanitized_prompt: Some("safe".to_string()),
            model: None,
            permission: Some("public".to_string()),
            approved: Some(true),
            purpose: None,
            operation_id: None,
            world_id: None,
            status: None,
            world_marble_url: None,
            assets: None,
            tags: Vec::new(),
            provenance: serde_json::Value::Null,
        });
        assert!(public_world.is_err());
    }

    #[test]
    fn mind_palace_derives_rooms_portals_and_focus_coach() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.create_memory_event(CreateMemoryEventRequest {
            source: Some("codex-work-memory".to_string()),
            kind: Some("assisted_import_batch".to_string()),
            content_ref: Some("omnimemory:test".to_string()),
            summary: Some("Codex remembered the latest Beagle Spatial Desk decision.".to_string()),
            tags: vec![
                "project:beagle".to_string(),
                "agent:codex".to_string(),
                "workbench".to_string(),
            ],
            metadata: Some(serde_json::json!({
                "privacy_class": "sensitive",
                "source_surface": "codex-work-memory"
            })),
            linked_chronoself_commits: Vec::new(),
            confidence: Some(0.88),
        })
        .unwrap();
        let portal = repo
            .create_conversation_portal(CreateConversationPortalRequest {
                title: "Claude Desktop idea thread".to_string(),
                provider: "Claude Desktop".to_string(),
                surface: Some("desktop-portal".to_string()),
                status: None,
                source_mode: None,
                privacy_class: Some("sensitive".to_string()),
                source_ref: Some("external-window:claude".to_string()),
                tags: vec!["project:beagle".to_string()],
                provenance: serde_json::json!({"operator": "demetrios"}),
            })
            .unwrap();
        let clip = repo
            .promote_conversation_portal_clip(
                &portal.id,
                PromoteConversationPortalRequest {
                    selected_text: "Insight: Beagle needs a Spatial Desk where agent work and free conversations can happen in parallel.".to_string(),
                    summary: Some("Spatial Desk parallel exocortex insight.".to_string()),
                    project_ref: Some("beagle".to_string()),
                    privacy_class: Some("sensitive".to_string()),
                    tags: vec!["spatial-desk".to_string()],
                    provenance: serde_json::json!({"selected_by": "human"}),
                },
            )
            .unwrap();
        assert!(clip.memory_event_id.is_some());
        assert!(clip.sounio_moment_id.is_some());

        let state = repo
            .record_focus_coach_event(FocusCoachEventRequest {
                event_kind: "start_focus".to_string(),
                status: Some("active".to_string()),
                intervention_id: None,
                project_slug: Some("beagle".to_string()),
                notes: Some("Implementation focus block.".to_string()),
                snoozed_minutes: None,
                provenance: serde_json::Value::Null,
            })
            .unwrap();
        assert_eq!(state.schema_version, FOCUS_COACH_SCHEMA);
        assert!(state.can_override);

        let palace = repo.mind_palace_snapshot().unwrap();
        assert_eq!(palace.schema_version, MIND_PALACE_SCHEMA);
        assert!(palace.rooms.iter().any(|room| room.id == "parallel-work"));
        assert!(palace
            .rooms
            .iter()
            .any(|room| room.id == "conversation-portals"));
        assert!(palace
            .desk
            .active_items
            .iter()
            .any(|item| item.kind == "conversation_portal"));
        assert!(palace
            .action_menu
            .actions
            .iter()
            .any(|action| action.id == "open-workbench"));

        let restricted = repo.promote_conversation_portal_clip(
            &portal.id,
            PromoteConversationPortalRequest {
                selected_text: "restricted: do not import".to_string(),
                summary: None,
                project_ref: None,
                privacy_class: Some("sensitive".to_string()),
                tags: Vec::new(),
                provenance: serde_json::Value::Null,
            },
        );
        assert!(restricted.is_err());
    }

    #[test]
    fn restricted_import_is_not_projected() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "manual".to_string(),
            session_id: Some("restricted-session".to_string()),
            original_date: None,
            raw_content: "Decisão: este payload restrito não deve virar átomo.".to_string(),
            title: Some("Restricted pilot".to_string()),
            tags: vec!["project:beagle".to_string()],
            extracted: None,
            confidence_score: Some(0.8),
            create_chronoself_commit: None,
            privacy_class: Some("restricted".to_string()),
            metadata: None,
        })
        .unwrap();

        let status = repo.memory_projection_status().unwrap();
        assert_eq!(status.episode_count, 0);
        assert_eq!(status.atom_count, 0);
    }

    #[test]
    fn assisted_import_batch_creates_omnimemory_projection_memory_and_audit() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let result = repo
            .assisted_import_batch(AssistedImportBatchRequest {
                source_platform: "Claude".to_string(),
                source_surface: "claude-ios".to_string(),
                import_scope: "current_conversation".to_string(),
                session_id: "claude-ios-visible-1".to_string(),
                project_ref: Some("beagle".to_string()),
                batch_index: 1,
                batch_total: 1,
                turns: vec![
                    AssistedImportTurn {
                        role: "user".to_string(),
                        content: "Decisão: Beagle deve usar GraphRAG++ persistente como núcleo."
                            .to_string(),
                        timestamp: Some("2026-04-26T16:30:00Z".to_string()),
                        model: None,
                    },
                    AssistedImportTurn {
                        role: "assistant".to_string(),
                        content:
                            "Hipótese: Claude iOS deve importar contexto visível via MCP para Episode+Atom."
                                .to_string(),
                        timestamp: Some("2026-04-26T16:31:00Z".to_string()),
                        model: Some("claude-sonnet-4".to_string()),
                    },
                ],
                tags: vec!["surface:claude-ios".to_string()],
                metadata: serde_json::json!({
                    "principal": "claude-connector",
                    "surface_observed": "anthropic-cloud",
                    "scopes": ["exocortex:read", "memory:write"],
                    "tool_manifest_hash": "sha256:test"
                }),
                coverage: serde_json::json!({"visible_turns": 2}),
                extracted: Some(OmniExtraction {
                    decisions: vec![
                        "Beagle deve usar GraphRAG++ persistente como núcleo.".to_string(),
                    ],
                    hypotheses: vec![
                        "Claude iOS deve importar contexto visível via MCP para Episode+Atom."
                            .to_string(),
                    ],
                    projects_mentioned: vec!["beagle".to_string()],
                    ..Default::default()
                }),
                privacy_class: Some("sensitive".to_string()),
                title: Some("Claude iOS visible context".to_string()),
                original_date: None,
                confidence_score: Some(0.88),
                create_chronoself_commit: Some(false),
                capture_session_id: None,
                artifact_refs: Vec::new(),
                transcription_segments: Vec::new(),
                visual_evidence_refs: Vec::new(),
            })
            .unwrap();

        assert_eq!(result.status, "imported");
        assert_eq!(result.source_platform, "claude");
        assert_eq!(result.source_surface, "claude-ios");
        assert_eq!(result.privacy_class, "sensitive");
        assert!(result.omnimemory.is_some());
        assert!(result.projection.as_ref().unwrap().atoms_created >= 2);
        assert_eq!(
            result.memory_event.as_ref().unwrap().kind,
            "assisted_import_batch"
        );
        assert_eq!(result.audit_event.as_ref().unwrap().status, "success");

        let status = repo.memory_projection_status().unwrap();
        assert_eq!(status.episode_count, 1);
        assert!(status.atom_count >= 2);
        let query = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "GraphRAG núcleo Claude iOS".to_string(),
                scope: None,
                max_items: Some(5),
                mode: None,
                ranking_policy: None,
            })
            .unwrap();
        assert!(!query.evidence.is_empty());
        assert!(query
            .evidence
            .iter()
            .any(|item| item.provenance["metadata"]["source_surface"] == "claude-ios"));
    }

    #[test]
    fn assisted_import_rejects_restricted_payload_before_omnimemory_write() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let result = repo
            .assisted_import_batch(AssistedImportBatchRequest {
                source_platform: "ChatGPT".to_string(),
                source_surface: "chatgpt-web".to_string(),
                import_scope: "current_conversation".to_string(),
                session_id: "restricted-visible-1".to_string(),
                project_ref: None,
                batch_index: 1,
                batch_total: 1,
                turns: vec![AssistedImportTurn {
                    role: "user".to_string(),
                    content: "Restricted payload".to_string(),
                    timestamp: None,
                    model: None,
                }],
                tags: Vec::new(),
                metadata: serde_json::json!({"principal": "chatgpt-connector"}),
                coverage: serde_json::Value::Null,
                extracted: None,
                privacy_class: Some("restricted".to_string()),
                title: None,
                original_date: None,
                confidence_score: None,
                create_chronoself_commit: None,
                capture_session_id: None,
                artifact_refs: Vec::new(),
                transcription_segments: Vec::new(),
                visual_evidence_refs: Vec::new(),
            })
            .unwrap();

        assert_eq!(result.status, "rejected");
        assert!(result.omnimemory.is_none());
        assert_eq!(result.audit_event.as_ref().unwrap().status, "rejected");
        assert_eq!(
            repo.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 10)
                .unwrap()
                .len(),
            0
        );
        assert_eq!(
            repo.read_recent_jsonl::<AuditEvent>(AUDIT_LOG, 10)
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn memory_export_candidates_quorum_and_query_mesh_are_append_only() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let imported = repo
            .assisted_import_batch(AssistedImportBatchRequest {
                source_platform: "codex".to_string(),
                source_surface: "codex-local".to_string(),
                import_scope: "work_memory".to_string(),
                session_id: "codex-v15".to_string(),
                project_ref: Some("beagle".to_string()),
                batch_index: 1,
                batch_total: 1,
                turns: vec![AssistedImportTurn {
                    role: "assistant".to_string(),
                    content:
                        "Decisão: v1.5 usa beagle-memory-engine federado sem mover a verdade canônica."
                            .to_string(),
                    timestamp: Some("2026-04-27T02:00:00Z".to_string()),
                    model: Some("codex".to_string()),
                }],
                tags: vec!["project:beagle".to_string(), "work-memory".to_string()],
                metadata: serde_json::json!({"principal": "codex", "branch": "codex/beagle-mcp-public-claude"}),
                coverage: serde_json::Value::Null,
                extracted: Some(OmniExtraction {
                    decisions: vec![
                        "v1.5 usa beagle-memory-engine federado sem mover a verdade canônica."
                            .to_string(),
                    ],
                    projects_mentioned: vec!["beagle".to_string()],
                    ..Default::default()
                }),
                privacy_class: Some("sensitive".to_string()),
                title: Some("Codex v1.5 work memory".to_string()),
                original_date: None,
                confidence_score: Some(0.93),
                create_chronoself_commit: Some(false),
                capture_session_id: None,
                artifact_refs: Vec::new(),
                transcription_segments: Vec::new(),
                visual_evidence_refs: Vec::new(),
            })
            .unwrap();
        assert_eq!(imported.status, "imported");

        let candidate = repo
            .create_memory_candidate(CreateMemoryCandidateRequest {
                candidate_type: "hyperedge".to_string(),
                text: "Federated memory engine candidates require Triad quorum before active retrieval."
                    .to_string(),
                source_refs: vec!["memory-engine:bakeoff-shadow".to_string()],
                relations: vec![MemoryRelation {
                    subject: "candidate".to_string(),
                    predicate: "requires".to_string(),
                    object: "triad-quorum".to_string(),
                    confidence: 0.91,
                }],
                tags: vec!["candidate".to_string(), "v1.5".to_string()],
                provenance: serde_json::json!({"runtime": "beagle-memory-engine"}),
                confidence: Some(0.84),
                privacy_class: Some("sensitive".to_string()),
            })
            .unwrap();
        let quorum = repo
            .record_candidate_quorum(
                &candidate.id,
                CandidateQuorumRequest {
                    memory_approved: true,
                    temporal_approved: true,
                    critical_approved: true,
                    rationale: Some(
                        "All three Triad voices accept promotion eligibility.".to_string(),
                    ),
                    reviewer: Some("test".to_string()),
                    quality_score: None,
                },
            )
            .unwrap();
        assert_eq!(quorum.status, "triad_pending");

        let export = repo
            .export_sanitized_memory(MemoryExportRequest {
                limit: Some(100),
                include_worlds: true,
                include_candidates: true,
                purpose: Some("memory-engine-test".to_string()),
            })
            .unwrap();
        assert!(export.privacy_policy.contains("restricted"));
        assert_eq!(export.candidates.len(), 1);
        assert!(export
            .synthetic_golden_queries
            .iter()
            .any(|query| query.domain == "work-memory"));

        let query = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "federated memory engine canonical truth".to_string(),
                scope: None,
                max_items: Some(5),
                mode: Some("adaptive-federation".to_string()),
                ranking_policy: None,
            })
            .unwrap();
        assert!(!query.mesh_trace.is_empty());
        assert!(!query.runtime_votes.is_empty());
        assert!(query.candidate_refs.contains(&candidate.id));

        let governance_before = repo.memory_governance_status().unwrap();
        assert_eq!(governance_before.pending_triads, 1);
        assert_eq!(governance_before.promoted_count, 0);

        let governance_run = repo
            .run_memory_governance(MemoryGovernanceRunRequest {
                limit: Some(20),
                reviewer: Some("test-governor".to_string()),
                dry_run: Some(false),
            })
            .unwrap();
        assert_eq!(governance_run.status, "completed");
        assert_eq!(governance_run.triad_pending, 1);
        assert_eq!(governance_run.quality_scores_written, 1);

        let promotion = repo
            .promote_memory_candidate(
                &candidate.id,
                CandidatePromoteRequest {
                    rationale: Some(
                        "Strict Triad 3/3 accepted the candidate for active memory.".to_string(),
                    ),
                    chronoself_commit_id: Some("chrono-test".to_string()),
                },
            )
            .unwrap();
        assert_eq!(promotion.candidate.status, "promoted");
        assert_eq!(promotion.promotion_decision.decision, "promoted");

        let governance_after = repo.memory_governance_status().unwrap();
        assert_eq!(governance_after.promoted_count, 1);
        assert_eq!(governance_after.pending_triads, 0);
        assert_eq!(
            governance_after
                .latest_promotion_decision
                .as_ref()
                .unwrap()
                .status,
            "promoted"
        );
    }

    #[test]
    fn sounio_program_check_requires_governance_and_blocks_restricted() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let mut program = default_beagle_self_writing_program();
        program.governance.privacy_class = "restricted".to_string();
        program.governance.provenance = serde_json::Value::Null;
        program.plan[0].provenance = serde_json::Value::Null;

        let checked = repo
            .check_sounio_program(SounioProgramCheckRequest {
                source_format: Some("json".to_string()),
                program,
            })
            .unwrap();

        assert_eq!(checked.status, "invalid");
        assert!(checked
            .errors
            .iter()
            .any(|error| error.contains("privacy_class=restricted")));
        assert!(checked
            .errors
            .iter()
            .any(|error| error.contains("governance.provenance")));
        assert!(checked
            .errors
            .iter()
            .any(|error| error.contains("retrieve_state provenance")));
        assert_eq!(checked.schema_version, SOUNIO_WORK_IR_SCHEMA);
    }

    #[test]
    fn sounio_paperrun_creates_trace_artifacts_and_home_trust_signal() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));

        let run = repo
            .start_paper_run(StartPaperRunRequest {
                paper_id: None,
                title: None,
                program: None,
                principal: Some("codex-test".to_string()),
                surface: Some("unit-test".to_string()),
                temporal_namespace: None,
                temporal_task_queue: None,
                dry_run: Some(true),
            })
            .unwrap();

        assert_eq!(run.status, "human_approval_pending");
        assert_eq!(run.temporal_status, "dry_run_not_started");
        assert_eq!(run.pending_approval_step.as_deref(), Some("human_approval"));
        assert!(run.sounio_program_hash.starts_with("sha256:"));
        assert!(run
            .artifact_refs
            .iter()
            .all(|artifact| artifact.starts_with("/orangefs/beagle-memory-lab/paperruns/")));

        let artifacts = repo.paper_run_artifacts(&run.id).unwrap().unwrap();
        assert!(artifacts
            .manuscript_markdown
            .contains("Self-Governing Exocortex"));
        assert_eq!(artifacts.paper_run_id, run.id);

        let approved = repo
            .approve_paper_run_step(
                &run.id,
                ApprovePaperRunStepRequest {
                    step_id: "human_approval".to_string(),
                    decision: Some("approved".to_string()),
                    reviewer: Some("demetrios".to_string()),
                    rationale: Some("Approved for durable PaperRun smoke.".to_string()),
                },
            )
            .unwrap();
        assert_eq!(approved.status, "approved_for_temporal_execution");
        assert_eq!(approved.temporal_status, "signal_approved");

        let traces = repo
            .sounio_trace_events(SounioTraceQuery {
                paper_run_id: Some(run.id.clone()),
                limit: Some(10),
            })
            .unwrap();
        assert_eq!(traces.len(), 2);
        assert!(traces
            .iter()
            .any(|event| event.event_type == "workflow_start_requested"));
        assert!(traces
            .iter()
            .any(|event| event.event_type == "human_approval"));

        let home = repo
            .build_home_snapshot(HomeQuery {
                active_project_slug: None,
                platform: Some("unit-test".to_string()),
            })
            .unwrap();
        let trust = home.trust_context.unwrap();
        assert_eq!(
            trust.sounio_paperrun_status.as_deref(),
            Some("beagle-self-writing-systems-paper:approved_for_temporal_execution")
        );
        assert!(trust
            .sounio_temporal_status
            .as_deref()
            .is_some_and(|status| status.ends_with(":signal_approved")));
        assert!(trust.sounio_latest_artifact.is_some());
    }

    #[test]
    fn sounio_claim_lifecycle_enforces_epistemic_gates_and_digest_sanitization() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let run = repo
            .start_paper_run(StartPaperRunRequest {
                paper_id: None,
                title: None,
                principal: Some("codex-test".to_string()),
                surface: Some("unit-test".to_string()),
                temporal_namespace: None,
                temporal_task_queue: None,
                program: None,
                dry_run: Some(true),
            })
            .unwrap();

        let checked = repo
            .check_sounio_claim(SounioClaimCheckRequest {
                claim: SounioClaimInput {
                    id: Some("claim-no-evidence".to_string()),
                    claim_text: "A claim cannot become Knowledge<T> without evidence.".to_string(),
                    subject: Some("sounio_claim_gate".to_string()),
                    value_type: None,
                    epistemic_status: Some("knowledge".to_string()),
                    evidence_refs: Vec::new(),
                    provenance: serde_json::Value::Null,
                    confidence: Some(0.9),
                    contestation: serde_json::json!({}),
                    review_state: None,
                    promotion_rule: None,
                    publication_readiness: None,
                    section_id: Some("Sounio IR".to_string()),
                    agent_refs: Vec::new(),
                    contract_refs: Vec::new(),
                    artifact_refs: Vec::new(),
                    chronoself_commit_refs: Vec::new(),
                    privacy_class: Some("sensitive".to_string()),
                    rationale: None,
                },
            })
            .unwrap();
        assert_eq!(checked.status, "valid");
        assert_eq!(checked.normalized_claim.epistemic_status, "belief");
        assert!(checked
            .warnings
            .iter()
            .any(|warning| warning.contains("Knowledge<T> requires")));

        let claim = repo
            .add_paper_run_claim(
                &run.id,
                AddPaperRunClaimRequest {
                    principal: Some("codex-test".to_string()),
                    surface: Some("unit-test".to_string()),
                    claim: SounioClaimInput {
                        id: Some("claim-sedenion-ssm-arc".to_string()),
                        claim_text: "Sedenion SSM is the first strong Sounio demonstration.".to_string(),
                        subject: Some("sedenion_ssm_arc".to_string()),
                        value_type: Some("Claim<T>".to_string()),
                        epistemic_status: Some("contest".to_string()),
                        evidence_refs: vec![
                            "artifact:sedenion_ssm_arc".to_string(),
                            "theorem_refs:sedenion_ssm".to_string(),
                        ],
                        provenance: serde_json::json!({
                            "source": "unit-test",
                            "human_review": true
                        }),
                        confidence: Some(0.8),
                        contestation: serde_json::json!({}),
                        review_state: None,
                        promotion_rule: None,
                        publication_readiness: None,
                        section_id: Some("Sounio IR".to_string()),
                        agent_refs: vec!["codex-test".to_string()],
                        contract_refs: Vec::new(),
                        artifact_refs: vec![
                            "/orangefs/beagle-memory-lab/paperruns/test/sedenion_ssm_public_case.json"
                                .to_string(),
                        ],
                        chronoself_commit_refs: Vec::new(),
                        privacy_class: Some("sensitive".to_string()),
                        rationale: None,
                    },
                },
            )
            .unwrap();
        assert_eq!(claim.epistemic_status, "contest");

        let reviewed = repo
            .review_sounio_claim(
                &run.id,
                &claim.id,
                ReviewSounioClaimRequest {
                    reviewer: Some("demetrios".to_string()),
                    decision: "promote_to_knowledge".to_string(),
                    rationale: Some("Evidence and provenance are present.".to_string()),
                    evidence_refs: Vec::new(),
                    epistemic_status: None,
                    publication_readiness: None,
                    provenance: serde_json::json!({"human_review": true}),
                },
            )
            .unwrap();
        assert_eq!(reviewed.epistemic_status, "knowledge");
        assert_eq!(
            reviewed.publication_readiness,
            "section_ready_with_provenance"
        );

        let theatre = repo.paper_run_theatre(&run.id).unwrap().unwrap();
        assert_eq!(theatre.claim_graph.status_counts.get("knowledge"), Some(&1));
        assert!(theatre.next_action.contains("human_approval"));

        let digest = repo.paper_run_public_digest(&run.id).unwrap().unwrap();
        assert_eq!(digest.schema_version, SOUNIO_PUBLIC_DIGEST_SCHEMA);
        assert!(digest
            .sedenion_ssm_case
            .to_string()
            .contains("sedenion-ssm-arc"));
        assert!(!digest
            .public_trace_digest
            .iter()
            .any(|entry| entry.to_string().contains("restricted")));
    }
}
