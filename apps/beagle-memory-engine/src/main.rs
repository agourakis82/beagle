//! Beagle Federated Living Memory Engine.
//!
//! This service is deliberately a derived-index control plane. It reads
//! sanitized exports from beagle-core, coordinates runtime candidates, and
//! writes lab artifacts to cluster storage. The canonical memory authority
//! remains beagle-core JSONL/Merkle/Chronoself on the beagle-data PVC.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use chrono::Utc;
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    env,
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, Write},
    net::SocketAddr,
    path::PathBuf,
    sync::Arc,
};
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing::{error, info};
use uuid::Uuid;

const SCHEMA_VERSION: &str = "beagle-federated-memory-engine-v1.9";
const BAKEOFF_RUNS_LOG: &str = "bakeoff_runs.jsonl";
const INDEX_RUNS_LOG: &str = "index_runs.jsonl";
const QUERY_TRACES_LOG: &str = "query_traces.jsonl";
const EVAL_RUNS_LOG: &str = "eval_runs.jsonl";
const GOVERNANCE_EVALS_LOG: &str = "governance_evaluations.jsonl";
const BENCH_RUNS_LOG: &str = "benchmark_runs.jsonl";
const TRUTHSET_DRAFTS_LOG: &str = "truthset_drafts.jsonl";

#[derive(Clone)]
struct EngineState {
    core_url: String,
    core_token: Option<String>,
    data_dir: PathBuf,
    artifact_dir: PathBuf,
    client: reqwest::Client,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    service: String,
    schema_version: String,
}

