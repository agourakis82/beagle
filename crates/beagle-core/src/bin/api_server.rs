//! API Server do BEAGLE Core
//!
//! Endpoint: POST /api/llm/complete
//! Usa TieredRouter com Grok 3 como Tier 1

use axum::{
    routing::{get, post},
    Json, Router,
};
use beagle_config::load as load_config;
use beagle_core::BeagleContext;
use beagle_llm::{ProviderTier, RequestMeta};
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

async fn health_handler(
    axum::extract::State(ctx): axum::extract::State<Arc<Mutex<BeagleContext>>>,
) -> Json<serde_json::Value> {
    let ctx = ctx.lock().await;
    let cfg = &ctx.cfg;
    let has_xai_key = cfg.llm.xai_api_key.is_some();

    Json(serde_json::json!({
        "status": "ok",
        "service": "beagle-core",
        "profile": cfg.profile,
        "safe_mode": cfg.safe_mode,
        "data_dir": cfg.storage.data_dir,
        "xai_api_key_present": has_xai_key,
    }))
}

async fn llm_complete_handler(
    axum::extract::State(ctx): axum::extract::State<Arc<Mutex<BeagleContext>>>,
    Json(req): Json<LlmRequest>,
) -> Result<Json<LlmResponse>, axum::http::StatusCode> {
    let mut ctx = ctx.lock().await;

    // Cria RequestMeta com heurísticas
    let mut meta = RequestMeta::from_prompt(&req.prompt);

    // Override com flags explícitas
    if req.requires_math {
        meta.requires_math = true;
    }
    if req.requires_high_quality {
        meta.requires_high_quality = true;
    }
    if req.offline_required {
        meta.offline_required = true;
    }

    // Usa run_id sintético para HTTP
    let run_id = "http_session";

    // Obtém stats atuais
    let current_stats = ctx.llm_stats.get_or_create(run_id);

    // Escolhe client com limites
    let (client, tier) = ctx.router.choose_with_limits(&meta, &current_stats);

    // Chama LLM
    let output = client.complete(&req.prompt).await.map_err(|e| {
        tracing::error!("LLM error: {}", e);
        axum::http::StatusCode::BAD_GATEWAY
    })?;

    // Atualiza stats
    ctx.llm_stats.update(run_id, |stats| {
        match tier {
            ProviderTier::Grok3 => {
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
            ProviderTier::Grok4Heavy => {
                stats.grok4_calls += 1;
                stats.grok4_tokens_in += output.tokens_in_est as u32;
                stats.grok4_tokens_out += output.tokens_out_est as u32;
            }
            _ => {
                // Outros tiers contam como Grok3 por enquanto
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
        }
    });

    Ok(Json(LlmResponse {
        text: output.text,
        provider: client.name().to_string(),
        tier: format!("{:?}", tier),
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
        .route("/health", get(health_handler))
        .with_state(ctx);

    let addr: std::net::SocketAddr = "0.0.0.0:8080".parse().unwrap();
    info!("🚀 BEAGLE Core API rodando em http://{}", addr);
    info!("   Endpoint: POST /api/llm/complete");
    info!("   Endpoint: GET /health");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
