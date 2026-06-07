//! GraphRAG / Personalized-PageRank multi-hop retrieval lane (HippoRAG-style).
//!
//! Single-hop, "lookup"-style queries are served well by dense / hybrid
//! retrieval (see [`crate::search`] and the TCR-QF fusion in
//! [`crate::rag::tcr_qf`]). Multi-hop / sense-making queries, however, need to
//! follow chains of associations across the knowledge graph — exactly what
//! [HippoRAG](https://arxiv.org/abs/2405.14831) achieves by running
//! **Personalized PageRank (PPR)** seeded on the query's entity nodes.
//!
//! This module is an **opt-in lane**: it does NOT replace or alter existing
//! retrieval functions. Callers decide (via [`RetrievalLane`] /
//! [`GraphRagLane::retrieve`]) when a query is multi-hop and should take the
//! PPR path. The PPR math itself is delegated to the existing
//! [`PageRankCalculator`] (extended with
//! [`PageRankCalculator::compute_personalized`]) — no PageRank is reimplemented
//! here.
//!
//! ## Pipeline
//! 1. **Seed derivation** — given the dense/lexical top-k nodes that match the
//!    query terms (plus optional per-seed scores), build a personalization
//!    vector over those seeds.
//! 2. **Graph propagation** — run Personalized PageRank (restart-biased toward
//!    the seeds) over the graph.
//! 3. **Rank & return** — return the top-`k` nodes/passages by PPR score.

use std::collections::HashMap;

use uuid::Uuid;

use super::tcr_qf::{GraphStructure, PageRankCalculator};

/// Which retrieval lane to use for a query.
///
/// This is a routing hint only; it lets a caller make the multi-hop decision
/// explicit and keep single-hop queries on the existing dense/hybrid path.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RetrievalLane {
    /// Single-hop / lookup query — keep using dense or hybrid retrieval.
    DenseHybrid,
    /// Multi-hop / sense-making query — use the PPR GraphRAG lane.
    GraphPpr,
}

/// A seed node for the GraphRAG lane: a node that matched the query in the
/// dense/lexical pre-retrieval stage, together with how strongly it matched.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Seed {
    /// Node id that matched the query.
    pub node_id: Uuid,
    /// Match strength (e.g. cosine similarity or BM25 score). Non-positive
    /// weights are treated as a uniform contribution so a seed is never silently
    /// dropped; use [`GraphRagLane::retrieve`] with explicit weights when you
    /// want score-weighted restart mass.
    pub weight: f32,
}

impl Seed {
    /// Convenience constructor with an explicit weight.
    pub fn new(node_id: Uuid, weight: f32) -> Self {
        Self { node_id, weight }
    }

    /// Convenience constructor for an unweighted seed (uniform restart mass).
    pub fn uniform(node_id: Uuid) -> Self {
        Self {
            node_id,
            weight: 1.0,
        }
    }
}

/// A single retrieval result from the GraphRAG lane.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GraphRagResult {
    /// Retrieved node id.
    pub node_id: Uuid,
    /// Personalized PageRank score (relevance under the seed-biased walk).
    pub score: f32,
    /// Whether this node was one of the original query seeds.
    pub is_seed: bool,
}

/// Configuration for the GraphRAG / PPR lane.
#[derive(Debug, Clone)]
pub struct GraphRagLane {
    /// Underlying PageRank engine (reused for the PPR math).
    pub calculator: PageRankCalculator,
    /// Maximum number of results to return.
    pub top_k: usize,
    /// If true, seed nodes themselves are eligible to appear in the results.
    /// If false, seeds are excluded so the lane surfaces *newly discovered*
    /// multi-hop neighbors instead of echoing the dense pre-retrieval hits.
    pub include_seeds: bool,
}

impl Default for GraphRagLane {
    fn default() -> Self {
        Self {
            calculator: PageRankCalculator::default(),
            top_k: 10,
            include_seeds: true,
        }
    }
}

impl GraphRagLane {
    /// Create a lane with default PPR parameters and the given `top_k`.
    pub fn new(top_k: usize) -> Self {
        Self {
            top_k,
            ..Self::default()
        }
    }

