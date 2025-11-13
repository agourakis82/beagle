//! Neuro-Symbolic Hybrid System
//! 
//! Integration of:
//! 1. Neural (LLM): Pattern recognition, generation, extraction
//! 2. Symbolic (Logic): Formal reasoning, consistency checking
//! 3. Constraint (Solver): Optimization under constraints

pub mod neural;
pub mod symbolic;
pub mod constraint;
pub mod integration;

pub use neural::NeuralExtractor;
pub use symbolic::{SymbolicReasoner, LogicRule, Predicate};
pub use constraint::ConstraintSolver;
pub use integration::HybridReasoner;

