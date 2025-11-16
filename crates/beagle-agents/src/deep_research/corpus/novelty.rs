//! Novelty scorer comparing hypotheses against scientific corpus
//!
//! Uses embedding-based similarity to measure how novel a hypothesis is
//! compared to existing literature from Semantic Scholar.

use super::{EmbeddingEngine, Paper, ScholarAPI};
use anyhow::Result;
use std::sync::Arc;
use tracing::{info, warn};

/// Novelty scorer that compares hypotheses against scientific corpus
pub struct NoveltyScorer {
    scholar: Arc<ScholarAPI>,
    embeddings: Arc<EmbeddingEngine>,
    corpus_cache: Arc<tokio::sync::RwLock<Vec<CorpusEntry>>>,
}

/// Cached corpus entry with embedding
#[derive(Debug, Clone)]
struct CorpusEntry {
    paper: Paper,
    embedding: Vec<f32>,
}

impl NoveltyScorer {
    /// Create a new novelty scorer
    pub fn new(scholar: Arc<ScholarAPI>, embeddings: Arc<EmbeddingEngine>) -> Self {
        Self {
            scholar,
            embeddings,
            corpus_cache: Arc::new(tokio::sync::RwLock::new(Vec::new())),
        }
    }

    /// Build corpus from search queries
    ///
    /// # Arguments
    /// * `queries` - Vector of search queries to populate corpus
    /// * `papers_per_query` - Number of papers to fetch per query
    ///
    /// # Returns
    /// Number of papers added to corpus
    pub async fn build_corpus(&self, queries: &[String], papers_per_query: usize) -> Result<usize> {
        info!("📚 Building corpus from {} queries", queries.len());

        let mut all_papers = Vec::new();

        for query in queries {
            let papers = self.scholar.search(query, papers_per_query).await?;
            all_papers.extend(papers);
        }

        // Remove duplicates by paper_id
        let mut seen = std::collections::HashSet::new();
        let unique_papers: Vec<Paper> = all_papers
            .into_iter()
            .filter(|p| seen.insert(p.paper_id.clone()))
            .collect();

        info!("📄 Found {} unique papers, generating embeddings...", unique_papers.len());

        // Generate embeddings for all papers
        let texts: Vec<String> = unique_papers
            .iter()
            .map(|p| {
                format!(
                    "{}. {}",
                    p.title,
                    p.abstract_text.as_deref().unwrap_or("")
                )
            })
            .collect();

        let embeddings = self.embeddings.embed_batch(&texts).await?;

        // Build corpus entries
        let mut entries = Vec::new();
        for (paper, embedding) in unique_papers.into_iter().zip(embeddings.into_iter()) {
            entries.push(CorpusEntry { paper, embedding });
        }

        // Update cache
        let mut cache = self.corpus_cache.write().await;
        cache.extend(entries);
        let total = cache.len();

        info!("✅ Corpus built: {} papers with embeddings", total);

        Ok(total)
    }

    /// Score novelty of a hypothesis against corpus
    ///
    /// # Arguments
    /// * `hypothesis_text` - Text of the hypothesis to score
    ///
    /// # Returns
    /// Novelty score (0.0 = highly similar to existing work, 1.0 = completely novel)
    ///
    /// Novelty is calculated as: 1.0 - max_similarity
    /// where max_similarity is the highest cosine similarity to any paper in corpus
    pub async fn score_novelty(&self, hypothesis_text: &str) -> Result<f64> {
        // Generate embedding for hypothesis
        let hyp_embedding = self.embeddings.embed(hypothesis_text).await?;

        // Compare against corpus
        let cache = self.corpus_cache.read().await;

        if cache.is_empty() {
            warn!("⚠️  Corpus is empty, returning default novelty 0.5");
            return Ok(0.5);
        }

        // Find maximum similarity
        let max_similarity = cache
            .iter()
            .map(|entry| EmbeddingEngine::cosine_similarity(&hyp_embedding, &entry.embedding))
            .fold(0.0f64, f64::max);

        // Novelty = 1.0 - similarity (higher similarity = lower novelty)
        let novelty = (1.0 - max_similarity).max(0.0);

        info!(
            "🎯 Novelty score: {:.3} (max_similarity: {:.3}, corpus_size: {})",
            novelty,
            max_similarity,
            cache.len()
        );

        Ok(novelty)
    }

    /// Find most similar papers to hypothesis
    ///
    /// # Arguments
    /// * `hypothesis_text` - Text of the hypothesis
    /// * `top_k` - Number of similar papers to return
    ///
    /// # Returns
    /// Vector of (paper, similarity_score) tuples, sorted by similarity
    pub async fn find_similar_papers(
        &self,
        hypothesis_text: &str,
        top_k: usize,
    ) -> Result<Vec<(Paper, f64)>> {
        let hyp_embedding = self.embeddings.embed(hypothesis_text).await?;

        let cache = self.corpus_cache.read().await;

        if cache.is_empty() {
            return Ok(vec![]);
        }

        // Calculate similarities
        let mut similarities: Vec<(Paper, f64)> = cache
            .iter()
            .map(|entry| {
                let sim = EmbeddingEngine::cosine_similarity(&hyp_embedding, &entry.embedding);
                (entry.paper.clone(), sim)
            })
            .collect();

        // Sort by similarity (descending)
        similarities.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

        // Take top k
        let top = similarities.into_iter().take(top_k).collect();

        Ok(top)
    }

    /// Get corpus size
    pub async fn corpus_size(&self) -> usize {
        self.corpus_cache.read().await.len()
    }

    /// Clear corpus cache
    pub async fn clear_corpus(&self) {
        let mut cache = self.corpus_cache.write().await;
        cache.clear();
        info!("🗑️  Corpus cache cleared");
    }
}


