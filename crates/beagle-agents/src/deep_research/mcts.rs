use super::{
    hypothesis::{Hypothesis, HypothesisTree},
    puct::PUCTSelector,
    simulation::{SimulationEngine, SimulationResult},
};
use anyhow::Result;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use serde_json;
use std::sync::Arc;
use tracing::info;
use uuid::Uuid;

/// Monte Carlo Tree Search engine for hypothesis discovery
pub struct MCTSEngine {
    llm: Arc<AnthropicClient>,
    simulator: Arc<SimulationEngine>,
    puct: PUCTSelector,

    /// Number of MCTS iterations
    iterations: usize,

    /// Max tree depth
    max_depth: usize,
}

impl MCTSEngine {
    pub fn new(
        llm: Arc<AnthropicClient>,
        simulator: Arc<SimulationEngine>,
        iterations: usize,
    ) -> Self {
        Self {
            llm,
            simulator,
            puct: PUCTSelector::new(std::f64::consts::SQRT_2),
            iterations,
            max_depth: 5,
        }
    }

    /// Run deep research to discover novel hypotheses
    pub async fn deep_research(&self, query: &str) -> Result<DeepResearchResult> {
        info!(
            "🔬 Starting deep research with {} iterations",
            self.iterations
        );

        // Initialize tree with root hypothesis
        let root = self.create_root_hypothesis(query).await?;
        let mut tree = HypothesisTree::new(root);

        // MCTS iterations
        for i in 0..self.iterations {
            info!("MCTS iteration {}/{}", i + 1, self.iterations);

            // 1. SELECT: traverse tree using PUCT
            let selected = self.select(&tree);

            // 2. EXPAND: generate new hypotheses
            let new_hypotheses = self.expand(&tree, selected).await?;

            // 3. SIMULATE: evaluate new hypotheses
            for hyp in new_hypotheses {
                let sim_result = self.simulator.simulate(&hyp).await?;

                // 4. BACKPROPAGATE: update values
                let hyp_id = tree.add_child(selected, hyp.clone());
                self.backpropagate(&mut tree, hyp_id, &sim_result);
            }
        }

        // Extract best hypotheses
        let best = tree
            .best_hypothesis()
            .ok_or_else(|| anyhow::anyhow!("No hypothesis found"))?
            .clone();

        let top_10 = self.get_top_k_hypotheses(&tree, 10);

        info!(
            "✅ Deep research complete. Best novelty: {:.2}, quality: {:.2}",
            best.novelty, best.q_value
        );

        Ok(DeepResearchResult {
            best_hypothesis: best,
            top_hypotheses: top_10,
            tree_size: tree.nodes.len(),
            iterations: self.iterations,
        })
    }

    async fn create_root_hypothesis(&self, query: &str) -> Result<Hypothesis> {
        Ok(Hypothesis {
            id: Uuid::new_v4(),
            content: format!("Root: {}", query),
            parent_id: None,
            q_value: 0.5,
            n_visits: 0,
            prior: 1.0,
            evidence: vec![],
            novelty: 0.5,
            plausibility: 0.5,
            testability: 0.5,
        })
    }

    fn select(&self, tree: &HypothesisTree) -> Uuid {
        let mut current = tree.root;

        for _ in 0..self.max_depth {
            if let Some(child) = self.puct.select_child(tree, current) {
                current = child;
            } else {
                break;
            }
        }

        current
    }

    async fn expand(&self, tree: &HypothesisTree, node_id: Uuid) -> Result<Vec<Hypothesis>> {
        let node = tree
            .nodes
            .get(&node_id)
            .ok_or_else(|| anyhow::anyhow!("Node not found"))?;

        let parent_content = &node.hypothesis.content;

        // Generate 3 new hypotheses branching from this one
        let prompt = format!(
            "Given this scientific hypothesis:\n\"{}\"\n\n\
             Generate 3 NOVEL hypotheses that:\n\
             1. Extend or refine this hypothesis\n\
             2. Are testable and plausible\n\
             3. Have not been extensively studied\n\
             4. Could lead to new discoveries\n\n\
             Format as JSON array of strings:\n\
             [\"hypothesis 1\", \"hypothesis 2\", \"hypothesis 3\"]",
            parent_content
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet4,
            messages: vec![Message::user(prompt)],
            max_tokens: 1000,
            temperature: 0.9, // High temp for creativity
            system: Some(
                "You are a creative scientific researcher generating novel hypotheses.".to_string(),
            ),
        };

        let response = self.llm.complete(request).await?;

        // Parse JSON
        let content = response.content.trim();
        let hypotheses_text: Vec<String> = serde_json::from_str(content).unwrap_or_else(|_| {
            vec![
                format!("Extension 1 of {}", parent_content),
                format!("Extension 2 of {}", parent_content),
                format!("Extension 3 of {}", parent_content),
            ]
        });

        let hypotheses = hypotheses_text
            .into_iter()
            .map(|text| Hypothesis {
                id: Uuid::new_v4(),
                content: text,
                parent_id: Some(node_id),
                q_value: 0.5,
                n_visits: 0,
                prior: 1.0 / 3.0,
                evidence: vec![],
                novelty: 0.5,
                plausibility: 0.5,
                testability: 0.5,
            })
            .collect();

        Ok(hypotheses)
    }

    fn backpropagate(&self, tree: &mut HypothesisTree, node_id: Uuid, result: &SimulationResult) {
        if let Some(node) = tree.nodes.get_mut(&node_id) {
            node.hypothesis.n_visits += 1;

            // Update Q value with simulation result
            let n = node.hypothesis.n_visits as f64;
            let old_q = node.hypothesis.q_value;
            let new_sample = result.quality;

            // Running average
            node.hypothesis.q_value = old_q + (new_sample - old_q) / n;

            // Update other metrics
            node.hypothesis.novelty = result.novelty;
            node.hypothesis.plausibility = result.plausibility;

            // Backpropagate to parent
            if let Some(parent_id) = node.hypothesis.parent_id {
                self.backpropagate(tree, parent_id, result);
            }
        }
    }

    fn get_top_k_hypotheses(&self, tree: &HypothesisTree, k: usize) -> Vec<Hypothesis> {
        let mut all_hyp: Vec<_> = tree
            .nodes
            .values()
            .map(|node| node.hypothesis.clone())
            .collect();

        all_hyp.sort_by(|a, b| {
            let score_a = a.q_value * a.novelty * a.plausibility;
            let score_b = b.q_value * b.novelty * b.plausibility;
            score_b.partial_cmp(&score_a).unwrap()
        });

        all_hyp.into_iter().take(k).collect()
    }
}

#[derive(Debug, Clone)]
pub struct DeepResearchResult {
    pub best_hypothesis: Hypothesis,
    pub top_hypotheses: Vec<Hypothesis>,
    pub tree_size: usize,
    pub iterations: usize,
}


