//! BEAGLE Core - Traits e Context para Injeção de Dependências
//!
//! Define interfaces abstratas (traits) para LLM, Vector Store e Graph Store,
//! permitindo que Darwin e HERMES operem com diferentes implementações
//! (Grok, Claude, Qdrant, Neo4j, mocks para testes, etc.).

pub mod traits;
pub mod context;
pub mod implementations;
pub mod stats;

pub use stats::LlmStatsRegistry;

pub use traits::*;
pub use context::*;
pub use implementations::*;

