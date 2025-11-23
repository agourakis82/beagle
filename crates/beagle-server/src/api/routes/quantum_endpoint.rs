//! Quantum-Inspired Reasoning Endpoint
//!
//! Provides quantum superposition and interference-based hypothesis reasoning

use axum::{extract::State, http::StatusCode, Json};
use beagle_agents::{
    HypothesisMetadata, InterferenceEngine, MeasurementOperator, SuperpositionState,
};
use serde::{Deserialize, Serialize};
use std::time::Instant;
use tracing::{info, warn};

use crate::state::AppState;

/// Request for quantum reasoning
#[derive(Debug, Deserialize)]
pub struct QuantumReasoningRequest {
    /// List of hypotheses with initial probabilities
    pub hypotheses: Vec<HypothesisInput>,

    /// Optional correlation matrix (NxN) for interference
    /// If not provided, will use simple heuristics
    #[serde(default)]
    pub correlation_matrix: Option<Vec<Vec<f64>>>,

    /// Measurement threshold (0.0-1.0)
    #[serde(default = "default_threshold")]
    pub threshold: f64,

    /// Interference strength (0.0-2.0)
    #[serde(default = "default_interference_strength")]
    pub interference_strength: f64,

    /// Use probabilistic collapse instead of deterministic
    #[serde(default)]
    pub probabilistic: bool,

    /// Apply decoherence before measurement
    #[serde(default)]
    pub apply_decoherence: bool,
}

#[derive(Debug, Deserialize)]
pub struct HypothesisInput {
    pub content: String,
    pub initial_probability: f64,

    #[serde(default)]
    pub confidence: f64,

    #[serde(default)]
    pub source: String,
}

fn default_threshold() -> f64 {
    0.15
}

fn default_interference_strength() -> f64 {
    1.0
}

/// Response from quantum reasoning
#[derive(Debug, Serialize)]
pub struct QuantumReasoningResponse {
    /// Selected hypothesis after measurement
    pub selected_hypothesis: String,

    /// Probability of selected hypothesis
    pub probability: f64,

    /// All hypotheses ranked by probability
    pub ranked_hypotheses: Vec<RankedHypothesis>,

    /// Alternative hypotheses (top 5)
    pub alternatives: Vec<AlternativeHypothesis>,

    /// Metadata about the quantum reasoning process
    pub metadata: QuantumMetadata,
}

#[derive(Debug, Serialize)]
pub struct RankedHypothesis {
    pub content: String,
    pub probability: f64,
    pub rank: usize,
}

#[derive(Debug, Serialize)]
pub struct AlternativeHypothesis {
    pub content: String,
    pub probability: f64,
}

#[derive(Debug, Serialize)]
pub struct QuantumMetadata {
    pub num_hypotheses: usize,
    pub interference_applied: bool,
    pub decoherence_applied: bool,
    pub measurement_type: String,
    pub processing_time_ms: u64,
    pub superposition_normalized: bool,
}

