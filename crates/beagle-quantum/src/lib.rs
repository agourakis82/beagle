//! beagle-quantum – Stochastic hypothesis sampler with interference weights
//!
//! Implements a documented stochastic sampling framework for multi-hypothesis
//! reasoning. Terminology is borrowed from quantum mechanics for conceptual
//! clarity, but there is no actual quantum computation here:
//! • Superposition: a ranked set of candidate hypotheses, each with a real-
//!   valued weight pair (re, im) used as an unnormalized probability score.
//! • Interference: weight adjustment that reinforces or dampens candidates
//!   based on structural overlap between hypotheses.
//! • Measurement: normalization + argmax selection with confidence logging.

pub mod interference;
pub mod mcts_integration;
pub mod measurement;
pub mod superposition;
pub mod traits;

pub use interference::InterferenceEngine;
pub use measurement::{CollapseStrategy, MeasurementOperator};
pub use superposition::{Hypothesis, HypothesisSet, SuperpositionAgent};
pub use traits::QuantumReasoner;
