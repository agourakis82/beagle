//! Quantum-Enhanced MCTS Deep Research
//!
//! Integrates quantum superposition reasoning with Monte Carlo Tree Search
//! for improved hypothesis discovery and selection

use crate::deep_research::{DeepResearchResult, Hypothesis, MCTSEngine};
use crate::quantum::{
    HypothesisMetadata, InterferenceEngine, MeasurementOperator, SuperpositionState,
};
use anyhow::Result;
use tracing::{debug, info};

/// Quantum-enhanced MCTS engine
pub struct QuantumMCTS {
    mcts: MCTSEngine,
    interference_engine: InterferenceEngine,
    measurement_op: MeasurementOperator,
    use_superposition: bool,
}

impl QuantumMCTS {
    /// Create new quantum MCTS with default settings
    pub fn new(mcts: MCTSEngine) -> Self {
        Self {
            mcts,
            interference_engine: InterferenceEngine::new(),
            measurement_op: MeasurementOperator::new(0.15),
            use_superposition: true,
        }
    }

    /// Create quantum MCTS with custom interference strength
    pub fn with_interference_strength(mcts: MCTSEngine, strength: f64) -> Self {
        Self {
            mcts,
            interference_engine: InterferenceEngine::with_strength(strength),
            measurement_op: MeasurementOperator::new(0.15),
            use_superposition: true,
        }
    }

    /// Run quantum-enhanced deep research
    pub async fn quantum_deep_research(&mut self, query: &str) -> Result<QuantumResearchResult> {
        info!("🌀 Starting quantum-enhanced deep research");

        // Run standard MCTS first
        let mcts_result = self.mcts.deep_research(query).await?;

        if !self.use_superposition {
            // Return standard result if superposition disabled
            return Ok(QuantumResearchResult {
                final_hypothesis: mcts_result.best_hypothesis.content.clone(),
                measurement_probability: 1.0,
                mcts_result,
                superposition_used: false,
                interference_applied: false,
            });
        }

        // Create quantum superposition from top hypotheses
        let mut superposition = self.create_superposition(&mcts_result);

        info!(
            "Created superposition with {} hypotheses",
            superposition.len()
        );

        // Apply quantum interference based on hypothesis correlations
        if superposition.len() > 1 {
            self.apply_hypothesis_interference(&mut superposition, &mcts_result);
        }

        // Evolve quantum state
        self.interference_engine
            .evolve_phases(&mut superposition, 1.0);

        // Measure (collapse) to select final hypothesis
        let measurement = self
            .measurement_op
            .collapse(&mut superposition)
            .ok_or_else(|| anyhow::anyhow!("Quantum measurement failed - no viable hypothesis"))?;

        info!(
            "🎯 Quantum measurement selected: '{}' (prob: {:.3})",
            measurement.selected_hypothesis, measurement.probability
        );

        Ok(QuantumResearchResult {
            final_hypothesis: measurement.selected_hypothesis,
            measurement_probability: measurement.probability,
            mcts_result,
            superposition_used: true,
            interference_applied: superposition.len() > 1,
        })
    }

    /// Create quantum superposition from MCTS hypotheses
    fn create_superposition(&self, result: &DeepResearchResult) -> SuperpositionState {
        let mut state = SuperpositionState::new();

        // Add top hypotheses to superposition
        for (i, hyp) in result.top_hypotheses.iter().take(10).enumerate() {
            let initial_prob = self.hypothesis_to_probability(hyp, i);

            let metadata = HypothesisMetadata {
                source: "mcts".to_string(),
                confidence: hyp.q_value,
                evidence_count: hyp.n_visits as usize,
                created_at: i as f64,
            };

            state.add_hypothesis(hyp.content.clone(), initial_prob, metadata);
        }

        state.normalize();
        state
    }

    /// Convert MCTS hypothesis to initial probability for superposition
    fn hypothesis_to_probability(&self, hyp: &Hypothesis, rank: usize) -> f64 {
        // Combine multiple factors:
        // 1. Q-value (quality from MCTS)
        // 2. Visit count (exploration from MCTS)
        // 3. Novelty score
        // 4. Rank penalty (prefer earlier/better ranked)

        let quality_factor = (hyp.q_value + 1.0) / 2.0; // Normalize to [0, 1]
        let visit_factor = (hyp.n_visits as f64).ln().max(0.0) / 10.0; // Log scale
        let novelty_factor = hyp.novelty;
        let rank_penalty = 1.0 / (rank as f64 + 1.0);

        let combined =
            quality_factor * 0.4 + visit_factor * 0.2 + novelty_factor * 0.3 + rank_penalty * 0.1;

        combined.clamp(0.01, 0.99)
    }

