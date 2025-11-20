//! API Server do BEAGLE Core
//!
//! Endpoint: POST /api/llm/complete
//! Usa TieredRouter com Grok 3 como Tier 1

use axum::{routing::post, Router, Json};
use beagle_core::BeagleContext;
use beagle_config::load as load_config;
use beagle_llm::RequestMeta;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::info;

#[derive(Deserialize)]
struct LlmRequest {
    prompt: String,
    #[serde(default)]
    requires_math: bool,
    #[serde(default)]
    requires_high_quality: bool,
    #[serde(default)]
    offline_required: bool,
}

#[derive(Serialize)]
struct LlmResponse {
    text: String,
    provider: String,
    tier: String,
}

async fn llm_complete_handler(
    axum::extract::State(ctx): axum::extract::State<Arc<Mutex<BeagleContext>>>,
    Json(req): Json<LlmRequest>,
) -> Result<Json<LlmResponse>, axum::http::StatusCode> {
    let ctx = ctx.lock().await;
    
    let meta = RequestMeta {
        requires_math: req.requires_math,
        requires_high_quality: req.requires_high_quality,
        offline_required: req.offline_required,
        requires_vision: false,
        approximate_tokens: req.prompt.len() / 4,
    };

    let client = ctx.router.choose(&meta);
    let tier = client.tier();
    
    let text = client
        .complete(&req.prompt)
        .await
        .map_err(|e| {
            tracing::error!("LLM error: {}", e);
            axum::http::StatusCode::BAD_GATEWAY
        })?;

    Ok(Json(LlmResponse {
        text,
        provider: client.name().to_string(),
        tier: tier.as_str().to_string(),
    }))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let cfg = load_config();
    let ctx = Arc::new(Mutex::new(BeagleContext::new(cfg).await?));

    let app = Router::new()
        .route("/api/llm/complete", post(llm_complete_handler))
        .with_state(ctx);

    let addr: std::net::SocketAddr = "0.0.0.0:8080".parse().unwrap();
    info!("🚀 BEAGLE Core API rodando em http://{}", addr);
    info!("   Endpoint: POST /api/llm/complete");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

