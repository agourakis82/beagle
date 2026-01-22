use crate::models::{ConversationSession, ConversationTurn, RetrievedContext};
use anyhow::{Context, Result};
use beagle_hypergraph::{CachedPostgresStorage, ContentType, Hyperedge, Node, StorageRepository};
use beagle_llm::embedding::EmbeddingClient;
use beagle_personality::Domain;
use chrono::{DateTime, Utc};
use serde_json::json;
use std::time::Duration;
use std::sync::Arc;
use tracing::{debug, info, warn};
use uuid::Uuid;

const DEVICE_ID: &str = "context-bridge";
const EDGE_LABEL: &str = "ConversationTurn";
const DEFAULT_MEMORY_QDRANT_COLLECTION: &str = "beagle-memory";

fn stable_uuid_for_parts(parts: &[&str]) -> Uuid {
    fn fnv1a64(s: &str) -> u64 {
        const OFFSET: u64 = 0xcbf29ce484222325;
        const PRIME: u64 = 0x100000001b3;
        let mut hash = OFFSET;
        for b in s.as_bytes() {
            hash ^= *b as u64;
            hash = hash.wrapping_mul(PRIME);
        }
        hash
    }

    let joined = parts.join("\u{1f}");
    let hi = fnv1a64(&format!("hi:{joined}"));
    let lo = fnv1a64(&format!("lo:{joined}"));
    Uuid::from_u128(((hi as u128) << 64) | lo as u128)
}

#[derive(Debug, Clone)]
struct MemoryVectorIndex {
    qdrant_url: String,
    collection: String,
    qdrant: reqwest::Client,
    embedder: EmbeddingClient,
}

impl MemoryVectorIndex {
    fn try_from_env() -> Result<Option<Self>> {
        let qdrant_url = std::env::var("QDRANT_URL")
            .or_else(|_| std::env::var("BEAGLE_QDRANT_URL"))
            .ok();
        let Some(qdrant_url) = qdrant_url else {
            return Ok(None);
        };

        let collection = std::env::var("BEAGLE_MEMORY_QDRANT_COLLECTION")
            .or_else(|_| std::env::var("BEAGLE_MEMORY_COLLECTION"))
            .unwrap_or_else(|_| DEFAULT_MEMORY_QDRANT_COLLECTION.to_string());

        let embedding_url = std::env::var("EMBEDDING_URL")
            .or_else(|_| std::env::var("BEAGLE_EMBEDDING_URL"))
            .unwrap_or_else(|_| "http://localhost:8001/v1".to_string());

        let qdrant = reqwest::Client::builder()
            .timeout(Duration::from_secs(60))
            .build()
            .context("Failed to build Qdrant HTTP client")?;

        Ok(Some(Self {
            qdrant_url: qdrant_url.trim_end_matches('/').to_string(),
            collection,
            qdrant,
            embedder: EmbeddingClient::new(embedding_url),
        }))
    }

    async fn ensure_collection(&self, vector_size: usize) -> Result<()> {
        let url = format!("{}/collections/{}", self.qdrant_url, self.collection);
        let resp = self.qdrant.get(&url).send().await?;
        if resp.status().as_u16() == 404 {
            let body = json!({ "vectors": { "size": vector_size, "distance": "Cosine" } });
            let resp = self.qdrant.put(&url).json(&body).send().await?;
            let status = resp.status();
            if !status.is_success() {
                let body = resp.text().await.unwrap_or_default();
                anyhow::bail!("Qdrant create collection error {status}: {body}");
            }
            return Ok(());
        }

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("Qdrant get collection error {status}: {body}");
        }

