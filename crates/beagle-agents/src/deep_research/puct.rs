use super::hypothesis::HypothesisTree;
use uuid::Uuid;

/// PUCT (Polynomial Upper Confidence Trees) selector
/// Balances exploitation vs exploration
pub struct PUCTSelector {
    /// Exploration constant (typically √2)
    pub c_puct: f64,
}

impl PUCTSelector {
    pub fn new(c_puct: f64) -> Self {
        Self { c_puct }
    }

    /// Select best child using PUCT formula:
    /// PUCT = Q(s,a) + c * P(s,a) * sqrt(N(s)) / (1 + N(s,a))
    pub fn select_child(&self, tree: &HypothesisTree, parent_id: Uuid) -> Option<Uuid> {
        let parent = tree.nodes.get(&parent_id)?;

        if parent.children.is_empty() {
            return None;
        }

        let parent_visits = parent.hypothesis.n_visits as f64;

        let mut best_child = None;
        let mut best_score = f64::NEG_INFINITY;

        for &child_id in &parent.children {
            let child = tree.nodes.get(&child_id)?;
            let child_hyp = &child.hypothesis;

            // Q value (exploitation)
            let q = child_hyp.q_value;

            // Prior probability from LLM
            let p = child_hyp.prior;

            // Visit counts
            let n = child_hyp.n_visits as f64;

            // PUCT formula
            let exploration = self.c_puct * p * parent_visits.sqrt() / (1.0 + n);
            let puct_score = q + exploration;

            if puct_score > best_score {
                best_score = puct_score;
                best_child = Some(child_id);
            }
        }

        best_child
    }

    /// Calculate upper confidence bound
    pub fn ucb_score(&self, q: f64, prior: f64, parent_n: u32, child_n: u32) -> f64 {
        let exploration = self.c_puct * prior * (parent_n as f64).sqrt() / (1.0 + child_n as f64);

        q + exploration
    }
}


