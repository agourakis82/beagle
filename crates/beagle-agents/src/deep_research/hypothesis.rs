use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

/// Hypothesis in the search tree
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hypothesis {
    pub id: Uuid,
    pub content: String,
    pub parent_id: Option<Uuid>,

    /// Quality score (0.0 - 1.0)
    pub q_value: f64,

    /// Visit count
    pub n_visits: u32,

    /// Prior probability from LLM
    pub prior: f64,

    /// Evidence supporting this hypothesis
    pub evidence: Vec<Evidence>,

    /// Novelty score (how different from known literature)
    pub novelty: f64,

    /// Plausibility (logical consistency)
    pub plausibility: f64,

    /// Testability (can we validate this?)
    pub testability: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Evidence {
    pub source: String,
    pub strength: f64,
    pub confidence: f64,
}

/// Node in MCTS tree
#[derive(Debug, Clone)]
pub struct HypothesisNode {
    pub hypothesis: Hypothesis,
    pub children: Vec<Uuid>,
    pub is_terminal: bool,
    pub value: f64,
}

/// Complete hypothesis tree
pub struct HypothesisTree {
    pub root: Uuid,
    pub nodes: HashMap<Uuid, HypothesisNode>,
}

impl HypothesisTree {
    pub fn new(root_hypothesis: Hypothesis) -> Self {
        let root_id = root_hypothesis.id;
        let root_node = HypothesisNode {
            hypothesis: root_hypothesis,
            children: vec![],
            is_terminal: false,
            value: 0.0,
        };

        let mut nodes = HashMap::new();
        nodes.insert(root_id, root_node);

        Self {
            root: root_id,
            nodes,
        }
    }

    pub fn add_child(&mut self, parent_id: Uuid, child: Hypothesis) -> Uuid {
        let child_id = child.id;
        let child_node = HypothesisNode {
            hypothesis: child,
            children: vec![],
            is_terminal: false,
            value: 0.0,
        };

        self.nodes.insert(child_id, child_node);

        if let Some(parent) = self.nodes.get_mut(&parent_id) {
            parent.children.push(child_id);
        }

        child_id
    }

    pub fn best_hypothesis(&self) -> Option<&Hypothesis> {
        self.nodes
            .values()
            .max_by(|a, b| {
                let score_a = a.hypothesis.q_value * a.hypothesis.novelty;
                let score_b = b.hypothesis.q_value * b.hypothesis.novelty;
                score_a.partial_cmp(&score_b).unwrap()
            })
            .map(|node| &node.hypothesis)
    }
}


