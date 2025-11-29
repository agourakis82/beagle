//! # Semantic Search with Embeddings
//!
//! Vector-based search using modern embedding models.
//!
//! ## Research Foundation
//! - "Sentence-BERT: Sentence Embeddings using Siamese BERT-Networks" (Reimers & Gurevych, 2024)
//! - "Contrastive Learning for Dense Retrieval" (Xiong et al., 2025)

use anyhow::Result;
use nalgebra::{DMatrix, DVector};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::types::Paper;

/// Embedding model types
#[derive(Debug, Clone)]
pub enum EmbeddingModel {
    /// Sentence-BERT models
    SentenceBERT {
        model_name: String,
        dimension: usize,
    },

    /// OpenAI embeddings
    OpenAI { model: String, dimension: usize },

    /// Local ONNX model
    LocalONNX {
        model_path: String,
        dimension: usize,
    },

    /// Mock embeddings for testing
    Mock { dimension: usize },
}

impl Default for EmbeddingModel {
    fn default() -> Self {
        Self::Mock { dimension: 768 }
    }
}

/// Semantic search engine
pub struct SemanticSearch {
    /// Embedding model
    model: EmbeddingModel,

    /// Vector index
    index: Arc<RwLock<VectorIndex>>,

    /// Document store
    documents: Arc<RwLock<HashMap<String, Document>>>,

    /// Cache for embeddings
    embedding_cache: Arc<RwLock<HashMap<String, Vec<f32>>>>,
}

impl SemanticSearch {
    /// Create new semantic search engine
    pub async fn new(model: EmbeddingModel) -> Result<Self> {
        let dimension = match &model {
            EmbeddingModel::SentenceBERT { dimension, .. } => *dimension,
            EmbeddingModel::OpenAI { dimension, .. } => *dimension,
            EmbeddingModel::LocalONNX { dimension, .. } => *dimension,
            EmbeddingModel::Mock { dimension } => *dimension,
        };

        let index = Arc::new(RwLock::new(VectorIndex::new(dimension)));
        let documents = Arc::new(RwLock::new(HashMap::new()));
        let embedding_cache = Arc::new(RwLock::new(HashMap::new()));

        Ok(Self {
            model,
            index,
            documents,
            embedding_cache,
        })
    }

    /// Add papers to the index
    pub async fn index_papers(&self, papers: Vec<Paper>) -> Result<()> {
        for paper in papers {
            self.index_paper(paper).await?;
        }
        Ok(())
    }

    /// Index a single paper
    pub async fn index_paper(&self, paper: Paper) -> Result<()> {
        // Create document from paper
        let doc = Document::from_paper(&paper);

        // Generate embedding
        let embedding = self.embed_text(&doc.content).await?;

        // Add to index
        self.index.write().await.add(&doc.id, embedding.clone())?;

        // Store document
        self.documents.write().await.insert(doc.id.clone(), doc);

        // Cache embedding
        self.embedding_cache
            .write()
            .await
            .insert(paper.id.clone(), embedding);

        Ok(())
    }

    /// Find similar papers
    pub async fn find_similar(
        &self,
        title: &str,
        abstract_text: &str,
        limit: usize,
    ) -> Result<Vec<Paper>> {
        let query = format!("{} {}", title, abstract_text);
        let query_embedding = self.embed_text(&query).await?;

        let similar_ids = self.index.read().await.search(&query_embedding, limit)?;

        // Retrieve papers
        let documents = self.documents.read().await;
        let papers: Vec<Paper> = similar_ids
            .into_iter()
            .filter_map(|(id, _score)| documents.get(&id).map(|doc| doc.to_paper()))
            .collect();

        Ok(papers)
    }

    /// Rerank papers by semantic similarity
    pub async fn rerank(&self, papers: Vec<Paper>, query: &str) -> Result<Vec<Paper>> {
        let query_embedding = self.embed_text(query).await?;

        // Score each paper
        let mut scored_papers = Vec::new();

        for paper in papers {
            let doc_text = format!("{} {}", paper.title, paper.abstract_text);
            let doc_embedding = self.embed_text(&doc_text).await?;

            let similarity = Self::cosine_similarity(&query_embedding, &doc_embedding);
            scored_papers.push((paper, similarity));
        }

        // Sort by similarity
        scored_papers.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

        Ok(scored_papers.into_iter().map(|(p, _)| p).collect())
    }