        Ok(())
    }

    async fn upsert_turn(&self, turn: &ConversationTurn) -> Result<()> {
        let text = format_turn_for_embedding(turn);
        if text.trim().is_empty() {
            return Ok(());
        }

        let embedding = self.embedder.embed(&text).await?;
        let vector_size = embedding.len();
        if vector_size == 0 {
            anyhow::bail!("Embedding server returned empty vector");
        }

        self.ensure_collection(vector_size).await?;

        let vector: Vec<f32> = embedding.into_iter().map(|v| v as f32).collect();
        let url = format!(
            "{}/collections/{}/points?wait=true",
            self.qdrant_url, self.collection
        );

        let payload = json!({
            "turn_id": turn.id.to_string(),
            "session_id": turn.session_id.to_string(),
            "timestamp": turn.timestamp.to_rfc3339(),
            "domain": turn.domain,
            "model": turn.model,
            "query": turn.query,
            "response": turn.response,
            "metadata": turn.metadata,
        });

        let body = json!({
            "points": [{
                "id": turn.id.to_string(),
                "vector": vector,
                "payload": payload,
            }]
        });

        let resp = self.qdrant.put(&url).json(&body).send().await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("Qdrant upsert error {status}: {body}");
        }

        Ok(())
    }

    async fn search_turns(&self, query: &str, limit: usize) -> Result<Vec<(ConversationTurn, f32)>> {
        let embedding = self.embedder.embed(query).await?;
        let vector_size = embedding.len();
        if vector_size == 0 {
            return Ok(vec![]);
        }

        self.ensure_collection(vector_size).await?;

        let vector: Vec<f32> = embedding.into_iter().map(|v| v as f32).collect();
        let url = format!(
            "{}/collections/{}/points/search",
            self.qdrant_url, self.collection
        );
        let body = json!({
            "vector": vector,
            "limit": limit,
            "with_payload": true,
            "with_vector": false,
        });

        let resp = self.qdrant.post(&url).json(&body).send().await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("Qdrant search error {status}: {body}");
        }

        let v: serde_json::Value = resp.json().await?;
        let results = v
            .get("result")
            .and_then(|value| value.as_array())
            .cloned()
            .unwrap_or_default();

        let mut out = Vec::new();
        for hit in results {
            let score = hit.get("score").and_then(|value| value.as_f64()).unwrap_or(0.0) as f32;
            let payload = match hit.get("payload") {
                Some(payload) => payload.clone(),
                None => continue,
            };

            let turn = parse_turn_from_qdrant_payload(payload).ok();
            if let Some(turn) = turn {
                out.push((turn, score));
            }
        }

        Ok(out)
    }
}

fn format_turn_for_embedding(turn: &ConversationTurn) -> String {
    let query = turn.query.trim();
    let response = turn.response.trim();

    match (!query.is_empty(), !response.is_empty()) {
        (true, true) => format!("User:\n{}\n\nAssistant:\n{}", query, response),
        (true, false) => format!("User:\n{}", query),
        (false, true) => format!("Assistant:\n{}", response),
        (false, false) => String::new(),
    }
}

fn parse_turn_from_qdrant_payload(payload: serde_json::Value) -> Result<ConversationTurn> {
    let turn_id = payload
        .get("turn_id")
        .and_then(|v| v.as_str())
        .and_then(|value| Uuid::parse_str(value).ok())
        .context("Missing payload.turn_id")?;
    let session_id = payload
        .get("session_id")
        .and_then(|v| v.as_str())
        .and_then(|value| Uuid::parse_str(value).ok())
        .context("Missing payload.session_id")?;
    let timestamp = payload
        .get("timestamp")
        .and_then(|v| v.as_str())
        .and_then(|value| DateTime::parse_from_rfc3339(value).ok())
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(Utc::now);

    let query = payload
        .get("query")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let response = payload
        .get("response")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let model = payload
        .get("model")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_string();

    let domain: Domain = payload
        .get("domain")
        .cloned()
        .map(|value| serde_json::from_value(value))
        .transpose()
        .context("Failed to deserialize domain")?
        .unwrap_or(Domain::General);

    let conv_metadata: crate::models::ConversationMetadata = payload
        .get("metadata")
        .cloned()
        .map(|value| serde_json::from_value(value))
        .transpose()
        .context("Failed to deserialize conversation metadata")?
        .unwrap_or_else(default_metadata);

    Ok(ConversationTurn {
        id: turn_id,
        session_id,
        query,
        response,
        domain,
        model,
        timestamp,
        metadata: conv_metadata,
    })
}

/// Context Bridge - Manages conversation memory in hypergraph
pub struct ContextBridge {
    storage: Arc<CachedPostgresStorage>,
    vector_index: Option<Arc<MemoryVectorIndex>>,
}

impl ContextBridge {
    /// Create new context bridge
    pub fn new(storage: Arc<CachedPostgresStorage>) -> Self {
        let vector_index = match MemoryVectorIndex::try_from_env() {
            Ok(Some(index)) => Some(Arc::new(index)),
            Ok(None) => None,
            Err(err) => {
                warn!(error = %err, "Memory vector index disabled (failed to initialize)");
                None
            }
        };

        Self {
            storage,
            vector_index,
        }
    }

