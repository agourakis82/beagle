use crate::http::AppState;
use axum::{extract::State, routing::{get, post}, Json, Router};
use beagle_darwin::{BridgeHealth, BridgeProviderInfo, BridgeRequest, BridgeResponse, ToolBridge};
use tracing::error;

pub fn darwin_hpc_routes() -> Router<AppState> {
    Router::new()
        .route("/api/darwin/bridge/execute", post(bridge_execute_handler))
        .route("/api/darwin/bridge/health", get(bridge_health_handler))
        .route("/api/darwin/bridge/providers", get(bridge_providers_handler))
}

async fn bridge_health_handler(
    State(state): State<AppState>,
) -> Json<BridgeHealth> {
    let cfg = {
        let ctx = state.ctx.lock().await;
        ctx.cfg.clone()
    };

    match ToolBridge::from_config(&cfg) {
        Ok(bridge) => Json(bridge.health()),
        Err(error) => {
            error!("failed to initialize tool bridge for health: {}", error);
            Json(BridgeHealth {
                status: "error".to_string(),
                safe_mode: cfg.safe_mode,
                dry_run: cfg.tool_bridge.dry_run,
                ledger_enabled: cfg.tool_bridge.ledger_enabled,
                data_dir: cfg.storage.data_dir,
                implemented_providers: 0,
                configured_providers: 0,
            })
        }
    }
}

async fn bridge_providers_handler(
    State(state): State<AppState>,
) -> Json<Vec<BridgeProviderInfo>> {
    let cfg = {
        let ctx = state.ctx.lock().await;
        ctx.cfg.clone()
    };

    match ToolBridge::from_config(&cfg) {
        Ok(bridge) => Json(bridge.providers()),
        Err(error) => {
            error!("failed to initialize tool bridge for providers: {}", error);
            Json(Vec::new())
        }
    }
}

async fn bridge_execute_handler(
    State(state): State<AppState>,
    Json(request): Json<BridgeRequest>,
) -> Json<BridgeResponse> {
    let cfg = {
        let ctx = state.ctx.lock().await;
        ctx.cfg.clone()
    };

    match ToolBridge::from_config(&cfg) {
        Ok(bridge) => Json(bridge.execute(request).await),
        Err(error) => {
            error!("failed to initialize tool bridge for execute: {}", error);
            Json(BridgeResponse {
                request_id: request.request_id,
                provider: request.provider,
                model: request.model,
                status: beagle_darwin::BridgeStatus::Error,
                latency_ms: 0,
                token_usage: None,
                estimated_cost_usd: None,
                output: serde_json::json!({}),
                error: Some(format!("tool bridge init failed: {}", error)),
                warnings: vec![],
            })
        }
    }
}
