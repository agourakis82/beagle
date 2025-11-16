//! Research endpoint using ResearcherAgent

use axum::{extract::State, http::StatusCode, Json};
use beagle_agents::ResearchResult;
use serde::{Deserialize, Serialize};
use tracing::{error, info};
use uuid::Uuid;

use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ResearchRequest {
    query: String,

    /// Optional session for conversation continuity
    #[serde(default)]
    session_id: Option<Uuid>,
}

#[derive(Debug, Serialize)]
pub struct ResearchResponse {
    /// Final answer
    answer: String,

    /// Domain detected
    domain: String,

    /// Research steps taken
    steps: Vec<ResearchStepResponse>,

    /// Performance metrics
    metrics: MetricsResponse,

    /// Session used (or created)
    session_id: Option<Uuid>,
}

#[derive(Debug, Serialize)]
pub struct ResearchStepResponse {
    step_number: usize,
    action: String,
    result: String,
    duration_ms: u64,
}

#[derive(Debug, Serialize)]
pub struct MetricsResponse {
    total_duration_ms: u64,
    llm_calls: usize,
    context_chunks_retrieved: usize,
    refinement_iterations: usize,
    quality_score: f32,
}

pub async fn research(
    State(state): State<AppState>,
    Json(req): Json<ResearchRequest>,
) -> Result<Json<ResearchResponse>, (StatusCode, String)> {
    info!("🔬 /dev/research - query: {}", req.query);

    // Get researcher agent
    let agent = state.researcher_agent().ok_or((
        StatusCode::SERVICE_UNAVAILABLE,
        "Researcher Agent not available".to_string(),
    ))?;

    // Execute research
    let result: ResearchResult = agent
        .research(&req.query, req.session_id)
        .await
        .map_err(|e| {
            error!("❌ Research failed: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
        })?;

    info!(
        "✅ Research complete: {} steps, {} LLM calls, quality: {:.2}",
        result.steps.len(),
        result.metrics.llm_calls,
        result.metrics.quality_score
    );

    // Convert to response
    Ok(Json(ResearchResponse {
        answer: result.answer,
        domain: format!("{:?}", result.domain),
        steps: result
            .steps
            .into_iter()
            .map(|s| ResearchStepResponse {
                step_number: s.step_number,
                action: s.action,
                result: s.result,
                duration_ms: s.duration_ms,
            })
            .collect(),
        metrics: MetricsResponse {
            total_duration_ms: result.metrics.total_duration_ms,
            llm_calls: result.metrics.llm_calls,
            context_chunks_retrieved: result.metrics.context_chunks_retrieved,
            refinement_iterations: result.metrics.refinement_iterations,
            quality_score: result.metrics.quality_score,
        },
        session_id: Some(result.session_id),
    }))
}
