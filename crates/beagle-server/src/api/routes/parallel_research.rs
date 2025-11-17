//! Parallel research endpoint using CoordinatorAgent

use axum::{extract::State, http::StatusCode, Json};
use beagle_agents::ResearchResult;
use serde::{Deserialize, Serialize};
use tracing::{error, info};
use uuid::Uuid;

use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ParallelResearchRequest {
    query: String,

    /// Optional session for conversation continuity
    #[serde(default)]
    session_id: Option<Uuid>,
}

#[derive(Debug, Serialize)]
pub struct ParallelResearchResponse {
    /// Final answer
    answer: String,

    /// Domain detected
    domain: String,

    /// Research steps taken (parallel execution)
    steps: Vec<ResearchStepResponse>,

    /// Performance metrics
    metrics: MetricsResponse,

    /// Execution mode
    mode: String,
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
    quality_score: f32,
}

pub async fn parallel_research(
    State(state): State<AppState>,
    Json(req): Json<ParallelResearchRequest>,
) -> Result<Json<ParallelResearchResponse>, (StatusCode, String)> {
    info!("🚀 /dev/research/parallel - query: {}", req.query);

    // Get coordinator agent
    let agent = state.coordinator_agent().ok_or((
        StatusCode::SERVICE_UNAVAILABLE,
        "Coordinator Agent not available".to_string(),
    ))?;

    // Execute parallel research
    let result: ResearchResult = agent
        .research(&req.query, req.session_id)
        .await
        .map_err(|e| {
            error!("❌ Parallel research failed: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
        })?;

    info!(
        "✅ Parallel research complete: {} steps, {} LLM calls ({}ms total)",
        result.steps.len(),
        result.metrics.llm_calls,
        result.metrics.total_duration_ms
    );

    // Convert to response
    Ok(Json(ParallelResearchResponse {
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
            quality_score: result.metrics.quality_score,
        },
        mode: "PARALLEL".to_string(),
    }))
}
