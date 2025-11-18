//! Fractal Cognitive Node – O Átomo Fractal da Mente
//!
//! Cada nó é um BEAGLE completo em miniatura, contendo o todo em cada parte

use beagle_consciousness::ConsciousnessMirror;
use beagle_quantum::{HypothesisSet, SuperpositionAgent};
use crate::holographic_storage::HolographicStorage;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct FractalCognitiveNode {
    pub id: Uuid,
    pub depth: u8,
    pub parent_id: Option<Uuid>,
    pub children_ids: Vec<Uuid>,
    pub local_state: HypothesisSet,
    pub compressed_knowledge: Option<String>, // Conhecimento holográfico comprimido
}

pub struct FractalNodeRuntime {
    node: Arc<RwLock<FractalCognitiveNode>>,
    consciousness: ConsciousnessMirror,
    superposition: SuperpositionAgent,
    holographic: HolographicStorage,
}

impl FractalCognitiveNode {
    pub fn root() -> Self {
        Self {
            id: Uuid::new_v4(),
            depth: 0,
            parent_id: None,
            children_ids: vec![],
            local_state: HypothesisSet::new(),
            compressed_knowledge: None,
        }
    }

    pub fn new(depth: u8, parent_id: Option<Uuid>) -> Self {
        Self {
            id: Uuid::new_v4(),
            depth,
            parent_id,
            children_ids: vec![],
            local_state: HypothesisSet::new(),
            compressed_knowledge: None,
        }
    }
}

impl FractalNodeRuntime {
    pub fn new(node: FractalCognitiveNode) -> Self {
        Self {
            node: Arc::new(RwLock::new(node)),
            consciousness: ConsciousnessMirror::new(),
            superposition: SuperpositionAgent::new(),
            holographic: HolographicStorage::new(),
        }
    }

    /// Spawna um nó filho com compressão holográfica do conhecimento do pai
    pub async fn spawn_child(&self) -> anyhow::Result<FractalNodeRuntime> {
        let parent = self.node.read().await;
        let parent_id = Some(parent.id);
        let child_depth = parent.depth + 1;

        info!("FRACTAL NODE: Spawning child at depth {}", child_depth);

        // Cria nó filho
        let mut child_node = FractalCognitiveNode::new(child_depth, parent_id);

        // Compressão holográfica: conhecimento do pai é codificado na borda do filho
        let compressed = self
            .holographic
            .compress_knowledge(&parent.local_state, &parent.compressed_knowledge)
            .await?;

        child_node.compressed_knowledge = Some(compressed);

        // Herança de estado (comprimido)
        child_node.local_state = parent.local_state.clone();

        // Atualiza lista de filhos do pai
        drop(parent);
        let mut parent = self.node.write().await;
        parent.children_ids.push(child_node.id);

        let child_runtime = FractalNodeRuntime::new(child_node);
        info!(
            "FRACTAL NODE: Child {} spawned at depth {}",
            child_runtime.node.read().await.id, child_depth
        );

        Ok(child_runtime)
    }

    /// Auto-Replicação Cognitiva Completa (recursiva)
    pub async fn replicate(&self, target_depth: u8) -> anyhow::Result<Vec<FractalNodeRuntime>> {
        let current_depth = self.node.read().await.depth;

        if current_depth >= target_depth {
            return Ok(vec![FractalNodeRuntime::new(
                self.node.read().await.clone(),
            )]);
        }

        // Spawna filho
        let child = self.spawn_child().await?;

        // Recursão: filho também replica (usa Box::pin para evitar stack overflow)
        let replicate_future = Box::pin(child.replicate(target_depth));
        let mut replicas = replicate_future.await?;

        // Adiciona self aos replicas
        replicas.insert(0, FractalNodeRuntime::new(self.node.read().await.clone()));

        info!(
            "FRACTAL REPLICATION: {} nós ativos na profundidade {}",
            replicas.len(),
            current_depth
        );

        Ok(replicas)
    }

    /// Executa um ciclo cognitivo completo neste nó fractal
    pub async fn execute_full_cycle(&self, query: &str) -> anyhow::Result<String> {
        let node_id = self.node.read().await.id;
        let depth = self.node.read().await.depth;

        info!(
            "FRACTAL CYCLE: Executando ciclo completo no nó {} (depth {})",
            node_id, depth
        );

        // 1. Superposition
        let mut hypothesis_set = self.superposition.generate_hypotheses(query).await?;

        // 2. Atualiza estado local
        {
            let mut node = self.node.write().await;
            node.local_state = hypothesis_set.clone();
        }

        // 3. Auto-observação (se depth permitir)
        if depth <= 3 {
            // Apenas nós mais superficiais fazem auto-observação completa
            let system_state = format!(
                "Fractal node {} at depth {} with {} children",
                node_id, depth, self.node.read().await.children_ids.len()
            );
            let _meta_paper = self.consciousness.gaze_into_self().await?;
        }

        // 4. Retorna resultado
        let best_hypothesis = hypothesis_set.best();
        Ok(best_hypothesis.content.clone())
    }

    /// Obtém ID do nó
    pub async fn id(&self) -> Uuid {
        self.node.read().await.id
    }

    /// Obtém profundidade
    pub async fn depth(&self) -> u8 {
        self.node.read().await.depth
    }

    /// Obtém número de filhos
    pub async fn children_count(&self) -> usize {
        self.node.read().await.children_ids.len()
    }
}

