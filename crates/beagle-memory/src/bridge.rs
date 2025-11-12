use crate::models::{ConversationSession, ConversationTurn, RetrievedContext};
use anyhow::{Context, Result};
use beagle_hypergraph::{CachedPostgresStorage, ContentType, Hyperedge, Node, StorageRepository};
use beagle_personality::Domain;
use chrono::{DateTime, Utc};
use serde_json::json;
use std::sync::Arc;
use tracing::{debug, info, warn};
use uuid::Uuid;

const DEVICE_ID: &str = "context-bridge";
const EDGE_LABEL: &str = "ConversationTurn";

/// Context Bridge - Manages conversation memory in hypergraph
pub struct ContextBridge {
    storage: Arc<CachedPostgresStorage>,
}

impl ContextBridge {
    /// Create new context bridge
    pub fn new(storage: Arc<CachedPostgresStorage>) -> Self {
        Self { storage }
    }

    /// Create new conversation session
    pub async fn create_session(&self, user_id: Option<String>) -> Result<ConversationSession> {
        let now = Utc::now();
        let session = ConversationSession {
            id: Uuid::new_v4(),
            user_id: user_id.clone(),
            started_at: now,
            last_active: now,
            turn_count: 0,
        };

        let metadata = json!({
            "session_id": session.id,
            "user_id": user_id,
            "started_at": session.started_at,
            "last_active": session.last_active,
            "turn_count": session.turn_count,
        });

        let session_node = Node::builder()
            .id(session.id)
            .content(format!("Conversation Session {}", session.id))
            .content_type(ContentType::Context)
            .metadata(metadata)
            .device_id(DEVICE_ID)
            .build()
            .context("Failed to build session node")?;

        self.storage
            .create_node(session_node)
            .await
            .context("Failed to persist session node")?;

        info!(session_id = %session.id, "✅ Created session");

        Ok(session)
    }

    /// Store a conversation turn in hypergraph
    pub async fn store_turn(&self, turn: ConversationTurn) -> Result<Uuid> {
        debug!(turn_id = %turn.id, "💾 Storing conversation turn");

        ensure_session_node(&self.storage, turn.session_id).await?;

        let query_node = Node::builder()
            .content(turn.query.clone())
            .content_type(ContentType::Context)
            .metadata(json!({
                "role": "user",
                "session_id": turn.session_id,
                "turn_id": turn.id,
                "timestamp": turn.timestamp,
                "domain": turn.domain,
            }))
            .device_id(DEVICE_ID)
            .build()
            .context("Failed to build query node")?;

        let query_node = self
            .storage
            .create_node(query_node)
            .await
            .context("Failed to create query node")?;

        let response_node = Node::builder()
            .content(turn.response.clone())
            .content_type(ContentType::Context)
            .metadata(json!({
                "role": "assistant",
                "session_id": turn.session_id,
                "turn_id": turn.id,
                "timestamp": turn.timestamp,
                "model": turn.model,
            }))
            .device_id(DEVICE_ID)
            .build()
            .context("Failed to build response node")?;

        let response_node = self
            .storage
            .create_node(response_node)
            .await
            .context("Failed to create response node")?;

        let metadata = json!({
            "turn_id": turn.id,
            "session_id": turn.session_id,
            "domain": turn.domain,
            "model": turn.model,
            "timestamp": turn.timestamp,
            "query": turn.query,
            "response": turn.response,
            "metadata": turn.metadata,
        });

        let mut edge = Hyperedge::new(
            EDGE_LABEL,
            vec![turn.session_id, query_node.id, response_node.id],
            true,
            DEVICE_ID,
        )
        .context("Failed to build conversation hyperedge")?;
        edge.metadata = metadata;

        self.storage
            .create_hyperedge(edge)
            .await
            .context("Failed to create conversation hyperedge")?;

        update_session_metadata(&self.storage, turn.session_id, turn.timestamp).await?;

        info!(turn_id = %turn.id, "✅ Stored conversation turn");

        Ok(turn.id)
    }

