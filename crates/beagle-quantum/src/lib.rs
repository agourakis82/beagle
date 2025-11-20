//! beagle-quantum – Quantum-Inspired Reasoning for BEAGLE SINGULARITY
//!
//! Implementa os três pilares quânticos clássicos simulados:
//! • Superposition: múltiplas hipóteses simultâneas com amplitudes complexas
//! • Interference: reforço ou cancelamento de caminhos
//! • Measurement: colapso probabilístico com logging de confiança

pub mod interference;
pub mod mcts_integration;
pub mod measurement;
pub mod superposition;
pub mod traits;

pub use interference::InterferenceEngine;
pub use measurement::{CollapseStrategy, MeasurementOperator};
pub use superposition::{Hypothesis, HypothesisSet, SuperpositionAgent};
pub use traits::QuantumReasoner;
