//! Memory endpoints for BEAGLE HTTP API

use crate::http::AppState;
use axum::http::StatusCode;
use axum::{extract::State, routing::post, Json, Router};
use beagle_memory::{ChatSession, MemoryQuery};
use serde::{Deserialize, Serialize};
use tracing::{error, warn};

#[derive(Deserialize)]
pub struct MemoryIngestChatRequest {
    pub source: String,
    pub session_id: String,
    pub turns: Vec<beagle_memory::ChatTurn>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Serialize)]
pub struct MemoryIngestChatResponse {
    pub status: String,
    pub session_id: String,
    pub num_turns: usize,
    pub num_chunks: usize,
}

#[derive(Deserialize)]
pub struct MemoryQueryRequest {
    pub query: String,
    #[serde(default)]
    pub scope: Option<String>,
    #[serde(default)]
    pub max_items: Option<usize>,
}

pub async fn memory_ingest_chat_handler(
    State(state): State<AppState>,
    Json(req): Json<MemoryIngestChatRequest>,
) -> Result<Json<MemoryIngestChatResponse>, StatusCode> {
    let ctx = state.ctx.lock().await;

    let session = ChatSession {
        source: req.source,
        session_id: req.session_id.clone(),
        turns: req.turns,
        tags: req.tags,
        metadata: req.metadata,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_ingest_session(session).await {
            Ok(stats) => Ok(Json(MemoryIngestChatResponse {
                status: "ok".to_string(),
                session_id: stats.session_id,
                num_turns: stats.num_turns,
                num_chunks: stats.num_chunks,
            })),
            Err(e) => {
                error!("Failed to ingest chat: {}", e);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_query_handler(
    State(state): State<AppState>,
    Json(req): Json<MemoryQueryRequest>,
) -> Result<Json<beagle_memory::MemoryResult>, StatusCode> {
    let ctx = state.ctx.lock().await;

    let query = MemoryQuery {
        query: req.query,
        scope: req.scope,
        max_items: req.max_items,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_query(query).await {
            Ok(result) => Ok(Json(result)),
            Err(e) => {
                error!("Failed to query memory: {}", e);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub fn memory_routes() -> Router<AppState> {
    Router::new()
        .route("/api/memory/ingest_chat", post(memory_ingest_chat_handler))
        .route("/api/memory/query", post(memory_query_handler))
}
