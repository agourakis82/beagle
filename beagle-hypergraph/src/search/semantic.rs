use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::Row;
use std::collections::HashMap;
use tracing::{debug, instrument};

use crate::{
    error::HypergraphError,
    models::{ContentType, Node, ValidationError},
    storage::{PostgresStorage, StorageRepository},
    types::{Embedding, EMBEDDING_DIMENSION},
};

/// Resultado retornado por buscas semânticas.
#[derive(Debug, Clone)]
pub struct SearchResult {
    pub node: Node,
    pub similarity: f32,
    pub distance: f32,
}

/// Provedor genérico de embeddings (OpenAI, modelos locais, mocks).
#[async_trait]
pub trait EmbeddingProvider {
    /// Gera embedding a partir de texto.
    async fn embed(&self, text: &str) -> Result<Vec<f32>, HypergraphError>;

    /// Dimensão do embedding produzido.
    fn dimension(&self) -> usize;
}

/// Motor de busca semântica sobre storage PostgreSQL com pgvector.
pub struct SemanticSearch<'a> {
    storage: &'a PostgresStorage,
}

impl<'a> SemanticSearch<'a> {
    pub fn new(storage: &'a PostgresStorage) -> Self {
        Self { storage }
    }

    fn ensure_valid_dimension(embedding: &[f32]) -> Result<(), HypergraphError> {
        if embedding.len() != EMBEDDING_DIMENSION {
            return Err(HypergraphError::ValidationError(
                ValidationError::InvalidEmbeddingDimension {
                    expected: EMBEDDING_DIMENSION,
                    got: embedding.len(),
                },
            ));
        }
        Ok(())
    }

    #[instrument(
        name = "semantic_search.by_vector",
        skip(self, query_embedding),
        fields(dimension = query_embedding.len(), limit = limit)
    )]
    pub async fn search_by_vector(
        &self,
        query_embedding: &[f32],
        limit: usize,
        similarity_threshold: f32,
    ) -> Result<Vec<SearchResult>, HypergraphError> {
        Self::ensure_valid_dimension(query_embedding)?;

        debug!(
            dimension = query_embedding.len(),
            limit,
            threshold = similarity_threshold,
            "Executando busca semântica"
        );

        let embedding_param = Embedding::from(query_embedding.to_vec());

        let rows = sqlx::query(
            r#"
            SELECT
                id,
                content,
                content_type,
                metadata,
                embedding,
                created_at,
                updated_at,
                deleted_at,
                device_id,
                version,
                embedding <=> $1::vector AS distance
            FROM nodes
            WHERE embedding IS NOT NULL
              AND deleted_at IS NULL
              AND (1 - (embedding <=> $1::vector)) >= $2
            ORDER BY embedding <=> $1::vector
            LIMIT $3
            "#,
        )
        .bind(embedding_param)
        .bind(similarity_threshold as f64)
        .bind(limit as i64)
        .fetch_all(self.storage.pool())
        .await
        .map_err(HypergraphError::from)?;

        let mut search_results = Vec::with_capacity(rows.len());

        for row in rows {
            let node = row_to_node_with_embedding(&row)?;
            let distance: f64 = row.try_get("distance").map_err(HypergraphError::from)?;
            let similarity = (1.0 - distance) as f32;

            search_results.push(SearchResult {
                node,
                similarity,
                distance: distance as f32,
            });
        }

        debug!(results = search_results.len(), "Busca semântica concluída");

        Ok(search_results)
    }

    #[instrument(
        name = "semantic_search.by_text",
        skip(self, provider),
        fields(query_len = query.len(), limit = limit)
    )]
    pub async fn search_by_text<P: EmbeddingProvider>(
        &self,
        query: &str,
        provider: &P,
        limit: usize,
        similarity_threshold: f32,
    ) -> Result<Vec<SearchResult>, HypergraphError> {
        let query_embedding = provider.embed(query).await?;

        if query_embedding.len() != provider.dimension() {
            return Err(HypergraphError::ValidationError(
                ValidationError::InvalidEmbeddingDimension {
                    expected: provider.dimension(),
                    got: query_embedding.len(),
                },
            ));
        }

        self.search_by_vector(&query_embedding, limit, similarity_threshold)
            .await
    }

    #[instrument(name = "semantic_search.similar_to", skip(self))]
    pub async fn find_similar(
        &self,
        node_id: uuid::Uuid,
        limit: usize,
        similarity_threshold: f32,
    ) -> Result<Vec<SearchResult>, HypergraphError> {
        let row = sqlx::query(
            r#"
            SELECT
                id,
                content,
                content_type,
                metadata,
                embedding,
                created_at,
                updated_at,
                deleted_at,
                device_id,
                version
            FROM nodes
            WHERE id = $1
              AND deleted_at IS NULL
              AND embedding IS NOT NULL
            "#,
        )
        .bind(node_id)
        .fetch_optional(self.storage.pool())
        .await
        .map_err(HypergraphError::from)?;

        let row = row.ok_or_else(|| {
            HypergraphError::NotFound(format!("Node {} not found or has no embedding", node_id))
        })?;

        let node = row_to_node_with_embedding(&row)?;
        let embedding_vector = node.embedding.as_deref().ok_or_else(|| {
            HypergraphError::ValidationError(ValidationError::MissingField("embedding".into()))
        })?;

        let results = self
            .search_by_vector(embedding_vector, limit + 1, similarity_threshold)
            .await?;

        let mut filtered: Vec<SearchResult> = results
            .into_iter()
            .filter(|result| result.node.id != node_id)
            .collect();

        if filtered.len() > limit {
            filtered.truncate(limit);
        }

        Ok(filtered)
    }

    #[instrument(name = "semantic_search.hybrid", skip(self, provider))]
    pub async fn hybrid_search<P: EmbeddingProvider>(
        &self,
        query: &str,
        provider: &P,
        limit: usize,
        semantic_weight: f32,
    ) -> Result<Vec<SearchResult>, HypergraphError> {
        if !(0.0..=1.0).contains(&semantic_weight) {
            return Err(HypergraphError::OperationNotPermitted {
                reason: "semantic_weight must be between 0.0 and 1.0".into(),
            });
        }

        let semantic_results = self.search_by_text(query, provider, limit * 2, 0.5).await?;

        let fts_results = self.storage.search_nodes_fulltext(query, limit * 2).await?;

        let mut combined_scores = HashMap::<uuid::Uuid, f32>::with_capacity(limit * 2);

        for (rank, result) in semantic_results.iter().enumerate() {
            let score = semantic_weight / (rank as f32 + 60.0);
            combined_scores
                .entry(result.node.id)
                .and_modify(|value| *value += score)
                .or_insert(score);
        }

        for (rank, node) in fts_results.iter().enumerate() {
            let score = (1.0 - semantic_weight) / (rank as f32 + 60.0);
            combined_scores
                .entry(node.id)
                .and_modify(|value| *value += score)
                .or_insert(score);
        }

        let mut combined: Vec<(uuid::Uuid, f32)> = combined_scores.into_iter().collect();
        combined.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        let mut final_results = Vec::new();

        for (node_id, _) in combined.into_iter().take(limit) {
            match self.storage.get_node(node_id).await {
                Ok(node) => final_results.push(SearchResult {
                    node,
                    similarity: 0.0,
                    distance: 0.0,
                }),
                Err(HypergraphError::NodeNotFound(_)) => continue,
                Err(err) => return Err(err),
            }
        }

        Ok(final_results)
    }
}

