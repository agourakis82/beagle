//! Beagle Workspace - Migração completa do darwin-workspace para Rust/Julia
//!
//! Features migradas:
//! - KEC 3.0 GPU-accelerated (Julia)
//! - PBPK modeling (Julia)
//! - Heliobiology pipelines (Julia)
//! - Embeddings SOTA (Rust)
//! - Vector search híbrido (Rust)
//! - Agentic workflows (Rust)

pub mod kec;
pub mod embeddings;
pub mod vector_search;
pub mod workflows;
pub mod pbpk;
pub mod heliobiology;
pub mod pcs;
pub mod scaffold;

pub use kec::Kec3Engine;
pub use embeddings::{EmbeddingManager, EmbeddingModel};
pub use vector_search::HybridVectorSearch;
pub use workflows::ResearchWorkflow;
pub use pbpk::PBPKPlatform;
pub use heliobiology::HeliobiologyPlatform;
pub use pcs::PCSSymbolicPsychiatry;
pub use scaffold::ScaffoldStudio;

use tracing::info;

/// Inicializa o Beagle Workspace
pub fn init() {
    info!("🚀 Beagle Workspace inicializado (100% Rust/Julia, zero Python)");
}
