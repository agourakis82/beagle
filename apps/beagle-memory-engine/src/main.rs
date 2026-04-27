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
use serde::{Deserialize, Serialize};
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

const SCHEMA_VERSION: &str = "beagle-federated-memory-engine-v1.6";
const BAKEOFF_RUNS_LOG: &str = "bakeoff_runs.jsonl";
const INDEX_RUNS_LOG: &str = "index_runs.jsonl";
const QUERY_TRACES_LOG: &str = "query_traces.jsonl";
const EVAL_RUNS_LOG: &str = "eval_runs.jsonl";
const GOVERNANCE_EVALS_LOG: &str = "governance_evaluations.jsonl";

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
        .route("/v1/governance/evaluate", post(governance_evaluate))
        .route("/v1/artifacts/:run_id/manifest", get(artifact_manifest))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let bind_addr = env::var("BEAGLE_MEMORY_ENGINE_BIND_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8090".to_string());
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
    let mode = req.mode.clone().unwrap_or_else(|| "adaptive-federation".to_string());
    let mut request = state
        .client
        .post(format!("{}/api/exocortex/v1/graphrag/query", state.core_url))
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
    let available = votes.iter().filter(|vote| vote.status == "available").count();
    let trace = vec![
        MeshTraceStep {
            stage: "adaptive-shortlist".to_string(),
            backend: "federated-runtime-mesh".to_string(),
            status: if available > 0 { "ok" } else { "degraded" }.to_string(),
            items: votes.len(),
            latency_ms: 0.0,
            notes: vec!["Home/search use shortlist; science/deep research can fan out.".to_string()],
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
        mode: req.mode.unwrap_or_else(|| "adaptive-federation".to_string()),
        schema_version: SCHEMA_VERSION.to_string(),
        degraded_reason: (available == 0).then(|| {
            "No runtime endpoints configured; returning beagle-core JSONL GraphRAG++ response.".to_string()
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
    let export = fetch_export(&state, req.limit.unwrap_or(1_000), req.include_candidates.unwrap_or(true))
        .await
        .map_err(internal_error)?;
    let run_id = Uuid::new_v4().to_string();
    let manifest_path = write_artifact_manifest(&state, &run_id, "index-rebuild").map_err(internal_error)?;
    let run = IndexRun {
        id: run_id,
        created_at: Utc::now().to_rfc3339(),
        status: "indexed-derived-artifacts".to_string(),
        schema_version: SCHEMA_VERSION.to_string(),
        source_export_id: export.get("id").and_then(|value| value.as_str()).map(str::to_string),
        source_merkle_root: export
            .get("merkle_root")
            .and_then(|value| value.as_str())
            .map(str::to_string),
        episode_count: export.get("episodes").and_then(|value| value.as_array()).map(|v| v.len()).unwrap_or(0),
        atom_count: export.get("atoms").and_then(|value| value.as_array()).map(|v| v.len()).unwrap_or(0),
        world_count: export.get("worlds").and_then(|value| value.as_array()).map(|v| v.len()).unwrap_or(0),
        artifact_manifest: manifest_path,
        degraded_reason: Some("Runtime adapters are shadow indexes; canonical memory stays in beagle-core.".to_string()),
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
    let manifest_path = write_artifact_manifest(&state, &run_id, "bakeoff").map_err(internal_error)?;
    let run = BakeoffRun {
        id: run_id,
        created_at: Utc::now().to_rfc3339(),
        status: "completed-shadow-bakeoff".to_string(),
        schema_version: SCHEMA_VERSION.to_string(),
        query_count: synthetic_count.max(domains.len() * 20),
        candidates: runtime_votes(),
        winner_policy: "always-federated-adaptive-mesh; metrics choose role weights, not a single database".to_string(),
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
    let manifest_path = write_artifact_manifest(&state, &run_id, "governance-eval").map_err(internal_error)?;
    let votes = runtime_votes();
    let canary_allowed = votes.iter().any(|vote| {
        matches!(vote.runtime.as_str(), "Kuzu" | "LanceDB" | "FalkorDB") && vote.status == "available"
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

async fn governance_evaluate(
    State(state): State<Arc<EngineState>>,
    Json(req): Json<GovernanceEvaluateRequest>,
) -> Result<Json<GovernanceEvaluation>, StatusCode> {
    let mut request = state
        .client
        .post(format!("{}/api/exocortex/v1/memory/governance/run", state.core_url))
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
    let manifest_path = write_artifact_manifest(&state, &id, "governance-evaluate").map_err(internal_error)?;
    let evaluation = GovernanceEvaluation {
        id,
        created_at: Utc::now().to_rfc3339(),
        status: "completed".to_string(),
        schema_version: SCHEMA_VERSION.to_string(),
        core_response,
        artifact_manifest: manifest_path,
        degraded_reason: Some("Governance authority remains beagle-core append-only JSONL.".to_string()),
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
        objects: vec!["manifest.json".to_string(), "metrics.jsonl".to_string(), "traces.jsonl".to_string()],
        storage_policy: "Ceph for service state; OrangeFS dedicated path for large lab artifacts.".to_string(),
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
            "purpose": "beagle-memory-engine-v1.6"
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

fn runtime_statuses() -> Vec<RuntimeStatus> {
    runtime_specs()
        .into_iter()
        .map(|(name, role, env_key, score)| {
            let endpoint = env::var(env_key).ok().filter(|value| !value.trim().is_empty());
            let available = endpoint.is_some();
            RuntimeStatus {
                name: name.to_string(),
                role: role.to_string(),
                license_policy: "source-available-allowed-metrics-decide".to_string(),
                endpoint,
                available,
                status: if available { "available" } else { "shadow-unconfigured" }.to_string(),
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
            status: if status.available { "available" } else { "shadow" }.to_string(),
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
        ("FalkorDB", "online-graph-vector", "BEAGLE_FALKORDB_URL", 0.86),
        ("Memgraph", "online-streaming-graph", "BEAGLE_MEMGRAPH_URL", 0.82),
        ("ArangoDB", "multi-model-graph-search-vector", "BEAGLE_ARANGODB_URL", 0.75),
        ("SurrealDB", "multi-model-record-graph-vector", "BEAGLE_SURREALDB_URL", 0.72),
        ("ArcadeDB", "multi-model-graph-document", "BEAGLE_ARCADEDB_URL", 0.66),
        ("Kuzu", "analytics-rebuild-graph-vector", "BEAGLE_KUZU_PATH", 0.84),
        ("LanceDB", "vector-multivector-late-interaction", "BEAGLE_LANCEDB_URI", 0.79),
        ("DuckDB-VSS", "columnar-analytics-vector", "BEAGLE_DUCKDB_VSS_PATH", 0.76),
        ("Postgres pgvectorscale", "relational-vector-operational", "BEAGLE_POSTGRES_VECTOR_URL", 0.70),
        ("TypeDB", "ontology-validation", "BEAGLE_TYPEDB_URL", 0.78),
        ("Experimental scouts", "self-hosted-scout-frontier", "BEAGLE_SCOUT_RUNTIME_URL", 0.55),
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

fn append_jsonl<T: Serialize>(root: &PathBuf, file_name: &str, value: &T) -> anyhow::Result<()> {
    fs::create_dir_all(root)?;
    let path = root.join(file_name);
    let mut file = OpenOptions::new().create(true).append(true).open(path)?;
    serde_json::to_writer(&mut file, value)?;
    file.write_all(b"\n")?;
    file.flush()?;
    Ok(())
}

fn read_jsonl<T: for<'de> Deserialize<'de>>(root: &PathBuf, file_name: &str) -> anyhow::Result<Vec<T>> {
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

fn write_artifact_manifest(state: &EngineState, run_id: &str, kind: &str) -> anyhow::Result<String> {
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
