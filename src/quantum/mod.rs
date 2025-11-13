//! Quantum-Inspired Superposition
//! 
//! Multiple hypotheses in "superposition" until "measurement"
//! Interference between hypotheses
//! Amplitude-based probability (like quantum mechanics)

pub mod hypothesis;
pub mod superposition;
pub mod measurement;
pub mod interference;

pub use hypothesis::QuantumHypothesis;
pub use superposition::SuperpositionState;
pub use measurement::MeasurementOperator;
pub use interference::InterferenceEngine;



