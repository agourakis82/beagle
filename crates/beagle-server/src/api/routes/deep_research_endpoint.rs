use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct DeepResearchRequest {
    query: String,
}

#[derive(Debug, Serialize)]
pub struct DeepResearchResponse {
    result: serde_json::Value,
}

pub async fn deep_research(
    State(state): State<AppState>,
    Json(req): Json<DeepResearchRequest>,
) -> Result<Json<DeepResearchResponse>, (StatusCode, String)> {
    info!("🔬 /dev/deep-research - query: {}", req.query);

    let engine = state.deep_research_engine().ok_or((
        StatusCode::SERVICE_UNAVAILABLE,
        "Deep Research not available".to_string(),
    ))?;

    let result = engine
        .deep_research(&req.query)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    info!("✅ Deep research complete: {} tree nodes", result.tree_size);

    // Serialize manually since DeepResearchResult may not implement Serialize
    let result_json = serde_json::json!({
        "tree_size": result.tree_size,
        "best_hypothesis": result.best_hypothesis.content,
        "iterations": result.iterations,
    });

    Ok(Json(DeepResearchResponse {
        result: result_json,
    }))
}
