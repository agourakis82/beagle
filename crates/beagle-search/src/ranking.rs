//! # Hybrid Ranking System
//!
//! Combines BM25, semantic similarity, and other signals for optimal ranking.
//!
//! ## Research Foundation
//! - "Learning to Rank for Information Retrieval" (Liu, 2024)
//! - "Neural Ranking Models with Weak Supervision" (Dehghani et al., 2025)

use anyhow::Result;
use std::collections::HashMap;

use crate::query_parser::ParsedQuery;
use crate::types::{Paper, SearchResult};
use crate::RankingWeights;

/// Ranking strategy trait
pub trait RankingStrategy: Send + Sync {
    /// Rank papers based on query
    fn rank(&self, papers: Vec<Paper>, query: &ParsedQuery) -> Result<Vec<Paper>>;
}

/// Hybrid ranking combining multiple signals
pub struct HybridRanker {
    /// Ranking weights
    weights: RankingWeights,

    /// BM25 parameters
    bm25_params: BM25Params,

    /// Authority scores cache
    authority_scores: HashMap<String, f32>,
}

impl HybridRanker {
    /// Create new hybrid ranker
    pub fn new(weights: RankingWeights) -> Self {
        Self {
            weights,
            bm25_params: BM25Params::default(),
            authority_scores: HashMap::new(),
        }
    }

    /// Rank search results
    pub fn rank(&self, results: SearchResult, query: &ParsedQuery) -> Result<SearchResult> {
        let mut scored_papers = Vec::new();

        for paper in results.papers {
            let score = self.calculate_score(&paper, query)?;
            scored_papers.push((paper, score));
        }

        // Sort by score
        scored_papers.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

        Ok(SearchResult {
            papers: scored_papers.into_iter().map(|(p, _)| p).collect(),
            total_results: results.total_results,
            query: results.query,
            metadata: results.metadata,
        })
    }

    /// Calculate hybrid score for a paper
    fn calculate_score(&self, paper: &Paper, query: &ParsedQuery) -> Result<f32> {
        let mut score = 0.0;

        // BM25 score
        if self.weights.bm25_weight > 0.0 {
            let bm25_score = self.calculate_bm25(paper, query)?;
            score += bm25_score * self.weights.bm25_weight;
        }

        // Semantic score (would be provided by semantic search)
        if self.weights.semantic_weight > 0.0 {
            let semantic_score = self.get_semantic_score(paper, query)?;
            score += semantic_score * self.weights.semantic_weight;
        }

        // Citation score
        if self.weights.citation_weight > 0.0 {
            let citation_score = self.calculate_citation_score(paper)?;
            score += citation_score * self.weights.citation_weight;
        }

        // Recency score
        if self.weights.recency_weight > 0.0 {
            let recency_score = self.calculate_recency_score(paper)?;
            score += recency_score * self.weights.recency_weight;
        }

        // Authority score
        if self.weights.authority_weight > 0.0 {
            let authority_score = self.calculate_authority_score(paper)?;
            score += authority_score * self.weights.authority_weight;
        }

        Ok(score)
    }

    /// Calculate BM25 score
    fn calculate_bm25(&self, paper: &Paper, query: &ParsedQuery) -> Result<f32> {
        let text = format!("{} {}", paper.title, paper.abstract_text);
        let doc_tokens: Vec<String> = text
            .to_lowercase()
            .split_whitespace()
            .map(|s| s.to_string())
            .collect();

        let mut score = 0.0;
        let doc_len = doc_tokens.len() as f32;
        let avg_doc_len = 500.0; // Approximate average document length

        for term in &query.terms {
            let term_lower = term.to_lowercase();
            let term_freq = doc_tokens
                .iter()
                .filter(|t| t.contains(&term_lower))
                .count() as f32;

            if term_freq > 0.0 {
                // Simplified BM25 calculation
                let idf = self.calculate_idf(&term_lower);
                let numerator = term_freq * (self.bm25_params.k1 + 1.0);
                let denominator = term_freq
                    + self.bm25_params.k1
                        * (1.0 - self.bm25_params.b + self.bm25_params.b * doc_len / avg_doc_len);

                score += idf * numerator / denominator;
            }
        }

        // Normalize to 0-1
        Ok((score / 10.0).min(1.0))
    }

    /// Calculate IDF (Inverse Document Frequency)
    fn calculate_idf(&self, term: &str) -> f32 {
        // Simplified IDF calculation
        // In practice, this would use corpus statistics
        match term {
            "the" | "a" | "an" | "and" | "or" | "but" => 0.1,
            "machine" | "learning" | "artificial" | "intelligence" => 2.0,
            "quantum" | "biology" | "neuroscience" => 3.0,
            _ => 1.5,
        }
    }

    /// Get semantic score (would be computed by semantic search)
    fn get_semantic_score(&self, _paper: &Paper, _query: &ParsedQuery) -> Result<f32> {
        // This would be provided by the semantic search module
        // For now, return a placeholder
        Ok(0.5)
    }