fn parse_content_type(raw: &str) -> Result<ContentType, HypergraphError> {
    match raw {
        "Thought" => Ok(ContentType::Thought),
        "Memory" => Ok(ContentType::Memory),
        "Context" => Ok(ContentType::Context),
        "Task" => Ok(ContentType::Task),
        "Note" => Ok(ContentType::Note),
        other => Err(HypergraphError::InternalError(format!(
            "Unknown content type: {other}"
        ))),
    }
}

fn row_to_node_with_embedding(row: &sqlx::postgres::PgRow) -> Result<Node, HypergraphError> {
    let content_type_raw: String = row.try_get("content_type").map_err(HypergraphError::from)?;
    let content_type = parse_content_type(&content_type_raw)?;

    let embedding: Option<Embedding> = row.try_get("embedding").map_err(HypergraphError::from)?;

    Ok(Node {
        id: row.try_get("id").map_err(HypergraphError::from)?,
        content: row.try_get("content").map_err(HypergraphError::from)?,
        content_type,
        metadata: row.try_get("metadata").map_err(HypergraphError::from)?,
        embedding,
        created_at: row
            .try_get::<DateTime<Utc>, _>("created_at")
            .map_err(HypergraphError::from)?,
        updated_at: row
            .try_get::<DateTime<Utc>, _>("updated_at")
            .map_err(HypergraphError::from)?,
        deleted_at: row
            .try_get::<Option<DateTime<Utc>>, _>("deleted_at")
            .map_err(HypergraphError::from)?,
        device_id: row.try_get("device_id").map_err(HypergraphError::from)?,
        version: row.try_get("version").map_err(HypergraphError::from)?,
    })
}

/// Provedor de embeddings baseado na API OpenAI.
pub struct OpenAIEmbeddings {
    api_key: String,
    model: String,
    client: reqwest::Client,
}

impl OpenAIEmbeddings {
    pub fn new(api_key: String) -> Self {
        Self {
            api_key,
            model: "text-embedding-ada-002".to_string(),
            client: reqwest::Client::new(),
        }
    }

