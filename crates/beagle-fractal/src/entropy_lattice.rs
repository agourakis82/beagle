//! Entropy Lattice – Lattice entrópico fractal
//!
//! Estrutura que mapeia entropia em múltiplas escalas simultaneamente

use petgraph::Graph;
use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone)]
pub struct EntropyLattice {
    graph: Graph<LatticeNode, LatticeEdge>,
    scale_levels: Vec<f64>, // Níveis de escala (micro → macro)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LatticeNode {
    pub scale: f64,
    pub entropy: f64,
    pub node_id: uuid::Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LatticeEdge {
    pub entropy_flow: f64,
    pub compression_ratio: f64,
}

impl EntropyLattice {
    pub fn new() -> Self {
        Self {
            graph: Graph::new(),
            scale_levels: vec![1.0, 10.0, 100.0, 1000.0, 10000.0], // 5 níveis de escala
        }
    }

    /// Adiciona nó ao lattice em uma escala específica
    pub fn add_node(&mut self, node_id: uuid::Uuid, scale: f64, entropy: f64) {
        let node = LatticeNode {
            scale,
            entropy,
            node_id,
        };
        self.graph.add_node(node);
        info!("ENTROPY LATTICE: Nó adicionado na escala {} com entropia {:.2}", scale, entropy);
    }

    /// Conecta dois nós com fluxo entrópico
    pub fn connect_nodes(
        &mut self,
        from: petgraph::graph::NodeIndex,
        to: petgraph::graph::NodeIndex,
        entropy_flow: f64,
        compression_ratio: f64,
    ) {
        let edge = LatticeEdge {
            entropy_flow,
            compression_ratio,
        };
        self.graph.add_edge(from, to, edge);
        info!(
            "ENTROPY LATTICE: Nós conectados com fluxo entrópico {:.2} (compressão {:.2}:1)",
            entropy_flow, compression_ratio
        );
    }

    /// Calcula entropia total do lattice em todas as escalas
    pub fn total_entropy(&self) -> f64 {
        self.graph
            .node_weights()
            .map(|n| n.entropy)
            .sum::<f64>()
    }

    /// Obtém entropia em uma escala específica
    pub fn entropy_at_scale(&self, scale: f64) -> f64 {
        self.graph
            .node_weights()
            .filter(|n| (n.scale - scale).abs() < 0.1)
            .map(|n| n.entropy)
            .sum()
    }
}

impl Default for EntropyLattice {
    fn default() -> Self {
        Self::new()
    }
}