    /// Create new conversation session
    pub async fn create_session(
        &self,
        session_id: Option<Uuid>,
        user_id: Option<String>,
    ) -> Result<ConversationSession> {
        let now = Utc::now();
        let id = session_id.unwrap_or_else(Uuid::new_v4);

        if let Ok(existing) = self.storage.get_node(id).await {
            let metadata = &existing.metadata;
            let user_id = metadata
                .get("user_id")
                .and_then(|value| value.as_str())
                .map(|value| value.to_string())
                .or(user_id);

            let started_at = metadata
                .get("started_at")
                .and_then(|value| value.as_str())
                .and_then(|value| DateTime::parse_from_rfc3339(value).ok())
                .map(|dt| dt.with_timezone(&Utc))
                .unwrap_or(existing.created_at);

            let last_active = metadata
                .get("last_active")
                .and_then(|value| value.as_str())
                .and_then(|value| DateTime::parse_from_rfc3339(value).ok())
                .map(|dt| dt.with_timezone(&Utc))
                .unwrap_or(existing.updated_at);

            let turn_count = metadata
                .get("turn_count")
                .and_then(|value| value.as_u64())
                .unwrap_or(0) as usize;

            return Ok(ConversationSession {
                id,
                user_id,
                started_at,
                last_active,
                turn_count,
            });
        }

        let session = ConversationSession {
            id,
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

        let turn_key = turn.id.to_string();
        let query_node_id = stable_uuid_for_parts(&["beagle-memory", "turn", &turn_key, "user"]);
        let response_node_id =
            stable_uuid_for_parts(&["beagle-memory", "turn", &turn_key, "assistant"]);
        let edge_id = stable_uuid_for_parts(&["beagle-memory", "turn", &turn_key, "edge"]);

        let query_node = Node::builder()
            .id(query_node_id)
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

        let query_node = match self.storage.create_node(query_node).await {
            Ok(node) => node,
            Err(err) => match self.storage.get_node(query_node_id).await {
                Ok(node) => node,
                Err(_) => return Err(err).context("Failed to create query node"),
            },
        };

        let response_node = Node::builder()
            .id(response_node_id)
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

        let response_node = match self.storage.create_node(response_node).await {
            Ok(node) => node,
            Err(err) => match self.storage.get_node(response_node_id).await {
                Ok(node) => node,
                Err(_) => return Err(err).context("Failed to create response node"),
            },
        };

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
        edge.id = edge_id;
        edge.metadata = metadata;

        let created_edge = match self.storage.create_hyperedge(edge).await {
            Ok(_) => true,
            Err(err) => match self.storage.get_hyperedge(edge_id).await {
                Ok(_) => false,
                Err(_) => return Err(err).context("Failed to create conversation hyperedge"),
            },
        };

        if created_edge {
            update_session_metadata(&self.storage, turn.session_id, turn.timestamp).await?;
        }

        if let Some(index) = &self.vector_index {
            if let Err(err) = index.upsert_turn(&turn).await {
                warn!(error = %err, turn_id = %turn.id, "Memory vector upsert failed");
            }
        }

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
        max_turns: usize,
        min_similarity: f32,
    ) -> Result<RetrievedContext> {
        debug!("🔍 Searching for similar context to: {}", query);

        let Some(index) = &self.vector_index else {
            warn!("Qdrant not configured; returning empty semantic context");
            return Ok(RetrievedContext {
                turns: vec![],
                relevance_scores: vec![],
                total_tokens: 0,
            });
        };

        let limit = std::cmp::max(max_turns, 1) * 3;
        let mut hits = index.search_turns(query, limit).await?;

        hits.retain(|(_, score)| *score >= min_similarity);
        hits.truncate(max_turns);

        let mut context = RetrievedContext {
            turns: hits.iter().map(|(t, _)| t.clone()).collect(),
            relevance_scores: hits.iter().map(|(_, s)| *s).collect(),
            total_tokens: 0,
        };

        // Rough approximation: 4 chars ≈ 1 token
        context.total_tokens = context
            .turns
            .iter()
            .map(|turn| turn.char_count() / 4)
            .sum();

        Ok(context)
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
