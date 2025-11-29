//! Real Search Engine with BM25 and Vector Search

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::{BinaryHeap, HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::RwLock;

/// Document for indexing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Document {
    pub id: String,
    pub title: String,
    pub content: String,
    pub metadata: HashMap<String, String>,
    pub embedding: Option<Vec<f32>>,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

/// Search result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub id: String,
    pub title: String,
    pub snippet: String,
    pub score: f32,
    pub highlights: Vec<String>,
    pub metadata: HashMap<String, String>,
}

/// Full-text search engine with BM25 and vector search
pub struct SearchEngine {
    /// Document storage
    documents: Arc<RwLock<HashMap<String, Document>>>,

    /// Inverted index: term -> document IDs
    inverted_index: Arc<RwLock<HashMap<String, HashSet<String>>>>,

    /// Document frequency for IDF calculation
    doc_frequencies: Arc<RwLock<HashMap<String, usize>>>,

    /// Document lengths for BM25
    doc_lengths: Arc<RwLock<HashMap<String, usize>>>,

    /// Vector index for semantic search
    vector_index: Arc<RwLock<VectorIndex>>,

    /// Total number of documents
    total_docs: Arc<RwLock<usize>>,

    /// Average document length
    avg_doc_length: Arc<RwLock<f32>>,

    /// BM25 parameters
    k1: f32,
    b: f32,
}

/// Vector index for similarity search
struct VectorIndex {
    embeddings: Vec<(String, Vec<f32>)>,
    dimension: usize,
}

/// Query parser
pub struct QueryParser {
    stop_words: HashSet<String>,
}

/// Query AST
#[derive(Debug, Clone)]
pub enum QueryNode {
    Term(String),
    Phrase(Vec<String>),
    And(Box<QueryNode>, Box<QueryNode>),
    Or(Box<QueryNode>, Box<QueryNode>),
    Not(Box<QueryNode>),
    Boost(Box<QueryNode>, f32),
}

impl SearchEngine {
    pub fn new() -> Self {
        Self {
            documents: Arc::new(RwLock::new(HashMap::new())),
            inverted_index: Arc::new(RwLock::new(HashMap::new())),
            doc_frequencies: Arc::new(RwLock::new(HashMap::new())),
            doc_lengths: Arc::new(RwLock::new(HashMap::new())),
            vector_index: Arc::new(RwLock::new(VectorIndex::new(768))),
            total_docs: Arc::new(RwLock::new(0)),
            avg_doc_length: Arc::new(RwLock::new(0.0)),
            k1: 1.2,
            b: 0.75,
        }
    }

    /// Index a document
    pub async fn index(&self, doc: Document) -> Result<(), SearchError> {
        let doc_id = doc.id.clone();
        let tokens = self.tokenize(&doc.content);
        let doc_length = tokens.len();

        // Store document
        let mut documents = self.documents.write().await;
        documents.insert(doc_id.clone(), doc.clone());

        // Update inverted index
        let mut index = self.inverted_index.write().await;
        let mut doc_freqs = self.doc_frequencies.write().await;

        let mut term_freqs = HashMap::new();
        for token in &tokens {
            *term_freqs.entry(token.clone()).or_insert(0) += 1;
        }

        for (term, _) in term_freqs {
            index
                .entry(term.clone())
                .or_insert_with(HashSet::new)
                .insert(doc_id.clone());

            *doc_freqs.entry(term).or_insert(0) += 1;
        }

        // Update document length
        let mut doc_lengths = self.doc_lengths.write().await;
        doc_lengths.insert(doc_id.clone(), doc_length);

        // Update statistics
        let mut total_docs = self.total_docs.write().await;
        *total_docs += 1;

        let mut avg_length = self.avg_doc_length.write().await;
        *avg_length =
            (*avg_length * (*total_docs - 1) as f32 + doc_length as f32) / *total_docs as f32;

        // Index embedding if present
        if let Some(embedding) = doc.embedding {
            let mut vector_index = self.vector_index.write().await;
            vector_index.add(doc_id, embedding);
        }

        Ok(())
    }

