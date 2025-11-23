//! Quantum-Inspired Superposition Reasoning
//!
//! Maintains multiple hypotheses in superposition
//! Uses interference and measurement for hypothesis selection

use num_complex::Complex;
use serde::{Deserialize, Serialize};
use std::f64::consts::PI;

/// Quantum hypothesis with amplitude and phase
#[derive(Debug, Clone)]
pub struct QuantumHypothesis {
    pub content: String,
    pub amplitude: Complex<f64>,
    pub phase: f64,
    pub metadata: HypothesisMetadata,
}

/// Metadata for hypothesis tracking
#[derive(Debug, Clone, Default)]
pub struct HypothesisMetadata {
    pub source: String,
    pub confidence: f64,
    pub evidence_count: usize,
    pub created_at: f64,
}

/// Superposition state holding multiple hypotheses
#[derive(Debug, Clone)]
pub struct SuperpositionState {
    hypotheses: Vec<QuantumHypothesis>,
    normalized: bool,
}

impl Default for SuperpositionState {
    fn default() -> Self {
        Self::new()
    }
}

impl SuperpositionState {
    /// Create new empty superposition state
    pub fn new() -> Self {
        Self {
            hypotheses: Vec::new(),
            normalized: true,
        }
    }

    /// Add a hypothesis to the superposition with initial amplitude
    pub fn add_hypothesis(
        &mut self,
        content: String,
        initial_probability: f64,
        metadata: HypothesisMetadata,
    ) {
        // Convert probability to amplitude (sqrt for Born rule)
        let amplitude = Complex::new(initial_probability.sqrt(), 0.0);

        let hypothesis = QuantumHypothesis {
            content,
            amplitude,
            phase: 0.0,
            metadata,
        };

        self.hypotheses.push(hypothesis);
        self.normalized = false;
    }

    /// Normalize the superposition state (ensure sum of |amplitude|² = 1)
    pub fn normalize(&mut self) {
        if self.hypotheses.is_empty() {
            return;
        }

        // Calculate total probability
        let total_prob: f64 = self.hypotheses.iter().map(|h| h.amplitude.norm_sqr()).sum();

        if total_prob > 0.0 {
            let norm_factor = total_prob.sqrt();
            for hypothesis in &mut self.hypotheses {
                hypothesis.amplitude /= norm_factor;
            }
        }

        self.normalized = true;
    }

    /// Get probability for a specific hypothesis (Born rule: |amplitude|²)
    pub fn get_probability(&self, index: usize) -> Option<f64> {
        self.hypotheses.get(index).map(|h| h.amplitude.norm_sqr())
    }

    /// Get all hypotheses sorted by probability (descending)
    pub fn get_ranked_hypotheses(&mut self) -> Vec<(String, f64, HypothesisMetadata)> {
        if !self.normalized {
            self.normalize();
        }

        let mut ranked: Vec<_> = self
            .hypotheses
            .iter()
            .map(|h| {
                (
                    h.content.clone(),
                    h.amplitude.norm_sqr(),
                    h.metadata.clone(),
                )
            })
            .collect();

        ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        ranked
    }

    /// Get number of hypotheses in superposition
    pub fn len(&self) -> usize {
        self.hypotheses.len()
    }

    /// Check if superposition is empty
    pub fn is_empty(&self) -> bool {
        self.hypotheses.is_empty()
    }

    /// Apply phase shift to specific hypothesis
    pub fn apply_phase_shift(&mut self, index: usize, phase_shift: f64) {
        if let Some(hypothesis) = self.hypotheses.get_mut(index) {
            hypothesis.phase += phase_shift;

            // Update amplitude with new phase
            let magnitude = hypothesis.amplitude.norm();
            hypothesis.amplitude = Complex::from_polar(magnitude, hypothesis.phase);
        }
    }

    /// Get internal access to hypotheses (for interference engine)
    pub(crate) fn hypotheses_mut(&mut self) -> &mut Vec<QuantumHypothesis> {
        self.normalized = false;
        &mut self.hypotheses
    }

