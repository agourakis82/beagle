//! Endpoints de saúde e readiness do serviço.

use axum::{extract::State, routing::get, Json, Router};
use serde::Serialize;
use utoipa::ToSchema;

use beagle_hypergraph::StorageRepository;

use crate::{error::ApiError, state::AppState};

/// Resposta consolidada de saúde do serviço.
#[derive(Debug, Serialize, ToSchema)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    #[schema(example = "healthy")]
    pub database: String,
    #[schema(example = "healthy")]
    pub cache: String,
    #[schema(example = 1)]
    pub pool_size: u32,
    #[schema(example = 0)]
    pub pool_idle: usize,
    #[schema(example = 2)]
    pub db_latency_ms: u64,
}

/// Roteador com endpoints de saúde.
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/health", get(health_check))
        .route("/ready", get(readiness_check))
        .route("/live", get(liveness_check))
}

/// Verificação de saúde completa.
#[utoipa::path(
    get,
    path = "/health",
    responses(
        (status = 200, description = "Serviço saudável", body = HealthResponse),
        (status = 503, description = "Serviço degradado")
    )
)]
pub async fn health_check(State(state): State<AppState>) -> Result<Json<HealthResponse>, ApiError> {
    let health = state.storage.health_check().await.map_err(ApiError::from)?;

    let cache_status = state
        .storage
        .cache_stats()
        .await
        .map(|_| "healthy".to_string())
        .unwrap_or_else(|_| "unhealthy".to_string());

    let payload = HealthResponse {
        status: if health.healthy {
            "ok".into()
        } else {
            "degraded".into()
        },
        version: env!("CARGO_PKG_VERSION").into(),
        database: if health.healthy {
            "healthy".into()
        } else {
            "unhealthy".into()
        },
        cache: cache_status,
        pool_size: health.pool_size,
        pool_idle: health.idle_connections,
        db_latency_ms: health.latency_ms,
    };

    Ok(Json(payload))
}

/// Readiness probe (Kubernetes).
#[utoipa::path(
    get,
    path = "/ready",
    responses(
        (status = 200, description = "Serviço pronto"),
        (status = 503, description = "Serviço ainda inicializando")
    )
)]
pub async fn readiness_check() -> &'static str {
    "ready"
}

/// Liveness probe (Kubernetes).
#[utoipa::path(
    get,
    path = "/live",
    responses((status = 200, description = "Serviço em execução"))
)]
pub async fn liveness_check() -> &'static str {
    "alive"
}







