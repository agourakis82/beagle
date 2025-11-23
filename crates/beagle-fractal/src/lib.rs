//! Fractal Cognitive Core - Recursão Infinita Segura + Compressão Holográfica Real
//!
//! Implementa substrato fractal auto-similar:
//! • Recursão infinita segura via Arc + async (sem stack overflow)
//! • Compressão holográfica real via BLAKE3 + bincode
//! • Auto-replicação controlada com target_depth
//! • Memória eficiente via Arc compartilhado
//!
//! ## Modules
//! - `fractal_node`: Core recursive cognitive nodes
//! - `entropy_lattice`: Multi-scale entropy tracking
//! - `holographic_storage`: Knowledge compression via holographic principle
//! - `self_replication`: System replication and export/import

// ============================================
// Module Declarations
// ============================================
pub mod fractal_node;
pub mod entropy_lattice;
pub mod holographic_storage;
pub mod self_replication;

// ============================================
// Type Re-exports
// ============================================
pub use fractal_node::{FractalCognitiveNode, FractalNodeRuntime};
pub use entropy_lattice::{EntropyLattice, LatticeNode, LatticeEdge};
pub use holographic_storage::HolographicStorage;
pub use self_replication::{SelfReplicator, ReplicationManifest};

// ============================================
// Core API Functions
// ============================================

use once_cell::sync::Lazy;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;

static GLOBAL_FRACTAL_ROOT: Lazy<RwLock<Option<Arc<FractalCognitiveNode>>>> =
    Lazy::new(|| RwLock::new(None));

/// Initialize the global fractal root node
pub async fn init_fractal_root() -> Arc<FractalCognitiveNode> {
    let root = Arc::new(FractalCognitiveNode::root());
    *GLOBAL_FRACTAL_ROOT.write().await = Some(root.clone());
    info!("🌳 Fractal root initialized");
    root
}

/// Get the global fractal root node
pub async fn get_root() -> Arc<FractalCognitiveNode> {
    GLOBAL_FRACTAL_ROOT
        .read()
        .await
        .clone()
        .expect("Fractal root not initialized. Call init_fractal_root first.")
}

/// Start eternal recursive cognitive processing
///
/// This function initiates the infinite recursive cognitive cycle at the fractal root.
/// It continuously processes queries through the entire fractal tree until stopped.
pub async fn start_eternal_recursion() -> anyhow::Result<()> {
    info!("🔄 Starting eternal fractal recursion...");

    let root = get_root().await;
    // Dereference the Arc to get the node, then wrap it in a runtime
    let root_node = (*root).clone();
    let runtime = FractalNodeRuntime::new(root_node);

    // Start continuous cognitive cycles at the root
    // This will spawn recursive processing across all depths
    loop {
        let query = "What am I? How do I improve? What is my purpose?";
        match runtime.execute_full_cycle(query).await {
            Ok(response) => {
                info!("🧠 Cycle completed: {}", &response[..std::cmp::min(100, response.len())]);
                tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
            }
            Err(e) => {
                info!("⚠️ Cycle error: {}", e);
                break;
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_fractal_root_initialization() {
        let root = init_fractal_root().await;
        assert_eq!(root.depth, 0);
        assert_eq!(root.parent_id, None);
    }

    #[tokio::test]
    async fn test_fractal_root_retrieval() {
        init_fractal_root().await;
        let root = get_root().await;
        assert_eq!(root.depth, 0);
    }
}