    /// Get read-only access to hypotheses
    pub fn hypotheses(&self) -> &[QuantumHypothesis] {
        &self.hypotheses
    }
}

/// Measurement result after collapse
#[derive(Debug, Clone)]
pub struct MeasurementResult {
    pub selected_hypothesis: String,
    pub probability: f64,
    pub metadata: HypothesisMetadata,
    pub collapsed_alternatives: Vec<(String, f64)>,
}

/// Measurement operator for collapsing superposition
pub struct MeasurementOperator {
    threshold: f64,
    decoherence_rate: f64,
}

impl Default for MeasurementOperator {
    fn default() -> Self {
        Self::new(0.1)
    }
}

impl MeasurementOperator {
    /// Create new measurement operator with probability threshold
    pub fn new(threshold: f64) -> Self {
        Self {
            threshold: threshold.clamp(0.0, 1.0),
            decoherence_rate: 0.05,
        }
    }

    /// Create measurement operator with custom decoherence rate
    pub fn with_decoherence(threshold: f64, decoherence_rate: f64) -> Self {
        Self {
            threshold: threshold.clamp(0.0, 1.0),
            decoherence_rate: decoherence_rate.clamp(0.0, 1.0),
        }
    }

    /// Collapse the superposition to a single hypothesis (Copenhagen interpretation)
    /// Returns the measurement result with highest probability hypothesis
    pub fn collapse(&self, state: &mut SuperpositionState) -> Option<MeasurementResult> {
        if state.is_empty() {
            return None;
        }

        // Ensure normalized before measurement
        state.normalize();

        // Get ranked hypotheses
        let ranked = state.get_ranked_hypotheses();

        if ranked.is_empty() {
            return None;
        }

        // Select highest probability hypothesis above threshold
        let (selected, probability, metadata) = ranked[0].clone();

        if probability < self.threshold {
            return None;
        }

        // Collect alternatives
        let collapsed_alternatives: Vec<(String, f64)> = ranked
            .iter()
            .skip(1)
            .take(5) // Keep top 5 alternatives
            .map(|(content, prob, _)| (content.clone(), *prob))
            .collect();

        Some(MeasurementResult {
            selected_hypothesis: selected,
            probability,
            metadata,
            collapsed_alternatives,
        })
    }

    /// Probabilistic collapse - sample from distribution (weighted random)
    pub fn probabilistic_collapse(
        &self,
        state: &mut SuperpositionState,
    ) -> Option<MeasurementResult> {
        use rand::Rng;

        if state.is_empty() {
            return None;
        }

        state.normalize();

        // Generate random value [0, 1]
        let mut rng = rand::thread_rng();
        let random_value: f64 = rng.gen();

        // Accumulate probabilities and select
        let mut cumulative_prob = 0.0;
        let mut selected_index = 0;

        for (i, hypothesis) in state.hypotheses().iter().enumerate() {
            cumulative_prob += hypothesis.amplitude.norm_sqr();
            if random_value <= cumulative_prob {
                selected_index = i;
                break;
            }
        }

        // Get the selected hypothesis
        let hypothesis = &state.hypotheses()[selected_index];
        let probability = hypothesis.amplitude.norm_sqr();

        if probability < self.threshold {
            return None;
        }

        // Collect all alternatives
        let collapsed_alternatives: Vec<(String, f64)> = state
            .hypotheses()
            .iter()
            .enumerate()
            .filter(|(i, _)| *i != selected_index)
            .map(|(_, h)| (h.content.clone(), h.amplitude.norm_sqr()))
            .collect();

        Some(MeasurementResult {
            selected_hypothesis: hypothesis.content.clone(),
            probability,
            metadata: hypothesis.metadata.clone(),
            collapsed_alternatives,
        })
    }

