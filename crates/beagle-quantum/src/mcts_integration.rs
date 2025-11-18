//! MCTS Integration – Monte Carlo Tree Search com Superposição
//!
//! Explora árvore de decisões mantendo múltiplas hipóteses simultâneas

use crate::superposition::HypothesisSet;
use petgraph::{Graph, Directed, graph::NodeIndex};
use std::collections::HashMap;
use tracing::debug;

pub struct QuantumMCTS {
    graph: Graph<HypothesisSet, f64, Directed>,
    node_map: HashMap<String, NodeIndex>,
}

impl QuantumMCTS {
    pub fn new() -> Self {
        Self {
            graph: Graph::new(),
            node_map: HashMap::new(),
        }
    }

    /// Adiciona um nó de superposição à árvore
    pub fn add_node(&mut self, id: String, hypothesis_set: HypothesisSet) -> NodeIndex {
        let node_idx = self.graph.add_node(hypothesis_set);
        self.node_map.insert(id, node_idx);
        node_idx
    }

    /// Conecta dois nós com um peso (probabilidade de transição)
    pub fn add_edge(&mut self, from: &str, to: &str, weight: f64) -> anyhow::Result<()> {
        let from_idx = self.node_map.get(from)
            .ok_or_else(|| anyhow::anyhow!("Nó '{}' não encontrado", from))?;
        let to_idx = self.node_map.get(to)
            .ok_or_else(|| anyhow::anyhow!("Nó '{}' não encontrado", to))?;
        
        self.graph.add_edge(*from_idx, *to_idx, weight);
        Ok(())
    }

    /// Explora a árvore mantendo superposição
    pub fn explore(&self, start: &str, depth: usize) -> anyhow::Result<HypothesisSet> {
        let start_idx = self.node_map.get(start)
            .ok_or_else(|| anyhow::anyhow!("Nó inicial '{}' não encontrado", start))?;
        
        let mut current_set = self.graph[*start_idx].clone();
        
        for _ in 0..depth {
            let mut next_set = HypothesisSet::new();
            
            // Explora vizinhos mantendo superposição
            for neighbor_idx in self.graph.neighbors(*start_idx) {
                let neighbor_set = &self.graph[neighbor_idx];
                // Combina hipóteses dos vizinhos
                for hyp in &neighbor_set.hypotheses {
                    next_set.add(hyp.content.clone(), Some(hyp.amplitude));
                }
            }
            
            if !next_set.hypotheses.is_empty() {
                current_set = next_set;
            } else {
                break;
            }
        }
        
        debug!("Exploração MCTS completa: {} hipóteses", current_set.hypotheses.len());
        Ok(current_set)
    }
}

impl Default for QuantumMCTS {
    fn default() -> Self {
        Self::new()
    }
}