    /// Retrieve conversation history for a session
    pub async fn get_session_history(
        &self,
        session_id: Uuid,
        max_turns: usize,
    ) -> Result<Vec<ConversationTurn>> {
        debug!(%session_id, "🔍 Retrieving history for session");

        let mut edges = self
            .storage
            .list_hyperedges(Some(session_id))
            .await
            .context("Failed to list hyperedges for session")?;

        edges.retain(|edge| edge.edge_type == EDGE_LABEL);

        edges.sort_by_key(|edge| {
            edge.metadata
                .get("timestamp")
                .and_then(|value| value.as_str())
                .and_then(|ts| DateTime::parse_from_rfc3339(ts).ok())
                .map(|dt| dt.with_timezone(&Utc))
                .unwrap_or_else(Utc::now)
        });

        let mut turns = Vec::new();
        for edge in edges.into_iter().take(max_turns) {
            match self.parse_turn_from_edge(edge).await {
                Ok(Some(turn)) => turns.push(turn),
                Ok(None) => continue,
                Err(err) => warn!(error = %err, "Failed to parse turn from edge"),
            }
        }

        info!(count = turns.len(), %session_id, "✅ Retrieved session history");

        Ok(turns)
    }

    /// Retrieve semantically similar past conversations
    pub async fn retrieve_similar_context(
        &self,
        query: &str,
        _max_turns: usize,
        _min_similarity: f32,
    ) -> Result<RetrievedContext> {
        debug!("🔍 Searching for similar context to: {}", query);

        // TODO: Implement semantic search via Qdrant
        warn!("⚠️ Semantic search not yet implemented, returning empty context");

        Ok(RetrievedContext {
            turns: vec![],
            relevance_scores: vec![],
            total_tokens: 0,
        })
    }

    /// Build context string from retrieved turns
    pub fn build_context_string(&self, context: &RetrievedContext) -> String {
        let mut result = String::new();

        if context.turns.is_empty() {
            return result;
        }

        result.push_str("=== Relevant Past Conversations ===\n\n");

        for (i, turn) in context.turns.iter().enumerate() {
            result.push_str(&format!(
                "[Turn {}] (Domain: {:?}, Relevance: {:.2})\n",
                i + 1,
                turn.domain,
                context.relevance_scores.get(i).unwrap_or(&0.0)
            ));
            result.push_str(&format!("Q: {}\n", turn.query));
            result.push_str(&format!("A: {}\n\n", turn.response));
        }

        result
    }