    /// Calculate citation-based score
    fn calculate_citation_score(&self, paper: &Paper) -> Result<f32> {
        // Logarithmic scaling of citation count
        let citations = paper.citation_count as f32;
        if citations == 0.0 {
            return Ok(0.0);
        }

        let score = (citations + 1.0).ln() / 10.0;
        Ok(score.min(1.0))
    }

    /// Calculate recency score
    fn calculate_recency_score(&self, paper: &Paper) -> Result<f32> {
        let now = chrono::Utc::now();
        let age_days = (now - paper.publication_date).num_days() as f32;

        // Exponential decay with half-life of 365 days
        let half_life = 365.0;
        let score = 0.5_f32.powf(age_days / half_life);

        Ok(score)
    }

    /// Calculate authority score based on journal/venue
    fn calculate_authority_score(&self, paper: &Paper) -> Result<f32> {
        // Check cache
        if let Some(journal) = &paper.journal {
            if let Some(&score) = self.authority_scores.get(journal) {
                return Ok(score);
            }

            // Calculate based on journal impact (simplified)
            let score = match journal.to_lowercase().as_str() {
                s if s.contains("nature") => 0.95,
                s if s.contains("science") => 0.95,
                s if s.contains("cell") => 0.90,
                s if s.contains("ieee") => 0.85,
                s if s.contains("acm") => 0.85,
                s if s.contains("plos") => 0.75,
                s if s.contains("arxiv") => 0.60,
                _ => 0.50,
            };

            Ok(score)
        } else {
            Ok(0.5) // Default score for unknown venues
        }
    }
}

/// BM25 parameters
#[derive(Debug, Clone)]
pub struct BM25Params {
    /// Term frequency saturation parameter
    pub k1: f32,

    /// Length normalization parameter
    pub b: f32,
}

impl Default for BM25Params {
    fn default() -> Self {
        Self { k1: 1.2, b: 0.75 }
    }
}

/// Learning-to-rank model
pub struct LearningToRank {
    /// Feature extractors
    feature_extractors: Vec<Box<dyn FeatureExtractor>>,

    /// Model weights
    weights: Vec<f32>,
}

impl LearningToRank {
    /// Create new L2R model
    pub fn new() -> Self {
        Self {
            feature_extractors: Self::default_extractors(),
            weights: vec![1.0; 10], // Default weights
        }
    }

    /// Default feature extractors
    fn default_extractors() -> Vec<Box<dyn FeatureExtractor>> {
        vec![
            Box::new(TitleMatchExtractor),
            Box::new(AbstractMatchExtractor),
            Box::new(AuthorMatchExtractor),
            Box::new(CitationCountExtractor),
            Box::new(RecencyExtractor),
            Box::new(FieldMatchExtractor),
            Box::new(JournalQualityExtractor),
            Box::new(QueryCoverageExtractor),
            Box::new(TitleLengthExtractor),
            Box::new(AbstractLengthExtractor),
        ]
    }

    /// Extract features for a paper
    pub fn extract_features(&self, paper: &Paper, query: &ParsedQuery) -> Vec<f32> {
        self.feature_extractors
            .iter()
            .map(|extractor| extractor.extract(paper, query))
            .collect()
    }

    /// Score a paper
    pub fn score(&self, paper: &Paper, query: &ParsedQuery) -> f32 {
        let features = self.extract_features(paper, query);

        features.iter().zip(&self.weights).map(|(f, w)| f * w).sum()
    }

    /// Train model with labeled data
    pub fn train(&mut self, training_data: Vec<(Paper, ParsedQuery, f32)>) -> Result<()> {
        // Simplified training using gradient descent
        // In practice, would use more sophisticated methods

        let learning_rate = 0.01;
        let epochs = 100;

        for _ in 0..epochs {
            let mut gradients = vec![0.0; self.weights.len()];

            for (paper, query, target) in &training_data {
                let features = self.extract_features(paper, query);
                let prediction = self.score(paper, query);
                let error = prediction - target;

                // Update gradients
                for (i, feature) in features.iter().enumerate() {
                    gradients[i] += error * feature;
                }
            }

            // Update weights
            for (i, gradient) in gradients.iter().enumerate() {
                self.weights[i] -= learning_rate * gradient / training_data.len() as f32;
            }
        }

        Ok(())
    }
}

/// Feature extractor trait
trait FeatureExtractor: Send + Sync {
    /// Extract feature value
    fn extract(&self, paper: &Paper, query: &ParsedQuery) -> f32;
}

// Feature extractors
struct TitleMatchExtractor;
impl FeatureExtractor for TitleMatchExtractor {
    fn extract(&self, paper: &Paper, query: &ParsedQuery) -> f32 {
        let title_lower = paper.title.to_lowercase();
        let matches = query
            .terms
            .iter()
            .filter(|term| title_lower.contains(&term.to_lowercase()))
            .count();

        matches as f32 / query.terms.len().max(1) as f32
    }
}

