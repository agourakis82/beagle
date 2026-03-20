use crate::http::AppState;
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use beagle_darwin::{
    read_recent_ledger_entries, BridgeHealth, BridgeLedgerEntry, BridgeProviderInfo, BridgeRequest,
    BridgeResponse, BridgeStatus, DarwinHpcGatewayClient, DarwinHpcGatewayError, HpcJobStatus,
    HpcProfile, HpcProfileCatalog, HpcSubmitRequest, HpcSubmitResponse, HpcTextArtifact,
    JobArtifactManifest, ObjectResultManifest, ResultCatalogEntry, ResultCatalogQuery,
    ResultCatalogResponse, ToolBridge,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::path::Path as FsPath;
use tracing::error;

type JsonError = (StatusCode, Json<Value>);

pub fn darwin_hpc_routes() -> Router<AppState> {
    Router::new()
        .route("/api/darwin/hpc/control", get(hpc_control_handler))
        .route("/api/darwin/hpc/profiles", get(hpc_profiles_handler))
        .route("/api/darwin/hpc/jobs/submit", post(hpc_job_submit_handler))
        .route("/api/darwin/hpc/jobs/:job_id", get(hpc_job_status_handler))
        .route(
            "/api/darwin/hpc/jobs/:job_id/artifact-manifest",
            get(hpc_job_manifest_handler),
        )
        .route("/api/darwin/hpc/jobs/:job_id/stdout", get(hpc_job_stdout_handler))
        .route("/api/darwin/hpc/jobs/:job_id/stderr", get(hpc_job_stderr_handler))
        .route("/api/darwin/hpc/results", get(hpc_results_handler))
        .route("/api/darwin/hpc/results/:job_id", get(hpc_result_lookup_handler))
        .route(
            "/api/darwin/hpc/results/:job_id/manifest",
            get(hpc_result_manifest_handler),
        )
        .route("/api/darwin/bridge/execute", post(bridge_execute_handler))
        .route("/api/darwin/bridge/health", get(bridge_health_handler))
        .route("/api/darwin/bridge/providers", get(bridge_providers_handler))
}

#[derive(Debug, Deserialize)]
struct ResultsQueryParams {
    #[serde(default)]
    profile_id: Option<String>,
    #[serde(default)]
    run_label: Option<String>,
    #[serde(default)]
    state: Option<String>,
    #[serde(default)]
    node_list: Option<String>,
}

#[derive(Debug, Serialize)]
struct HpcControlSurfaceSummary {
    status: String,
    gateway_base_url: String,
    profiles: Vec<HpcProfile>,
    recent_results: Vec<ResultCatalogEntry>,
    bridge_health: BridgeHealth,
    bridge_providers: Vec<BridgeProviderInfo>,
    recent_bridge_ledger: Vec<BridgeLedgerEntry>,
}

async fn hpc_control_handler(
    State(state): State<AppState>,
) -> Result<Json<HpcControlSurfaceSummary>, JsonError> {
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let gateway = gateway_client()?;
    let bridge = tool_bridge_from_cfg(&cfg)?;

    let profiles = gateway
        .profiles()
        .await
        .map_err(gateway_error_response)?
        .profiles;

    let results = gateway
        .results(&ResultCatalogQuery::default())
        .await
        .map_err(gateway_error_response)?;

    let recent_bridge_ledger = read_recent_ledger_entries(data_dir, 10).map_err(|error| {
        internal_error_response("bridge_ledger_read_failed", error.to_string())
    })?;

    Ok(Json(HpcControlSurfaceSummary {
        status: "ok".to_string(),
        gateway_base_url: gateway.base_url().to_string(),
        profiles,
        recent_results: results.results.into_iter().take(5).collect(),
        bridge_health: bridge.health(),
        bridge_providers: bridge.providers(),
        recent_bridge_ledger,
    }))
}

async fn hpc_profiles_handler(
    State(_state): State<AppState>,
) -> Result<Json<HpcProfileCatalog>, JsonError> {
    let gateway = gateway_client()?;
    gateway
        .profiles()
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_job_submit_handler(
    State(_state): State<AppState>,
    Json(request): Json<HpcSubmitRequest>,
) -> Result<Json<HpcSubmitResponse>, JsonError> {
    let gateway = gateway_client()?;
    gateway
        .submit_job(&request)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_job_status_handler(
    State(_state): State<AppState>,
    Path(job_id): Path<u64>,
) -> Result<Json<HpcJobStatus>, JsonError> {
    let gateway = gateway_client()?;
    gateway
        .job_status(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_job_manifest_handler(
    State(_state): State<AppState>,
    Path(job_id): Path<u64>,
) -> Result<Json<JobArtifactManifest>, JsonError> {
    let gateway = gateway_client()?;
    gateway
        .job_artifact_manifest(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_job_stdout_handler(
    State(_state): State<AppState>,
    Path(job_id): Path<u64>,
) -> Result<Json<HpcTextArtifact>, JsonError> {
    let gateway = gateway_client()?;
    gateway
        .job_stdout(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_job_stderr_handler(
    State(_state): State<AppState>,
    Path(job_id): Path<u64>,
) -> Result<Json<HpcTextArtifact>, JsonError> {
    let gateway = gateway_client()?;
    gateway
        .job_stderr(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_results_handler(
    State(_state): State<AppState>,
    Query(query): Query<ResultsQueryParams>,
) -> Result<Json<ResultCatalogResponse>, JsonError> {
    let gateway = gateway_client()?;
    let query = ResultCatalogQuery {
        profile_id: query.profile_id,
        run_label: query.run_label,
        state: query.state,
        node_list: query.node_list,
    };

    gateway
        .results(&query)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_result_lookup_handler(
    State(_state): State<AppState>,
    Path(job_id): Path<u64>,
) -> Result<Json<ResultCatalogEntry>, JsonError> {
    let gateway = gateway_client()?;
    gateway
        .result_by_job(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_result_manifest_handler(
    State(_state): State<AppState>,
    Path(job_id): Path<u64>,
) -> Result<Json<ObjectResultManifest>, JsonError> {
    let gateway = gateway_client()?;
    gateway
        .result_manifest(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn bridge_health_handler(State(state): State<AppState>) -> Json<BridgeHealth> {
    let cfg = current_cfg(&state).await;

    match ToolBridge::from_config(&cfg) {
        Ok(bridge) => Json(bridge.health()),
        Err(error) => {
            error!("failed to initialize tool bridge for health: {}", error);
            Json(BridgeHealth {
                status: "error".to_string(),
                safe_mode: cfg.safe_mode,
                dry_run: cfg.tool_bridge.dry_run,
                ledger_enabled: cfg.tool_bridge.ledger_enabled,
                data_dir: cfg.storage.data_dir,
                implemented_providers: 0,
                configured_providers: 0,
            })
        }
    }
}

async fn bridge_providers_handler(
    State(state): State<AppState>,
) -> Json<Vec<BridgeProviderInfo>> {
    let cfg = current_cfg(&state).await;

    match ToolBridge::from_config(&cfg) {
        Ok(bridge) => Json(bridge.providers()),
        Err(error) => {
            error!("failed to initialize tool bridge for providers: {}", error);
            Json(Vec::new())
        }
    }
}

async fn bridge_execute_handler(
    State(state): State<AppState>,
    Json(request): Json<BridgeRequest>,
) -> Json<BridgeResponse> {
    let cfg = current_cfg(&state).await;

    match ToolBridge::from_config(&cfg) {
        Ok(bridge) => Json(bridge.execute(request).await),
        Err(error) => {
            error!("failed to initialize tool bridge for execute: {}", error);
            Json(BridgeResponse {
                request_id: request.request_id,
                provider: request.provider,
                model: request.model,
                status: BridgeStatus::Error,
                latency_ms: 0,
                token_usage: None,
                estimated_cost_usd: None,
                output: json!({}),
                error: Some(format!("tool bridge init failed: {}", error)),
                warnings: vec![],
            })
        }
    }
}

async fn current_cfg(state: &AppState) -> beagle_config::BeagleConfig {
    let ctx = state.ctx.lock().await;
    ctx.cfg.clone()
}

fn gateway_client() -> Result<DarwinHpcGatewayClient, JsonError> {
    DarwinHpcGatewayClient::from_env().map_err(|error| {
        internal_error_response("darwin_hpc_gateway_init_failed", error.to_string())
    })
}

fn tool_bridge_from_cfg(cfg: &beagle_config::BeagleConfig) -> Result<ToolBridge, JsonError> {
    ToolBridge::from_config(cfg)
        .map_err(|error| internal_error_response("tool_bridge_init_failed", error.to_string()))
}

fn gateway_error_response(error: DarwinHpcGatewayError) -> JsonError {
    let status = error
        .status_code
        .and_then(|code| StatusCode::from_u16(code).ok())
        .unwrap_or(StatusCode::BAD_GATEWAY);

    (
        status,
        Json(json!({
            "error": "darwin_hpc_gateway_error",
            "detail": error.message,
        })),
    )
}

fn internal_error_response(code: &str, detail: String) -> JsonError {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(json!({
            "error": code,
            "detail": detail,
        })),
    )
}