    /// Run the HippoRAG-style retrieval lane.
    ///
    /// Builds a personalization (restart) vector from `seeds`, runs Personalized
    /// PageRank over `graph` via the shared [`PageRankCalculator`], and returns
    /// the top-`top_k` nodes ranked by PPR score (descending). Ties are broken
    /// deterministically by node id so results are stable across runs.
    ///
    /// Returns an empty vector if the graph is empty or no seed maps to a node
    /// in the graph.
    pub fn retrieve(&self, graph: &GraphStructure, seeds: &[Seed]) -> Vec<GraphRagResult> {
        if graph.nodes.is_empty() || seeds.is_empty() {
            return Vec::new();
        }

        // Build the personalization vector. Seeds with non-positive weights fall
        // back to a uniform 1.0 contribution so they still anchor the walk.
        let mut personalization: HashMap<Uuid, f32> = HashMap::new();
        let mut seed_ids: HashMap<Uuid, ()> = HashMap::new();
        for seed in seeds {
            let w = if seed.weight > 0.0 { seed.weight } else { 1.0 };
            *personalization.entry(seed.node_id).or_insert(0.0) += w;
            seed_ids.insert(seed.node_id, ());
        }

        let scores = self.calculator.compute_personalized(graph, &personalization);
        if scores.is_empty() {
            return Vec::new();
        }

        let mut ranked: Vec<GraphRagResult> = scores
            .into_iter()
            .filter_map(|(node_id, score)| {
                let is_seed = seed_ids.contains_key(&node_id);
                if !self.include_seeds && is_seed {
                    return None;
                }
                Some(GraphRagResult {
                    node_id,
                    score,
                    is_seed,
                })
            })
            .collect();

        // Sort by score desc, then node id asc for deterministic tie-breaking.
        ranked.sort_by(|a, b| {
            b.score
                .partial_cmp(&a.score)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| a.node_id.cmp(&b.node_id))
        });

        ranked.truncate(self.top_k);
        ranked
    }
}

