//! beagle-search - Scientific paper search clients
//!
//! Provides unified interfaces for searching scientific literature:
//! - PubMed (biomedical/life sciences via NCBI E-utilities)
//! - arXiv (physics, math, CS, etc.)
//!
//! All clients support:
//! - Rate limiting (respects API limits)
//! - Retry with exponential backoff
//! - Structured result types
//! - Async/await

pub mod arxiv;
pub mod pubmed;
pub mod storage;
pub mod types;

pub use arxiv::ArxivClient;
pub use pubmed::PubMedClient;
pub use types::{Author, Paper, SearchError, SearchQuery, SearchResult};

use async_trait::async_trait;

/// Unified trait for scientific paper search backends
#[async_trait]
pub trait SearchClient: Send + Sync {
    /// Search for papers matching the query
    async fn search(&self, query: &SearchQuery) -> Result<SearchResult, SearchError>;

    /// Fetch full paper details by ID
    async fn fetch_paper(&self, id: &str) -> Result<Paper, SearchError>;

    /// Get the name of this search backend
    fn backend_name(&self) -> &str;
}
