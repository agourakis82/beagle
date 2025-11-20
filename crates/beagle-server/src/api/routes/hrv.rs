//! HRV Endpoint - Recebe métricas do Apple Watch e ajusta loop metacognitivo

use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use beagle_physio::{integrate_physio_metrics, speed_control};
use crate::state::AppState;
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

    // Ajusta velocidade do loop global baseado no estado
    let speed_multiplier = match payload.state.as_str() {
        "FLOW" => {
            let multiplier = 1.5; // Acelera 50%
            speed_control::set_global_speed_multiplier(multiplier);
            info!("🚀 Acelerando loop (FLOW) — multiplicador: {:.1}x", multiplier);
            multiplier
        }
        "STRESS" => {
            let multiplier = 0.7; // Desacelera 30%
            speed_control::set_global_speed_multiplier(multiplier);
            warn!("⏸️  Desacelerando loop (STRESS) — multiplicador: {:.1}x", multiplier);
            multiplier
        }
        "NORMAL" => {
            let multiplier = 1.0; // Normal
            speed_control::set_global_speed_multiplier(multiplier);
            multiplier
        }
        _ => {
            let multiplier = 1.0;
            speed_control::set_global_speed_multiplier(multiplier);
            multiplier
        }
    };

    Ok(Json(HRVResponse {
        status: "HRV OK".to_string(),
        speed_multiplier,
    }))
}

// Funções de velocidade exportadas via beagle-physio::speed_control

pub fn router() -> Router<AppState> {
    Router::new().route("/api/hrv", post(hrv_endpoint))
}

