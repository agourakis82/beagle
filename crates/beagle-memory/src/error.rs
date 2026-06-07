//! Error types for the memory crate.

use thiserror::Error;

/// Errors that can occur within the memory subsystem (RAG engine, retrieval).
#[derive(Debug, Error)]
pub enum MemoryError {
    /// A document or chunk could not be embedded.
    #[error("embedding failed: {0}")]
    Embedding(String),

    /// Retrieval / search failed.
    #[error("retrieval failed: {0}")]
    Retrieval(String),

    /// Reranking failed (callers should fall back to the unranked fused order).
    #[error("rerank failed: {0}")]
    Rerank(String),

    /// Underlying storage failure.
    #[error("storage error: {0}")]
    Storage(String),

    /// Catch-all wrapped error.
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}
