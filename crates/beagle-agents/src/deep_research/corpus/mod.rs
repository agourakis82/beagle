//! Scientific corpus integration for novelty detection
//!
//! This module provides integration with Semantic Scholar API and embedding-based
//! novelty scoring to compare hypotheses against existing scientific literature.

pub mod semantic_scholar;
pub mod embeddings;
pub mod novelty;

pub use semantic_scholar::{Paper, ScholarAPI};
pub use embeddings::EmbeddingEngine;
pub use novelty::NoveltyScorer;