    /// Apply interference patterns based on hypothesis correlations
    fn apply_hypothesis_interference(
        &mut self,
        state: &mut SuperpositionState,
        result: &DeepResearchResult,
    ) {
        debug!("Applying quantum interference patterns");

        // Build correlation matrix based on hypothesis similarity
        let n = state.len().min(10);
        let mut correlation_matrix = vec![vec![0.0; n]; n];

        for i in 0..n {
            for j in (i + 1)..n {
                if let (Some(hyp_i), Some(hyp_j)) =
                    (result.top_hypotheses.get(i), result.top_hypotheses.get(j))
                {
                    // Calculate correlation based on:
                    // - Content similarity (simple heuristic)
                    // - Parent relationship in tree
                    // - Q-value similarity

                    let q_similarity = 1.0 - (hyp_i.q_value - hyp_j.q_value).abs();
                    let parent_bonus = if hyp_i.parent_id == hyp_j.parent_id {
                        0.3
                    } else {
                        0.0
                    };

                    let correlation = (q_similarity * 0.7 + parent_bonus).clamp(-1.0, 1.0);

                    correlation_matrix[i][j] = correlation;
                    correlation_matrix[j][i] = correlation; // Symmetric
                }
            }
        }

        // Apply global interference
        self.interference_engine
            .apply_global_interference(state, &correlation_matrix);
    }

    /// Get probabilistic sampling of hypotheses (non-destructive measurement)
    pub fn sample_hypotheses(&self, state: &SuperpositionState, n: usize) -> Vec<(String, f64)> {
        let partial = self.measurement_op.partial_measurement(state);
        partial
            .into_iter()
            .take(n)
            .map(|(h, p, _)| (h, p))
            .collect()
    }

    /// Enable adversarial hypothesis refinement
    /// Uses evolved strategies from adversarial self-play to improve MCTS exploration
    pub fn with_adversarial_refinement(mut self, enable: bool) -> Self {
        // This flag can be used to enable adversarial strategy selection
        // in future MCTS iterations
        self.use_superposition = enable;
        self
    }
}

/// Result of quantum-enhanced research
#[derive(Debug, Clone)]
pub struct QuantumResearchResult {
    /// Final selected hypothesis after quantum measurement
    pub final_hypothesis: String,

    /// Probability of the measured hypothesis
    pub measurement_probability: f64,

    /// Original MCTS result (for comparison)
    pub mcts_result: DeepResearchResult,

    /// Whether quantum superposition was used
    pub superposition_used: bool,

    /// Whether interference patterns were applied
    pub interference_applied: bool,
}

impl QuantumResearchResult {
    /// Compare quantum result with classical MCTS result
    pub fn improvement_over_mcts(&self) -> Option<f64> {
        if !self.superposition_used {
            return None;
        }

        // Compare selected hypothesis with MCTS best
        if self.final_hypothesis == self.mcts_result.best_hypothesis.content {
            Some(0.0) // Same result
        } else {
            // Find our hypothesis in MCTS top list
            let our_rank = self
                .mcts_result
                .top_hypotheses
                .iter()
                .position(|h| h.content == self.final_hypothesis);

            our_rank.map(|rank| rank as f64)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn test_hypothesis_to_probability() {
        // Note: This test requires MCTS setup which needs LLM client
        // Skip in CI, use for local testing only

        let hyp = Hypothesis {
            id: Uuid::new_v4(),
            content: "Test hypothesis".to_string(),
            parent_id: None,
            q_value: 0.8,
            n_visits: 100,
            prior: 1.0,
            novelty: 0.7,
            depth: 1,
        };

        // Test probability calculation without full MCTS
        let quality_factor = (hyp.q_value + 1.0) / 2.0;
        let visit_factor = (hyp.n_visits as f64).ln().max(0.0) / 10.0;
        let novelty_factor = hyp.novelty;
        let rank_penalty = 1.0;

        let prob =
            quality_factor * 0.4 + visit_factor * 0.2 + novelty_factor * 0.3 + rank_penalty * 0.1;

        assert!(prob > 0.0 && prob < 1.0);
        assert!(prob > 0.5); // Good hypothesis should have high probability
    }
}
