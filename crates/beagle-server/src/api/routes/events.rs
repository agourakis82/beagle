use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use beagle_events::BeagleEvent;
use serde::{Deserialize, Serialize};

use crate::{error::ApiError, state::AppState};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/events/publish", post(publish_event))
        .route("/events/health", get(health_check))
}

#[derive(Debug, Deserialize)]
struct PublishRequest {
    event: serde_json::Value,
}

#[derive(Debug, Serialize)]
struct PublishResponse {
    event_id: String,
    status: String,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    pulsar_connected: bool,
}

/// Publish event (REST API)
#[axum::debug_handler]
async fn publish_event(
    State(state): State<AppState>,
    Json(payload): Json<PublishRequest>,
) -> Result<Json<PublishResponse>, ApiError> {
    let event = serde_json::from_value::<BeagleEvent>(payload.event)
        .map_err(|e| ApiError::BadRequest(format!("Invalid event: {}", e)))?;

    let mut publisher = state.event_publisher.lock().await;
    publisher
        .publish(&event)
        .await
        .map_err(|e| ApiError::Internal(format!("Failed to publish: {}", e)))?;

    Ok(Json(PublishResponse {
        event_id: event.metadata.event_id.to_string(),
        status: "published".to_string(),
    }))
}

/// Health check
#[axum::debug_handler]
async fn health_check(State(_state): State<AppState>) -> Json<HealthResponse> {
    // TODO: implement real check when available
    let connected = true;
    Json(HealthResponse {
        status: if connected {
            "healthy".into()
        } else {
            "degraded".into()
        },
        pulsar_connected: connected,
    })
}
