//! Hyperbolic Semantic Networks - 100% Rust
//! Implementa redes semânticas em espaços hiperbólicos usando petgraph

use ndarray::Array1;
use petgraph::algo::connected_components;
use petgraph::graph::NodeIndex;
use petgraph::{Graph, Undirected};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};
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
            Self::poincare_distance(
                &Self::project_to_poincare_ball(emb_a),
                &Self::project_to_poincare_ball(emb_b),
                self.hyperbolic_radius as f64,
            )
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

        let query_arr = Self::project_to_poincare_ball(&query_embedding);
        let mut distances = Vec::new();

        for (node_idx, embedding) in &self.embeddings {
            let hyperbolic_dist = Self::poincare_distance(
                &Self::project_to_poincare_ball(embedding),
                &query_arr,
                self.hyperbolic_radius as f64,
            );
            distances.push((*node_idx, hyperbolic_dist));
        }

        distances.sort_by(|a, b| a.1.total_cmp(&b.1));
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

        let num_components = connected_components(&self.graph);
        info!("✅ Número de componentes conectados: {}", num_components);

        let mut communities: Vec<Vec<NodeIndex>> = Vec::new();
        let mut visited = HashSet::new();

        for start in self.graph.node_indices() {
            if visited.contains(&start) {
                continue;
            }

            let mut component = Vec::new();
            let mut queue = VecDeque::from([start]);
            visited.insert(start);

            while let Some(node) = queue.pop_front() {
                component.push(node);
                for neighbor in self.graph.neighbors(node) {
                    if visited.insert(neighbor) {
                        queue.push_back(neighbor);
                    }
                }
            }

            communities.push(component);
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

    fn project_to_poincare_ball(embedding: &Array1<f32>) -> Vec<f64> {
        let norm = embedding
            .iter()
            .map(|v| (*v as f64).powi(2))
            .sum::<f64>()
            .sqrt();

        if norm <= f64::EPSILON {
            return vec![0.0; embedding.len()];
        }

        // Keeps every external embedding strictly inside the unit ball.
        let scale = norm.tanh() / norm * 0.999_999;
        embedding.iter().map(|v| *v as f64 * scale).collect()
    }

    fn poincare_distance(a: &[f64], b: &[f64], radius: f64) -> f64 {
        if a.len() != b.len() {
            return f64::INFINITY;
        }

        let norm_a_sq = a.iter().map(|v| v * v).sum::<f64>().min(0.999_999);
        let norm_b_sq = b.iter().map(|v| v * v).sum::<f64>().min(0.999_999);
        let diff_sq = a
            .iter()
            .zip(b.iter())
            .map(|(x, y)| (x - y).powi(2))
            .sum::<f64>();

        let denominator = ((1.0 - norm_a_sq) * (1.0 - norm_b_sq)).max(1e-12);
        let acosh_arg = (1.0 + 2.0 * diff_sq / denominator).max(1.0);

        radius.max(1e-6) * acosh_arg.acosh()
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
        assert!(metrics.avg_hyperbolic_distance.is_finite());
        assert!(metrics.avg_hyperbolic_distance > 0.0);
    }

    #[test]
    fn test_hyperbolic_communities_are_real_components() {
        let mut network = HyperbolicSemanticNetwork::new(1.0);

        let a = network.add_node("a".to_string(), array![0.1, 0.0]);
        let b = network.add_node("b".to_string(), array![0.2, 0.0]);
        let c = network.add_node("c".to_string(), array![0.0, 0.2]);

        network.add_edge(a, b, 1.0);

        let communities = network.find_communities();
        assert_eq!(communities.len(), 2);
        assert!(communities.iter().any(|community| community.len() == 2));
        assert!(communities.iter().any(|community| community.contains(&c)));
    }

    #[test]
    fn test_semantic_search_returns_finite_ordered_distances() {
        let mut network = HyperbolicSemanticNetwork::new(1.0);

        let near = network.add_node("near".to_string(), array![0.1, 0.1]);
        let far = network.add_node("far".to_string(), array![2.0, 2.0]);

        let results = network.semantic_search(array![0.11, 0.09], 2);
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].0, near);
        assert_eq!(results[1].0, far);
        assert!(results.iter().all(|(_, distance)| distance.is_finite()));
    }
}