    async fn parse_turn_from_edge(&self, edge: Hyperedge) -> Result<Option<ConversationTurn>> {
        let metadata = edge.metadata.clone();

        let turn_id = metadata
            .get("turn_id")
            .and_then(|v| v.as_str())
            .and_then(|value| Uuid::parse_str(value).ok())
            .context("Hyperedge missing turn_id")?;
        let session_id = metadata
            .get("session_id")
            .and_then(|v| v.as_str())
            .and_then(|value| Uuid::parse_str(value).ok())
            .context("Hyperedge missing session_id")?;

        let base_timestamp = metadata
            .get("timestamp")
            .and_then(|v| v.as_str())
            .and_then(|value| DateTime::parse_from_rfc3339(value).ok())
            .map(|dt| dt.with_timezone(&Utc))
            .unwrap_or_else(Utc::now);

        let domain: Domain = serde_json::from_value(
            metadata
                .get("domain")
                .cloned()
                .context("Hyperedge missing domain")?,
        )
        .context("Failed to deserialize domain")?;

        let model = metadata
            .get("model")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        let conv_metadata: crate::models::ConversationMetadata = metadata
            .get("metadata")
            .cloned()
            .map(|value| serde_json::from_value(value))
            .transpose()
            .context("Failed to deserialize conversation metadata")?
            .unwrap_or_else(default_metadata);

        let query_from_metadata = metadata
            .get("query")
            .and_then(|value| value.as_str())
            .map(|value| value.to_owned());
        let response_from_metadata = metadata
            .get("response")
            .and_then(|value| value.as_str())
            .map(|value| value.to_owned());

        let (query, response, timestamp) =
            if let (Some(query), Some(response)) = (query_from_metadata, response_from_metadata) {
                (query, response, base_timestamp)
            } else {
                let nodes = self
                    .storage
                    .batch_get_nodes(edge.node_ids.clone())
                    .await
                    .context("Failed to load nodes for edge")?;

                let mut query: Option<(String, DateTime<Utc>)> = None;
                let mut response: Option<(String, DateTime<Utc>)> = None;
                let mut latest_timestamp = base_timestamp;

                for node in nodes {
                    let role = node
                        .metadata
                        .get("role")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");

                    let node_timestamp = node
                        .metadata
                        .get("timestamp")
                        .and_then(|v| v.as_str())
                        .and_then(|value| DateTime::parse_from_rfc3339(value).ok())
                        .map(|dt| dt.with_timezone(&Utc))
                        .unwrap_or(base_timestamp);

                    latest_timestamp = std::cmp::max(latest_timestamp, node_timestamp);

                    match role {
                        "user" => {
                            query = Some((node.content.clone(), node_timestamp));
                        }
                        "assistant" => {
                            response = Some((node.content.clone(), node_timestamp));
                        }
                        _ => {}
                    }
                }

                match (query, response) {
                    (Some((query, _)), Some((response, _))) => (query, response, latest_timestamp),
                    _ => return Ok(None),
                }
            };

        Ok(Some(ConversationTurn {
            id: turn_id,
            session_id,
            query,
            response,
            domain,
            model,
            timestamp,
            metadata: conv_metadata,
        }))
    }
}

fn default_metadata() -> crate::models::ConversationMetadata {
    crate::models::ConversationMetadata {
        system_prompt_preview: None,
        feedback: None,
        metrics: crate::models::PerformanceMetrics {
            latency_ms: 0,
            tokens_input: None,
            tokens_output: None,
            cost_usd: None,
        },
        tags: vec![],
    }
}

async fn ensure_session_node(storage: &Arc<CachedPostgresStorage>, session_id: Uuid) -> Result<()> {
    if storage.get_node(session_id).await.is_ok() {
        return Ok(());
    }

    warn!(%session_id, "Session node missing; recreating placeholder");

    let node = Node::builder()
        .id(session_id)
        .content(format!("Conversation Session {}", session_id))
        .content_type(ContentType::Context)
        .metadata(json!({
            "session_id": session_id,
            "reconstructed": true,
        }))
        .device_id(DEVICE_ID)
        .build()
        .context("Failed to build placeholder session node")?;

    storage
        .create_node(node)
        .await
        .context("Failed to create placeholder session node")?;

    Ok(())
}

async fn update_session_metadata(
    storage: &Arc<CachedPostgresStorage>,
    session_id: Uuid,
    last_timestamp: DateTime<Utc>,
) -> Result<()> {
    let mut session_node = storage
        .get_node(session_id)
        .await
        .context("Failed to load session node for update")?;

    let metadata = session_node.metadata.clone();
    let mut map = metadata.as_object().cloned().unwrap_or_default();

    let turn_count = map.get("turn_count").and_then(|v| v.as_u64()).unwrap_or(0);

    map.insert("turn_count".into(), json!(turn_count + 1));
    map.insert("last_active".into(), json!(last_timestamp));

    session_node.metadata = serde_json::Value::Object(map);
    session_node.updated_at = last_timestamp;

    storage
        .update_node(session_node)
        .await
        .context("Failed to update session node metadata")?;

    Ok(())
}

#[cfg(test)]
mod tests {
    // TODO: add integration tests with test database
}