/// Quantum reasoning endpoint handler
pub async fn quantum_reasoning(
    State(_state): State<AppState>,
    Json(req): Json<QuantumReasoningRequest>,
) -> Result<Json<QuantumReasoningResponse>, StatusCode> {
    let start = Instant::now();

    info!(
        "🌀 Quantum reasoning request with {} hypotheses",
        req.hypotheses.len()
    );

    if req.hypotheses.is_empty() {
        warn!("Empty hypotheses list");
        return Err(StatusCode::BAD_REQUEST);
    }

    if req.hypotheses.len() > 100 {
        warn!("Too many hypotheses: {}", req.hypotheses.len());
        return Err(StatusCode::BAD_REQUEST);
    }

    // Create superposition state
    let mut superposition = SuperpositionState::new();

    for (i, hyp) in req.hypotheses.iter().enumerate() {
        let metadata = HypothesisMetadata {
            source: if hyp.source.is_empty() {
                "user".to_string()
            } else {
                hyp.source.clone()
            },
            confidence: hyp.confidence,
            evidence_count: 0,
            created_at: i as f64,
        };

        superposition.add_hypothesis(
            hyp.content.clone(),
            hyp.initial_probability.clamp(0.001, 0.999),
            metadata,
        );
    }

    superposition.normalize();

    // Apply interference if correlation matrix provided or if enough hypotheses
    let mut interference_applied = false;
    if req.hypotheses.len() > 1 {
        let mut engine = InterferenceEngine::with_strength(req.interference_strength);

        if let Some(matrix) = &req.correlation_matrix {
            // Validate matrix dimensions
            if matrix.len() == req.hypotheses.len()
                && matrix.iter().all(|row| row.len() == req.hypotheses.len())
            {
                engine.apply_global_interference(&mut superposition, matrix);
                interference_applied = true;
                info!("Applied custom correlation matrix");
            } else {
                warn!("Invalid correlation matrix dimensions, skipping interference");
            }
        } else if req.hypotheses.len() <= 10 {
            // Auto-generate simple correlation matrix for small sets
            let n = req.hypotheses.len();
            let mut auto_matrix = vec![vec![0.0; n]; n];

            for i in 0..n {
                for j in (i + 1)..n {
                    // Simple heuristic: adjacent hypotheses have slight positive correlation
                    let correlation = if j == i + 1 { 0.3 } else { 0.0 };
                    auto_matrix[i][j] = correlation;
                    auto_matrix[j][i] = correlation;
                }
            }

            engine.apply_global_interference(&mut superposition, &auto_matrix);
            interference_applied = true;
            info!("Applied auto-generated correlation matrix");
        }
    }

    // Apply decoherence if requested
    let mut decoherence_applied = false;
    if req.apply_decoherence {
        let measurement_op = MeasurementOperator::with_decoherence(req.threshold, 0.1);
        measurement_op.apply_decoherence(&mut superposition, 5.0);
        decoherence_applied = true;
        info!("Applied decoherence");
    }

    // Measurement
    let measurement_op = MeasurementOperator::new(req.threshold);
    let measurement_result = if req.probabilistic {
        measurement_op.probabilistic_collapse(&mut superposition)
    } else {
        measurement_op.collapse(&mut superposition)
    };

    let result = match measurement_result {
        Some(m) => m,
        None => {
            warn!("Measurement failed - no viable hypothesis above threshold");
            return Err(StatusCode::UNPROCESSABLE_ENTITY);
        }
    };

    // Get ranked hypotheses
    let ranked = superposition.get_ranked_hypotheses();
    let ranked_hypotheses: Vec<RankedHypothesis> = ranked
        .iter()
        .enumerate()
        .map(|(i, (content, prob, _))| RankedHypothesis {
            content: content.clone(),
            probability: *prob,
            rank: i + 1,
        })
        .collect();

    let alternatives: Vec<AlternativeHypothesis> = result
        .collapsed_alternatives
        .iter()
        .map(|(content, prob)| AlternativeHypothesis {
            content: content.clone(),
            probability: *prob,
        })
        .collect();

    let elapsed = start.elapsed().as_millis() as u64;

    info!(
        "✅ Quantum reasoning complete in {}ms: selected '{}' (prob: {:.3})",
        elapsed, result.selected_hypothesis, result.probability
    );

    Ok(Json(QuantumReasoningResponse {
        selected_hypothesis: result.selected_hypothesis,
        probability: result.probability,
        ranked_hypotheses,
        alternatives,
        metadata: QuantumMetadata {
            num_hypotheses: req.hypotheses.len(),
            interference_applied,
            decoherence_applied,
            measurement_type: if req.probabilistic {
                "probabilistic".to_string()
            } else {
                "deterministic".to_string()
            },
            processing_time_ms: elapsed,
            superposition_normalized: true,
        },
    }))
}
