//! Hyperbolic Semantic Networks - 100% Rust
//! Implementa redes semânticas em espaços hiperbólicos usando petgraph

use ndarray::{Array1, Array2};
use petgraph::algo::{connected_components, dijkstra};
use petgraph::graph::NodeIndex;
use petgraph::{EdgeType, Graph, Undirected};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::info;

/// Rede semântica hiperbólica
pub struct HyperbolicSemanticNetwork {
    graph: Graph<String, f64, Undirected>,
    embeddings: HashMap<NodeIndex, Array1<f32>>,
    hyperbolic_radius: f32,
}

impl HyperbolicSemanticNetwork {
    pub fn new(hyperbolic_radius: f32) -> Self {
        info!(
            "🌐 HyperbolicSemanticNetwork inicializado (radius: {})",
            hyperbolic_radius
        );
        Self {
            graph: Graph::new_undirected(),
            embeddings: HashMap::new(),
            hyperbolic_radius,
        }
    }

    pub fn add_node(&mut self, concept: String, embedding: Array1<f32>) -> NodeIndex {
        let node_idx = self.graph.add_node(concept.clone());
        self.embeddings.insert(node_idx, embedding);
        info!("➕ Nó adicionado: {} (idx: {:?})", concept, node_idx);
        node_idx
    }

    pub fn add_edge(&mut self, a: NodeIndex, b: NodeIndex, weight: f64) {
        self.graph.add_edge(a, b, weight);
        info!(
            "🔗 Aresta adicionada: {:?} -> {:?} (weight: {})",
            a, b, weight
        );
    }

    /// Computa distância hiperbólica entre dois nós
    pub fn hyperbolic_distance(&self, a: NodeIndex, b: NodeIndex) -> f64 {
        if let (Some(emb_a), Some(emb_b)) = (self.embeddings.get(&a), self.embeddings.get(&b)) {
            // Distância euclidiana no espaço de embeddings
            let euclidean = ((emb_a - emb_b).mapv(|x| (x as f64).powi(2))).sum().sqrt();

            // Projeta para espaço hiperbólico (Poincaré disk model)
            let hyperbolic = self.hyperbolic_radius as f64
                * ((euclidean / self.hyperbolic_radius as f64).tanh().acosh() * 2.0);

            hyperbolic
        } else {
            f64::INFINITY
        }
    }

    /// Busca semântica usando distância hiperbólica
    pub fn semantic_search(
        &self,
        query_embedding: Array1<f32>,
        top_k: usize,
    ) -> Vec<(NodeIndex, f64)> {
        info!("🔍 Busca semântica (top-{})", top_k);

        let query_arr = Array1::from_vec(query_embedding.to_vec());
        let mut distances = Vec::new();

        for (node_idx, embedding) in &self.embeddings {
            let dist = ((embedding - &query_arr).mapv(|x| (x as f64).powi(2)))
                .sum()
                .sqrt();
            let hyperbolic_dist = self.hyperbolic_radius as f64
                * ((dist / self.hyperbolic_radius as f64).tanh().acosh() * 2.0);
            distances.push((*node_idx, hyperbolic_dist));
        }

        distances.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
        distances.truncate(top_k);

        distances
    }

    /// Computa centralidade hiperbólica
    pub fn hyperbolic_centrality(&self, node: NodeIndex) -> f64 {
        // Centralidade baseada em distâncias hiperbólicas
        let mut total_distance = 0.0;
        let mut count = 0;

        for other_node in self.graph.node_indices() {
            if other_node != node {
                let dist = self.hyperbolic_distance(node, other_node);
                if dist.is_finite() {
                    total_distance += dist;
                    count += 1;
                }
            }
        }

        if count > 0 {
            1.0 / (total_distance / count as f64 + 1e-6)
        } else {
            0.0
        }
    }

    /// Encontra comunidades usando clustering hiperbólico
    pub fn find_communities(&self) -> Vec<Vec<NodeIndex>> {
        info!("🔬 Encontrando comunidades hiperbólicas");

        // Usa connected components como base
        let components = connected_components(&self.graph);

        // Agrupa nós por componente
        let mut communities: Vec<Vec<NodeIndex>> = Vec::new();
        let mut component_map: HashMap<usize, Vec<NodeIndex>> = HashMap::new();

        for (idx, comp) in components.iter().enumerate() {
            component_map
                .entry(*comp)
                .or_insert_with(Vec::new)
                .push(NodeIndex::new(idx));
        }

        for community in component_map.values() {
            communities.push(community.clone());
        }

        info!("✅ Encontradas {} comunidades", communities.len());
        communities
    }

    /// Computa métricas da rede hiperbólica
    pub fn compute_metrics(&self) -> HyperbolicMetrics {
        let n_nodes = self.graph.node_count();
        let n_edges = self.graph.edge_count();

        // Average degree
        let avg_degree = if n_nodes > 0 {
            (2.0 * n_edges as f64) / n_nodes as f64
        } else {
            0.0
        };

        // Average hyperbolic distance
        let mut total_dist = 0.0;
        let mut count = 0;

        for node_a in self.graph.node_indices() {
            for node_b in self.graph.node_indices() {
                if node_a < node_b {
                    let dist = self.hyperbolic_distance(node_a, node_b);
                    if dist.is_finite() {
                        total_dist += dist;
                        count += 1;
                    }
                }
            }
        }

        let avg_hyperbolic_dist = if count > 0 {
            total_dist / count as f64
        } else {
            0.0
        };

        HyperbolicMetrics {
            n_nodes,
            n_edges,
            avg_degree,
            avg_hyperbolic_distance: avg_hyperbolic_dist,
            hyperbolic_radius: self.hyperbolic_radius as f64,
        }
    }
}

/// Métricas da rede hiperbólica
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HyperbolicMetrics {
    pub n_nodes: usize,
    pub n_edges: usize,
    pub avg_degree: f64,
    pub avg_hyperbolic_distance: f64,
    pub hyperbolic_radius: f64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use ndarray::array;

    #[test]
    fn test_hyperbolic_network() {
        let mut network = HyperbolicSemanticNetwork::new(1.0);

        let emb1 = array![1.0, 0.0, 0.0];
        let emb2 = array![0.0, 1.0, 0.0];

        let node1 = network.add_node("concept1".to_string(), emb1);
        let node2 = network.add_node("concept2".to_string(), emb2);

        network.add_edge(node1, node2, 1.0);

        let metrics = network.compute_metrics();
        assert_eq!(metrics.n_nodes, 2);
        assert_eq!(metrics.n_edges, 1);
    }
}
