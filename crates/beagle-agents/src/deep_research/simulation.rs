use super::{
    corpus::NoveltyScorer,
    hypothesis::Hypothesis,
};
use crate::{
    CausalGraph, CausalReasoner, DebateOrchestrator, DebateTranscript, HypergraphReasoner,
};
use anyhow::Result;
use std::collections::HashSet;
use std::sync::Arc;
use tracing::info;

/// Simulates hypothesis validation using all available tools
pub struct SimulationEngine {
    debate: Arc<DebateOrchestrator>,
    reasoning: Arc<HypergraphReasoner>,
    causal: Arc<CausalReasoner>,
    novelty_scorer: Option<Arc<NoveltyScorer>>,
}

impl SimulationEngine {
    pub fn new(
        debate: Arc<DebateOrchestrator>,
        reasoning: Arc<HypergraphReasoner>,
        causal: Arc<CausalReasoner>,
    ) -> Self {
        Self {
            debate,
            reasoning,
            causal,
            novelty_scorer: None,
        }
    }

    /// Create with novelty scorer for real corpus-based novelty detection
    pub fn with_novelty_scorer(
        debate: Arc<DebateOrchestrator>,
        reasoning: Arc<HypergraphReasoner>,
        causal: Arc<CausalReasoner>,
        novelty_scorer: Arc<NoveltyScorer>,
    ) -> Self {
        Self {
            debate,
            reasoning,
            causal,
            novelty_scorer: Some(novelty_scorer),
        }
    }

    /// Simulate hypothesis through multiple validation methods
    pub async fn simulate(&self, hypothesis: &Hypothesis) -> Result<SimulationResult> {
        let preview_len = hypothesis.content.len().min(50);
        info!(
            "🧪 Simulating hypothesis: {}",
            &hypothesis.content[..preview_len]
        );

        // 1. Adversarial debate to test robustness
        let debate_result = self.debate.conduct_debate(&hypothesis.content).await?;

        // 2. Causal analysis to check mechanisms
        let causal_graph = self
            .causal
            .extract_causal_graph(&hypothesis.content)
            .await?;

        // 3. Reasoning path to find support/contradiction
        // (simplified - placeholder for future reasoning integration)
        let _ = Arc::clone(&self.reasoning);

        // Aggregate scores
        let debate_strength = debate_result.synthesis.final_confidence;
        let causal_strength = self.evaluate_causal_graph(&causal_graph);

        // Combined quality score
        let quality = (debate_strength as f64 * 0.5) + (causal_strength * 0.5);

        // Novelty: use corpus-based scorer if available, otherwise fallback to heuristic
        let novelty = if let Some(ref scorer) = self.novelty_scorer {
            scorer.score_novelty(&hypothesis.content).await.unwrap_or_else(|e| {
                info!("⚠️  Novelty scoring failed: {}, using heuristic", e);
                self.calculate_novelty_heuristic(&hypothesis.content)
            })
        } else {
            self.calculate_novelty_heuristic(&hypothesis.content)
        };

        // Plausibility: logical consistency
        let plausibility = self.check_plausibility(&causal_graph);

        Ok(SimulationResult {
            quality,
            novelty,
            plausibility,
            debate_transcript: debate_result,
            causal_graph,
            evidence_strength: quality,
        })
    }

    fn evaluate_causal_graph(&self, graph: &CausalGraph) -> f64 {
        if graph.edges.is_empty() {
            return 0.3;
        }

        // Strong causal graph = many edges with high strength
        let avg_strength: f64 =
            graph.edges.iter().map(|e| e.strength as f64).sum::<f64>() / graph.edges.len() as f64;

        let complexity_bonus = (graph.edges.len() as f64 / 10.0).min(0.3);

        (avg_strength + complexity_bonus).min(1.0)
    }

    /// Heuristic novelty calculation (fallback when corpus not available)
    fn calculate_novelty_heuristic(&self, content: &str) -> f64 {
        // Heuristic based on concept combinations
        let unique_concepts = content
            .split_whitespace()
            .filter(|w| w.len() > 5)
            .collect::<HashSet<_>>()
            .len();

        (unique_concepts as f64 / 20.0).min(1.0)
    }

    fn check_plausibility(&self, graph: &CausalGraph) -> f64 {
        // Check for logical contradictions
        // (simplified - would need more sophisticated analysis)

        if graph.nodes.is_empty() {
            return 0.5;
        }

        // No obvious contradictions = high plausibility
        0.8
    }
}

#[derive(Debug, Clone)]
pub struct SimulationResult {
    pub quality: f64,
    pub novelty: f64,
    pub plausibility: f64,
    pub debate_transcript: DebateTranscript,
    pub causal_graph: CausalGraph,
    pub evidence_strength: f64,
}
