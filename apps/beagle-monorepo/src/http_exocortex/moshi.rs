//! Moshi full-duplex voice proxy.
//!
//! GET /api/moshi/v1/session — WebSocket upgrade, bidirectional proxy to
//! moshi.moshi.svc:8998, Inner Monologue text frames captured to exocortex.

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
};
use chrono::Utc;
use futures::{SinkExt, StreamExt};
use serde_json::json;
use std::env;
use tokio_tungstenite::{connect_async, tungstenite::Message as TungMsg};
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::http::AppState;

/// All routes are behind `api_token_auth` middleware (http.rs protected_routes).
/// This handler adds an explicit Origin allowlist as defense-in-depth against
/// Cross-Site WebSocket Hijacking, even though Bearer tokens are not forwarded by
/// browsers cross-origin (making CSWSH low-risk here).
pub(crate) async fn moshi_session_handler(
    ws: WebSocketUpgrade,
    headers: HeaderMap,
    State(state): State<AppState>,
) -> impl IntoResponse {
    // Origin check: allow same-origin requests and the known Beagle iOS/web origins.
    // BEAGLE_ALLOWED_ORIGINS is comma-separated, e.g. "https://beagle.sounio.dev,beagle-app".
    // If unset, only requests without an Origin header (native clients, curl) are allowed.
    let allowed = env::var("BEAGLE_ALLOWED_ORIGINS").unwrap_or_default();
    if let Some(origin) = headers.get(axum::http::header::ORIGIN).and_then(|v| v.to_str().ok()) {
        let permitted = allowed
            .split(',')
            .map(str::trim)
            .any(|o| !o.is_empty() && (origin == o || origin.starts_with(o)));
        if !permitted {
            warn!("moshi: rejected WS upgrade from unlisted origin: {origin}");
            return (StatusCode::FORBIDDEN, "origin not permitted").into_response();
        }
    }
    ws.on_upgrade(move |socket| handle_moshi_session(socket, state))
}

async fn handle_moshi_session(client_ws: WebSocket, _state: AppState) {
    let session_id = Uuid::new_v4().to_string();
    let beagle_core_url = env::var("BEAGLE_CORE_SELF_URL")
        .unwrap_or_else(|_| "http://localhost:8080".to_string());
    let beagle_api_token = env::var("BEAGLE_API_TOKEN").unwrap_or_default();

    let http_client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .expect("reqwest client");

    // Open capture session (fail-soft)
    let capture_url = format!(
        "{}/api/exocortex/v1/capture/sessions",
        beagle_core_url.trim_end_matches('/')
    );
    let _ = http_client
        .post(&capture_url)
        .bearer_auth(&beagle_api_token)
        .json(&json!({
            "session_id": session_id,
            "mode": "moshi_voice",
            "surface": "moshi-proxy",
            "privacy_class": "sensitive",
            "tags": ["moshi", "voice-mode", "inner-monologue"]
        }))
        .send()
        .await
        .map_err(|e| warn!("moshi: could not open capture session: {e}"));

    info!("moshi: opened capture session {session_id}");

    let moshi_url = env::var("MOSHI_SERVER_URL")
        .unwrap_or_else(|_| "ws://moshi.moshi.svc:8998/api".to_string());

    let upstream = match connect_async(&moshi_url).await {
        Ok((ws_stream, _)) => ws_stream,
        Err(e) => {
            error!("moshi: could not connect to upstream {moshi_url}: {e}");
            close_capture_session(
                &http_client,
                &beagle_core_url,
                &beagle_api_token,
                &session_id,
                "upstream_connect_failed",
            )
            .await;
            return;
        }
    };

    info!("moshi: connected to upstream, session {session_id}");

    let (mut client_sink, mut client_stream) = client_ws.split();
    let (mut upstream_sink, mut upstream_stream) = upstream.split();

    let session_b = session_id.clone();
    let base_b = beagle_core_url.clone();
    let token_b = beagle_api_token.clone();
    let http_b = http_client.clone();

    let client_to_upstream = tokio::spawn(async move {
        while let Some(Ok(msg)) = client_stream.next().await {
            match msg {
                Message::Binary(data) => {
                    if upstream_sink.send(TungMsg::Binary(data.into())).await.is_err() {
                        break;
                    }
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    });

    let upstream_to_client = tokio::spawn(async move {
        let mut buf = String::new();
        while let Some(Ok(msg)) = upstream_stream.next().await {
            match msg {
                TungMsg::Binary(data) => {
                    if client_sink
                        .send(Message::Binary(data.into()))
                        .await
                        .is_err()
                    {
                        break;
                    }
                }
                TungMsg::Text(text) => {
                    buf.push_str(&text);
                    buf.push(' ');
                    let _ = client_sink.send(Message::Text(text.into())).await;
                    if buf.len() >= 20 {
                        append_monologue(&http_b, &base_b, &token_b, &session_b, buf.trim()).await;
                        buf.clear();
                    }
                }
                TungMsg::Close(_) => break,
                _ => {}
            }
        }
        if !buf.trim().is_empty() {
            append_monologue(&http_b, &base_b, &token_b, &session_b, buf.trim()).await;
        }
    });

    tokio::select! {
        _ = client_to_upstream => {}
        _ = upstream_to_client => {}
    }

    info!("moshi: session {session_id} closed");
    close_capture_session(&http_client, &beagle_core_url, &beagle_api_token, &session_id, "disconnected").await;
}

async fn append_monologue(client: &reqwest::Client, base: &str, token: &str, sid: &str, text: &str) {
    let url = format!(
        "{}/api/exocortex/v1/capture/sessions/{}/events",
        base.trim_end_matches('/'),
        sid
    );
    let _ = client
        .post(&url)
        .bearer_auth(token)
        .json(&json!({
            "kind": "inner_monologue",
            "content": text,
            "occurred_at": Utc::now().to_rfc3339(),
            "metadata": { "source": "moshi-proxy" }
        }))
        .send()
        .await
        .map_err(|e| warn!("moshi: append_monologue failed: {e}"));
}

async fn close_capture_session(client: &reqwest::Client, base: &str, token: &str, sid: &str, reason: &str) {
    let url = format!(
        "{}/api/exocortex/v1/capture/sessions/{}/events",
        base.trim_end_matches('/'),
        sid
    );
    let _ = client
        .post(&url)
        .bearer_auth(token)
        .json(&json!({
            "kind": "session_closed",
            "content": reason,
            "occurred_at": Utc::now().to_rfc3339(),
            "metadata": { "source": "moshi-proxy" }
        }))
        .send()
        .await
        .map_err(|e| warn!("moshi: close_capture_session failed: {e}"));
}