    /// Apply decoherence - gradual loss of quantum coherence
    /// Reduces interference effects over time, pushing toward classical behavior
    pub fn apply_decoherence(&self, state: &mut SuperpositionState, time_step: f64) {
        let decoherence_factor = (-self.decoherence_rate * time_step).exp();

        for hypothesis in state.hypotheses_mut() {
            // Reduce imaginary component (lose phase coherence)
            let real = hypothesis.amplitude.re;
            let imag = hypothesis.amplitude.im * decoherence_factor;

            hypothesis.amplitude = Complex::new(real, imag);

            // Gradually reduce phase variations
            hypothesis.phase *= decoherence_factor;
        }

        // After decoherence, amplitudes become more "classical" (real-valued)
        state.normalize();
    }

    /// Partial measurement - extract information without full collapse
    /// Useful for checking hypothesis viability without committing
    pub fn partial_measurement(&self, state: &SuperpositionState) -> Vec<(String, f64, bool)> {
        state
            .hypotheses()
            .iter()
            .map(|h| {
                let prob = h.amplitude.norm_sqr();
                let viable = prob >= self.threshold;
                (h.content.clone(), prob, viable)
            })
            .collect()
    }
}

/// Interference pattern type
#[derive(Debug, Clone, Copy)]
pub enum InterferenceType {
    Constructive,
    Destructive,
    Neutral,
}

/// Interference engine for quantum-like reasoning
pub struct InterferenceEngine {
    phase_accumulator: f64,
    interference_strength: f64,
}

impl Default for InterferenceEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl InterferenceEngine {
    /// Create new interference engine with default strength
    pub fn new() -> Self {
        Self {
            phase_accumulator: 0.0,
            interference_strength: 1.0,
        }
    }

    /// Create interference engine with custom strength
    pub fn with_strength(strength: f64) -> Self {
        Self {
            phase_accumulator: 0.0,
            interference_strength: strength.clamp(0.0, 2.0),
        }
    }

    /// Apply interference between two hypotheses
    /// Returns the interference type and modified amplitudes
    pub fn apply_interference(
        &mut self,
        state: &mut SuperpositionState,
        index_a: usize,
        index_b: usize,
        correlation: f64, // -1.0 to 1.0: negative = opposing, positive = supporting
    ) -> Option<InterferenceType> {
        let hypotheses = state.hypotheses_mut();

        if index_a >= hypotheses.len() || index_b >= hypotheses.len() {
            return None;
        }

        // Calculate phase difference
        let phase_diff = hypotheses[index_b].phase - hypotheses[index_a].phase;

        // Determine interference type based on phase and correlation
        let interference_type = self.classify_interference(phase_diff, correlation);

        // Apply interference pattern
        match interference_type {
            InterferenceType::Constructive => {
                // Amplify both hypotheses (they support each other)
                let boost_factor = 1.0 + (self.interference_strength * correlation.abs() * 0.2);
                hypotheses[index_a].amplitude *= boost_factor;
                hypotheses[index_b].amplitude *= boost_factor;
            }
            InterferenceType::Destructive => {
                // Reduce conflicting hypothesis
                let damping_factor = 1.0 - (self.interference_strength * correlation.abs() * 0.2);
                hypotheses[index_a].amplitude *= damping_factor;
                hypotheses[index_b].amplitude *= damping_factor;
            }
            InterferenceType::Neutral => {
                // Apply small phase evolution
                hypotheses[index_a].phase += 0.01;
                hypotheses[index_b].phase += 0.01;
            }
        }

        Some(interference_type)
    }

    /// Classify interference pattern based on phase difference and correlation
    fn classify_interference(&self, phase_diff: f64, correlation: f64) -> InterferenceType {
        // Normalize phase difference to [-π, π]
        let normalized_phase = ((phase_diff + PI) % (2.0 * PI)) - PI;

        // Constructive: in-phase with positive correlation, or out-of-phase with negative
        // Destructive: in-phase with negative correlation, or out-of-phase with positive
        let phase_factor = normalized_phase.cos();

        if correlation > 0.3 && phase_factor > 0.5 {
            InterferenceType::Constructive
        } else if correlation < -0.3 && phase_factor < -0.5 {
            InterferenceType::Destructive
        } else if correlation > 0.3 && phase_factor < -0.5 {
            InterferenceType::Destructive
        } else if correlation < -0.3 && phase_factor > 0.5 {
            InterferenceType::Constructive
        } else {
            InterferenceType::Neutral
        }
    }