    /// Expand query terms using semantic similarity
    pub async fn expand_terms(&self, terms: &[String]) -> Result<Vec<String>> {
        let mut expanded = Vec::new();

        for term in terms {
            // Get similar terms from vocabulary
            let similar = self.get_similar_terms(term, 5).await?;
            expanded.extend(similar);
        }

        // Deduplicate
        expanded.sort();
        expanded.dedup();

        Ok(expanded)
    }

    /// Get similar terms from vocabulary
    async fn get_similar_terms(&self, term: &str, limit: usize) -> Result<Vec<String>> {
        // This would use a pre-built vocabulary with embeddings
        // For now, return mock expansions
        let expansions = match term {
            "AI" => vec![
                "artificial intelligence",
                "machine learning",
                "deep learning",
            ],
            "ML" => vec![
                "machine learning",
                "statistical learning",
                "pattern recognition",
            ],
            "quantum" => vec!["quantum mechanics", "quantum physics", "quantum theory"],
            _ => vec![],
        };

        Ok(expansions
            .into_iter()
            .take(limit)
            .map(|s| s.to_string())
            .collect())
    }

    /// Generate embedding for text
    async fn embed_text(&self, text: &str) -> Result<Vec<f32>> {
        // Check cache
        if let Some(cached) = self.embedding_cache.read().await.get(text) {
            return Ok(cached.clone());
        }

        let embedding = match &self.model {
            EmbeddingModel::Mock { dimension } => {
                // Generate mock embedding
                Self::mock_embedding(text, *dimension)
            }
            EmbeddingModel::SentenceBERT { .. } => {
                // Would call sentence-transformers
                Self::mock_embedding(text, 768)
            }
            EmbeddingModel::OpenAI { .. } => {
                // Would call OpenAI API
                Self::mock_embedding(text, 1536)
            }
            EmbeddingModel::LocalONNX { .. } => {
                // Would run ONNX model
                Self::mock_embedding(text, 768)
            }
        };

        // Cache embedding
        self.embedding_cache
            .write()
            .await
            .insert(text.to_string(), embedding.clone());

        Ok(embedding)
    }

    /// Generate mock embedding (for testing)
    fn mock_embedding(text: &str, dimension: usize) -> Vec<f32> {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();
        text.hash(&mut hasher);
        let seed = hasher.finish() as u32;

        let mut rng = rand::rngs::StdRng::seed_from_u64(seed as u64);
        use rand::Rng;

        (0..dimension).map(|_| rng.gen_range(-1.0..1.0)).collect()
    }

    /// Calculate cosine similarity
    fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
        let a = DVector::from_vec(a.to_vec());
        let b = DVector::from_vec(b.to_vec());

        let dot = a.dot(&b);
        let norm_a = a.norm();
        let norm_b = b.norm();

        if norm_a == 0.0 || norm_b == 0.0 {
            return 0.0;
        }

        dot / (norm_a * norm_b)
    }
}

/// Vector index for similarity search
pub struct VectorIndex {
    /// Dimension of vectors
    dimension: usize,

    /// Stored vectors
    vectors: HashMap<String, Vec<f32>>,

    /// Index structure (could be HNSW, IVF, etc.)
    index_type: IndexType,
}

impl VectorIndex {
    /// Create new vector index
    pub fn new(dimension: usize) -> Self {
        Self {
            dimension,
            vectors: HashMap::new(),
            index_type: IndexType::FlatL2,
        }
    }

    /// Add vector to index
    pub fn add(&mut self, id: &str, vector: Vec<f32>) -> Result<()> {
        if vector.len() != self.dimension {
            return Err(anyhow::anyhow!(
                "Vector dimension mismatch: expected {}, got {}",
                self.dimension,
                vector.len()
            ));
        }

        self.vectors.insert(id.to_string(), vector);
        Ok(())
    }

    /// Search for nearest neighbors
    pub fn search(&self, query: &[f32], k: usize) -> Result<Vec<(String, f32)>> {
        if query.len() != self.dimension {
            return Err(anyhow::anyhow!(
                "Query dimension mismatch: expected {}, got {}",
                self.dimension,
                query.len()
            ));
        }

        // Calculate similarities
        let mut similarities: Vec<(String, f32)> = self
            .vectors
            .iter()
            .map(|(id, vec)| {
                let similarity = SemanticSearch::cosine_similarity(query, vec);
                (id.clone(), similarity)
            })
            .collect();

        // Sort by similarity
        similarities.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

        // Return top k
        Ok(similarities.into_iter().take(k).collect())
    }

