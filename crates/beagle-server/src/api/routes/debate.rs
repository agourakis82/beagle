use axum::{extract::State, http::StatusCode, Json};
use beagle_agents::DebateTranscript;
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct DebateRequest {
    query: String,
}

#[derive(Debug, Serialize)]
pub struct DebateResponse {
    transcript: DebateTranscript,
}

pub async fn debate(
    State(state): State<AppState>,
    Json(req): Json<DebateRequest>,
) -> Result<Json<DebateResponse>, (StatusCode, String)> {
    info!("🥊 /dev/debate - query: {}", req.query);

    let orchestrator = state.debate_orchestrator().ok_or((
        StatusCode::SERVICE_UNAVAILABLE,
        "Debate not available".to_string(),
    ))?;

    let transcript = orchestrator.conduct_debate(&req.query).await.map_err(|e| {
        error!("Debate orchestration failure: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
    })?;

    info!("✅ Debate complete: {} rounds", transcript.rounds.len());

    Ok(Json(DebateResponse { transcript }))
}