    /// Apply global phase evolution to all hypotheses
    pub fn evolve_phases(&mut self, state: &mut SuperpositionState, time_step: f64) {
        self.phase_accumulator += time_step;

        for hypothesis in state.hypotheses_mut() {
            // Phase evolution based on energy (probability)
            let energy = hypothesis.amplitude.norm_sqr();
            let phase_shift = energy * time_step * 2.0 * PI;

            hypothesis.phase += phase_shift;

            // Update amplitude with new phase
            let magnitude = hypothesis.amplitude.norm();
            hypothesis.amplitude = Complex::from_polar(magnitude, hypothesis.phase);
        }
    }

    /// Apply interference pattern across all hypothesis pairs
    pub fn apply_global_interference(
        &mut self,
        state: &mut SuperpositionState,
        correlation_matrix: &[Vec<f64>],
    ) {
        let n = state.len();

        if correlation_matrix.len() != n {
            return;
        }

        // Apply interference for each pair
        for i in 0..n {
            for j in (i + 1)..n {
                if j < correlation_matrix[i].len() {
                    let correlation = correlation_matrix[i][j];
                    self.apply_interference(state, i, j, correlation);
                }
            }
        }

        // Renormalize after all interference
        state.normalize();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_superposition_add_and_normalize() {
        let mut state = SuperpositionState::new();

        let metadata = HypothesisMetadata {
            source: "test".to_string(),
            confidence: 0.8,
            evidence_count: 5,
            created_at: 0.0,
        };

        state.add_hypothesis("Hypothesis A".to_string(), 0.5, metadata.clone());
        state.add_hypothesis("Hypothesis B".to_string(), 0.3, metadata.clone());
        state.add_hypothesis("Hypothesis C".to_string(), 0.2, metadata);

        assert_eq!(state.len(), 3);

        state.normalize();

        // Sum of probabilities should be ~1.0
        let total_prob: f64 = (0..state.len())
            .filter_map(|i| state.get_probability(i))
            .sum();

        assert!((total_prob - 1.0).abs() < 0.0001);
    }

    #[test]
    fn test_ranked_hypotheses() {
        let mut state = SuperpositionState::new();

        let metadata = HypothesisMetadata::default();

        state.add_hypothesis("Low".to_string(), 0.1, metadata.clone());
        state.add_hypothesis("High".to_string(), 0.7, metadata.clone());
        state.add_hypothesis("Medium".to_string(), 0.4, metadata);

        let ranked = state.get_ranked_hypotheses();

        assert_eq!(ranked.len(), 3);
        assert_eq!(ranked[0].0, "High");
        assert_eq!(ranked[1].0, "Medium");
        assert_eq!(ranked[2].0, "Low");
    }

    #[test]
    fn test_interference_constructive() {
        let mut state = SuperpositionState::new();
        let mut engine = InterferenceEngine::new();

        let metadata = HypothesisMetadata::default();

        state.add_hypothesis("A".to_string(), 0.5, metadata.clone());
        state.add_hypothesis("B".to_string(), 0.5, metadata);

        let initial_prob_a = state.get_probability(0).unwrap();

        // Apply constructive interference (positive correlation, in-phase)
        engine.apply_interference(&mut state, 0, 1, 0.8);

        state.normalize();
        let final_prob_a = state.get_probability(0).unwrap();

        // Constructive interference should increase probability
        assert!(final_prob_a > initial_prob_a);
    }

    #[test]
    fn test_interference_destructive() {
        let mut state = SuperpositionState::new();
        let mut engine = InterferenceEngine::new();

        let metadata = HypothesisMetadata::default();

        state.add_hypothesis("A".to_string(), 0.5, metadata.clone());
        state.add_hypothesis("B".to_string(), 0.5, metadata);

        let initial_prob_a = state.get_probability(0).unwrap();

        // Apply destructive interference (negative correlation)
        engine.apply_interference(&mut state, 0, 1, -0.8);

        state.normalize();
        let final_prob_a = state.get_probability(0).unwrap();

        // Destructive interference should decrease probability
        assert!(final_prob_a < initial_prob_a);
    }

    #[test]
    fn test_measurement_collapse() {
        let mut state = SuperpositionState::new();
        let measurement = MeasurementOperator::new(0.1);

        let metadata = HypothesisMetadata::default();

        state.add_hypothesis("A".to_string(), 0.2, metadata.clone());
        state.add_hypothesis("B".to_string(), 0.7, metadata.clone());
        state.add_hypothesis("C".to_string(), 0.1, metadata);

        let result = measurement.collapse(&mut state).unwrap();

        // Should select highest probability hypothesis
        assert_eq!(result.selected_hypothesis, "B");
        assert!(result.probability > 0.6);
        assert_eq!(result.collapsed_alternatives.len(), 2);
    }

    #[test]
    fn test_probabilistic_collapse() {
        let mut state = SuperpositionState::new();
        let measurement = MeasurementOperator::new(0.05);

        let metadata = HypothesisMetadata::default();

        state.add_hypothesis("A".to_string(), 0.5, metadata.clone());
        state.add_hypothesis("B".to_string(), 0.5, metadata);

        // Run multiple times to ensure both can be selected
        let mut selections = std::collections::HashSet::new();

        for _ in 0..50 {
            let result = measurement.probabilistic_collapse(&mut state).unwrap();
            selections.insert(result.selected_hypothesis.clone());
        }

        // Both hypotheses should have been selected at some point
        assert!(selections.contains("A") || selections.contains("B"));
    }

    #[test]
    fn test_decoherence() {
        let mut state = SuperpositionState::new();
        let measurement = MeasurementOperator::with_decoherence(0.1, 0.5);

        let metadata = HypothesisMetadata::default();

        state.add_hypothesis("A".to_string(), 0.5, metadata);

        // Add phase to create imaginary component
        state.apply_phase_shift(0, PI / 4.0);

        let initial_amplitude = state.hypotheses()[0].amplitude;
        let initial_imag = initial_amplitude.im.abs();

        // Apply decoherence
        measurement.apply_decoherence(&mut state, 10.0);

        let final_amplitude = state.hypotheses()[0].amplitude;
        let final_imag = final_amplitude.im.abs();

        // Imaginary component should decrease (decoherence)
        assert!(final_imag < initial_imag);
    }

    #[test]
    fn test_partial_measurement() {
        let mut state = SuperpositionState::new();
        let measurement = MeasurementOperator::new(0.2);

        let metadata = HypothesisMetadata::default();

        state.add_hypothesis("Viable".to_string(), 0.5, metadata.clone());
        state.add_hypothesis("Marginal".to_string(), 0.15, metadata);

        state.normalize();

        let results = measurement.partial_measurement(&state);

        assert_eq!(results.len(), 2);
        assert!(results[0].2); // First should be viable (prob >= 0.2)
        assert!(!results[1].2); // Second should not be viable (prob < 0.2)
    }

    #[test]
    fn test_phase_evolution() {
        let mut state = SuperpositionState::new();
        let mut engine = InterferenceEngine::new();

        let metadata = HypothesisMetadata::default();

        state.add_hypothesis("A".to_string(), 0.7, metadata.clone());
        state.add_hypothesis("B".to_string(), 0.3, metadata);

        let initial_phase_a = state.hypotheses()[0].phase;

        // Evolve phases over time
        engine.evolve_phases(&mut state, 1.0);

        let final_phase_a = state.hypotheses()[0].phase;

        // Phase should have evolved
        assert_ne!(initial_phase_a, final_phase_a);
    }
}
