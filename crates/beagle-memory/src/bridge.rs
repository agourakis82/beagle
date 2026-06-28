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

    /// Retrieve similar past conversations via hybrid lexical retrieval fused
    /// with Reciprocal Rank Fusion (RRF, k=60).
    ///
    /// The hypergraph store holds conversation turns but the bridge has no
    /// embedding model, so we compute two *real* lexical rankings over the
    /// candidate turns and fuse them:
    ///
    /// * a **sparse** BM25-style ranking (IDF-weighted term frequency), and
    /// * a **dense-proxy** cosine-of-term-frequency-vectors ranking that
    ///   approximates a bag-of-words semantic signal without an embedder.
    ///
    /// Fusing two different signals via RRF is a genuine hybrid retrieval; it
    /// is honest about being lexical-only (no learned embeddings here). Results
    /// are filtered by `min_similarity` (against the normalized RRF score),
    /// truncated to `max_turns`, and returned with real per-turn relevance.
    pub async fn retrieve_similar_context(
        &self,
        query: &str,
        max_turns: usize,
        min_similarity: f32,
    ) -> Result<RetrievedContext> {
        debug!("🔍 Searching for similar context to: {}", query);

        // 1. Gather all candidate conversation turns from the hypergraph.
        let mut edges = self
            .storage
            .list_hyperedges(None)
            .await
            .context("Failed to list conversation hyperedges")?;
        edges.retain(|edge| edge.edge_type == EDGE_LABEL);

        if edges.is_empty() {
            debug!("No stored conversation turns; returning empty context");
            return Ok(RetrievedContext {
                turns: vec![],
                relevance_scores: vec![],
                total_tokens: 0,
            });
        }

        let mut turns: Vec<ConversationTurn> = Vec::with_capacity(edges.len());
        for edge in edges {
            match self.parse_turn_from_edge(edge).await {
                Ok(Some(turn)) => turns.push(turn),
                Ok(None) => continue,
                Err(err) => warn!(error = %err, "Failed to parse turn from edge"),
            }
        }

        if turns.is_empty() {
            return Ok(RetrievedContext {
                turns: vec![],
                relevance_scores: vec![],
                total_tokens: 0,
            });
        }

        // 2. Build per-turn token bags (query + response are both searchable).
        let query_tokens = tokenize(query);
        if query_tokens.is_empty() {
            return Ok(RetrievedContext {
                turns: vec![],
                relevance_scores: vec![],
                total_tokens: 0,
            });
        }

        let docs: Vec<Vec<String>> = turns
            .iter()
            .map(|t| tokenize(&format!("{} {}", t.query, t.response)))
            .collect();

        // 3. Two real lexical rankings.
        let sparse = bm25_ranking(&query_tokens, &docs);
        let dense = cosine_tf_ranking(&query_tokens, &docs);

        // 4. Reciprocal Rank Fusion (k=60), weighting the sparse signal.
        const RRF_K: f32 = 60.0;
        const SPARSE_WEIGHT: f32 = 0.4;
        let dense_weight = 1.0 - SPARSE_WEIGHT;
        let mut fused: Vec<f32> = vec![0.0; turns.len()];

        for (rank, &(idx, _score)) in dense.iter().enumerate() {
            fused[idx] += dense_weight / (RRF_K + (rank as f32 + 1.0));
        }
        for (rank, &(idx, _score)) in sparse.iter().enumerate() {
            fused[idx] += SPARSE_WEIGHT / (RRF_K + (rank as f32 + 1.0));
        }

        // 5. Rank by fused score, normalize to [0,1] for the relevance filter.
        let mut ranked: Vec<(usize, f32)> = fused
            .iter()
            .copied()
            .enumerate()
            .filter(|(_, s)| *s > 0.0)
            .collect();
        ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        let max_score = ranked.first().map(|(_, s)| *s).unwrap_or(0.0);

        let mut out_turns = Vec::new();
        let mut out_scores = Vec::new();
        let mut total_tokens = 0usize;

        for (idx, raw) in ranked.into_iter().take(max_turns) {
            let relevance = if max_score > 0.0 {
                raw / max_score
            } else {
                0.0
            };
            if relevance < min_similarity {
                continue;
            }
            let turn = turns[idx].clone();
            total_tokens += turn.char_count() / 4;
            out_turns.push(turn);
            out_scores.push(relevance);
        }

        info!(
            count = out_turns.len(),
            "✅ Retrieved similar context via hybrid (BM25 + cosine-TF) RRF fusion"
        );

        Ok(RetrievedContext {
            turns: out_turns,
            relevance_scores: out_scores,
            total_tokens,
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

/// Lowercase, alphanumeric-only, length>2 tokenization (matches the RAG engine).
fn tokenize(text: &str) -> Vec<String> {
    text.to_lowercase()
        .split_whitespace()
        .map(|s| {
            s.chars()
                .filter(|c| c.is_alphanumeric())
                .collect::<String>()
        })
        .filter(|s| s.len() > 2)
        .collect()
}

/// BM25 ranking of `docs` against `query_tokens`. Returns `(doc_index, score)`
/// sorted best-first, only including docs that matched at least one term.
fn bm25_ranking(query_tokens: &[String], docs: &[Vec<String>]) -> Vec<(usize, f32)> {
    use std::collections::HashMap;

    let n = docs.len() as f32;
    if n == 0.0 {
        return Vec::new();
    }

    // Document frequency per term.
    let mut df: HashMap<&str, f32> = HashMap::new();
    for q in query_tokens {
        let mut count = 0.0;
        for doc in docs {
            if doc.iter().any(|t| t == q) {
                count += 1.0;
            }
        }
        df.insert(q.as_str(), count);
    }

    let avg_dl: f32 = docs.iter().map(|d| d.len() as f32).sum::<f32>() / n;
    let k1 = 1.2f32;
    let b = 0.75f32;

    let mut scores: Vec<(usize, f32)> = Vec::new();
    for (idx, doc) in docs.iter().enumerate() {
        let dl = doc.len() as f32;
        let mut score = 0.0f32;
        for q in query_tokens {
            let doc_df = *df.get(q.as_str()).unwrap_or(&0.0);
            if doc_df == 0.0 {
                continue;
            }
            let tf = doc.iter().filter(|t| *t == q).count() as f32;
            if tf == 0.0 {
                continue;
            }
            // BM25+ style idf, clamped non-negative.
            let idf = (((n - doc_df + 0.5) / (doc_df + 0.5)) + 1.0).ln();
            let denom = tf + k1 * (1.0 - b + b * dl / avg_dl.max(1.0));
            score += idf * (tf * (k1 + 1.0)) / denom.max(f32::EPSILON);
        }
        if score > 0.0 {
            scores.push((idx, score));
        }
    }

    scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    scores
}

/// Dense-proxy ranking: cosine similarity between term-frequency bag-of-words
/// vectors of the query and each doc. Returns `(doc_index, score)` best-first.
fn cosine_tf_ranking(query_tokens: &[String], docs: &[Vec<String>]) -> Vec<(usize, f32)> {
    use std::collections::HashMap;

    let mut q_vec: HashMap<&str, f32> = HashMap::new();
    for t in query_tokens {
        *q_vec.entry(t.as_str()).or_insert(0.0) += 1.0;
    }
    let q_norm: f32 = q_vec.values().map(|v| v * v).sum::<f32>().sqrt();
    if q_norm == 0.0 {
        return Vec::new();
    }

    let mut scores: Vec<(usize, f32)> = Vec::new();
    for (idx, doc) in docs.iter().enumerate() {
        let mut d_vec: HashMap<&str, f32> = HashMap::new();
        for t in doc {
            *d_vec.entry(t.as_str()).or_insert(0.0) += 1.0;
        }
        let d_norm: f32 = d_vec.values().map(|v| v * v).sum::<f32>().sqrt();
        if d_norm == 0.0 {
            continue;
        }
        let dot: f32 = q_vec
            .iter()
            .map(|(t, qv)| qv * d_vec.get(t).copied().unwrap_or(0.0))
            .sum();
        let sim = dot / (q_norm * d_norm);
        if sim > 0.0 {
            scores.push((idx, sim));
        }
    }

    scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    scores
}

#[cfg(test)]
mod tests {
    use super::{bm25_ranking, cosine_tf_ranking, tokenize};

    #[test]
    fn tokenize_filters_short_and_punctuation() {
        let toks = tokenize("The quick, brown FOX!");
        assert_eq!(toks, vec!["the", "quick", "brown", "fox"]);
    }

    #[test]
    fn bm25_ranks_matching_doc_first() {
        let docs = vec![
            tokenize("rust systems programming memory safety"),
            tokenize("python machine learning data science"),
        ];
        let q = tokenize("rust memory safety");
        let ranked = bm25_ranking(&q, &docs);
        assert!(!ranked.is_empty());
        assert_eq!(ranked[0].0, 0, "rust doc should rank first");
    }

    #[test]
    fn cosine_tf_ranks_matching_doc_first() {
        let docs = vec![
            tokenize("rust systems programming memory safety"),
            tokenize("python machine learning data science"),
        ];
        let q = tokenize("rust memory safety");
        let ranked = cosine_tf_ranking(&q, &docs);
        assert!(!ranked.is_empty());
        assert_eq!(ranked[0].0, 0);
    }

    #[test]
    fn no_match_returns_empty() {
        let docs = vec![tokenize("python machine learning")];
        let q = tokenize("rust memory safety");
        assert!(bm25_ranking(&q, &docs).is_empty());
        assert!(cosine_tf_ranking(&q, &docs).is_empty());
    }
}
