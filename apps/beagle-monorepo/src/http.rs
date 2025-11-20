use axum::{routing::post, Json, Router};
use axum::http::StatusCode;
use beagle_core::BeagleContext;
use beagle_llm::meta::RequestMeta;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::info;

#[derive(Deserialize)]
pub struct LlmRequest {
    pub prompt: String,
    #[serde(default)]
    pub requires_math: bool,
    #[serde(default)]
    pub requires_high_quality: bool,
    #[serde(default)]
    pub offline_required: bool,
}

#[derive(Serialize)]
pub struct LlmResponse {
    pub text: String,
    pub provider: String,
}

#[derive(Clone)]
pub struct AppState {
    pub ctx: Arc<Mutex<BeagleContext>>,
}

pub fn build_router(state: AppState) -> Router {
    Router::new()
        .route("/api/llm/complete", post(llm_complete_handler))
        .with_state(state)
}

async fn llm_complete_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<LlmRequest>,
) -> Result<Json<LlmResponse>, StatusCode> {
    let mut ctx = state.ctx.lock().await;

    let meta = RequestMeta {
        offline_required: req.offline_required,
        requires_math_proof: req.requires_math,
        estimated_tokens: req.prompt.len() / 4,
        high_bias_risk: req.requires_high_quality,
    };

    let client = ctx.router.choose(&meta);
    info!(
        requires_math = meta.requires_math_proof,
        requires_high_quality = meta.high_bias_risk,
        offline_required = meta.offline_required,
        "LLM request routed"
    );

    let text = client
        .complete(&req.prompt)
        .await
        .map_err(|_| StatusCode::BAD_GATEWAY)?;

    Ok(Json(LlmResponse {
        text,
        provider: "tiered-router".to_string(),
    }))
}
