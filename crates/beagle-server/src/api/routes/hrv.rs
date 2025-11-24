//! HRV Endpoint - Recebe métricas do Apple Watch e ajusta loop metacognitivo

use crate::state::AppState;
use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use beagle_config::{compute_gain_from_hrv, HrvControlConfig};
use beagle_physio::{integrate_physio_metrics, speed_control};
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

/// Request do Apple Watch
#[derive(Debug, Deserialize)]
pub struct HRVRequest {
    pub hrv: f64,
    pub state: String,
    pub timestamp: f64,
}

/// Response do endpoint
#[derive(Debug, Serialize)]
pub struct HRVResponse {
    pub status: String,
    pub speed_multiplier: f64,
}

/// Handler para receber HRV do Apple Watch
#[axum::debug_handler]
pub async fn hrv_endpoint(
    State(_state): State<AppState>,
    Json(payload): Json<HRVRequest>,
) -> Result<Json<HRVResponse>, StatusCode> {
    info!(
        "📊 HRV recebido: {:.1} ms — Estado: {}",
        payload.hrv, payload.state
    );

    // Integra no módulo de métricas fisiológicas
    let _physio_state = integrate_physio_metrics(payload.hrv, 0.0, 0.0)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Calcula gain baseado em HRV usando beagle-config (com SAFE_MODE clamp)
    let hrv_cfg = HrvControlConfig::from_env();
    let speed_multiplier = compute_gain_from_hrv(payload.hrv as f32, Some(hrv_cfg.clone())) as f64;

    // Aplica multiplicador no speed control
    speed_control::set_global_speed_multiplier(speed_multiplier);

    // Log baseado no estado recebido
    match payload.state.as_str() {
        "FLOW" => {
            info!(
                "🚀 Acelerando loop (FLOW) — HRV={:.1}ms → multiplicador: {:.2}x",
                payload.hrv, speed_multiplier
            );
        }
        "STRESS" => {
            warn!(
                "⏸️  Desacelerando loop (STRESS) — HRV={:.1}ms → multiplicador: {:.2}x",
                payload.hrv, speed_multiplier
            );
        }
        _ => {
            info!(
                "📊 Ajustando loop (NORMAL) — HRV={:.1}ms → multiplicador: {:.2}x",
                payload.hrv, speed_multiplier
            );
        }
    }

    Ok(Json(HRVResponse {
        status: "HRV OK".to_string(),
        speed_multiplier,
    }))
}

// Funções de velocidade exportadas via beagle-physio::speed_control

pub fn router() -> Router<AppState> {
    Router::new().route("/api/hrv", post(hrv_endpoint))
}
