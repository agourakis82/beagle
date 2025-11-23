//! Memory Engine - Unified interface for ingesting and querying memory
//!
//! Provides a high-level API for:
//! - Ingesting chat sessions (ChatGPT, Claude, Grok, local)
//! - Querying memory with semantic search
//! - Integration with GraphRAG and vector stores

use crate::bridge::ContextBridge;
use crate::models::ConversationTurn;
use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{info, warn};
use uuid::Uuid;

/// Simplified chat turn for ingestion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatTurn {
    pub role: String, // "user" | "assistant"
    pub content: String,
    pub timestamp: Option<DateTime<Utc>>,
    pub model: Option<String>,
}

/// Chat session for ingestion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatSession {
    pub source: String, // "chatgpt" | "claude" | "grok" | "local"
    pub session_id: String,
    pub turns: Vec<ChatTurn>,
    pub tags: Vec<String>,
    pub metadata: serde_json::Value,
}

/// Memory query
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryQuery {
    pub query: String,
    pub scope: Option<String>, // "general" | "scientific" | "pcs" | "pbpk" | "fractal"
    pub max_items: Option<usize>,
}

/// Highlight from memory query
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryResultHighlight {
    pub source: String,
    pub date: Option<DateTime<Utc>>,
    pub snippet: String,
    pub run_id: Option<String>,
    pub session_id: Option<String>,
    pub relevance: f32,
}

/// Memory query result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryResult {
    pub summary: String,
    pub highlights: Vec<MemoryResultHighlight>,
    pub links: Vec<serde_json::Value>,
}

/// Ingest statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IngestStats {
    pub num_turns: usize,
    pub num_chunks: usize,
    pub session_id: String,
}

/// Memory Engine - Main interface for memory operations
pub struct MemoryEngine {
    bridge: Arc<ContextBridge>,
    // TODO: Add Qdrant client, Neo4j client, etc. when available
}

impl MemoryEngine {
    /// Create new MemoryEngine
    pub fn new(bridge: Arc<ContextBridge>) -> Self {
        Self { bridge }
    }

    /// Ingest a chat session into memory
    pub async fn ingest_chat(&self, session: ChatSession) -> Result<IngestStats> {
        info!(
            source = %session.source,
            session_id = %session.session_id,
            turns = session.turns.len(),
            "Ingesting chat session"
        );

        // Convert ChatSession to ConversationSession + ConversationTurns
        let session_uuid = Uuid::parse_str(&session.session_id).unwrap_or_else(|_| Uuid::new_v4());

        // Create or get session
        let _conv_session = self
            .bridge
            .create_session(None)
            .await
            .context("Failed to create conversation session")?;

        let mut num_chunks = 0;

        // Ingest each turn
        for (idx, turn) in session.turns.iter().enumerate() {
            let _timestamp = turn.timestamp.unwrap_or_else(|| Utc::now());

            // Convert ChatTurn to ConversationTurn
            let conv_turn = ConversationTurn::new(
                session_uuid,
                if turn.role == "user" {
                    turn.content.clone()
                } else {
                    String::new()
                },
                if turn.role == "assistant" {
                    turn.content.clone()
                } else {
                    String::new()
                },
                beagle_personality::Domain::General, // Default, can be enhanced
                turn.model.clone().unwrap_or_else(|| "unknown".to_string()),
            );

            // Store turn
            match self.bridge.store_turn(conv_turn).await {
                Ok(_) => {
                    num_chunks += 1;
                }
                Err(e) => {
                    warn!(
                        turn_index = idx,
                        error = %e,
                        "Failed to store turn"
                    );
                }
            }
        }

        Ok(IngestStats {
            num_turns: session.turns.len(),
            num_chunks,
            session_id: session.session_id,
        })
    }

    /// Query memory with semantic search
    pub async fn query(&self, q: MemoryQuery) -> Result<MemoryResult> {
        info!(
            query_preview = %q.query.chars().take(50).collect::<String>(),
            scope = ?q.scope,
            max_items = q.max_items.unwrap_or(5),
            "Querying memory"
        );

        let max_items = q.max_items.unwrap_or(5);

        // Use ContextBridge to retrieve relevant turns
        // TODO: Enhance with vector search (Qdrant) and graph traversal (Neo4j)
        let retrieved = self
            .bridge
            .retrieve_similar_context(&q.query, max_items, 0.3)
            .await
            .context("Failed to retrieve context")?;

        // Convert RetrievedContext to MemoryResultHighlight
        let highlights: Vec<MemoryResultHighlight> = retrieved
            .turns
            .iter()
            .zip(retrieved.relevance_scores.iter())
            .map(|(turn, score)| {
                // Create snippet from turn
                let snippet = if !turn.query.is_empty() && !turn.response.is_empty() {
                    format!(
                        "Q: {}\nA: {}",
                        turn.query.chars().take(100).collect::<String>(),
                        turn.response.chars().take(200).collect::<String>()
                    )
                } else if !turn.query.is_empty() {
                    turn.query.chars().take(200).collect::<String>()
                } else {
                    turn.response.chars().take(200).collect::<String>()
                };

                MemoryResultHighlight {
                    source: format!("conversation_{}", turn.session_id),
                    date: Some(turn.timestamp),
                    snippet,
                    run_id: None, // Can be extracted from metadata if available
                    session_id: Some(turn.session_id.to_string()),
                    relevance: *score,
                }
            })
            .collect();

        // Generate summary (simple version: join highlights)
        // TODO: Use LLM to generate better summary
        let summary = if highlights.is_empty() {
            "No relevant context found.".to_string()
        } else {
            format!(
                "Found {} relevant context items:\n{}",
                highlights.len(),
                highlights
                    .iter()
                    .take(3)
                    .map(|h| format!("- {}", h.snippet.chars().take(100).collect::<String>()))
                    .collect::<Vec<_>>()
                    .join("\n")
            )
        };

        // Create links
        let links: Vec<serde_json::Value> = highlights
            .iter()
            .filter_map(|h| {
                h.session_id.as_ref().map(|sid| {
                    serde_json::json!({
                        "type": "session",
                        "id": sid,
                        "label": format!("Session {}", sid)
                    })
                })
            })
            .collect();

        Ok(MemoryResult {
            summary,
            highlights,
            links,
        })
    }
}

/// Mock MemoryEngine for testing
#[cfg(test)]
pub struct MockMemoryEngine {
    pub ingested_sessions: Vec<ChatSession>,
    pub query_results: Vec<MemoryResult>,
}

#[cfg(test)]
impl MockMemoryEngine {
    pub fn new() -> Self {
        Self {
            ingested_sessions: Vec::new(),
            query_results: Vec::new(),
        }
    }

    pub async fn ingest_chat(&mut self, session: ChatSession) -> Result<IngestStats> {
        self.ingested_sessions.push(session.clone());
        Ok(IngestStats {
            num_turns: session.turns.len(),
            num_chunks: session.turns.len(),
            session_id: session.session_id,
        })
    }

    pub async fn query(&self, _q: MemoryQuery) -> Result<MemoryResult> {
        // Return first mock result or empty
        self.query_results
            .first()
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("No mock results configured"))
    }
}