struct AbstractMatchExtractor;
impl FeatureExtractor for AbstractMatchExtractor {
    fn extract(&self, paper: &Paper, query: &ParsedQuery) -> f32 {
        let abstract_lower = paper.abstract_text.to_lowercase();
        let matches = query
            .terms
            .iter()
            .filter(|term| abstract_lower.contains(&term.to_lowercase()))
            .count();

        matches as f32 / query.terms.len().max(1) as f32
    }
}

struct AuthorMatchExtractor;
impl FeatureExtractor for AuthorMatchExtractor {
    fn extract(&self, paper: &Paper, query: &ParsedQuery) -> f32 {
        let author_names: Vec<String> = paper
            .authors
            .iter()
            .map(|a| a.name.to_lowercase())
            .collect();

        let matches = query
            .terms
            .iter()
            .filter(|term| {
                let term_lower = term.to_lowercase();
                author_names.iter().any(|name| name.contains(&term_lower))
            })
            .count();

        if matches > 0 {
            1.0
        } else {
            0.0
        }
    }
}

struct CitationCountExtractor;
impl FeatureExtractor for CitationCountExtractor {
    fn extract(&self, paper: &Paper, _query: &ParsedQuery) -> f32 {
        (paper.citation_count as f32 + 1.0).ln() / 10.0
    }
}

struct RecencyExtractor;
impl FeatureExtractor for RecencyExtractor {
    fn extract(&self, paper: &Paper, _query: &ParsedQuery) -> f32 {
        let age_days = (chrono::Utc::now() - paper.publication_date).num_days() as f32;
        0.5_f32.powf(age_days / 365.0)
    }
}

struct FieldMatchExtractor;
impl FeatureExtractor for FieldMatchExtractor {
    fn extract(&self, paper: &Paper, query: &ParsedQuery) -> f32 {
        if let Some(fields) = query.filters.get("field") {
            let matches = paper
                .fields
                .iter()
                .filter(|f| fields.contains(&f.to_string()))
                .count();

            matches as f32 / fields.len().max(1) as f32
        } else {
            0.5 // Neutral score if no field filter
        }
    }
}

struct JournalQualityExtractor;
impl FeatureExtractor for JournalQualityExtractor {
    fn extract(&self, paper: &Paper, _query: &ParsedQuery) -> f32 {
        if let Some(journal) = &paper.journal {
            match journal.to_lowercase().as_str() {
                s if s.contains("nature") => 1.0,
                s if s.contains("science") => 1.0,
                s if s.contains("cell") => 0.95,
                s if s.contains("ieee") => 0.9,
                s if s.contains("acm") => 0.9,
                _ => 0.5,
            }
        } else {
            0.3
        }
    }
}

struct QueryCoverageExtractor;
impl FeatureExtractor for QueryCoverageExtractor {
    fn extract(&self, paper: &Paper, query: &ParsedQuery) -> f32 {
        let text = format!("{} {}", paper.title, paper.abstract_text).to_lowercase();
        let covered = query
            .terms
            .iter()
            .filter(|term| text.contains(&term.to_lowercase()))
            .count();

        covered as f32 / query.terms.len().max(1) as f32
    }
}

struct TitleLengthExtractor;
impl FeatureExtractor for TitleLengthExtractor {
    fn extract(&self, paper: &Paper, _query: &ParsedQuery) -> f32 {
        // Prefer moderate length titles
        let words = paper.title.split_whitespace().count() as f32;
        1.0 / (1.0 + (words - 10.0).abs() / 10.0)
    }
}

struct AbstractLengthExtractor;
impl FeatureExtractor for AbstractLengthExtractor {
    fn extract(&self, paper: &Paper, _query: &ParsedQuery) -> f32 {
        // Prefer substantial abstracts
        let words = paper.abstract_text.split_whitespace().count() as f32;
        (words / 200.0).min(1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bm25_scoring() {
        let ranker = HybridRanker::new(RankingWeights::default());

        let paper = Paper {
            title: "Deep Learning for Natural Language Processing".to_string(),
            abstract_text: "This paper presents neural network methods for NLP tasks".to_string(),
            citation_count: 100,
            publication_date: chrono::Utc::now() - chrono::Duration::days(30),
            ..Default::default()
        };

        let query = ParsedQuery {
            original: "deep learning NLP".to_string(),
            terms: vec![
                "deep".to_string(),
                "learning".to_string(),
                "NLP".to_string(),
            ],
            filters: HashMap::new(),
            operators: vec![],
        };

        let score = ranker.calculate_bm25(&paper, &query).unwrap();
        assert!(score > 0.0);
        assert!(score <= 1.0);
    }

    #[test]
    fn test_feature_extraction() {
        let l2r = LearningToRank::new();

        let paper = Paper {
            title: "Machine Learning".to_string(),
            abstract_text: "A survey of ML methods".to_string(),
            citation_count: 50,
            ..Default::default()
        };

        let query = ParsedQuery {
            original: "machine learning".to_string(),
            terms: vec!["machine".to_string(), "learning".to_string()],
            filters: HashMap::new(),
            operators: vec![],
        };

        let features = l2r.extract_features(&paper, &query);
        assert_eq!(features.len(), 10);
        assert!(features[0] > 0.0); // Title match should be high
    }
}

