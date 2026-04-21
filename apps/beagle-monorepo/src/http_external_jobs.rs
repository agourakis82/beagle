// http_external_jobs.rs
//
// Ingest endpoints for externally-managed jobs (cockpit reconciler).
// Cockpit owns the K8s/Slurm job lifecycle; beagle owns the cognitive
// aggregator (`/api/v1/cognitive/state`). These two routes are the thin
// bridge: cockpit's reconciler POSTs state transitions here, they land in
// ScienceJobRegistry, and the aggregator surfaces them unchanged.

use crate::http::AppState;
use crate::jobs::ScienceJobStatus;
use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
pub struct ExternalRegisterRequest {
    pub job_id: String,
    /// Free-form kind label (e.g. preset slug "sounio-test-suite").
    pub kind: String,
    /// One of: "created" | "running" | "done" | "error".
    pub status: String,
    #[serde(default)]
    pub started_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Deserialize)]
pub struct ExternalCompleteRequest {
    pub job_id: String,
    pub kind: String,
    /// One of: "done" | "error".
    pub status: String,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub exit_code: Option<i32>,
}

#[derive(Serialize)]
pub struct ExternalAck {
    pub ok: bool,
    pub job_id: String,
    pub truth_mode: &'static str,
}

fn parse_status(raw: &str, error: Option<String>) -> Result<ScienceJobStatus, String> {
    match raw.to_ascii_lowercase().as_str() {
        "created" | "pending" => Ok(ScienceJobStatus::Created),
        "running" => Ok(ScienceJobStatus::Running),
        "done" | "succeeded" | "success" => Ok(ScienceJobStatus::Done),
        "error" | "failed" | "failure" => {
            Ok(ScienceJobStatus::Error(error.unwrap_or_else(|| "failed".into())))
        }
        other => Err(format!("unknown status: {}", other)),
    }
}

async fn register_handler(
    State(state): State<AppState>,
    Json(req): Json<ExternalRegisterRequest>,
) -> Result<Json<ExternalAck>, (StatusCode, String)> {
    let status = parse_status(&req.status, req.error.clone())
        .map_err(|e| (StatusCode::BAD_REQUEST, e))?;
    state
        .science_jobs
        .register_external(req.job_id.clone(), req.kind, status, req.started_at)
        .await;
    Ok(Json(ExternalAck {
        ok: true,
        job_id: req.job_id,
        truth_mode: "observed",
    }))
}

async fn complete_handler(
    State(state): State<AppState>,
    Json(req): Json<ExternalCompleteRequest>,
) -> Result<Json<ExternalAck>, (StatusCode, String)> {
    let err_msg = req.error.clone().or_else(|| {
        req.exit_code
            .filter(|c| *c != 0)
            .map(|c| format!("exit_code={}", c))
    });
    let status = parse_status(&req.status, err_msg.clone())
        .map_err(|e| (StatusCode::BAD_REQUEST, e))?;
    state
        .science_jobs
        .complete_external(req.job_id.clone(), req.kind, status, err_msg)
        .await;
    Ok(Json(ExternalAck {
        ok: true,
        job_id: req.job_id,
        truth_mode: "observed",
    }))
}

pub fn external_jobs_routes() -> Router<AppState> {
    Router::new()
        .route("/api/jobs/external/register", post(register_handler))
        .route("/api/jobs/external/complete", post(complete_handler))
}
