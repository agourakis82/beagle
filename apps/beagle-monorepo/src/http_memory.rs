//! Memory endpoints for BEAGLE HTTP API

use crate::http::AppState;
use crate::http_exocortex::{append_conversation_passages, query_projected_memory_for_memory_api};
use anyhow::Context;
use axum::http::StatusCode;
use axum::{extract::State, routing::post, Json, Router};
use beagle_config::beagle_data_dir;
use beagle_memory::{ChatSession, MemoryQuery};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use tokio::io::AsyncWriteExt;
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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AppendOnlyMemorySession {
    source: String,
    session_id: String,
    #[serde(default)]
    content_hash: Option<String>,
    turns: Vec<beagle_memory::ChatTurn>,
    tags: Vec<String>,
    metadata: serde_json::Value,
    ingested_at: DateTime<Utc>,
}

pub async fn memory_ingest_chat_handler(
    State(state): State<AppState>,
    Json(req): Json<MemoryIngestChatRequest>,
) -> Result<Json<MemoryIngestChatResponse>, StatusCode> {
    let session = ChatSession {
        source: req.source,
        session_id: req.session_id.clone(),
        turns: req.turns,
        tags: req.tags,
        metadata: req.metadata,
    };

    // Always persist the raw session turns as durable conversation passages in
    // the exocortex store (not the fallback dir), regardless of which memory
    // backend handles the ingest. Fail-soft: a passage write must never fail
    // the ingest.
    persist_conversation_passages(&session);

    // Auto-refresh the memory-engine semantic index after ingest (debounced/coalesced, fail-soft).
    crate::http_exocortex::trigger_reindex_debounced();

    #[cfg(feature = "memory")]
    {
        let result = {
            let ctx = state.ctx.lock().await;
            ctx.memory().ingest_session(session.clone()).await
        };

        match result {
            Ok(stats) => Ok(Json(MemoryIngestChatResponse {
                status: "ok".to_string(),
                session_id: stats.session_id,
                num_turns: stats.num_turns,
                num_chunks: stats.num_chunks,
            })),
            Err(e) if is_memory_engine_unavailable(&e) => {
                warn!("MemoryEngine unavailable, using append-only exocortex memory fallback");
                fallback_ingest_chat(&fallback_memory_root(), session)
                    .await
                    .map(Json)
                    .map_err(|err| {
                        error!("Failed to ingest chat with fallback memory: {}", err);
                        StatusCode::INTERNAL_SERVER_ERROR
                    })
            }
            Err(e) => {
                error!("Failed to ingest chat: {}", e);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        let _ = state;
        warn!("Memory feature not enabled, using append-only exocortex memory fallback");
        fallback_ingest_chat(&fallback_memory_root(), session)
            .await
            .map(Json)
            .map_err(|err| {
                error!("Failed to ingest chat with fallback memory: {}", err);
                StatusCode::INTERNAL_SERVER_ERROR
            })
    }
}

pub async fn memory_query_handler(
    State(state): State<AppState>,
    Json(req): Json<MemoryQueryRequest>,
) -> Result<Json<beagle_memory::MemoryResult>, StatusCode> {
    let query = MemoryQuery {
        query: req.query,
        scope: req.scope,
        max_items: req.max_items,
    };

    match query_projected_memory_for_memory_api(query.clone()) {
        Ok(Some(result)) => return Ok(Json(result)),
        Ok(None) => {}
        Err(error) => warn!(
            "GraphRAG++ projected memory unavailable, falling back to legacy memory query: {}",
            error
        ),
    }

    #[cfg(feature = "memory")]
    {
        let result = {
            let ctx = state.ctx.lock().await;
            ctx.memory().query(query.clone()).await
        };

        match result {
            Ok(result) => Ok(Json(result)),
            Err(e) if is_memory_engine_unavailable(&e) => {
                warn!("MemoryEngine unavailable, using append-only exocortex memory fallback");
                fallback_query_memory(&fallback_memory_root(), query)
                    .await
                    .map(Json)
                    .map_err(|err| {
                        error!("Failed to query fallback memory: {}", err);
                        StatusCode::INTERNAL_SERVER_ERROR
                    })
            }
            Err(e) => {
                error!("Failed to query memory: {}", e);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        let _ = state;
        warn!("Memory feature not enabled, using append-only exocortex memory fallback");
        fallback_query_memory(&fallback_memory_root(), query)
            .await
            .map(Json)
            .map_err(|err| {
                error!("Failed to query fallback memory: {}", err);
                StatusCode::INTERNAL_SERVER_ERROR
            })
    }
}

pub fn memory_routes() -> Router<AppState> {
    Router::new()
        .route("/api/memory/ingest_chat", post(memory_ingest_chat_handler))
        .route("/api/memory/query", post(memory_query_handler))
}

fn is_memory_engine_unavailable(error: &anyhow::Error) -> bool {
    error.to_string().contains("MemoryEngine not initialized")
}

/// Fail-soft writer for durable conversation passages. A write error here must
/// never fail the ingest, so the result is logged and otherwise ignored.
fn persist_conversation_passages(session: &ChatSession) {
    match append_conversation_passages(session) {
        Ok(true) => {}
        Ok(false) => {
            warn!(
                "skipped restricted conversation passages for session {}",
                session.session_id
            );
        }
        Err(err) => {
            warn!(
                "failed to persist conversation passages for session {}: {}",
                session.session_id, err
            );
        }
    }
}

fn fallback_memory_root() -> PathBuf {
    beagle_data_dir().join("exocortex").join("memory")
}

fn fallback_memory_file(root: &Path) -> PathBuf {
    root.join("chat_sessions.jsonl")
}

async fn fallback_ingest_chat(
    root: &Path,
    session: ChatSession,
) -> anyhow::Result<MemoryIngestChatResponse> {
    tokio::fs::create_dir_all(root)
        .await
        .with_context(|| format!("create fallback memory dir {}", root.display()))?;

    let num_turns = session.turns.len();
    let session_hash = fallback_session_hash(&session)?;
    if let Some(existing) = find_fallback_session_by_hash(root, &session_hash).await? {
        return Ok(MemoryIngestChatResponse {
            status: "duplicate".to_string(),
            session_id: existing.session_id,
            num_turns: existing.turns.len(),
            num_chunks: existing.turns.len(),
        });
    }
    let stored = AppendOnlyMemorySession {
        source: session.source,
        session_id: session.session_id.clone(),
        content_hash: Some(format!("sha256:{}", session_hash)),
        turns: session.turns,
        tags: session.tags,
        metadata: session.metadata,
        ingested_at: Utc::now(),
    };

    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(fallback_memory_file(root))
        .await
        .context("open fallback memory jsonl")?;

    let line = serde_json::to_string(&stored).context("serialize fallback memory session")?;
    file.write_all(line.as_bytes()).await?;
    file.write_all(b"\n").await?;
    file.flush().await?;

    Ok(MemoryIngestChatResponse {
        status: "ok".to_string(),
        session_id: stored.session_id,
        num_turns,
        num_chunks: num_turns,
    })
}

async fn find_fallback_session_by_hash(
    root: &Path,
    session_hash: &str,
) -> anyhow::Result<Option<AppendOnlyMemorySession>> {
    let file = fallback_memory_file(root);
    let Ok(contents) = tokio::fs::read_to_string(&file).await else {
        return Ok(None);
    };
    let wanted = format!("sha256:{}", session_hash);
    for line in contents.lines().filter(|line| !line.trim().is_empty()) {
        let Ok(session) = serde_json::from_str::<AppendOnlyMemorySession>(line) else {
            continue;
        };
        if session.content_hash.as_deref() == Some(wanted.as_str()) {
            return Ok(Some(session));
        }
    }
    Ok(None)
}

fn fallback_session_hash(session: &ChatSession) -> anyhow::Result<String> {
    let canonical = serde_json::to_vec(&serde_json::json!({
        "source": &session.source,
        "session_id": &session.session_id,
        "turns": &session.turns,
    }))?;
    let mut hasher = Sha256::new();
    hasher.update(canonical);
    Ok(hex_digest(hasher.finalize()))
}

fn hex_digest(bytes: impl AsRef<[u8]>) -> String {
    bytes
        .as_ref()
        .iter()
        .map(|byte| format!("{:02x}", byte))
        .collect()
}

async fn fallback_query_memory(
    root: &Path,
    query: MemoryQuery,
) -> anyhow::Result<beagle_memory::MemoryResult> {
    let max_items = query.max_items.unwrap_or(5).clamp(1, 20);
    let file = fallback_memory_file(root);
    let Ok(contents) = tokio::fs::read_to_string(&file).await else {
        return Ok(beagle_memory::MemoryResult {
            summary: "No append-only memory has been ingested yet.".to_string(),
            highlights: Vec::new(),
            links: Vec::new(),
        });
    };

    let needle = query.query.to_lowercase();
    let tokens: Vec<String> = needle
        .split_whitespace()
        .filter(|token| token.len() > 2)
        .map(ToOwned::to_owned)
        .collect();

    let mut highlights = Vec::new();
    for line in contents.lines().filter(|line| !line.trim().is_empty()) {
        let Ok(session) = serde_json::from_str::<AppendOnlyMemorySession>(line) else {
            continue;
        };

        if let Some(scope) = query.scope.as_deref() {
            let scope = scope.to_lowercase();
            let in_scope = session.tags.iter().any(|tag| tag.to_lowercase() == scope)
                || session.source.to_lowercase() == scope;
            if !in_scope {
                continue;
            }
        }

        for turn in &session.turns {
            let content = turn.content.to_lowercase();
            let token_hits = tokens
                .iter()
                .filter(|token| content.contains(token.as_str()))
                .count();
            let exact_hit = !needle.is_empty() && content.contains(&needle);
            if !exact_hit && token_hits == 0 {
                continue;
            }

            let relevance = if exact_hit {
                1.0
            } else {
                (token_hits as f32 / tokens.len().max(1) as f32).clamp(0.1, 0.95)
            };

            highlights.push(beagle_memory::MemoryResultHighlight {
                source: session.source.clone(),
                date: Some(session.ingested_at),
                snippet: truncate_chars(&turn.content, 500),
                run_id: None,
                session_id: Some(session.session_id.clone()),
                relevance,
            });
        }
    }

    highlights.sort_by(|a, b| {
        b.relevance
            .partial_cmp(&a.relevance)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    highlights.truncate(max_items);

    let summary = if highlights.is_empty() {
        format!("No append-only memory matches found for '{}'.", query.query)
    } else {
        format!(
            "Found {} append-only memory match(es) for '{}'.",
            highlights.len(),
            query.query
        )
    };

    Ok(beagle_memory::MemoryResult {
        summary,
        highlights,
        links: Vec::new(),
    })
}

fn truncate_chars(value: &str, max_chars: usize) -> String {
    value.chars().take(max_chars).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn fallback_memory_round_trip_finds_ingested_chat() {
        let temp = tempfile::tempdir().unwrap();
        let session = ChatSession {
            source: "codex_test".to_string(),
            session_id: "session-1".to_string(),
            turns: vec![beagle_memory::ChatTurn {
                role: "user".to_string(),
                content: "A sentinela exocortex-utf8-memoria está viva.".to_string(),
                timestamp: None,
                model: None,
            }],
            tags: vec!["smoke".to_string()],
            metadata: serde_json::json!({"kind": "test"}),
        };

        let ingest = fallback_ingest_chat(temp.path(), session.clone())
            .await
            .unwrap();
        assert_eq!(ingest.status, "ok");
        assert_eq!(ingest.num_turns, 1);
        let duplicate = fallback_ingest_chat(temp.path(), session).await.unwrap();
        assert_eq!(duplicate.status, "duplicate");

        let result = fallback_query_memory(
            temp.path(),
            MemoryQuery {
                query: "exocortex-utf8-memoria".to_string(),
                scope: Some("smoke".to_string()),
                max_items: Some(5),
            },
        )
        .await
        .unwrap();

        assert_eq!(result.highlights.len(), 1);
        assert_eq!(
            result.highlights[0].session_id.as_deref(),
            Some("session-1")
        );
    }
}
