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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MemoryNeighbor {
    pub item_id: String,
    pub text: String,
    pub distance: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MemoryPlacement {
    pub item_id: String,
    pub node_index: usize,
    pub nearest_neighbors: Vec<MemoryNeighbor>,
    pub novelty_score: f64,
    pub fertile_link_score: f64,
}

#[derive(Debug, Clone)]
struct StoredMemory {
    id: String,
    text: String,
}

/// Places captured thoughts in hyperbolic semantic space without a remote embedding service.
pub struct HyperbolicMemoryPlacer {
    network: HyperbolicSemanticNetwork,
    items: HashMap<NodeIndex, StoredMemory>,
    embedding_dims: usize,
    link_top_k: usize,
}

impl HyperbolicMemoryPlacer {
    pub fn new(hyperbolic_radius: f32, embedding_dims: usize) -> Self {
        Self {
            network: HyperbolicSemanticNetwork::new(hyperbolic_radius),
            items: HashMap::new(),
            embedding_dims: embedding_dims.max(8),
            link_top_k: 3,
        }
    }

    pub fn add_memory(
        &mut self,
        item_id: impl Into<String>,
        text: impl Into<String>,
    ) -> MemoryPlacement {
        let item_id = item_id.into();
        let text = text.into();
        let embedding = self.embed_text(&text);
        let nearest_neighbors =
            self.nearest_neighbors_for_embedding(embedding.clone(), self.link_top_k);
        let novelty_score =
            Self::novelty_from_neighbors(&nearest_neighbors, self.network.hyperbolic_radius as f64);
        let fertile_link_score = Self::fertile_link_score(&nearest_neighbors, novelty_score);

        let node = self.network.add_node(text.clone(), embedding);
        self.items.insert(
            node,
            StoredMemory {
                id: item_id.clone(),
                text: text.clone(),
            },
        );

        for neighbor in &nearest_neighbors {
            if let Some(neighbor_node) = self.node_for_item_id(&neighbor.item_id) {
                let weight = 1.0 / (1.0 + neighbor.distance);
                self.network.add_edge(node, neighbor_node, weight);
            }
        }

        MemoryPlacement {
            item_id,
            node_index: node.index(),
            nearest_neighbors,
            novelty_score,
            fertile_link_score,
        }
    }

    pub fn preview_memory(
        &self,
        item_id: impl Into<String>,
        text: impl AsRef<str>,
    ) -> MemoryPlacement {
        let item_id = item_id.into();
        let embedding = self.embed_text(text.as_ref());
        let nearest_neighbors = self.nearest_neighbors_for_embedding(embedding, self.link_top_k);
        let novelty_score =
            Self::novelty_from_neighbors(&nearest_neighbors, self.network.hyperbolic_radius as f64);
        let fertile_link_score = Self::fertile_link_score(&nearest_neighbors, novelty_score);

        MemoryPlacement {
            item_id,
            node_index: usize::MAX,
            nearest_neighbors,
            novelty_score,
            fertile_link_score,
        }
    }

    pub fn metrics(&self) -> HyperbolicMetrics {
        self.network.compute_metrics()
    }

    fn nearest_neighbors_for_embedding(
        &self,
        embedding: Array1<f32>,
        top_k: usize,
    ) -> Vec<MemoryNeighbor> {
        self.network
            .semantic_search(embedding, top_k)
            .into_iter()
            .filter_map(|(node, distance)| {
                self.items.get(&node).map(|item| MemoryNeighbor {
                    item_id: item.id.clone(),
                    text: item.text.clone(),
                    distance,
                })
            })
            .collect()
    }

    fn node_for_item_id(&self, item_id: &str) -> Option<NodeIndex> {
        self.items
            .iter()
            .find_map(|(node, item)| (item.id == item_id).then_some(*node))
    }

    fn embed_text(&self, text: &str) -> Array1<f32> {
        let mut vector = vec![0.0_f32; self.embedding_dims];
        let mut token_count = 0.0_f32;

        for token in tokenize(text) {
            let hash = stable_hash(&token);
            let index = (hash as usize) % self.embedding_dims;
            vector[index] += 1.0;
            token_count += 1.0;
        }

        if token_count > 0.0 {
            let norm = vector.iter().map(|value| value * value).sum::<f32>().sqrt();
            if norm > f32::EPSILON {
                for value in &mut vector {
                    *value /= norm;
                }
            }
        }

        Array1::from_vec(vector)
    }

    fn novelty_from_neighbors(neighbors: &[MemoryNeighbor], radius: f64) -> f64 {
        if neighbors.is_empty() {
            return 1.0;
        }

        let avg_distance = neighbors
            .iter()
            .map(|neighbor| neighbor.distance)
            .sum::<f64>()
            / neighbors.len() as f64;
        (avg_distance / (avg_distance + radius.max(1e-6))).clamp(0.0, 1.0)
    }

    fn fertile_link_score(neighbors: &[MemoryNeighbor], novelty_score: f64) -> f64 {
        if neighbors.len() < 2 {
            return novelty_score;
        }

        let avg = neighbors
            .iter()
            .map(|neighbor| neighbor.distance)
            .sum::<f64>()
            / neighbors.len() as f64;
        let variance = neighbors
            .iter()
            .map(|neighbor| (neighbor.distance - avg).powi(2))
            .sum::<f64>()
            / neighbors.len() as f64;
        let spread = variance.sqrt();

        (novelty_score * (1.0 + spread)).clamp(0.0, 1.0)
    }
}

impl Default for HyperbolicMemoryPlacer {
    fn default() -> Self {
        Self::new(1.0, 64)
    }
}

fn tokenize(text: &str) -> Vec<String> {
    let stopwords = HashSet::from([
        "a", "an", "and", "as", "da", "das", "de", "do", "dos", "e", "em", "for", "in", "is", "o",
        "of", "on", "os", "para", "por", "the", "to", "um", "uma", "with",
    ]);

    text.split(|character: char| !character.is_alphanumeric())
        .map(str::to_lowercase)
        .filter(|token| token.len() > 2 && !stopwords.contains(token.as_str()))
        .collect()
}

fn stable_hash(text: &str) -> u64 {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in text.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
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

    #[test]
    fn test_memory_placement_links_related_thoughts() {
        let mut placer = HyperbolicMemoryPlacer::new(1.0, 64);

        placer.add_memory(
            "m1",
            "entropy increases when temperature rises in closed systems",
        );
        placer.add_memory(
            "m2",
            "patient consent metadata belongs in the clinical archive",
        );

        let placement = placer.add_memory(
            "m3",
            "temperature and entropy increase together in this experiment",
        );

        assert_eq!(placement.item_id, "m3");
        assert_eq!(placement.nearest_neighbors.len(), 2);
        assert_eq!(placement.nearest_neighbors[0].item_id, "m1");
        assert!(placement.novelty_score.is_finite());
        assert!((0.0..=1.0).contains(&placement.novelty_score));
        assert!((0.0..=1.0).contains(&placement.fertile_link_score));
    }

    #[test]
    fn test_memory_placement_updates_network_metrics() {
        let mut placer = HyperbolicMemoryPlacer::new(1.0, 32);

        let first = placer.add_memory("m1", "void analysis surfaces missing evidence");
        let second = placer.add_memory("m2", "missing evidence should be reintegrated");

        let metrics = placer.metrics();
        assert_eq!(first.nearest_neighbors.len(), 0);
        assert_eq!(second.nearest_neighbors.len(), 1);
        assert_eq!(metrics.n_nodes, 2);
        assert_eq!(metrics.n_edges, 1);
        assert!(metrics.avg_hyperbolic_distance.is_finite());
    }

    #[test]
    fn test_memory_preview_does_not_mutate_network() {
        let mut placer = HyperbolicMemoryPlacer::new(1.0, 32);
        placer.add_memory("m1", "paradox ledger preserves real contradictions");

        let before = placer.metrics();
        let preview = placer.preview_memory(
            "candidate",
            "contradictions should be preserved before repair",
        );
        let after = placer.metrics();

        assert_eq!(preview.node_index, usize::MAX);
        assert_eq!(preview.nearest_neighbors[0].item_id, "m1");
        assert_eq!(before.n_nodes, after.n_nodes);
        assert_eq!(before.n_edges, after.n_edges);
    }
}
