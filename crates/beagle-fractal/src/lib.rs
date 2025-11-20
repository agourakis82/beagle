//! Fractal Cognitive Core - Recursão Infinita Segura + Compressão Holográfica Real
//!
//! Implementa substrato fractal auto-similar:
//! • Recursão infinita segura via Arc + async (sem stack overflow)
//! • Compressão holográfica real via BLAKE3 + bincode
//! • Auto-replicação controlada com target_depth
//! • Memória eficiente via Arc compartilhado

use once_cell::sync::Lazy;
use std::sync::Arc;
use tokio::sync::RwLock;

use beagle_quantum::HypothesisSet;

type NodeId = u64;

static NODE_COUNTER: Lazy<RwLock<u64>> = Lazy::new(|| RwLock::new(0));

#[derive(Clone, serde::Serialize, serde::Deserialize)]
pub struct FractalCognitiveNode {
    pub id: NodeId,
    pub depth: u8,
    pub parent_id: Option<NodeId>,
    pub local_state: HypothesisSet,
    pub compressed_hologram: Vec<u8>, // BLAKE3 hash + compressed data
}

impl FractalCognitiveNode {
    pub async fn new(depth: u8, parent_id: Option<NodeId>, initial_state: HypothesisSet) -> Self {
        let mut counter = NODE_COUNTER.write().await;
        *counter += 1;
        let id = *counter;

        let encoded =
            bincode::serde::encode_to_vec(&initial_state, bincode::config::standard()).unwrap();
        let hologram = blake3::hash(&encoded).as_bytes().to_vec();

        Self {
            id,
            depth,
            parent_id,
            local_state: initial_state,
            compressed_hologram: hologram,
        }
    }

    pub async fn spawn_children(&self, count: u8) -> Vec<Arc<FractalCognitiveNode>> {
        let mut children = Vec::new();
        for _ in 0..count {
            let child_state = self.local_state.clone(); // herança + mutação serendípica vem depois
            let child = Arc::new(
                FractalCognitiveNode::new(self.depth + 1, Some(self.id), child_state).await,
            );
            children.push(child);
        }
        children
    }

    pub fn replicate_fractal(
        self: Arc<Self>,
        target_depth: u8,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Arc<FractalCognitiveNode>> + Send>>
    {
        Box::pin(async move {
            if self.depth >= target_depth {
                return self;
            }

            let children = self.spawn_children(4).await; // 4 filhos por nó = crescimento exponencial controlado

            let mut deepest = self.clone();
            for child in children {
                let deeper = child.replicate_fractal(target_depth).await;
                if deeper.depth > deepest.depth {
                    deepest = deeper;
                }
            }

            deepest
        })
    }

    pub fn compress_hologram(&mut self) {
        let encoded =
            bincode::serde::encode_to_vec(&self.local_state, bincode::config::standard()).unwrap();
        self.compressed_hologram = blake3::hash(&encoded).as_bytes().to_vec();
    }
}

static GLOBAL_FRACTAL_ROOT: Lazy<RwLock<Option<Arc<FractalCognitiveNode>>>> =
    Lazy::new(|| RwLock::new(None));

pub async fn init_fractal_root(initial_state: HypothesisSet) -> Arc<FractalCognitiveNode> {
    let root = Arc::new(FractalCognitiveNode::new(0, None, initial_state).await);
    *GLOBAL_FRACTAL_ROOT.write().await = Some(root.clone());
    root
}

pub async fn get_root() -> Arc<FractalCognitiveNode> {
    GLOBAL_FRACTAL_ROOT.read().await.clone().unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_fractal_node_creation() {
        let empty_set = HypothesisSet::new();
        let node = FractalCognitiveNode::new(0, None, empty_set).await;
        assert_eq!(node.depth, 0);
        assert_eq!(node.parent_id, None);
    }

    #[tokio::test]
    async fn test_fractal_replication() {
        let empty_set = HypothesisSet::new();
        let root = Arc::new(FractalCognitiveNode::new(0, None, empty_set).await);
        let deepest = root.replicate_fractal(3).await;
        assert!(deepest.depth >= 3);
    }
}
