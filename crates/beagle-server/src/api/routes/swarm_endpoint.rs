use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct SwarmRequest {
    query: String,
}

#[derive(Debug, Serialize)]
pub struct SwarmResponse {
    consensus: Vec<String>,
    iterations: usize,
    n_agents: usize,
}

pub async fn swarm_explore(
    State(state): State<AppState>,
    Json(req): Json<SwarmRequest>,
) -> Result<Json<SwarmResponse>, (StatusCode, String)> {
    info!("🐝 /dev/swarm - query: {}", req.query);
    
    // Note: SwarmOrchestrator needs to be wrapped in Mutex in AppState for this to work properly
    // For now, we'll create a new orchestrator instance
    // TODO: Wrap SwarmOrchestrator in Mutex in AppState
    let llm = state.anthropic_client()
        .ok_or((StatusCode::SERVICE_UNAVAILABLE, "Anthropic client not available".to_string()))?;
    
    let mut orchestrator = beagle_agents::SwarmOrchestrator::new(20, llm);
    
    let result = orchestrator.explore(&req.query).await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    
    info!("✅ Swarm exploration complete: {} iterations", result.iterations);
    
    Ok(Json(SwarmResponse {
        consensus: result.consensus,
        iterations: result.iterations,
        n_agents: result.n_agents,
    }))
}