    pub fn with_model(api_key: String, model: String) -> Self {
        Self {
            api_key,
            model,
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl EmbeddingProvider for OpenAIEmbeddings {
    async fn embed(&self, text: &str) -> Result<Vec<f32>, HypergraphError> {
        #[derive(serde::Serialize)]
        struct EmbedRequest<'a> {
            input: &'a str,
            model: &'a str,
        }

        #[derive(serde::Deserialize)]
        struct EmbedResponse {
            data: Vec<EmbedData>,
        }

        #[derive(serde::Deserialize)]
        struct EmbedData {
            embedding: Vec<f32>,
        }

        let response = self
            .client
            .post("https://api.openai.com/v1/embeddings")
            .bearer_auth(&self.api_key)
            .json(&EmbedRequest {
                input: text,
                model: &self.model,
            })
            .send()
            .await
            .map_err(|err| HypergraphError::External(format!("OpenAI request error: {err}")))?;

        if !response.status().is_success() {
            let detail = response
                .text()
                .await
                .unwrap_or_else(|_| "unknown error".to_string());
            return Err(HypergraphError::External(format!(
                "OpenAI API returned error: {detail}"
            )));
        }

        let embed_response = response
            .json::<EmbedResponse>()
            .await
            .map_err(|err| HypergraphError::External(format!("OpenAI parse error: {err}")))?;

        embed_response
            .data
            .into_iter()
            .next()
            .map(|item| item.embedding)
            .ok_or_else(|| HypergraphError::External("OpenAI response missing embedding".into()))
    }

    fn dimension(&self) -> usize {
        EMBEDDING_DIMENSION
    }
}

/// Provedor mock determinístico para cenários de teste.
pub struct MockEmbeddings;

#[async_trait]
impl EmbeddingProvider for MockEmbeddings {
    async fn embed(&self, text: &str) -> Result<Vec<f32>, HypergraphError> {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();
        text.hash(&mut hasher);
        let seed = hasher.finish();

        let mut embedding = Vec::with_capacity(EMBEDDING_DIMENSION);
        for i in 0..EMBEDDING_DIMENSION {
            let raw = seed.wrapping_add(i as u64) as f64 / u64::MAX as f64;
            embedding.push((raw * 2.0 - 1.0) as f32);
        }

        Ok(embedding)
    }

    fn dimension(&self) -> usize {
        EMBEDDING_DIMENSION
    }
}

#[cfg(test)]
mod semantic_tests {
    use super::*;
    use crate::models::{ContentType, Node};
    use crate::storage::{PostgresStorage, StorageRepository};

    fn test_database_url() -> String {
        std::env::var("DATABASE_URL").expect("DATABASE_URL must be set for semantic tests")
    }

    #[tokio::test]
    async fn test_semantic_search_by_vector() {
        let storage = PostgresStorage::new(&test_database_url()).await.unwrap();

        let embedding1 = vec![0.1f32; EMBEDDING_DIMENSION];
        let embedding2 = vec![0.9f32; EMBEDDING_DIMENSION];

        let node1 = Node::builder()
            .content("Machine learning and artificial intelligence")
            .content_type(ContentType::Thought)
            .embedding(embedding1.clone())
            .device_id("test-device")
            .build()
            .unwrap();

        let node2 = Node::builder()
            .content("Cooking recipes and food")
            .content_type(ContentType::Note)
            .embedding(embedding2.clone())
            .device_id("test-device")
            .build()
            .unwrap();

        let node1 = storage.create_node(node1).await.unwrap();
        let node2 = storage.create_node(node2).await.unwrap();

        let search = SemanticSearch::new(&storage);
        let results = search.search_by_vector(&embedding1, 10, 0.9).await.unwrap();

        assert!(results.iter().any(|r| r.node.id == node1.id));
        assert!(results.first().map(|r| r.similarity).unwrap_or(0.0) > 0.99);
        assert!(results.iter().all(|r| r.similarity >= 0.9));

        // Cleanup
        storage.delete_node(node1.id).await.unwrap();
        storage.delete_node(node2.id).await.unwrap();
    }

    #[tokio::test]
    async fn test_find_similar_nodes() {
        let storage = PostgresStorage::new(&test_database_url()).await.unwrap();

        let base_embedding = vec![0.5f32; EMBEDDING_DIMENSION];

        let node = Node::builder()
            .content("Reference node for similarity")
            .content_type(ContentType::Context)
            .embedding(base_embedding.clone())
            .device_id("test-device")
            .build()
            .unwrap();

        let node = storage.create_node(node).await.unwrap();

        // Add a slightly different node to ensure we can retrieve something
        let neighbour = Node::builder()
            .content("Similar context node")
            .content_type(ContentType::Context)
            .embedding(
                base_embedding
                    .iter()
                    .map(|v| v + 0.0001)
                    .collect::<Vec<f32>>(),
            )
            .device_id("test-device")
            .build()
            .unwrap();

        let neighbour = storage.create_node(neighbour).await.unwrap();

        let search = SemanticSearch::new(&storage);
        let similar = search.find_similar(node.id, 5, 0.7).await.unwrap();

        assert!(similar.iter().all(|r| r.node.id != node.id));

        // Cleanup
        storage.delete_node(node.id).await.unwrap();
        storage.delete_node(neighbour.id).await.unwrap();
    }

    #[tokio::test]
    async fn test_mock_embeddings() {
        let provider = MockEmbeddings;

        let embedding1 = provider.embed("hello world").await.unwrap();
        let embedding2 = provider.embed("hello world").await.unwrap();

        assert_eq!(embedding1, embedding2);
        assert_eq!(embedding1.len(), EMBEDDING_DIMENSION);
    }
}
