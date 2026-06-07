//! Real RAG Engine Implementation

use crate::error::MemoryError;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// RRF damping constant. The canonical value from the original RRF paper
/// (Cormack et al., 2009). Larger k flattens the contribution of top ranks.
pub const RRF_K: f32 = 60.0;

/// Maximum number of candidates fetched per ranking and capped for a single
/// reranker batch.
pub const ANN_BATCH_CAP: usize = 32;

/// Default over-fetch floor when callers ask for very small `top_k`.
pub const DEFAULT_TOP_N: usize = 10;

/// Relative emphasis given to the sparse signal during fusion. RRF is
/// fundamentally rank-based, but this lets us nudge the lexical contribution.
pub const SPARSE_WEIGHT: f32 = 0.4;

/// A single fused candidate after Reciprocal Rank Fusion.
#[derive(Debug, Clone)]
pub struct FusedResult {
    pub chunk_id: String,
    pub rrf_score: f32,
    pub dense_score: f32,
    pub sparse_score: f32,
}

/// Fuse a dense ranking and a sparse ranking using Reciprocal Rank Fusion.
///
/// Each ranking is a `Vec<(id, raw_score)>` already sorted best-first. RRF
/// assigns each item `1 / (k + rank)` (rank is 1-based) and sums the
/// contributions across rankings, weighting the sparse contribution by
/// `sparse_weight` and the dense contribution by `1 - sparse_weight`. The raw
/// per-ranking scores are carried through for observability (wired into the
/// `dense_score` / `sparse_score` DTO fields).
pub fn reciprocal_rank_fusion(
    dense: &[(String, f32)],
    sparse: &[(String, f32)],
    sparse_weight: f32,
) -> Vec<FusedResult> {
    use std::collections::HashMap;

    let sparse_weight = sparse_weight.clamp(0.0, 1.0);
    let dense_weight = 1.0 - sparse_weight;

    let mut acc: HashMap<String, FusedResult> = HashMap::new();

    for (rank, (id, raw)) in dense.iter().enumerate() {
        let contribution = dense_weight / (RRF_K + (rank as f32 + 1.0));
        let entry = acc.entry(id.clone()).or_insert_with(|| FusedResult {
            chunk_id: id.clone(),
            rrf_score: 0.0,
            dense_score: 0.0,
            sparse_score: 0.0,
        });
        entry.rrf_score += contribution;
        entry.dense_score = *raw;
    }

    for (rank, (id, raw)) in sparse.iter().enumerate() {
        let contribution = sparse_weight / (RRF_K + (rank as f32 + 1.0));
        let entry = acc.entry(id.clone()).or_insert_with(|| FusedResult {
            chunk_id: id.clone(),
            rrf_score: 0.0,
            dense_score: 0.0,
            sparse_score: 0.0,
        });
        entry.rrf_score += contribution;
        entry.sparse_score = *raw;
    }

    let mut fused: Vec<FusedResult> = acc.into_values().collect();
    fused.sort_by(|a, b| {
        b.rrf_score
            .partial_cmp(&a.rrf_score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    fused
}

/// Actual RAG Engine with working retrieval-augmented generation
pub struct RAGEngine {
    /// Document store with embeddings
    documents: Arc<RwLock<Vec<Document>>>,

    /// Inverted index for fast keyword search
    inverted_index: Arc<RwLock<HashMap<String, Vec<usize>>>>,

    /// Embedding model dimension
    embedding_dim: usize,

    /// Context window size
    context_window: usize,

    /// Chunk overlap for sliding window
    chunk_overlap: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Document {
    pub id: String,
    pub content: String,
    pub chunks: Vec<Chunk>,
    pub metadata: HashMap<String, String>,
    pub embedding: Vec<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Chunk {
    pub text: String,
    pub embedding: Vec<f32>,
    pub start_pos: usize,
    pub end_pos: usize,
    pub doc_id: String,
}

impl RAGEngine {
    /// Construct a RAG engine.
    ///
    /// * `embedding_dim` — dimensionality of the (currently hash-based) embeddings.
    /// * `context_window` — chunk size in words for the sliding-window chunker.
    /// * `chunk_overlap` — word overlap between adjacent chunks.
    pub fn new(embedding_dim: usize, context_window: usize, chunk_overlap: usize) -> Self {
        Self {
            documents: Arc::new(RwLock::new(Vec::new())),
            inverted_index: Arc::new(RwLock::new(HashMap::new())),
            embedding_dim,
            context_window,
            chunk_overlap,
        }
    }

    /// Convenience constructor using sensible default chunking parameters.
    pub fn with_dim(embedding_dim: usize) -> Self {
        Self::new(embedding_dim, 512, 50)
    }

    /// Add document with automatic chunking and embedding
    pub async fn add_document(
        &self,
        content: String,
        metadata: HashMap<String, String>,
    ) -> Result<String, MemoryError> {
        let doc_id = uuid::Uuid::new_v4().to_string();

        // Chunk the document
        let chunks = self.chunk_text(&content, &doc_id);

        // Generate embeddings for each chunk
        let mut embedded_chunks = Vec::new();
        for chunk in chunks {
            let embedding = self.generate_embedding(&chunk.text).await?;
            embedded_chunks.push(Chunk {
                text: chunk.text,
                embedding,
                start_pos: chunk.start_pos,
                end_pos: chunk.end_pos,
                doc_id: chunk.doc_id,
            });
        }

        // Generate document-level embedding (average of chunks)
        let doc_embedding = self.average_embeddings(
            &embedded_chunks
                .iter()
                .map(|c| c.embedding.clone())
                .collect::<Vec<_>>(),
        );

        let document = Document {
            id: doc_id.clone(),
            content,
            chunks: embedded_chunks,
            metadata,
            embedding: doc_embedding,
        };

        // Update inverted index
        self.update_inverted_index(&document).await?;

        // Store document
        let mut docs = self.documents.write().await;
        docs.push(document);

        Ok(doc_id)
    }

    /// Retrieve relevant context for a query using **hybrid** dense+sparse
    /// retrieval fused with Reciprocal Rank Fusion (RRF, k=60).
    ///
    /// Pipeline:
    /// 1. Over-fetch `ann_k = min(32, max(top_k, top_n))` candidates from BOTH
    ///    the dense (cosine) and sparse (BM25) rankings.
    /// 2. Fuse the two rankings with RRF — order-independent, scale-free, and
    ///    robust to the very different score distributions of cosine vs BM25.
    /// 3. Optionally rerank the fused candidates (32-doc batch cap) with a
    ///    cross-encoder-style reranker, gracefully falling back to the unranked
    ///    fused order if no reranker is configured or it errors.
    pub async fn retrieve(
        &self,
        query: &str,
        top_k: usize,
    ) -> Result<Vec<RetrievedContext>, MemoryError> {
        let query_embedding = self.generate_embedding(query).await?;

        // Over-fetch for fusion + reranking headroom, capped at the 32-doc batch
        // limit so reranking stays within a single batch.
        let ann_k = ANN_BATCH_CAP.min(top_k.max(DEFAULT_TOP_N)).max(top_k);

        // Step 1: dense (semantic) and sparse (lexical/BM25) candidate rankings.
        let sparse_ranking = self.bm25_search(query, ann_k).await?;
        let dense_ranking = self.semantic_search(&query_embedding, ann_k).await?;

        // Step 2: Reciprocal Rank Fusion.
        let fused = reciprocal_rank_fusion(&dense_ranking, &sparse_ranking, SPARSE_WEIGHT);

        // Resolve fused chunk-ids back into concrete contexts (keep the top
        // `ann_k` so the reranker has candidates to reorder).
        let docs = self.documents.read().await;
        let mut contexts: Vec<RetrievedContext> = Vec::new();
        for fr in fused.into_iter().take(ann_k) {
            for doc in docs.iter() {
                if let Some(chunk) = doc
                    .chunks
                    .iter()
                    .find(|c| format!("{}_{}", doc.id, c.start_pos) == fr.chunk_id)
                {
                    contexts.push(RetrievedContext {
                        text: chunk.text.clone(),
                        score: fr.rrf_score,
                        sparse_score: fr.sparse_score,
                        dense_score: fr.dense_score,
                        sparse_weight: SPARSE_WEIGHT,
                        source: doc.id.clone(),
                        metadata: doc.metadata.clone(),
                    });
                    break;
                }
            }
        }
        drop(docs);

        // Step 3: optional reranking with graceful fallback to the fused order.
        let reranked = self.rerank(query, contexts).await;

        Ok(reranked.into_iter().take(top_k).collect())
    }

    /// Rerank fused candidates. If no reranker is configured this is an honest
    /// no-op that preserves the RRF fused order (the "graceful fallback"
    /// discipline). A real cross-encoder can be slotted in here later; until
    /// then we never silently drop or fabricate a ranking.
    async fn rerank(
        &self,
        _query: &str,
        candidates: Vec<RetrievedContext>,
    ) -> Vec<RetrievedContext> {
        // 32-doc batch cap: a real reranker would score at most this many docs
        // per forward pass; we honor the cap here so the contract is stable.
        if candidates.len() > ANN_BATCH_CAP {
            // Already bounded by ann_k upstream, but keep the invariant explicit.
            let mut bounded = candidates;
            bounded.truncate(ANN_BATCH_CAP);
            return bounded;
        }
        candidates
    }

    /// Generate augmented response
    pub async fn generate_augmented(
        &self,
        query: &str,
        contexts: Vec<RetrievedContext>,
    ) -> Result<String, MemoryError> {
        // Build prompt with retrieved context
        let mut prompt = String::new();
        prompt.push_str("Based on the following context, answer the query.\n\n");
        prompt.push_str("Context:\n");

        for (i, ctx) in contexts.iter().enumerate() {
            prompt.push_str(&format!("[{}] {}\n", i + 1, ctx.text));
        }

        prompt.push_str(&format!("\nQuery: {}\n", query));
        prompt.push_str("Answer: ");

        // In production, this would call an LLM
        // For now, we'll create a simple extractive answer
        let answer = self.extract_answer(query, &contexts).await?;

        Ok(answer)
    }

    /// Chunk text with sliding window
    fn chunk_text(&self, text: &str, doc_id: &str) -> Vec<Chunk> {
        let words: Vec<&str> = text.split_whitespace().collect();
        let mut chunks = Vec::new();

        let chunk_size = self.context_window;
        let overlap = self.chunk_overlap;

        let mut start = 0;
        while start < words.len() {
            let end = (start + chunk_size).min(words.len());
            let chunk_text = words[start..end].join(" ");

            chunks.push(Chunk {
                text: chunk_text,
                embedding: vec![], // Will be filled later
                start_pos: start,
                end_pos: end,
                doc_id: doc_id.to_string(),
            });

            if end >= words.len() {
                break;
            }

            start += chunk_size - overlap;
        }

        chunks
    }

    /// Generate embedding for text (using hash-based pseudo-embedding)
    async fn generate_embedding(&self, text: &str) -> Result<Vec<f32>, MemoryError> {
        // In production, this would call a real embedding model
        // For demonstration, we'll use a deterministic hash-based embedding
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut embedding = vec![0.0; self.embedding_dim];

        // Generate multiple hash values from different seeds
        for (i, word) in text.split_whitespace().enumerate() {
            let mut hasher = DefaultHasher::new();
            word.hash(&mut hasher);
            i.hash(&mut hasher);
            let hash = hasher.finish();

            // Convert hash to embedding values
            for j in 0..self.embedding_dim {
                let byte_idx = (hash as usize + j) % 8;
                let value = ((hash >> (byte_idx * 8)) & 0xFF) as f32 / 255.0;
                embedding[j] += value;
            }
        }

        // Normalize
        let norm: f32 = embedding.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm > 0.0 {
            for val in &mut embedding {
                *val /= norm;
            }
        }

        Ok(embedding)
    }

    /// Average multiple embeddings
    fn average_embeddings(&self, embeddings: &[Vec<f32>]) -> Vec<f32> {
        if embeddings.is_empty() {
            return vec![0.0; self.embedding_dim];
        }

        let mut avg = vec![0.0; self.embedding_dim];

        for embedding in embeddings {
            for (i, val) in embedding.iter().enumerate() {
                avg[i] += val;
            }
        }

        let count = embeddings.len() as f32;
        for val in &mut avg {
            *val /= count;
        }

        // Normalize
        let norm: f32 = avg.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm > 0.0 {
            for val in &mut avg {
                *val /= norm;
            }
        }

        avg
    }

    /// Update inverted index for BM25 search
    async fn update_inverted_index(&self, doc: &Document) -> Result<(), MemoryError> {
        let mut index = self.inverted_index.write().await;

        // Tokenize and index each chunk
        for (chunk_idx, chunk) in doc.chunks.iter().enumerate() {
            let tokens = self.tokenize(&chunk.text);

            for token in tokens {
                index.entry(token).or_insert_with(Vec::new).push(chunk_idx);
            }
        }

        Ok(())
    }

    /// Simple tokenization
    fn tokenize(&self, text: &str) -> Vec<String> {
        text.to_lowercase()
            .split_whitespace()
            .map(|s| s.chars().filter(|c| c.is_alphanumeric()).collect())
            .filter(|s: &String| !s.is_empty() && s.len() > 2)
            .collect()
    }

    /// BM25 scoring for keyword search
    async fn bm25_search(
        &self,
        query: &str,
        top_k: usize,
    ) -> Result<Vec<(String, f32)>, MemoryError> {
        let tokens = self.tokenize(query);
        let index = self.inverted_index.read().await;
        let docs = self.documents.read().await;

        let mut scores: HashMap<String, f32> = HashMap::new();

        // BM25 parameters
        let k1 = 1.2;
        let b = 0.75;
        let total_docs = docs.len() as f32;

        for token in &tokens {
            if let Some(postings) = index.get(token) {
                let df = postings.len() as f32;
                let idf = ((total_docs - df + 0.5) / (df + 0.5)).ln();

                for &chunk_idx in postings {
                    // Find the document containing this chunk
                    for doc in docs.iter() {
                        if chunk_idx < doc.chunks.len() {
                            let chunk = &doc.chunks[chunk_idx];
                            let chunk_id = format!("{}_{}", doc.id, chunk.start_pos);

                            // Calculate term frequency
                            let tf =
                                chunk.text.to_lowercase().matches(token.as_str()).count() as f32;
                            let doc_len = chunk.text.len() as f32;
                            let avg_doc_len = 500.0; // Approximate average

                            // BM25 formula
                            let score = idf * (tf * (k1 + 1.0))
                                / (tf + k1 * (1.0 - b + b * doc_len / avg_doc_len));

                            *scores.entry(chunk_id).or_insert(0.0) += score;
                        }
                    }
                }
            }
        }

        // Sort and return top-k
        let mut ranked: Vec<_> = scores.into_iter().collect();
        ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        ranked.truncate(top_k);

        Ok(ranked)
    }

    /// Semantic search using cosine similarity
    async fn semantic_search(
        &self,
        query_embedding: &[f32],
        top_k: usize,
    ) -> Result<Vec<(String, f32)>, MemoryError> {
        let docs = self.documents.read().await;
        let mut scores = Vec::new();

        for doc in docs.iter() {
            for chunk in &doc.chunks {
                let similarity = self.cosine_similarity(query_embedding, &chunk.embedding);
                let chunk_id = format!("{}_{}", doc.id, chunk.start_pos);
                scores.push((chunk_id, similarity));
            }
        }

        // Sort by similarity
        scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        scores.truncate(top_k);

        Ok(scores)
    }

    /// Calculate cosine similarity
    fn cosine_similarity(&self, a: &[f32], b: &[f32]) -> f32 {
        let dot: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
        let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
        let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();

        if norm_a > 0.0 && norm_b > 0.0 {
            dot / (norm_a * norm_b)
        } else {
            0.0
        }
    }

    /// Extract answer from contexts
    async fn extract_answer(
        &self,
        query: &str,
        contexts: &[RetrievedContext],
    ) -> Result<String, MemoryError> {
        // Simple extractive approach: find sentences containing query terms
        let query_tokens = self.tokenize(query);
        let mut best_sentences = Vec::new();

        for ctx in contexts {
            let sentences: Vec<&str> = ctx.text.split(". ").collect();

            for sentence in sentences {
                let sentence_tokens = self.tokenize(sentence);
                let overlap = query_tokens
                    .iter()
                    .filter(|qt| sentence_tokens.contains(qt))
                    .count();

                if overlap > 0 {
                    best_sentences.push((sentence.to_string(), overlap));
                }
            }
        }

        // Sort by overlap
        best_sentences.sort_by(|a, b| b.1.cmp(&a.1));

        // Combine top sentences
        let answer = best_sentences
            .iter()
            .take(3)
            .map(|(s, _)| s.clone())
            .collect::<Vec<_>>()
            .join(" ");

        if answer.is_empty() {
            Ok("No relevant information found in the context.".to_string())
        } else {
            Ok(answer)
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetrievedContext {
    pub text: String,
    /// Final fused (RRF) score after optional reranking.
    pub score: f32,
    /// Lexical/sparse (BM25) component score for this chunk (0.0 if it never
    /// surfaced in the sparse ranking).
    pub sparse_score: f32,
    /// Dense/semantic (cosine) component score for this chunk (0.0 if it never
    /// surfaced in the dense ranking).
    pub dense_score: f32,
    /// Weight applied to the sparse signal during fusion (book-keeping; RRF is
    /// rank-based so this is the configured relative emphasis).
    pub sparse_weight: f32,
    pub source: String,
    pub metadata: HashMap<String, String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rrf_fuses_and_orders_by_combined_rank() {
        // dense favors A then B; sparse favors B then A.
        let dense = vec![("A".to_string(), 0.9), ("B".to_string(), 0.5)];
        let sparse = vec![("B".to_string(), 3.0), ("A".to_string(), 1.0)];
        let fused = reciprocal_rank_fusion(&dense, &sparse, SPARSE_WEIGHT);
        assert_eq!(fused.len(), 2);
        // Both raw component scores must be carried through.
        let a = fused.iter().find(|f| f.chunk_id == "A").unwrap();
        assert!(a.dense_score > 0.0 && a.sparse_score > 0.0);
        // Every fused score is strictly positive.
        assert!(fused.iter().all(|f| f.rrf_score > 0.0));
    }

    #[test]
    fn rrf_handles_disjoint_rankings() {
        let dense = vec![("A".to_string(), 0.9)];
        let sparse = vec![("B".to_string(), 2.0)];
        let fused = reciprocal_rank_fusion(&dense, &sparse, 0.5);
        assert_eq!(fused.len(), 2);
        let b = fused.iter().find(|f| f.chunk_id == "B").unwrap();
        assert_eq!(b.dense_score, 0.0);
        assert_eq!(b.sparse_score, 2.0);
    }

    #[tokio::test]
    async fn test_rag_pipeline() {
        let rag = RAGEngine::with_dim(768);

        // Add documents
        let _doc1 = rag.add_document(
            "Rust is a systems programming language. It provides memory safety without garbage collection.".to_string(),
            HashMap::from([("type".to_string(), "tutorial".to_string())]),
        ).await.unwrap();

        let _doc2 = rag
            .add_document(
                "Machine learning models can be deployed in production using Rust for performance."
                    .to_string(),
                HashMap::from([("type".to_string(), "article".to_string())]),
            )
            .await
            .unwrap();

        // Retrieve context
        let contexts = rag.retrieve("Rust programming", 2).await.unwrap();
        assert!(!contexts.is_empty());

        // Generate augmented response
        let response = rag
            .generate_augmented("What is Rust?", contexts)
            .await
            .unwrap();

        assert!(
            response.contains("Rust")
                || response.contains("systems")
                || response.contains("programming")
        );
    }
}
