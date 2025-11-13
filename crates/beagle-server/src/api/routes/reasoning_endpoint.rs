use axum::{extract::State, http::StatusCode, Json};
use beagle_agents::ReasoningPath;
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ReasoningRequest {
    source: String,
    target: String,
    #[serde(default = "default_max_hops")]
    max_hops: usize,
}

fn default_max_hops() -> usize {
    3
}

#[derive(Debug, Serialize)]
pub struct ReasoningResponse {
    paths: Vec<ReasoningPath>,
    visualization: String,
}

pub async fn reasoning(
    State(state): State<AppState>,
    Json(req): Json<ReasoningRequest>,
) -> Result<Json<ReasoningResponse>, (StatusCode, String)> {
    info!("🕸️ /dev/reasoning - {} → {}", req.source, req.target);

    let reasoner = state.hypergraph_reasoner().ok_or((
        StatusCode::SERVICE_UNAVAILABLE,
        "Reasoner not available".to_string(),
    ))?;

    let paths = reasoner
        .find_reasoning_paths(&req.source, &req.target, req.max_hops)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let visualization = reasoner.visualize_paths(&paths);

    info!("✅ Found {} reasoning paths", paths.len());

    Ok(Json(ReasoningResponse {
        paths,
        visualization,
    }))
}