/// Convenience free function mirroring [`GraphRagLane::retrieve`] with default
/// lane parameters. Opt-in entry point for callers that just want the HippoRAG
/// pattern without constructing a [`GraphRagLane`].
pub fn personalized_pagerank_retrieve(
    graph: &GraphStructure,
    seeds: &[Seed],
    top_k: usize,
) -> Vec<GraphRagResult> {
    GraphRagLane::new(top_k).retrieve(graph, seeds)
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::tcr_qf::NodeInfo;
    use chrono::Utc;

    /// Build a graph from explicit nodes + directed edges for testing.
    fn build_graph(nodes: &[Uuid], edges: &[(Uuid, Uuid)]) -> GraphStructure {
        let mut g = GraphStructure::default();
        for id in nodes {
            g.nodes.insert(
                *id,
                NodeInfo {
                    id: *id,
                    created_at: Utc::now(),
                },
            );
        }
        for (from, to) in edges {
            g.edges.push((*from, *to));
        }
        g
    }

    /// A small two-cluster graph with a multi-hop bridge:
    ///
    /// Cluster A:  a0 <-> a1 <-> a2   (densely connected)
    /// Cluster B:  b0 <-> b1 <-> b2
    /// Bridge:     a2 -> b0          (single multi-hop link between clusters)
    ///
    /// Seeding on cluster A should rank cluster-A nodes (and the bridge target
    /// reachable via the multi-hop edge) above the far side of cluster B.
    fn two_cluster_graph() -> (GraphStructure, [Uuid; 6]) {
        let ids = [
            Uuid::from_u128(1),
            Uuid::from_u128(2),
            Uuid::from_u128(3),
            Uuid::from_u128(4),
            Uuid::from_u128(5),
            Uuid::from_u128(6),
        ];
        let [a0, a1, a2, b0, b1, b2] = ids;
        let edges = vec![
            // Cluster A (bidirectional)
            (a0, a1),
            (a1, a0),
            (a1, a2),
            (a2, a1),
            (a0, a2),
            (a2, a0),
            // Cluster B (bidirectional)
            (b0, b1),
            (b1, b0),
            (b1, b2),
            (b2, b1),
            (b0, b2),
            (b2, b0),
            // Bridge: A -> B (one direction, multi-hop)
            (a2, b0),
        ];
        (build_graph(&ids, &edges), ids)
    }

    #[test]
    fn ppr_biases_toward_seed_cluster_vs_uniform() {
        let (graph, ids) = two_cluster_graph();
        let [a0, _a1, _a2, _b0, _b1, b2] = ids;

        // Uniform PageRank: no bias toward any cluster.
        let calc = PageRankCalculator::default();
        let uniform = calc.compute(&graph);

        // Personalized PageRank seeded entirely on cluster A node a0.
        let lane = GraphRagLane {
            top_k: 6,
            include_seeds: true,
            ..GraphRagLane::default()
        };
        let results = lane.retrieve(&graph, &[Seed::uniform(a0)]);
        let ppr: HashMap<Uuid, f32> = results.iter().map(|r| (r.node_id, r.score)).collect();

        // The seed a0 must gain relative mass under PPR vs uniform.
        assert!(
            ppr[&a0] > uniform[&a0],
            "seed a0 should gain mass under PPR ({} vs uniform {})",
            ppr[&a0],
            uniform[&a0]
        );

        // The far side of the other cluster (b2) must lose mass under PPR.
        assert!(
            ppr[&b2] < uniform[&b2],
            "far cluster node b2 should lose mass under PPR ({} vs uniform {})",
            ppr[&b2],
            uniform[&b2]
        );

        // And the seed cluster should outrank the far cluster under PPR.
        assert!(
            ppr[&a0] > ppr[&b2],
            "seed cluster node a0 ({}) should outrank far node b2 ({}) under PPR",
            ppr[&a0],
            ppr[&b2]
        );
    }

    #[test]
    fn multi_hop_bridge_target_ranks_above_far_cluster() {
        // Known multi-hop structure: seeding cluster A, the bridge target b0
        // (one hop across the bridge) should rank above b2 (the far end of
        // cluster B), demonstrating multi-hop reachability.
        let (graph, ids) = two_cluster_graph();
        let [a0, a1, a2, b0, _b1, b2] = ids;

        let results = personalized_pagerank_retrieve(
            &graph,
            &[Seed::uniform(a0), Seed::uniform(a1), Seed::uniform(a2)],
            6,
        );
        let ppr: HashMap<Uuid, f32> = results.iter().map(|r| (r.node_id, r.score)).collect();

        assert!(
            ppr[&b0] > ppr[&b2],
            "bridge target b0 ({}) should outrank far node b2 ({})",
            ppr[&b0],
            ppr[&b2]
        );

        // Top result should be a cluster-A node (the seeded region).
        let cluster_a = [a0, a1, a2];
        assert!(
            cluster_a.contains(&results[0].node_id),
            "top PPR result {} should be in the seeded cluster A",
            results[0].node_id
        );
    }

    #[test]
    fn weighted_seeds_concentrate_mass() {
        // Two equal-size disjoint clusters, no bridge. Weighting one cluster's
        // seed more heavily should make it rank higher than an equally-seeded
        // node in the other cluster.
        let ids = [
            Uuid::from_u128(10),
            Uuid::from_u128(11),
            Uuid::from_u128(20),
            Uuid::from_u128(21),
        ];
        let [x0, x1, y0, y1] = ids;
        let edges = vec![(x0, x1), (x1, x0), (y0, y1), (y1, y0)];
        let graph = build_graph(&ids, &edges);

        let results =
            personalized_pagerank_retrieve(&graph, &[Seed::new(x0, 9.0), Seed::new(y0, 1.0)], 4);
        let ppr: HashMap<Uuid, f32> = results.iter().map(|r| (r.node_id, r.score)).collect();

        assert!(
            ppr[&x0] > ppr[&y0],
            "heavily-weighted seed x0 ({}) should outrank lightly-weighted seed y0 ({})",
            ppr[&x0],
            ppr[&y0]
        );
    }

    #[test]
    fn include_seeds_flag_excludes_seeds() {
        let (graph, ids) = two_cluster_graph();
        let [a0, _a1, _a2, _b0, _b1, _b2] = ids;

        let lane = GraphRagLane {
            top_k: 6,
            include_seeds: false,
            ..GraphRagLane::default()
        };
        let results = lane.retrieve(&graph, &[Seed::uniform(a0)]);

        assert!(
            results.iter().all(|r| r.node_id != a0),
            "seed a0 must be excluded when include_seeds = false"
        );
        assert!(
            results.iter().all(|r| !r.is_seed),
            "no result should be flagged as a seed when include_seeds = false"
        );
    }

    #[test]
    fn empty_inputs_return_empty() {
        let (graph, ids) = two_cluster_graph();
        let empty = GraphStructure::default();

        assert!(personalized_pagerank_retrieve(&empty, &[Seed::uniform(ids[0])], 5).is_empty());
        assert!(personalized_pagerank_retrieve(&graph, &[], 5).is_empty());
    }

    #[test]
    fn ppr_with_empty_personalization_matches_uniform() {
        // Guard: compute_personalized with empty vector == uniform compute().
        let (graph, _ids) = two_cluster_graph();
        let calc = PageRankCalculator::default();
        let uniform = calc.compute(&graph);
        let via_personalized = calc.compute_personalized(&graph, &HashMap::new());

        for (id, score) in &uniform {
            let other = via_personalized[id];
            assert!(
                (score - other).abs() < 1e-6,
                "uniform vs empty-personalization mismatch for {id}: {score} vs {other}"
            );
        }
    }
}
