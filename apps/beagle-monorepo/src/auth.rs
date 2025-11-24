//! API Token Authentication Middleware
//!
//! Implementa autenticação via Bearer token para proteger endpoints sensíveis.

use axum::{
    body::Body,
    extract::State,
    http::{Request, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{debug, warn};

use crate::http::AppState;

#[derive(Serialize)]
struct AuthErrorResponse {
    error: String,
    reason: String,
}

/// Middleware de autenticação via API token (Bearer)
///
/// Valida que o header `Authorization: Bearer <token>` corresponda ao
/// `BEAGLE_API_TOKEN` configurado.
///
/// Se `api_token` não estiver configurado (None):
/// - Em dev/lab: permite acesso mas loga WARNING
/// - Em prod: nunca deve acontecer (validado no load)
pub async fn api_token_auth(
    State(state): State<AppState>,
    mut req: Request<Body>,
    next: Next,
) -> Result<Response, StatusCode> {
    let ctx = state.ctx.lock().await;

    // Se não há token configurado, permite acesso (com warning em dev)
    let Some(ref expected_token) = ctx.cfg.api_token else {
        if ctx.cfg.profile != "prod" {
            warn!(
                "API token não configurado no profile '{}' - acesso permitido sem autenticação",
                ctx.cfg.profile
            );
        }
        drop(ctx); // Release lock antes de chamar next
        return Ok(next.run(req).await);
    };

    // Extrai header Authorization
    let auth_header = req
        .headers()
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .unwrap_or("");

    // Valida formato Bearer <token>
    let expected = format!("Bearer {}", expected_token);

    if auth_header != expected {
        debug!(
            "Auth failed: expected '{}', got '{}'",
            if expected_token.len() > 8 {
                format!("Bearer {}...", &expected_token[..8])
            } else {
                "Bearer <token>".to_string()
            },
            if auth_header.len() > 20 {
                format!("{}...", &auth_header[..20])
            } else {
                auth_header.to_string()
            }
        );

        drop(ctx); // Release lock

        return Err(StatusCode::UNAUTHORIZED);
    }

    drop(ctx); // Release lock antes de chamar next
    Ok(next.run(req).await)
}

/// Handler de erro customizado para retornar JSON em vez de texto plano
pub async fn auth_error_handler(status: StatusCode) -> impl IntoResponse {
    if status == StatusCode::UNAUTHORIZED {
        (
            StatusCode::UNAUTHORIZED,
            Json(AuthErrorResponse {
                error: "unauthorized".to_string(),
                reason: "invalid or missing API token".to_string(),
            }),
        )
    } else {
        (
            status,
            Json(AuthErrorResponse {
                error: "error".to_string(),
                reason: format!("HTTP {}", status.as_u16()),
            }),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{JobRegistry, ScienceJobRegistry};
    use axum::{
        body::Body,
        http::{Request, StatusCode},
        middleware,
        routing::get,
        Router,
    };
    use beagle_config::BeagleConfig;
    use beagle_core::BeagleContext;
    use beagle_observer::UniversalObserver;
    use tower::ServiceExt; // for `oneshot`

    async fn dummy_handler() -> &'static str {
        "ok"
    }

    fn create_test_state(api_token: Option<String>, profile: &str) -> AppState {
        let mut cfg = BeagleConfig {
            profile: profile.to_string(),
            safe_mode: true,
            api_token,
            llm: Default::default(),
            storage: beagle_config::model::StorageConfig {
                data_dir: beagle_config::beagle_data_dir()
                    .to_string_lossy()
                    .to_string(),
            },
            graph: Default::default(),
            hermes: Default::default(),
            advanced: Default::default(),
            observer: Default::default(),
        };

        let ctx = BeagleContext {
            cfg,
            router: beagle_llm::TieredRouter::new(Default::default()),
            llm_stats: beagle_llm::LlmStatsRegistry::new(),
        };

        AppState {
            ctx: Arc::new(Mutex::new(ctx)),
            jobs: Arc::new(JobRegistry::new()),
            science_jobs: Arc::new(ScienceJobRegistry::new()),
            observer: Arc::new(UniversalObserver::new().unwrap()),
        }
    }

    #[tokio::test]
    async fn test_auth_with_valid_token() {
        let state = create_test_state(Some("test-secret-token".to_string()), "dev");

        let app = Router::new()
            .route("/test", get(dummy_handler))
            .route_layer(middleware::from_fn_with_state(
                state.clone(),
                api_token_auth,
            ))
            .with_state(state);

        let req = Request::builder()
            .uri("/test")
            .header("Authorization", "Bearer test-secret-token")
            .body(Body::empty())
            .unwrap();

        let response = app.oneshot(req).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_auth_with_invalid_token() {
        let state = create_test_state(Some("test-secret-token".to_string()), "dev");

        let app = Router::new()
            .route("/test", get(dummy_handler))
            .route_layer(middleware::from_fn_with_state(
                state.clone(),
                api_token_auth,
            ))
            .with_state(state);

        let req = Request::builder()
            .uri("/test")
            .header("Authorization", "Bearer wrong-token")
            .body(Body::empty())
            .unwrap();

        let response = app.oneshot(req).await.unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn test_auth_without_header() {
        let state = create_test_state(Some("test-secret-token".to_string()), "dev");

        let app = Router::new()
            .route("/test", get(dummy_handler))
            .route_layer(middleware::from_fn_with_state(
                state.clone(),
                api_token_auth,
            ))
            .with_state(state);

        let req = Request::builder().uri("/test").body(Body::empty()).unwrap();

        let response = app.oneshot(req).await.unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn test_auth_with_no_token_configured_dev() {
        let state = create_test_state(None, "dev");

        let app = Router::new()
            .route("/test", get(dummy_handler))
            .route_layer(middleware::from_fn_with_state(
                state.clone(),
                api_token_auth,
            ))
            .with_state(state);

        let req = Request::builder().uri("/test").body(Body::empty()).unwrap();

        let response = app.oneshot(req).await.unwrap();
        // Sem token configurado em dev, permite acesso
        assert_eq!(response.status(), StatusCode::OK);
    }
}
