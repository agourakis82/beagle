//! Rotas de exportação Prometheus para observabilidade operacional.

use axum::{routing::get, Router};

use crate::{error::ApiError, metrics, state::AppState};

/// Constrói o sub-roteador que expõe `/metrics`.
pub fn router() -> Router<AppState> {
    Router::new().route("/metrics", get(metrics_endpoint))
}

async fn metrics_endpoint() -> Result<impl axum::response::IntoResponse, ApiError> {
    metrics::metrics_handler().await
}
