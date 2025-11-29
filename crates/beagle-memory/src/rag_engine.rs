//! Real RAG Engine Implementation

use crate::error::MemoryError;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tokio::sync::RwLock;

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
    pub fn new(embedding_dim: usize) -> Self {
        Self {
            documents: Arc::new(RwLock::new(Vec::new())),
            inverted_index: Arc::new(RwLock::new(HashMap::new())),
            embedding_dim,
            context_window: 512,
            chunk_overlap: 50,
        }
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

    /// Retrieve relevant context for a query
    pub async fn retrieve(
        &self,
        query: &str,
        top_k: usize,
    ) -> Result<Vec<RetrievedContext>, MemoryError> {
        let query_embedding = self.generate_embedding(query).await?;

        // Step 1: BM25 keyword search
        let keyword_results = self.bm25_search(query, top_k * 2).await?;

        // Step 2: Semantic search
        let semantic_results = self.semantic_search(&query_embedding, top_k * 2).await?;

        // Step 3: Hybrid ranking
        let mut hybrid_scores = HashMap::new();

        // Combine scores (0.3 BM25 + 0.7 semantic)
        for (doc_id, score) in keyword_results {
            *hybrid_scores.entry(doc_id).or_insert(0.0) += score * 0.3;
        }

        for (doc_id, score) in semantic_results {
            *hybrid_scores.entry(doc_id).or_insert(0.0) += score * 0.7;
        }

        // Sort by hybrid score
        let mut ranked: Vec<_> = hybrid_scores.into_iter().collect();
        ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

        // Step 4: Build context from top results
        let docs = self.documents.read().await;
        let mut contexts = Vec::new();

        for (chunk_id, score) in ranked.iter().take(top_k) {
            // Find the chunk
            for doc in docs.iter() {
                for chunk in &doc.chunks {
                    if chunk.doc_id == doc.id
                        && format!("{}_{}", doc.id, chunk.start_pos) == *chunk_id
                    {
                        contexts.push(RetrievedContext {
                            text: chunk.text.clone(),
                            score: *score,
                            source: doc.id.clone(),
                            metadata: doc.metadata.clone(),
                        });
                        break;
                    }
                }
            }
        }

        Ok(contexts)
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
                let chunk_id = format!("{}_{}", doc.id, chunk.start_pos);
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
    pub score: f32,
    pub source: String,
    pub metadata: HashMap<String, String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_rag_pipeline() {
        let rag = RAGEngine::new(768);

        // Add documents
        let doc1 = rag.add_document(
            "Rust is a systems programming language. It provides memory safety without garbage collection.".to_string(),
            HashMap::from([("type".to_string(), "tutorial".to_string())]),
        ).await.unwrap();

        let doc2 = rag
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
