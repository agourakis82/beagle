use axum::{extract::State, http::StatusCode, Json};
use beagle_agents::{CausalGraph, InterventionResult};
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct CausalExtractionRequest {
    text: String,
}

#[derive(Debug, Deserialize)]
pub struct InterventionRequest {
    graph: CausalGraph,
    variable: String,
    value: String,
}

#[derive(Debug, Serialize)]
pub struct CausalExtractionResponse {
    graph: CausalGraph,
    visualization: String,
}

pub async fn extract_causal_graph(
    State(state): State<AppState>,
    Json(req): Json<CausalExtractionRequest>,
) -> Result<Json<CausalExtractionResponse>, (StatusCode, String)> {
    info!("🔗 /dev/causal/extract - {} chars", req.text.len());

    let reasoner = state
        .causal_reasoner()
        .ok_or((
            StatusCode::SERVICE_UNAVAILABLE,
            "Causal reasoner not available".to_string(),
        ))?;

    let graph = reasoner
        .extract_causal_graph(&req.text)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let visualization = reasoner.visualize_graph(&graph);

    info!(
        "✅ Extracted graph: {} nodes, {} edges",
        graph.nodes.len(),
        graph.edges.len()
    );

    Ok(Json(CausalExtractionResponse {
        graph,
        visualization,
    }))
}

pub async fn intervention(
    State(state): State<AppState>,
    Json(req): Json<InterventionRequest>,
) -> Result<Json<InterventionResult>, (StatusCode, String)> {
    info!("🔬 /dev/causal/intervention - do({} = {})", req.variable, req.value);

    let reasoner = state
        .causal_reasoner()
        .ok_or((
            StatusCode::SERVICE_UNAVAILABLE,
            "Causal reasoner not available".to_string(),
        ))?;

    let result = reasoner
        .intervention(&req.graph, &req.variable, &req.value)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    info!("✅ Intervention analysis complete");

    Ok(Json(result))
}


