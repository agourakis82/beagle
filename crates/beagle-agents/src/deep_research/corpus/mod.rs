//! Scientific corpus integration for novelty detection
//!
//! This module provides integration with Semantic Scholar API and embedding-based
//! novelty scoring to compare hypotheses against existing scientific literature.

pub mod embeddings;
pub mod novelty;
pub mod semantic_scholar;

pub use embeddings::EmbeddingEngine;
pub use novelty::NoveltyScorer;
pub use semantic_scholar::{Paper, ScholarAPI};
