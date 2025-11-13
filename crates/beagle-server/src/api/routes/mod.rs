//! Registro das rotas HTTP expostas.

use axum::Router;

use crate::state::AppState;

pub mod auth;
pub mod causal_endpoint;
pub mod chat;
pub mod chat_public;
pub mod debate;
pub mod dev;
pub mod health;
pub mod hyperedges;
pub mod metrics;
pub mod nodes;
pub mod parallel_research;
pub mod reasoning_endpoint;
pub mod research;
pub mod search;

/// Rotas de health-check.
pub fn health_routes() -> Router<AppState> {
    Router::new().merge(health::router())
}

/// Rotas de CRUD para nós.
pub fn node_routes() -> Router<AppState> {
    Router::new().merge(nodes::router())
}

/// Rotas de CRUD de hiperedges.
pub fn hyperedge_routes() -> Router<AppState> {
    Router::new().merge(hyperedges::router())
}

/// Rotas de busca e análises.
pub fn search_routes() -> Router<AppState> {
    Router::new().merge(search::router())
}

/// Rotas de autenticação.
pub fn auth_routes() -> Router<AppState> {
    Router::new().merge(auth::router())
}

/// Rotas de telemetria e métricas.
pub fn metrics_routes() -> Router<AppState> {
    Router::new().merge(metrics::router())
}

/// Rotas de chat com Vertex AI.
pub fn chat_routes() -> Router<AppState> {
    Router::new().merge(chat::router())
}

/// Rotas de chat públicas (sem autenticação).
pub fn chat_public_routes() -> Router<AppState> {
    Router::new().merge(chat_public::router())
}