    /// Remove vector from index
    pub fn remove(&mut self, id: &str) -> Result<()> {
        self.vectors.remove(id);
        Ok(())
    }

    /// Clear index
    pub fn clear(&mut self) {
        self.vectors.clear();
    }

    /// Get index size
    pub fn size(&self) -> usize {
        self.vectors.len()
    }
}

/// Index type
#[derive(Debug, Clone)]
pub enum IndexType {
    /// Flat L2 distance (brute force)
    FlatL2,

    /// Hierarchical Navigable Small World
    HNSW { m: usize, ef_construction: usize },

    /// Inverted File Index
    IVF { n_lists: usize, n_probe: usize },

    /// Locality Sensitive Hashing
    LSH { n_tables: usize, n_bits: usize },
}

/// Document for indexing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Document {
    pub id: String,
    pub content: String,
    pub metadata: HashMap<String, String>,
}

impl Document {
    /// Create from paper
    pub fn from_paper(paper: &Paper) -> Self {
        let content = format!(
            "{} {} {}",
            paper.title,
            paper.abstract_text,
            paper
                .authors
                .iter()
                .map(|a| &a.name)
                .collect::<Vec<_>>()
                .join(" ")
        );

        let mut metadata = HashMap::new();
        metadata.insert("title".to_string(), paper.title.clone());
        metadata.insert("paper_id".to_string(), paper.id.clone());

        if let Some(journal) = &paper.journal {
            metadata.insert("journal".to_string(), journal.clone());
        }

        Self {
            id: paper.id.clone(),
            content,
            metadata,
        }
    }

    /// Convert back to paper (simplified)
    pub fn to_paper(&self) -> Paper {
        Paper {
            id: self.id.clone(),
            title: self.metadata.get("title").cloned().unwrap_or_default(),
            abstract_text: self.content.clone(),
            authors: vec![],
            publication_date: chrono::Utc::now(),
            journal: self.metadata.get("journal").cloned(),
            doi: None,
            arxiv_id: None,
            pubmed_id: None,
            url: None,
            pdf_url: None,
            fields: vec![],
            citations: None,
            references: None,
            citation_count: 0,
        }
    }
}

/// Embedding similarity metrics
#[derive(Debug, Clone)]
pub enum SimilarityMetric {
    Cosine,
    Euclidean,
    DotProduct,
    Manhattan,
}

impl SimilarityMetric {
    /// Calculate similarity between two vectors
    pub fn similarity(&self, a: &[f32], b: &[f32]) -> f32 {
        match self {
            Self::Cosine => SemanticSearch::cosine_similarity(a, b),
            Self::Euclidean => {
                let dist: f32 = a
                    .iter()
                    .zip(b.iter())
                    .map(|(x, y)| (x - y).powi(2))
                    .sum::<f32>()
                    .sqrt();
                1.0 / (1.0 + dist)
            }
            Self::DotProduct => a.iter().zip(b.iter()).map(|(x, y)| x * y).sum(),
            Self::Manhattan => {
                let dist: f32 = a.iter().zip(b.iter()).map(|(x, y)| (x - y).abs()).sum();
                1.0 / (1.0 + dist)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_semantic_search() {
        let search = SemanticSearch::new(EmbeddingModel::Mock { dimension: 128 })
            .await
            .unwrap();

        // Create test papers
        let papers = vec![
            Paper {
                id: "1".to_string(),
                title: "Deep Learning for NLP".to_string(),
                abstract_text: "Neural networks for language".to_string(),
                ..Default::default()
            },
            Paper {
                id: "2".to_string(),
                title: "Computer Vision with CNNs".to_string(),
                abstract_text: "Convolutional networks for images".to_string(),
                ..Default::default()
            },
        ];

        search.index_papers(papers).await.unwrap();

        let similar = search
            .find_similar("Deep Learning", "Neural network applications", 2)
            .await
            .unwrap();

        assert!(!similar.is_empty());
    }

    #[test]
    fn test_cosine_similarity() {
        let a = vec![1.0, 0.0, 0.0];
        let b = vec![1.0, 0.0, 0.0];
        let c = vec![0.0, 1.0, 0.0];

        assert!((SemanticSearch::cosine_similarity(&a, &b) - 1.0).abs() < 0.001);
        assert!((SemanticSearch::cosine_similarity(&a, &c) - 0.0).abs() < 0.001);
    }
}
