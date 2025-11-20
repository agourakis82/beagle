//! Beagle Workspace - Migração completa do darwin-workspace para Rust/Julia
//!
//! Features migradas:
//! - KEC 3.0 GPU-accelerated (Julia)
//! - PBPK modeling (Julia)
//! - Heliobiology pipelines (Julia)
//! - Embeddings SOTA (Rust)
//! - Vector search híbrido (Rust)
//! - Agentic workflows (Rust)

pub mod embeddings;
pub mod heliobiology;
pub mod kec;
pub mod pbpk;
pub mod pcs;
pub mod scaffold;
pub mod vector_search;
pub mod workflows;

pub use embeddings::{EmbeddingManager, EmbeddingModel};
pub use heliobiology::HeliobiologyPlatform;
pub use kec::Kec3Engine;
pub use pbpk::PBPKPlatform;
pub use pcs::PCSSymbolicPsychiatry;
pub use scaffold::ScaffoldStudio;
pub use vector_search::HybridVectorSearch;
pub use workflows::ResearchWorkflow;

use tracing::info;

/// Inicializa o Beagle Workspace
pub fn init() {
    info!("🚀 Beagle Workspace inicializado (100% Rust/Julia, zero Python)");
}
