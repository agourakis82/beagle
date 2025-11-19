//! Vector Search Híbrido - Dense + Sparse + RRF
//! Integrado com beagle-hypergraph

use anyhow::Result;
use beagle_hypergraph::search::{SearchResult, SemanticSearch};
use beagle_hypergraph::embeddings::EmbeddingGenerator;
use std::sync::Arc;
use tracing::info;

pub struct HybridVectorSearch {
    semantic_search: Arc<SemanticSearch>,
}

impl HybridVectorSearch {
    pub fn new(semantic_search: Arc<SemanticSearch>) -> Self {
        info!("🔍 HybridVectorSearch inicializado");
        Self { semantic_search }
    }

    pub async fn search<G: EmbeddingGenerator>(
        &self,
        query: &str,
        provider: &G,
        top_k: usize,
        dense_weight: f32,
    ) -> Result<Vec<SearchResult>> {
        info!("🔎 Buscando top-{} resultados (dense_weight: {})", top_k, dense_weight);
        
        let results = self
            .semantic_search
            .hybrid_search(query, provider, top_k, dense_weight)
            .await
            .map_err(|e| anyhow::anyhow!("Search error: {}", e))?;

        Ok(results)
    }

    pub async fn search_by_vector(
        &self,
        query_embedding: &[f32],
        top_k: usize,
        threshold: f32,
    ) -> Result<Vec<SearchResult>> {
        info!("🔎 Busca por vetor (top-{}, threshold: {})", top_k, threshold);
        
        let results = self
            .semantic_search
            .search_by_vector(query_embedding, top_k, threshold)
            .await
            .map_err(|e| anyhow::anyhow!("Vector search error: {}", e))?;

        Ok(results)
    }
}