    /// Search using BM25
    pub async fn search(
        &self,
        query: &str,
        limit: usize,
    ) -> Result<Vec<SearchResult>, SearchError> {
        let query_tokens = self.tokenize(query);

        if query_tokens.is_empty() {
            return Ok(Vec::new());
        }

        let documents = self.documents.read().await;
        let index = self.inverted_index.read().await;
        let doc_freqs = self.doc_frequencies.read().await;
        let doc_lengths = self.doc_lengths.read().await;
        let total_docs = *self.total_docs.read().await;
        let avg_doc_length = *self.avg_doc_length.read().await;

        // Calculate BM25 scores
        let mut scores: HashMap<String, f32> = HashMap::new();

        for token in &query_tokens {
            if let Some(doc_ids) = index.get(token) {
                let df = doc_freqs.get(token).copied().unwrap_or(0) as f32;
                let idf = ((total_docs as f32 - df + 0.5) / (df + 0.5)).ln();

                for doc_id in doc_ids {
                    if let Some(doc) = documents.get(doc_id) {
                        let doc_length = doc_lengths.get(doc_id).copied().unwrap_or(0) as f32;
                        let tf = self.term_frequency(&doc.content, token);

                        // BM25 formula
                        let score = idf * (tf * (self.k1 + 1.0))
                            / (tf
                                + self.k1 * (1.0 - self.b + self.b * doc_length / avg_doc_length));

                        *scores.entry(doc_id.clone()).or_insert(0.0) += score;
                    }
                }
            }
        }

        // Sort by score
        let mut results: Vec<_> = scores.into_iter().collect();
        results.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        results.truncate(limit);

        // Build search results
        let mut search_results = Vec::new();

        for (doc_id, score) in results {
            if let Some(doc) = documents.get(&doc_id) {
                let snippet = self.generate_snippet(&doc.content, &query_tokens, 150);
                let highlights = self.highlight_terms(&doc.content, &query_tokens);

                search_results.push(SearchResult {
                    id: doc.id.clone(),
                    title: doc.title.clone(),
                    snippet,
                    score,
                    highlights,
                    metadata: doc.metadata.clone(),
                });
            }
        }

        Ok(search_results)
    }

    /// Semantic search using embeddings
    pub async fn semantic_search(
        &self,
        query_embedding: Vec<f32>,
        limit: usize,
    ) -> Result<Vec<SearchResult>, SearchError> {
        let vector_index = self.vector_index.read().await;
        let similar = vector_index.search(&query_embedding, limit);

        let documents = self.documents.read().await;
        let mut results = Vec::new();

        for (doc_id, score) in similar {
            if let Some(doc) = documents.get(&doc_id) {
                results.push(SearchResult {
                    id: doc.id.clone(),
                    title: doc.title.clone(),
                    snippet: doc.content.chars().take(150).collect(),
                    score,
                    highlights: Vec::new(),
                    metadata: doc.metadata.clone(),
                });
            }
        }

        Ok(results)
    }

    /// Hybrid search combining BM25 and semantic
    pub async fn hybrid_search(
        &self,
        query: &str,
        query_embedding: Option<Vec<f32>>,
        limit: usize,
        bm25_weight: f32,
        semantic_weight: f32,
    ) -> Result<Vec<SearchResult>, SearchError> {
        // Get BM25 results
        let bm25_results = self.search(query, limit * 2).await?;

        // Get semantic results if embedding provided
        let semantic_results = if let Some(embedding) = query_embedding {
            self.semantic_search(embedding, limit * 2).await?
        } else {
            Vec::new()
        };

        // Combine scores
        let mut combined_scores: HashMap<String, f32> = HashMap::new();

        for result in bm25_results {
            *combined_scores.entry(result.id).or_insert(0.0) += result.score * bm25_weight;
        }

        for result in semantic_results {
            *combined_scores.entry(result.id).or_insert(0.0) += result.score * semantic_weight;
        }

        // Sort and retrieve top results
        let mut sorted: Vec<_> = combined_scores.into_iter().collect();
        sorted.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        sorted.truncate(limit);

        let documents = self.documents.read().await;
        let mut results = Vec::new();

        for (doc_id, score) in sorted {
            if let Some(doc) = documents.get(&doc_id) {
                let snippet = self.generate_snippet(&doc.content, &self.tokenize(query), 150);

                results.push(SearchResult {
                    id: doc.id.clone(),
                    title: doc.title.clone(),
                    snippet,
                    score,
                    highlights: Vec::new(),
                    metadata: doc.metadata.clone(),
                });
            }
        }

        Ok(results)
    }

    /// Faceted search with aggregations
    pub async fn faceted_search(
        &self,
        query: &str,
        facet_fields: Vec<String>,
    ) -> Result<FacetedResults, SearchError> {
        let results = self.search(query, 100).await?;

        let documents = self.documents.read().await;
        let mut facets: HashMap<String, HashMap<String, usize>> = HashMap::new();

        for field in facet_fields {
            facets.insert(field.clone(), HashMap::new());
        }

        for result in &results {
            if let Some(doc) = documents.get(&result.id) {
                for (field, values) in &facets {
                    if let Some(value) = doc.metadata.get(field) {
                        *values
                            .get_mut(field)
                            .unwrap()
                            .entry(value.clone())
                            .or_insert(0) += 1;
                    }
                }
            }
        }

        Ok(FacetedResults { results, facets })
    }

    /// Tokenize text
    fn tokenize(&self, text: &str) -> Vec<String> {
        text.to_lowercase()
            .split_whitespace()
            .map(|s| {
                s.chars()
                    .filter(|c| c.is_alphanumeric())
                    .collect::<String>()
            })
            .filter(|s| !s.is_empty() && s.len() > 1)
            .collect()
    }

