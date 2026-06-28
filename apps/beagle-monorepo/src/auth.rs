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
use beagle_darwin::{consumer_identity_for_id, ConsumerId};
use serde::Serialize;
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
    let auth_header = req
        .headers()
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .unwrap_or("");

    if ctx.cfg.consumers.policy_enabled {
        let consumer_header = req
            .headers()
            .get("X-Beagle-Consumer")
            .and_then(|h| h.to_str().ok())
            .unwrap_or("");

        let Some(consumer_id) = ConsumerId::from_header(consumer_header) else {
            warn!("consumer policy enabled but X-Beagle-Consumer is missing or invalid");
            drop(ctx);
            return Err(StatusCode::UNAUTHORIZED);
        };

        let identity = consumer_identity_for_id(consumer_id);
        let expected_token = match consumer_id {
            ConsumerId::BeagleOperator => ctx
                .cfg
                .consumers
                .operator_token
                .as_ref()
                .or(ctx.cfg.api_token.as_ref()),
            ConsumerId::DarwinResearch => ctx.cfg.consumers.research_token.as_ref(),
        };

        let Some(expected_token) = expected_token else {
            warn!(
                consumer = %identity.id,
                "consumer policy enabled but no token is configured for this consumer"
            );
            drop(ctx);
            return Err(StatusCode::UNAUTHORIZED);
        };

        let expected = format!("Bearer {}", expected_token);
        if auth_header != expected {
            debug!(
                consumer = %identity.id,
                "Auth failed for consumer-aware token validation"
            );
            drop(ctx);
            return Err(StatusCode::UNAUTHORIZED);
        }

        req.extensions_mut().insert(identity);
        drop(ctx);
        return Ok(next.run(req).await);
    }

    // Se não há token configurado, permite acesso (com warning em dev)
    let Some(ref expected_token) = ctx.cfg.api_token else {
        if ctx.cfg.profile != "prod" {
            warn!(
                "API token não configurado no profile '{}' - acesso permitido sem autenticação",
                ctx.cfg.profile
            );
        }
        req.extensions_mut()
            .insert(consumer_identity_for_id(ConsumerId::BeagleOperator));
        drop(ctx); // Release lock antes de chamar next
        return Ok(next.run(req).await);
    };

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

    req.extensions_mut()
        .insert(consumer_identity_for_id(ConsumerId::BeagleOperator));
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
    use std::sync::Arc;
    use tokio::sync::Mutex;
    use tower::util::ServiceExt; // for `oneshot`

    async fn dummy_handler() -> &'static str {
        "ok"
    }

    async fn create_test_state(api_token: Option<String>, profile: &str) -> AppState {
        let cfg = BeagleConfig {
            profile: profile.to_string(),
            safe_mode: true,
            api_token,
            llm: Default::default(),
            storage: beagle_config::StorageConfig {
                data_dir: beagle_config::beagle_data_dir()
                    .to_string_lossy()
                    .to_string(),
            },
            graph: Default::default(),
            hermes: Default::default(),
            tool_bridge: Default::default(),
            workspace: Default::default(),
            advanced: Default::default(),
            consumers: Default::default(),
            observer: Default::default(),
        };

        let ctx = BeagleContext::new_with_mocks(cfg);

        AppState {
            ctx: Arc::new(Mutex::new(ctx)),
            jobs: Arc::new(JobRegistry::new()),
            science_jobs: Arc::new(ScienceJobRegistry::new()),
            observer: Arc::new(UniversalObserver::new().await.unwrap()),
        }
    }

    #[tokio::test]
    async fn test_auth_with_valid_token() {
        let state = create_test_state(Some("test-secret-token".to_string()), "dev").await;

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
        let state = create_test_state(Some("test-secret-token".to_string()), "dev").await;

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
        let state = create_test_state(Some("test-secret-token".to_string()), "dev").await;

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
        let state = create_test_state(None, "dev").await;

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

    #[tokio::test]
    async fn test_auth_with_consumer_policy_research_token() {
        let state = create_test_state(Some("operator-token".to_string()), "dev").await;
        {
            let mut ctx = state.ctx.lock().await;
            ctx.cfg.consumers.policy_enabled = true;
            ctx.cfg.consumers.operator_token = Some("operator-token".to_string());
            ctx.cfg.consumers.research_token = Some("research-token".to_string());
        }

        let app = Router::new()
            .route("/test", get(dummy_handler))
            .route_layer(middleware::from_fn_with_state(
                state.clone(),
                api_token_auth,
            ))
            .with_state(state);

        let req = Request::builder()
            .uri("/test")
            .header("Authorization", "Bearer research-token")
            .header("X-Beagle-Consumer", "darwin-research")
            .body(Body::empty())
            .unwrap();

        let response = app.oneshot(req).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_auth_with_consumer_policy_missing_consumer_header() {
        let state = create_test_state(Some("operator-token".to_string()), "dev").await;
        {
            let mut ctx = state.ctx.lock().await;
            ctx.cfg.consumers.policy_enabled = true;
            ctx.cfg.consumers.operator_token = Some("operator-token".to_string());
            ctx.cfg.consumers.research_token = Some("research-token".to_string());
        }

        let app = Router::new()
            .route("/test", get(dummy_handler))
            .route_layer(middleware::from_fn_with_state(
                state.clone(),
                api_token_auth,
            ))
            .with_state(state);

        let req = Request::builder()
            .uri("/test")
            .header("Authorization", "Bearer operator-token")
            .body(Body::empty())
            .unwrap();

        let response = app.oneshot(req).await.unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }
}
