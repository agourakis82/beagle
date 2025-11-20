//! Módulo de busca semântica do hipergrafo Beagle.
//!
//! Expõe mecanismos baseados em embeddings vetoriais (pgvector) e integrações
//! com provedores externos de embeddings (OpenAI) e provedores mock para testes.

#[cfg(feature = "database")]
pub mod semantic;

pub use crate::embeddings::EmbeddingGenerator;
#[cfg(feature = "database")]
pub use semantic::{MockEmbeddings, SearchResult, SemanticSearch};