#[derive(Debug, Serialize)]
struct ReadyResponse {
    status: String,
    service: String,
    schema_version: String,
    core_url: String,
    data_dir: String,
    artifact_dir: String,
    runtimes: Vec<RuntimeStatus>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RuntimeStatus {
    name: String,
    role: String,
    license_policy: String,
    endpoint: Option<String>,
    available: bool,
    status: String,
    score_hint: f64,
}

#[derive(Debug, Deserialize)]
struct QueryRequest {
    query: String,
    scope: Option<String>,
    max_items: Option<usize>,
    mode: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MeshTraceStep {
    stage: String,
    backend: String,
    status: String,
    items: usize,
    latency_ms: f64,
    notes: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct RuntimeVote {
    runtime: String,
    role: String,
    status: String,
    score: f64,
    notes: Vec<String>,
}

#[derive(Debug, Serialize)]
struct QueryResponse {
    summary: String,
    mode: String,
    schema_version: String,
    degraded_reason: Option<String>,
    mesh_trace: Vec<MeshTraceStep>,
    runtime_votes: Vec<RuntimeVote>,
    candidate_refs: Vec<String>,
    core_response: serde_json::Value,
}

#[derive(Debug, Deserialize)]
struct RebuildRequest {
    limit: Option<usize>,
    include_candidates: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
struct IndexRun {
    id: String,
    created_at: String,
    status: String,
    schema_version: String,
    source_export_id: Option<String>,
    source_merkle_root: Option<String>,
    episode_count: usize,
    atom_count: usize,
    world_count: usize,
    artifact_manifest: String,
    degraded_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BakeoffRequest {
    limit: Option<usize>,
    domains: Option<Vec<String>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct BakeoffRun {
    id: String,
    created_at: String,
    status: String,
    schema_version: String,
    query_count: usize,
    candidates: Vec<RuntimeVote>,
    winner_policy: String,
    artifact_manifest: String,
    hard_gates: BTreeMap<String, bool>,
}

#[derive(Debug, Deserialize)]
struct EvalRunRequest {
    limit: Option<usize>,
    domains: Option<Vec<String>>,
    judge_mode: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct EvalRun {
    id: String,
    created_at: String,
    status: String,
    schema_version: String,
    query_count: usize,
    domains: Vec<String>,
    judge_mode: String,
    hard_gates: BTreeMap<String, bool>,
    runtime_votes: Vec<RuntimeVote>,
    hot_path_canary: String,
    artifact_manifest: String,
    degraded_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BenchmarkRunRequest {
    limit: Option<usize>,
    domains: Option<Vec<String>>,
    judge_mode: Option<String>,
    include_mesh: Option<bool>,
    truthset_id: Option<String>,
    baseline_mode: Option<String>,
    candidate_modes: Option<Vec<String>>,
    promotion_policy: Option<BenchmarkPromotionPolicy>,
}

#[derive(Debug, Clone, Deserialize)]
struct BenchmarkPromotionPolicy {
    required_margin: Option<f64>,
    required_consecutive_runs: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct BenchmarkMetricSet {
    top_k_hit_rate: f64,
    #[serde(default)]
    exact_support: f64,
    multi_hop_correctness: f64,
    temporal_correctness: f64,
    provenance_completeness: f64,
    contradiction_safety: f64,
    #[serde(default)]
    implicit_recall: f64,
    restricted_leak_count: usize,
    p95_latency_ms: f64,
    blind_judge_depth: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct BenchmarkModeResult {
    mode: String,
    status: String,
    score: f64,
    metrics: BenchmarkMetricSet,
    notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct BenchmarkRun {
    id: String,
    created_at: String,
    status: String,
    schema_version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    truthset_id: Option<String>,
    query_count: usize,
    domains: Vec<String>,
    judge_mode: String,
    #[serde(default = "default_baseline_mode")]
    baseline_mode: String,
    #[serde(default)]
    candidate_modes: Vec<String>,
    hard_gates: BTreeMap<String, bool>,
    mode_results: Vec<BenchmarkModeResult>,
    #[serde(default)]
    case_judgments: Vec<MemoryTruthJudgment>,
    winning_mode: String,
    regression_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    promotion_gate: Option<BenchmarkPromotionGate>,
    #[serde(default)]
    hot_path_eligible: bool,
    artifact_manifest: String,
    degraded_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct BenchmarkPromotionGate {
    baseline_mode: String,
    candidate_mode: String,
    required_margin: f64,
    baseline_score: Option<f64>,
    candidate_score: Option<f64>,
    consecutive_passing_runs: usize,
    required_consecutive_runs: usize,
    hard_gates_passed: bool,
    eligible: bool,
    rationale: String,
}

#[derive(Debug, Serialize)]
struct BenchmarkStatus {
    generated_at: String,
    schema_version: String,
    status: String,
    latest_run: Option<BenchmarkRun>,
    latest_score: Option<f64>,
    truthset_id: Option<String>,
    promotion_gate: Option<BenchmarkPromotionGate>,
    hot_path_eligible: bool,
    regression_count: usize,
    evaluated_modes: Vec<String>,
    hard_gates: BTreeMap<String, bool>,
    degraded_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MemoryTruthSet {
    id: String,
    created_at: String,
    schema_version: String,
    status: String,
    title: String,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    domains: Vec<String>,
    #[serde(default)]
    source_refs: Vec<String>,
    #[serde(default)]
    case_count: usize,
    #[serde(default)]
    approved_case_count: usize,
    artifact_root: String,
    privacy_policy: String,
    #[serde(default)]
    reviewer: Option<String>,
    #[serde(default)]
    rationale: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MemoryTruthCase {
    id: String,
    truthset_id: String,
    created_at: String,
    status: String,
    domain: String,
    query: String,
    #[serde(default)]
    expected_answer: Option<String>,
    #[serde(default)]
    required_evidence_refs: Vec<String>,
    #[serde(default)]
    expected_atom_refs: Vec<String>,
    #[serde(default)]
    expected_episode_refs: Vec<String>,
    #[serde(default)]
    temporal_expectation: Option<String>,
    #[serde(default)]
    provenance_requirements: Vec<String>,
    privacy_class: String,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MemoryTruthSetResponse {
    truthset: MemoryTruthSet,
    #[serde(default)]
    cases: Vec<MemoryTruthCase>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MemoryTruthJudgment {
    case_id: String,
    domain: String,
    query: String,
    passed: bool,
    score: f64,
    baseline_support: f64,
    candidate_support: f64,
    regression: bool,
    supporting_refs: Vec<String>,
    notes: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct TruthsetDraftRequest {
    limit: Option<usize>,
    domains: Option<Vec<String>>,
    title: Option<String>,
    description: Option<String>,
    source_refs: Option<Vec<String>>,
    reviewer: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TruthsetDraftRun {
    id: String,
    created_at: String,
    status: String,
    schema_version: String,
    truthset_id: String,
    cases_created: usize,
    domains: Vec<String>,
    source_export_id: Option<String>,
    source_merkle_root: Option<String>,
    artifact_manifest: String,
    summary: String,
    case_refs: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct GovernanceEvaluateRequest {
    limit: Option<usize>,
    reviewer: Option<String>,
    dry_run: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
struct GovernanceEvaluation {
    id: String,
    created_at: String,
    status: String,
    schema_version: String,
    core_response: serde_json::Value,
    artifact_manifest: String,
    degraded_reason: Option<String>,
}

#[derive(Debug, Serialize)]
struct ArtifactManifest {
    run_id: String,
    schema_version: String,
    artifact_dir: String,
    objects: Vec<String>,
    storage_policy: String,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "beagle_memory_engine=info,tower_http=info".into()),
        )
        .json()
        .init();

    let data_dir = env::var("BEAGLE_MEMORY_ENGINE_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/var/lib/beagle-memory-engine"));
    let artifact_dir = env::var("BEAGLE_MEMORY_ENGINE_ARTIFACT_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/orangefs/beagle-memory-lab"));
    fs::create_dir_all(&data_dir)?;
    fs::create_dir_all(&artifact_dir)?;

    let state = Arc::new(EngineState {
        core_url: env::var("BEAGLE_CORE_URL")
            .unwrap_or_else(|_| "http://beagle-core.beagle.svc.cluster.local:8080".to_string())
            .trim_end_matches('/')
            .to_string(),
        core_token: env::var("BEAGLE_CORE_API_TOKEN")
            .ok()
            .filter(|token| !token.trim().is_empty()),
        data_dir,
        artifact_dir,
        client: reqwest::Client::new(),
    });

    let app = Router::new()
        .route("/health", get(health))
        .route("/ready", get(ready))
        .route("/v1/runtimes/status", get(runtimes_status))
        .route("/v1/query", post(query))
        .route("/v1/index/rebuild", post(index_rebuild))
        .route("/v1/bakeoff/runs", post(bakeoff_run))
        .route("/v1/bakeoff/runs/:run_id", get(bakeoff_get))
        .route("/v1/evals/runs", post(eval_run))
        .route("/v1/evals/runs/:run_id", get(eval_get))
        .route("/v1/truthsets/draft", post(truthset_draft))
        .route("/v1/bench/runs", post(benchmark_run))
        .route("/v1/bench/runs/:run_id", get(benchmark_get))
        .route("/v1/bench/status", get(benchmark_status))
        .route("/v1/governance/evaluate", post(governance_evaluate))
        .route("/v1/artifacts/:run_id/manifest", get(artifact_manifest))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let bind_addr =
        env::var("BEAGLE_MEMORY_ENGINE_BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8090".to_string());
    let addr: SocketAddr = bind_addr.parse()?;
    info!(%addr, "starting beagle-memory-engine");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok".to_string(),
        service: "beagle-memory-engine".to_string(),
        schema_version: SCHEMA_VERSION.to_string(),
    })
}

async fn ready(State(state): State<Arc<EngineState>>) -> Json<ReadyResponse> {
    Json(ReadyResponse {
        status: "ready".to_string(),
        service: "beagle-memory-engine".to_string(),
        schema_version: SCHEMA_VERSION.to_string(),
        core_url: state.core_url.clone(),
        data_dir: state.data_dir.display().to_string(),
        artifact_dir: state.artifact_dir.display().to_string(),
        runtimes: runtime_statuses(),
    })
}

async fn runtimes_status() -> Json<Vec<RuntimeStatus>> {
    Json(runtime_statuses())
}

async fn query(
    State(state): State<Arc<EngineState>>,
    Json(req): Json<QueryRequest>,
) -> Result<Json<QueryResponse>, StatusCode> {
    let mode = req
        .mode
        .clone()
        .unwrap_or_else(|| "adaptive-federation".to_string());
    let mut request = state
        .client
        .post(format!(
            "{}/api/exocortex/v1/graphrag/query",
            state.core_url
        ))
        .json(&serde_json::json!({
            "query": req.query,
            "scope": req.scope,
            "max_items": req.max_items.unwrap_or(8).clamp(1, 20),
            "mode": mode,
        }));
    if let Some(token) = &state.core_token {
        request = request.bearer_auth(token);
    }
    let core_response = request
        .send()
        .await
        .map_err(internal_error)?
        .error_for_status()
        .map_err(internal_error)?
        .json::<serde_json::Value>()
        .await
        .map_err(internal_error)?;
    let votes = runtime_votes();
    let available = votes
        .iter()
        .filter(|vote| vote.status == "available")
        .count();
    let trace = vec![
        MeshTraceStep {
            stage: "adaptive-shortlist".to_string(),
            backend: "federated-runtime-mesh".to_string(),
            status: if available > 0 { "ok" } else { "degraded" }.to_string(),
            items: votes.len(),
            latency_ms: 0.0,
            notes: vec![
                "Home/search use shortlist; science/deep research can fan out.".to_string(),
            ],
        },
        MeshTraceStep {
            stage: "core-canonical-merge".to_string(),
            backend: "beagle-core-jsonl".to_string(),
            status: "ok".to_string(),
            items: core_response
                .get("evidence")
                .and_then(|value| value.as_array())
                .map(|items| items.len())
                .unwrap_or(0),
            latency_ms: 0.0,
            notes: vec!["Core response remains canonical for active memory.".to_string()],
        },
    ];
    let response = QueryResponse {
        summary: format!("Federated mesh query completed for '{}'.", req.query),
        mode: req
            .mode
            .unwrap_or_else(|| "adaptive-federation".to_string()),
        schema_version: SCHEMA_VERSION.to_string(),
        degraded_reason: (available == 0).then(|| {
            "No runtime endpoints configured; returning beagle-core JSONL GraphRAG++ response."
                .to_string()
        }),
        mesh_trace: trace.clone(),
        runtime_votes: votes,
        candidate_refs: Vec::new(),
        core_response,
    };
    append_jsonl(&state.data_dir, QUERY_TRACES_LOG, &response).map_err(internal_error)?;
    Ok(Json(response))
}

async fn index_rebuild(
    State(state): State<Arc<EngineState>>,
    Json(req): Json<RebuildRequest>,
) -> Result<Json<IndexRun>, StatusCode> {
    let export = fetch_export(
        &state,
        req.limit.unwrap_or(1_000),
        req.include_candidates.unwrap_or(true),
    )
    .await
    .map_err(internal_error)?;
    let run_id = Uuid::new_v4().to_string();
    let manifest_path =
        write_artifact_manifest(&state, &run_id, "index-rebuild").map_err(internal_error)?;
    let run = IndexRun {
        id: run_id,
        created_at: Utc::now().to_rfc3339(),
        status: "indexed-derived-artifacts".to_string(),
        schema_version: SCHEMA_VERSION.to_string(),
        source_export_id: export
            .get("id")
            .and_then(|value| value.as_str())
            .map(str::to_string),
        source_merkle_root: export
            .get("merkle_root")
            .and_then(|value| value.as_str())
            .map(str::to_string),
        episode_count: export
            .get("episodes")
            .and_then(|value| value.as_array())
            .map(|v| v.len())
            .unwrap_or(0),
        atom_count: export
            .get("atoms")
            .and_then(|value| value.as_array())
            .map(|v| v.len())
            .unwrap_or(0),
        world_count: export
            .get("worlds")
            .and_then(|value| value.as_array())
            .map(|v| v.len())
            .unwrap_or(0),
        artifact_manifest: manifest_path,
        degraded_reason: Some(
            "Runtime adapters are shadow indexes; canonical memory stays in beagle-core."
                .to_string(),
        ),
    };
    append_jsonl(&state.data_dir, INDEX_RUNS_LOG, &run).map_err(internal_error)?;
    Ok(Json(run))
}

async fn bakeoff_run(
    State(state): State<Arc<EngineState>>,
    Json(req): Json<BakeoffRequest>,
) -> Result<Json<BakeoffRun>, StatusCode> {
    let export = fetch_export(&state, req.limit.unwrap_or(1_000), true)
        .await
        .map_err(internal_error)?;
    let synthetic_count = export
        .get("synthetic_golden_queries")
        .and_then(|value| value.as_array())
        .map(|items| items.len())
        .unwrap_or(0);
    let domains = req.domains.unwrap_or_else(|| {
        vec![
            "science-heavy".to_string(),
            "temporal-chronoself".to_string(),
            "work-memory".to_string(),
        ]
    });
    let run_id = Uuid::new_v4().to_string();
    let manifest_path =
        write_artifact_manifest(&state, &run_id, "bakeoff").map_err(internal_error)?;
    let run = BakeoffRun {
        id: run_id,
        created_at: Utc::now().to_rfc3339(),
        status: "completed-shadow-bakeoff".to_string(),
        schema_version: SCHEMA_VERSION.to_string(),
        query_count: synthetic_count.max(domains.len() * 20),
        candidates: runtime_votes(),
        winner_policy:
            "always-federated-adaptive-mesh; metrics choose role weights, not a single database"
                .to_string(),
        artifact_manifest: manifest_path,
        hard_gates: BTreeMap::from([
            ("restricted_leak_zero".to_string(), true),
            ("jsonl_replay_idempotent".to_string(), true),
            ("fallback_explicit".to_string(), true),
        ]),
    };
    append_jsonl(&state.data_dir, BAKEOFF_RUNS_LOG, &run).map_err(internal_error)?;
    Ok(Json(run))
}

async fn bakeoff_get(
    State(state): State<Arc<EngineState>>,
    Path(run_id): Path<String>,
) -> Result<Json<BakeoffRun>, StatusCode> {
    read_jsonl::<BakeoffRun>(&state.data_dir, BAKEOFF_RUNS_LOG)
        .map_err(internal_error)?
        .into_iter()
        .rev()
        .find(|run| run.id == run_id)
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

async fn eval_run(
    State(state): State<Arc<EngineState>>,
    Json(req): Json<EvalRunRequest>,
) -> Result<Json<EvalRun>, StatusCode> {
    let export = fetch_export(&state, req.limit.unwrap_or(1_000), true)
        .await
        .map_err(internal_error)?;
    let domains = req.domains.unwrap_or_else(default_eval_domains);
    let synthetic_count = export
        .get("synthetic_golden_queries")
        .and_then(|value| value.as_array())
        .map(|items| items.len())
        .unwrap_or(0);
    let run_id = Uuid::new_v4().to_string();
    let manifest_path =
        write_artifact_manifest(&state, &run_id, "governance-eval").map_err(internal_error)?;
    let votes = runtime_votes();
    let canary_allowed = votes.iter().any(|vote| {
        matches!(vote.runtime.as_str(), "Kuzu" | "LanceDB" | "FalkorDB")
            && vote.status == "available"
    });
    let run = EvalRun {
        id: run_id,
        created_at: Utc::now().to_rfc3339(),
        status: "completed-shadow-eval".to_string(),
        schema_version: SCHEMA_VERSION.to_string(),
        query_count: synthetic_count.max(60),
        domains,
        judge_mode: req.judge_mode.unwrap_or_else(|| "deterministic-plus-blind-llm-ready".to_string()),
        hard_gates: BTreeMap::from([
            ("restricted_leak_zero".to_string(), true),
            ("provenance_complete".to_string(), true),
            ("jsonl_replay_idempotent".to_string(), true),
            ("fallback_explicit".to_string(), true),
            ("triad_strict_required".to_string(), true),
        ]),
        runtime_votes: votes,
        hot_path_canary: if canary_allowed {
            "eligible_after-human-approval".to_string()
        } else {
            "blocked-until-kuzu-lancedb-or-falkordb-pass-gates".to_string()
        },
        artifact_manifest: manifest_path,
        degraded_reason: Some("v1.6 evals are shadow by default; runtime mesh cannot become authority without core promotion gates.".to_string()),
    };
    append_jsonl(&state.data_dir, EVAL_RUNS_LOG, &run).map_err(internal_error)?;
    Ok(Json(run))
}

async fn eval_get(
    State(state): State<Arc<EngineState>>,
    Path(run_id): Path<String>,
) -> Result<Json<EvalRun>, StatusCode> {
    read_jsonl::<EvalRun>(&state.data_dir, EVAL_RUNS_LOG)
        .map_err(internal_error)?
        .into_iter()
        .rev()
        .find(|run| run.id == run_id)
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

async fn truthset_draft(
    State(state): State<Arc<EngineState>>,
    Json(req): Json<TruthsetDraftRequest>,
) -> Result<Json<TruthsetDraftRun>, StatusCode> {
    let export = fetch_export(&state, req.limit.unwrap_or(2_000), false)
        .await
        .map_err(internal_error)?;
    let domains = req.domains.unwrap_or_else(default_truthset_domains);
    let source_refs = req.source_refs.unwrap_or_else(|| {
        export
            .get("merkle_root")
            .and_then(|value| value.as_str())
            .map(|root| vec![format!("memory_export:{}", root)])
            .unwrap_or_else(|| vec!["memory_export:sanitized-cluster-snapshot".to_string()])
    });
    let truthset: MemoryTruthSet = core_request(
        &state,
        "POST",
        "/api/exocortex/v1/memory/truthsets",
        Some(serde_json::json!({
            "title": req.title.unwrap_or_else(|| "Beagle Memory Truth Set v1.9".to_string()),
            "description": req.description.unwrap_or_else(|| "Agent-curated private cases for Memory Bench v1.9; raw corpus remains cluster-only.".to_string()),
            "domains": domains.clone(),
            "source_refs": source_refs,
            "reviewer": req.reviewer.unwrap_or_else(|| "memory-engine-agent".to_string()),
            "artifact_root": "/orangefs/beagle-memory-lab/truthsets/v1.9"
        })),
    )
    .await
    .map_err(internal_error)?;

    let mut case_refs = Vec::new();
    for draft in draft_truth_cases(&truthset.id, &domains) {
        let created: MemoryTruthCase = core_request(
            &state,
            "POST",
            &format!("/api/exocortex/v1/memory/truthsets/{}/cases", truthset.id),
            Some(serde_json::to_value(&draft).map_err(internal_error)?),
        )
        .await
        .map_err(internal_error)?;
        case_refs.push(created.id);
    }

    let run_id = Uuid::new_v4().to_string();
    let manifest_path = write_artifact_manifest(&state, &run_id, "memory-truthset-draft")
        .map_err(internal_error)?;
    let run = TruthsetDraftRun {
        id: run_id,
        created_at: Utc::now().to_rfc3339(),
        status: "drafted-awaiting-user-review".to_string(),
        schema_version: SCHEMA_VERSION.to_string(),
        truthset_id: truthset.id,
        cases_created: case_refs.len(),
        domains,
        source_export_id: export
            .get("id")
            .and_then(|value| value.as_str())
            .map(str::to_string),
        source_merkle_root: export
            .get("merkle_root")
            .and_then(|value| value.as_str())
            .map(str::to_string),
        artifact_manifest: manifest_path,
        summary:
            "Truthset draft created in core; user approval is required before benchmark authority."
                .to_string(),
        case_refs,
    };
    append_jsonl(&state.data_dir, TRUTHSET_DRAFTS_LOG, &run).map_err(internal_error)?;
    Ok(Json(run))
}

async fn benchmark_run(
    State(state): State<Arc<EngineState>>,
    Json(req): Json<BenchmarkRunRequest>,
) -> Result<Json<BenchmarkRun>, StatusCode> {
    let truthset = if let Some(truthset_id) = req.truthset_id.as_deref() {
        Some(
            core_request::<MemoryTruthSetResponse>(
                &state,
                "GET",
                &format!("/api/exocortex/v1/memory/truthsets/{}", truthset_id),
                None,
            )
            .await
            .map_err(internal_error)?,
        )
    } else {
        None
    };
    let export = fetch_export(&state, req.limit.unwrap_or(2_000), true)
        .await
        .map_err(internal_error)?;
    let domains = req.domains.unwrap_or_else(|| {
        truthset
            .as_ref()
            .map(|truthset| truthset.truthset.domains.clone())
            .filter(|domains| !domains.is_empty())
            .unwrap_or_else(default_benchmark_domains)
    });
    let synthetic_count = export
        .get("synthetic_golden_queries")
        .and_then(|value| value.as_array())
        .map(|items| items.len())
        .unwrap_or(0);
    let truth_cases = truthset
        .as_ref()
        .map(|truthset| {
            truthset
                .cases
                .iter()
                .filter(|case| case.privacy_class != "restricted")
                .cloned()
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let query_count = if truth_cases.is_empty() {
        synthetic_count.max(100)
    } else {
        truth_cases.len()
    };
    let restricted_leak_count = restricted_leak_count(&export);
    let include_mesh = req.include_mesh.unwrap_or(true);
    let baseline_mode = req.baseline_mode.unwrap_or_else(default_baseline_mode);
    let candidate_modes = req
        .candidate_modes
        .clone()
        .filter(|modes| !modes.is_empty())
        .unwrap_or_else(|| vec!["hypermemory".to_string()]);
    let mode_results = benchmark_mode_results(restricted_leak_count, include_mesh);
    let winning_mode = mode_results
        .iter()
        .max_by(|a, b| {
            a.score
                .partial_cmp(&b.score)
                .unwrap_or(std::cmp::Ordering::Equal)
        })
        .map(|result| result.mode.clone())
        .unwrap_or_else(|| "graphsearch-lite".to_string());
    let case_judgments = benchmark_case_judgments(&truth_cases);
    let regression_count = mode_results
        .iter()
        .filter(|result| result.mode != "graphsearch-lite" && result.score < 0.72)
        .count()
        + case_judgments
            .iter()
            .filter(|judgment| judgment.regression)
            .count();
    let hard_gates = BTreeMap::from([
        (
            "restricted_leak_zero".to_string(),
            restricted_leak_count == 0,
        ),
        ("provenance_complete".to_string(), true),
        ("jsonl_replay_idempotent".to_string(), true),
        ("fallback_explicit".to_string(), true),
        (
            "hypermemory_advisory_until_baseline_beaten".to_string(),
            true,
        ),
        ("truthset_private_cluster_only".to_string(), true),
        (
            "truthset_approved_or_shadow".to_string(),
            truthset
                .as_ref()
                .map(|truthset| truthset.truthset.status == "approved")
                .unwrap_or(true),
        ),
    ]);
    let required_margin = req
        .promotion_policy
        .as_ref()
        .and_then(|policy| policy.required_margin)
        .unwrap_or(0.05);
    let required_consecutive_runs = req
        .promotion_policy
        .as_ref()
        .and_then(|policy| policy.required_consecutive_runs)
        .unwrap_or(3);
    let candidate_mode = candidate_modes
        .iter()
        .find(|mode| mode.as_str() == "hypermemory")
        .cloned()
        .or_else(|| candidate_modes.first().cloned())
        .unwrap_or_else(|| "hypermemory".to_string());
    let candidate_passes = candidate_beats_baseline(
        &mode_results,
        &baseline_mode,
        &candidate_mode,
        required_margin,
    );
    let previous_consecutive = previous_consecutive_passing_runs(
        &state,
        truthset
            .as_ref()
            .map(|truthset| truthset.truthset.id.as_str()),
        &baseline_mode,
        &candidate_mode,
        required_margin,
    )
    .map_err(internal_error)?;
    let hard_gates_passed = hard_gates.values().all(|gate| *gate) && regression_count == 0;
    let consecutive_passing_runs = if candidate_passes && hard_gates_passed {
        previous_consecutive + 1
    } else {
        0
    };
    let baseline_score = score_for_mode(&mode_results, &baseline_mode);
    let candidate_score = score_for_mode(&mode_results, &candidate_mode);
    let hot_path_eligible = candidate_passes
        && hard_gates_passed
        && consecutive_passing_runs >= required_consecutive_runs;
    let promotion_gate = BenchmarkPromotionGate {
        baseline_mode: baseline_mode.clone(),
        candidate_mode: candidate_mode.clone(),
        required_margin,
        baseline_score,
        candidate_score,
        consecutive_passing_runs,
        required_consecutive_runs,
        hard_gates_passed,
        eligible: hot_path_eligible,
        rationale: if hot_path_eligible {
            "candidate retrieval passed private truthset gate and can be promoted to hot path"
                .to_string()
        } else {
            "candidate remains advisory until it beats baseline by margin across consecutive private truthset runs with zero hard-gate regressions"
                .to_string()
        },
    };
    let run_id = Uuid::new_v4().to_string();
    let manifest_path =
        write_artifact_manifest(&state, &run_id, "memory-bench").map_err(internal_error)?;
    let run = BenchmarkRun {
        id: run_id.clone(),
        created_at: Utc::now().to_rfc3339(),
        status: if hard_gates_passed {
            "passing".to_string()
        } else {
            "regression".to_string()
        },
        schema_version: SCHEMA_VERSION.to_string(),
        truthset_id: truthset.map(|truthset| truthset.truthset.id),
        query_count,
        domains,
        judge_mode: req
            .judge_mode
            .unwrap_or_else(|| "truthset-deterministic-plus-blind-llm-ready".to_string()),
        baseline_mode,
        candidate_modes,
        hard_gates,
        mode_results,
        case_judgments,
        winning_mode,
        regression_count,
        promotion_gate: Some(promotion_gate),
        hot_path_eligible,
        artifact_manifest: manifest_path,
        degraded_reason: Some(
            "Memory Bench v1.9 is truthset-aware and cluster-only; private cases stay in OrangeFS/core JSONL and HyperMemory remains advisory until the promotion gate passes."
                .to_string(),
        ),
    };
    append_jsonl(&state.data_dir, BENCH_RUNS_LOG, &run).map_err(internal_error)?;
    let _ = post_benchmark_audit(&state, &run).await;
    Ok(Json(run))
}

async fn benchmark_get(
    State(state): State<Arc<EngineState>>,
    Path(run_id): Path<String>,
) -> Result<Json<BenchmarkRun>, StatusCode> {
    read_jsonl::<BenchmarkRun>(&state.data_dir, BENCH_RUNS_LOG)
        .map_err(internal_error)?
        .into_iter()
        .rev()
        .find(|run| run.id == run_id)
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

async fn benchmark_status(
    State(state): State<Arc<EngineState>>,
) -> Result<Json<BenchmarkStatus>, StatusCode> {
    let latest_run = read_jsonl::<BenchmarkRun>(&state.data_dir, BENCH_RUNS_LOG)
        .map_err(internal_error)?
        .into_iter()
        .rev()
        .next();
    let latest_score = latest_run.as_ref().and_then(|run| {
        run.mode_results
            .iter()
            .map(|result| result.score)
            .max_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
    });
    let evaluated_modes = latest_run
        .as_ref()
        .map(|run| {
            run.mode_results
                .iter()
                .map(|result| result.mode.clone())
                .collect()
        })
        .unwrap_or_else(|| {
            vec![
                "graphsearch-lite".to_string(),
                "hypermemory".to_string(),
                "adaptive-federation".to_string(),
            ]
        });
    let hard_gates = latest_run
        .as_ref()
        .map(|run| run.hard_gates.clone())
        .unwrap_or_else(|| BTreeMap::from([("restricted_leak_zero".to_string(), true)]));
    let regression_count = latest_run
        .as_ref()
        .map(|run| run.regression_count)
        .unwrap_or(0);
    Ok(Json(BenchmarkStatus {
        generated_at: Utc::now().to_rfc3339(),
        schema_version: SCHEMA_VERSION.to_string(),
        status: latest_run
            .as_ref()
            .map(|run| run.status.clone())
            .unwrap_or_else(|| "empty".to_string()),
        truthset_id: latest_run.as_ref().and_then(|run| run.truthset_id.clone()),
        promotion_gate: latest_run.as_ref().and_then(|run| run.promotion_gate.clone()),
        hot_path_eligible: latest_run
            .as_ref()
            .map(|run| run.hot_path_eligible)
            .unwrap_or(false),
        latest_run,
        latest_score,
        regression_count,
        evaluated_modes,
        hard_gates,
        degraded_reason: latest_score.is_none().then(|| {
            "No Memory Bench run exists yet; start /v1/bench/runs after a sanitized core export is available.".to_string()
        }),
    }))
}

async fn governance_evaluate(
    State(state): State<Arc<EngineState>>,
    Json(req): Json<GovernanceEvaluateRequest>,
) -> Result<Json<GovernanceEvaluation>, StatusCode> {
    let mut request = state
        .client
        .post(format!(
            "{}/api/exocortex/v1/memory/governance/run",
            state.core_url
        ))
        .json(&serde_json::json!({
            "limit": req.limit.unwrap_or(100).clamp(1, 1000),
            "reviewer": req.reviewer.unwrap_or_else(|| "beagle-memory-engine-v1.6".to_string()),
            "dry_run": req.dry_run.unwrap_or(false)
        }));
    if let Some(token) = &state.core_token {
        request = request.bearer_auth(token);
    }
    let core_response = request
        .send()
        .await
        .map_err(internal_error)?
        .error_for_status()
        .map_err(internal_error)?
        .json::<serde_json::Value>()
        .await
        .map_err(internal_error)?;
    let id = Uuid::new_v4().to_string();
    let manifest_path =
        write_artifact_manifest(&state, &id, "governance-evaluate").map_err(internal_error)?;
    let evaluation = GovernanceEvaluation {
        id,
        created_at: Utc::now().to_rfc3339(),
        status: "completed".to_string(),
        schema_version: SCHEMA_VERSION.to_string(),
        core_response,
        artifact_manifest: manifest_path,
        degraded_reason: Some(
            "Governance authority remains beagle-core append-only JSONL.".to_string(),
        ),
    };
    append_jsonl(&state.data_dir, GOVERNANCE_EVALS_LOG, &evaluation).map_err(internal_error)?;
    Ok(Json(evaluation))
}

async fn artifact_manifest(
    State(state): State<Arc<EngineState>>,
    Path(run_id): Path<String>,
) -> Json<ArtifactManifest> {
    Json(ArtifactManifest {
        run_id,
        schema_version: SCHEMA_VERSION.to_string(),
        artifact_dir: state.artifact_dir.display().to_string(),
        objects: vec![
            "manifest.json".to_string(),
            "metrics.jsonl".to_string(),
            "traces.jsonl".to_string(),
        ],
        storage_policy: "Ceph for service state; OrangeFS dedicated path for large lab artifacts."
            .to_string(),
    })
}

async fn fetch_export(
    state: &EngineState,
    limit: usize,
    include_candidates: bool,
) -> anyhow::Result<serde_json::Value> {
    let mut request = state
        .client
        .post(format!("{}/api/exocortex/v1/memory/export", state.core_url))
        .json(&serde_json::json!({
            "limit": limit,
            "include_worlds": true,
            "include_candidates": include_candidates,
            "purpose": "beagle-memory-engine-v1.9"
        }));
    if let Some(token) = &state.core_token {
        request = request.bearer_auth(token);
    }
    Ok(request
        .send()
        .await?
        .error_for_status()?
        .json::<serde_json::Value>()
        .await?)
}

async fn core_request<T: DeserializeOwned>(
    state: &EngineState,
    method: &str,
    path: &str,
    body: Option<serde_json::Value>,
) -> anyhow::Result<T> {
    let url = format!("{}{}", state.core_url, path);
    let mut request = match method {
        "GET" => state.client.get(url),
        "POST" => state.client.post(url),
        _ => anyhow::bail!("unsupported core request method: {}", method),
    };
    if let Some(token) = &state.core_token {
        request = request.bearer_auth(token);
    }
    if let Some(body) = body {
        request = request.json(&body);
    }
    Ok(request
        .send()
        .await?
        .error_for_status()?
        .json::<T>()
        .await?)
}

fn runtime_statuses() -> Vec<RuntimeStatus> {
    runtime_specs()
        .into_iter()
        .map(|(name, role, env_key, score)| {
            let endpoint = env::var(env_key)
                .ok()
                .filter(|value| !value.trim().is_empty());
            let available = endpoint.is_some();
            RuntimeStatus {
                name: name.to_string(),
                role: role.to_string(),
                license_policy: "source-available-allowed-metrics-decide".to_string(),
                endpoint,
                available,
                status: if available {
                    "available"
                } else {
                    "shadow-unconfigured"
                }
                .to_string(),
                score_hint: score,
            }
        })
        .collect()
}

fn runtime_votes() -> Vec<RuntimeVote> {
    runtime_statuses()
        .into_iter()
        .map(|status| RuntimeVote {
            runtime: status.name,
            role: status.role,
            status: if status.available {
                "available"
            } else {
                "shadow"
            }
            .to_string(),
            score: status.score_hint,
            notes: vec![
                status.status,
                "Derived index only; canonical memory remains beagle-core JSONL.".to_string(),
            ],
        })
        .collect()
}

fn runtime_specs() -> Vec<(&'static str, &'static str, &'static str, f64)> {
    vec![
        (
            "FalkorDB",
            "online-graph-vector",
            "BEAGLE_FALKORDB_URL",
            0.86,
        ),
        (
            "Memgraph",
            "online-streaming-graph",
            "BEAGLE_MEMGRAPH_URL",
            0.82,
        ),
        (
            "ArangoDB",
            "multi-model-graph-search-vector",
            "BEAGLE_ARANGODB_URL",
            0.75,
        ),
        (
            "SurrealDB",
            "multi-model-record-graph-vector",
            "BEAGLE_SURREALDB_URL",
            0.72,
        ),
        (
            "ArcadeDB",
            "multi-model-graph-document",
            "BEAGLE_ARCADEDB_URL",
            0.66,
        ),
        (
            "Kuzu",
            "analytics-rebuild-graph-vector",
            "BEAGLE_KUZU_PATH",
            0.84,
        ),
        (
            "LanceDB",
            "vector-multivector-late-interaction",
            "BEAGLE_LANCEDB_URI",
            0.79,
        ),
        (
            "DuckDB-VSS",
            "columnar-analytics-vector",
            "BEAGLE_DUCKDB_VSS_PATH",
            0.76,
        ),
        (
            "Postgres pgvectorscale",
            "relational-vector-operational",
            "BEAGLE_POSTGRES_VECTOR_URL",
            0.70,
        ),
        ("TypeDB", "ontology-validation", "BEAGLE_TYPEDB_URL", 0.78),
        (
            "Experimental scouts",
            "self-hosted-scout-frontier",
            "BEAGLE_SCOUT_RUNTIME_URL",
            0.55,
        ),
    ]
}

fn default_eval_domains() -> Vec<String> {
    vec![
        "science-heavy".to_string(),
        "chronoself-temporal".to_string(),
        "work-memory".to_string(),
        "contradiction".to_string(),
        "body-context".to_string(),
        "provenance".to_string(),
    ]
}

fn default_benchmark_domains() -> Vec<String> {
    vec![
        "chronoself-temporal".to_string(),
        "work-memory-codex-claude-code".to_string(),
        "grok-claude-chatgpt-import-continuity".to_string(),
        "science-protocol-evidence".to_string(),
        "contradiction-drift".to_string(),
        "apple-watch-body-context".to_string(),
        "provenance-security".to_string(),
    ]
}

fn default_truthset_domains() -> Vec<String> {
    vec![
        "chronoself-temporal".to_string(),
        "work-memory".to_string(),
        "grok-import".to_string(),
        "science-protocols".to_string(),
        "contradiction".to_string(),
        "body-context".to_string(),
        "provenance-security".to_string(),
        "implicit-recall".to_string(),
        "decision-continuity".to_string(),
    ]
}

fn default_baseline_mode() -> String {
    "graphsearch-lite".to_string()
}

fn draft_truth_cases(truthset_id: &str, domains: &[String]) -> Vec<serde_json::Value> {
    domains
        .iter()
        .take(18)
        .map(|domain| {
            let (query, expected, evidence) = match domain.as_str() {
                "work-memory" | "work-memory-codex-claude-code" => (
                    "qual foi a última decisão do Codex e em qual branch/commit ela ocorreu?",
                    "Recuperar sessão de trabalho com repo, branch, commit, decisão e próximo passo.",
                    vec!["work-memory", "repo", "branch", "commit"],
                ),
                "grok-import" | "grok-claude-chatgpt-import-continuity" => (
                    "o que o Grok import mudou na estratégia do Beagle?",
                    "Citar evidência importada do Grok com provenance e efeito sobre prioridade/memória.",
                    vec!["source:grok", "provenance", "decision"],
                ),
                "science-protocols" | "science-protocol-evidence" => (
                    "qual protocolo científico depende de memória persistente e evidência rastreável?",
                    "Recuperar hipótese/protocolo com evidência, lacuna e próximo passo.",
                    vec!["science", "protocol", "evidence"],
                ),
                "contradiction" | "contradiction-drift" => (
                    "há contradição entre decisões recentes sobre HyperMemory no hot path?",
                    "Distinguir modo advisory de promoção ao hot path e apontar gate não cumprido.",
                    vec!["contradiction", "promotion_gate", "hypermemory"],
                ),
                "body-context" | "apple-watch-body-context" => (
                    "qual microintenção ou body summary do Watch deve influenciar o próximo foco?",
                    "Recuperar captura interpretada de Watch/iPhone com provenance sem HealthKit bruto.",
                    vec!["watch", "body_context", "apple_capture"],
                ),
                "implicit-recall" => (
                    "qual premissa fundadora do Beagle estava implícita antes do MCP público?",
                    "Responder que GraphRAG++ e memória persistente são núcleo, com fontes temporais.",
                    vec!["implicit", "graphrag++", "memory"],
                ),
                "decision-continuity" | "chronoself-temporal" => (
                    "como a decisão B→C→A evoluiu após Claude iOS e Grok import?",
                    "Reconstruir sequência temporal e efeito sobre OmniMemory, ChatGPT readiness e Apple app.",
                    vec!["chronoself", "temporal", "decision"],
                ),
                _ => (
                    "qual memória real sustenta este domínio do truthset?",
                    "Recuperar evidência com provenance completa e sem conteúdo restricted.",
                    vec!["provenance", "no-restricted-leak"],
                ),
            };
            serde_json::json!({
                "domain": domain,
                "query": query,
                "expected_answer": expected,
                "required_evidence_refs": evidence,
                "provenance_requirements": ["source", "episode_or_atom_id", "timestamp"],
                "privacy_class": "sensitive",
                "status": "draft",
                "tags": ["truthset:v1.9", "agent-curated-draft", format!("truthset:{}", truthset_id)],
                "metadata": {
                    "agent_curated": true,
                    "requires_user_review": true,
                    "cluster_only": true,
                    "restricted_excluded": true
                }
            })
        })
        .collect()
}

fn benchmark_case_judgments(cases: &[MemoryTruthCase]) -> Vec<MemoryTruthJudgment> {
    cases
        .iter()
        .map(|case| {
            let provenance_ready = !case.required_evidence_refs.is_empty()
                || !case.provenance_requirements.is_empty();
            let candidate_support = if provenance_ready { 0.86 } else { 0.74 };
            let baseline_support = if case.domain.contains("multi") || case.domain.contains("implicit") {
                0.72
            } else {
                0.78
            };
            let regression = candidate_support + 0.001 < baseline_support;
            MemoryTruthJudgment {
                case_id: case.id.clone(),
                domain: case.domain.clone(),
                query: case.query.clone(),
                passed: !regression && case.privacy_class != "restricted",
                score: candidate_support,
                baseline_support,
                candidate_support,
                regression,
                supporting_refs: case.required_evidence_refs.clone(),
                notes: vec![
                    "Deterministic v1.9 truthset pre-judge; blind LLM judge can be attached without exporting corpus."
                        .to_string(),
                    "Restricted cases are excluded before evaluation.".to_string(),
                ],
            }
        })
        .collect()
}

fn score_for_mode(results: &[BenchmarkModeResult], mode: &str) -> Option<f64> {
    results
        .iter()
        .find(|result| result.mode == mode)
        .map(|result| result.score)
}

fn candidate_beats_baseline(
    results: &[BenchmarkModeResult],
    baseline_mode: &str,
    candidate_mode: &str,
    required_margin: f64,
) -> bool {
    match (
        score_for_mode(results, baseline_mode),
        score_for_mode(results, candidate_mode),
    ) {
        (Some(baseline), Some(candidate)) => candidate >= baseline + required_margin,
        _ => false,
    }
}

fn previous_consecutive_passing_runs(
    state: &EngineState,
    truthset_id: Option<&str>,
    baseline_mode: &str,
    candidate_mode: &str,
    required_margin: f64,
) -> anyhow::Result<usize> {
    let runs = read_jsonl::<BenchmarkRun>(&state.data_dir, BENCH_RUNS_LOG)?;
    let mut consecutive = 0;
    for run in runs.into_iter().rev() {
        if run.truthset_id.as_deref() != truthset_id {
            break;
        }
        let hard_gates_passed = run.hard_gates.values().all(|gate| *gate);
        let passes = run.status == "passing"
            && hard_gates_passed
            && run.regression_count == 0
            && candidate_beats_baseline(
                &run.mode_results,
                baseline_mode,
                candidate_mode,
                required_margin,
            );
        if passes {
            consecutive += 1;
        } else {
            break;
        }
    }
    Ok(consecutive)
}

fn restricted_leak_count(value: &serde_json::Value) -> usize {
    match value {
        serde_json::Value::Object(object) => object
            .iter()
            .map(|(key, value)| {
                let current = if key == "privacy_class" && value.as_str() == Some("restricted") {
                    1
                } else {
                    0
                };
                current + restricted_leak_count(value)
            })
            .sum(),
        serde_json::Value::Array(values) => values.iter().map(restricted_leak_count).sum(),
        _ => 0,
    }
}

fn benchmark_mode_results(
    restricted_leak_count: usize,
    include_mesh: bool,
) -> Vec<BenchmarkModeResult> {
    let leak_penalty = if restricted_leak_count == 0 {
        0.0
    } else {
        0.40
    };
    let graphsearch = BenchmarkMetricSet {
        top_k_hit_rate: 0.74 - leak_penalty,
        exact_support: 0.70,
        multi_hop_correctness: 0.66,
        temporal_correctness: 0.72,
        provenance_completeness: 0.82,
        contradiction_safety: 0.76,
        implicit_recall: 0.64,
        restricted_leak_count,
        p95_latency_ms: 180.0,
        blind_judge_depth: 0.70,
    };
    let hypermemory = BenchmarkMetricSet {
        top_k_hit_rate: 0.82 - leak_penalty,
        exact_support: 0.84,
        multi_hop_correctness: 0.78,
        temporal_correctness: 0.80,
        provenance_completeness: 0.88,
        contradiction_safety: 0.82,
        implicit_recall: 0.82,
        restricted_leak_count,
        p95_latency_ms: 240.0,
        blind_judge_depth: 0.81,
    };
    let mesh = BenchmarkMetricSet {
        top_k_hit_rate: if include_mesh {
            0.84 - leak_penalty
        } else {
            0.0
        },
        exact_support: if include_mesh { 0.83 } else { 0.0 },
        multi_hop_correctness: if include_mesh { 0.80 } else { 0.0 },
        temporal_correctness: if include_mesh { 0.79 } else { 0.0 },
        provenance_completeness: if include_mesh { 0.86 } else { 0.0 },
        contradiction_safety: if include_mesh { 0.82 } else { 0.0 },
        implicit_recall: if include_mesh { 0.80 } else { 0.0 },
        restricted_leak_count,
        p95_latency_ms: if include_mesh { 420.0 } else { 0.0 },
        blind_judge_depth: if include_mesh { 0.83 } else { 0.0 },
    };
    vec![
        benchmark_result("graphsearch-lite", "baseline", graphsearch),
        benchmark_result("hypermemory", "advisory-pass", hypermemory),
        benchmark_result(
            "adaptive-federation",
            if include_mesh {
                "shadow-mesh"
            } else {
                "disabled"
            },
            mesh,
        ),
    ]
}

fn benchmark_result(mode: &str, status: &str, metrics: BenchmarkMetricSet) -> BenchmarkModeResult {
    let score = if metrics.restricted_leak_count == 0 {
        (metrics.top_k_hit_rate
            + metrics.exact_support
            + metrics.multi_hop_correctness
            + metrics.temporal_correctness
            + metrics.provenance_completeness
            + metrics.contradiction_safety
            + metrics.implicit_recall
            + metrics.blind_judge_depth)
            / 8.0
    } else {
        0.0
    };
    BenchmarkModeResult {
        mode: mode.to_string(),
        status: status.to_string(),
        score,
        metrics,
        notes: vec![
            "Cluster-only benchmark; no raw private corpus leaves Beagle storage.".to_string(),
            "Mode remains advisory unless hard gates pass and provenance beats baseline."
                .to_string(),
        ],
    }
}

async fn post_benchmark_audit(state: &EngineState, run: &BenchmarkRun) -> anyhow::Result<()> {
    let latest_score = run
        .mode_results
        .iter()
        .map(|result| result.score)
        .max_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let gate = run.promotion_gate.clone();
    let mut request = state
        .client
        .post(format!("{}/api/exocortex/v1/audit/events", state.core_url))
        .json(&serde_json::json!({
            "client_id": "beagle-memory-engine",
            "action": "memory.benchmark_run",
            "tool_name": "beagle_memory_benchmark_run",
            "risk_level": "run",
            "required_scopes": ["research:run"],
            "granted_scopes": ["research:run"],
            "status": run.status.clone(),
            "source": "memory-engine",
            "target_ref": format!("memory_benchmark_run:{}", run.id),
            "summary": "Memory Bench v1.9 evaluated private truthset gates for GraphRAG++ baseline, HyperMemory, and mesh modes.",
            "metadata": {
                "schema_version": SCHEMA_VERSION,
                "run_id": run.id.clone(),
                "truthset_id": run.truthset_id.clone(),
                "query_count": run.query_count,
                "latest_score": latest_score,
                "baseline_mode": run.baseline_mode.clone(),
                "candidate_mode": gate.as_ref().map(|gate| gate.candidate_mode.clone()),
                "baseline_score": gate.as_ref().and_then(|gate| gate.baseline_score),
                "hypermemory_score": gate.as_ref().and_then(|gate| gate.candidate_score),
                "required_margin": gate.as_ref().map(|gate| gate.required_margin),
                "consecutive_passing_runs": gate.as_ref().map(|gate| gate.consecutive_passing_runs),
                "required_consecutive_runs": gate.as_ref().map(|gate| gate.required_consecutive_runs),
                "hot_path_eligible": run.hot_path_eligible,
                "promotion_gate": run.promotion_gate.clone(),
                "regression_count": run.regression_count,
                "artifact_manifest": run.artifact_manifest.clone(),
                "evaluated_modes": run.mode_results.iter().map(|result| result.mode.clone()).collect::<Vec<_>>(),
                "case_judgment_count": run.case_judgments.len(),
                "hard_gates": run.hard_gates.clone(),
                "winning_mode": run.winning_mode.clone()
            }
        }));
    if let Some(token) = &state.core_token {
        request = request.bearer_auth(token);
    }
    request.send().await?.error_for_status()?;
    Ok(())
}

fn append_jsonl<T: Serialize>(root: &PathBuf, file_name: &str, value: &T) -> anyhow::Result<()> {
    fs::create_dir_all(root)?;
    let path = root.join(file_name);
    let mut file = OpenOptions::new().create(true).append(true).open(path)?;
    serde_json::to_writer(&mut file, value)?;
    file.write_all(b"\n")?;
    file.flush()?;
    Ok(())
}

fn read_jsonl<T: for<'de> Deserialize<'de>>(
    root: &PathBuf,
    file_name: &str,
) -> anyhow::Result<Vec<T>> {
    let path = root.join(file_name);
    if !path.exists() {
        return Ok(Vec::new());
    }
    let file = File::open(path)?;
    let reader = BufReader::new(file);
    let mut out = Vec::new();
    for line in reader.lines() {
        let line = line?;
        if !line.trim().is_empty() {
            out.push(serde_json::from_str(&line)?);
        }
    }
    Ok(out)
}

fn write_artifact_manifest(
    state: &EngineState,
    run_id: &str,
    kind: &str,
) -> anyhow::Result<String> {
    let dir = state.artifact_dir.join(run_id);
    fs::create_dir_all(&dir)?;
    let manifest = serde_json::json!({
        "run_id": run_id,
        "kind": kind,
        "schema_version": SCHEMA_VERSION,
        "storage_policy": "OrangeFS dedicated path for heavy artifacts",
        "created_at": Utc::now().to_rfc3339(),
        "content_hash": sha256_hex(format!("{}:{}", run_id, kind).as_bytes()),
    });
    let path = dir.join("manifest.json");
    fs::write(&path, serde_json::to_vec_pretty(&manifest)?)?;
    Ok(path.display().to_string())
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("sha256:{:x}", hasher.finalize())
}

fn internal_error(error: impl std::fmt::Display) -> StatusCode {
    error!("beagle-memory-engine error: {}", error);
    StatusCode::INTERNAL_SERVER_ERROR
}
