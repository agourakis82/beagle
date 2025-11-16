//! Módulo de busca semântica do hipergrafo Beagle.
//!
//! Expõe mecanismos baseados em embeddings vetoriais (pgvector) e integrações
//! com provedores externos de embeddings (OpenAI) e provedores mock para testes.

pub mod semantic;

pub use crate::embeddings::EmbeddingGenerator;
pub use semantic::{MockEmbeddings, SearchResult, SemanticSearch};