    /// Calculate term frequency
    fn term_frequency(&self, text: &str, term: &str) -> f32 {
        text.to_lowercase().matches(term).count() as f32
    }

    /// Generate snippet with query terms
    fn generate_snippet(&self, content: &str, query_terms: &[String], max_length: usize) -> String {
        let sentences: Vec<&str> = content.split(". ").collect();
        let mut best_sentence = "";
        let mut best_score = 0;

        for sentence in sentences {
            let sentence_lower = sentence.to_lowercase();
            let score = query_terms
                .iter()
                .filter(|term| sentence_lower.contains(term.as_str()))
                .count();

            if score > best_score {
                best_score = score;
                best_sentence = sentence;
            }
        }

        if best_sentence.len() > max_length {
            format!("{}...", &best_sentence[..max_length])
        } else {
            best_sentence.to_string()
        }
    }

    /// Highlight query terms in text
    fn highlight_terms(&self, text: &str, terms: &[String]) -> Vec<String> {
        let mut highlights = Vec::new();
        let words: Vec<&str> = text.split_whitespace().collect();

        for (i, word) in words.iter().enumerate() {
            let word_lower = word.to_lowercase();
            for term in terms {
                if word_lower.contains(term) {
                    let start = i.saturating_sub(5);
                    let end = (i + 5).min(words.len());
                    let context = words[start..end].join(" ");
                    highlights.push(context);
                    break;
                }
            }
        }

        highlights
    }
}

impl VectorIndex {
    fn new(dimension: usize) -> Self {
        Self {
            embeddings: Vec::new(),
            dimension,
        }
    }

    fn add(&mut self, id: String, embedding: Vec<f32>) {
        if embedding.len() == self.dimension {
            self.embeddings.push((id, embedding));
        }
    }

    fn search(&self, query: &[f32], limit: usize) -> Vec<(String, f32)> {
        let mut scores = Vec::new();

        for (id, embedding) in &self.embeddings {
            let similarity = self.cosine_similarity(query, embedding);
            scores.push((id.clone(), similarity));
        }

        scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        scores.truncate(limit);
        scores
    }

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
}

impl QueryParser {
    pub fn new() -> Self {
        let stop_words = vec![
            "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "he", "in",
            "is", "it", "its", "of", "on", "that", "the", "to", "was", "will", "with",
        ]
        .into_iter()
        .map(String::from)
        .collect();

        Self { stop_words }
    }

    /// Parse query string into AST
    pub fn parse(&self, query: &str) -> QueryNode {
        // Simple implementation - just treat as terms
        // In production, would parse AND, OR, NOT, quotes, etc.
        let terms: Vec<_> = query
            .split_whitespace()
            .filter(|w| !self.stop_words.contains(&w.to_lowercase()))
            .map(|w| QueryNode::Term(w.to_string()))
            .collect();

        if terms.is_empty() {
            QueryNode::Term(String::new())
        } else if terms.len() == 1 {
            terms.into_iter().next().unwrap()
        } else {
            // Default to AND for multiple terms
            terms
                .into_iter()
                .reduce(|acc, term| QueryNode::And(Box::new(acc), Box::new(term)))
                .unwrap()
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FacetedResults {
    pub results: Vec<SearchResult>,
    pub facets: HashMap<String, HashMap<String, usize>>,
}

#[derive(Debug, thiserror::Error)]
pub enum SearchError {
    #[error("Index error: {0}")]
    IndexError(String),

    #[error("Query error: {0}")]
    QueryError(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_bm25_search() {
        let engine = SearchEngine::new();

        // Index documents
        let doc1 = Document {
            id: "1".to_string(),
            title: "Rust Programming".to_string(),
            content: "Rust is a systems programming language focused on safety and performance"
                .to_string(),
            metadata: HashMap::from([("category".to_string(), "programming".to_string())]),
            embedding: None,
            timestamp: chrono::Utc::now(),
        };

        let doc2 = Document {
            id: "2".to_string(),
            title: "Python Guide".to_string(),
            content: "Python is a high-level programming language known for simplicity".to_string(),
            metadata: HashMap::from([("category".to_string(), "programming".to_string())]),
            embedding: None,
            timestamp: chrono::Utc::now(),
        };

        engine.index(doc1).await.unwrap();
        engine.index(doc2).await.unwrap();

        // Search
        let results = engine.search("rust safety", 10).await.unwrap();

        assert!(!results.is_empty());
        assert_eq!(results[0].id, "1");
    }

    #[tokio::test]
    async fn test_query_parser() {
        let parser = QueryParser::new();

        let query = parser.parse("rust AND programming");

        match query {
            QueryNode::And(left, right) => {
                assert!(matches!(*left, QueryNode::Term(_)));
                assert!(matches!(*right, QueryNode::Term(_)));
            }
            _ => panic!("Expected AND node"),
        }
    }
}
