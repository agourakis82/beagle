//! First-Order Logic Engine
//!
//! Supports:
//! - Predicates: P(x, y)
//! - Quantifiers: ∀x, ∃x
//! - Connectives: ∧, ∨, ¬, →, ↔
//! - Unification & Resolution (partial; roadmap)

pub mod engine;
pub mod syntax;

pub use engine::{KnowledgeBase, LogicEngine, Proof, ProofStep, Rule};
pub use syntax::{Formula, Predicate, Term};

use thiserror::Error;

#[derive(Error, Debug)]
pub enum LogicError {
    #[error("Parse error: {0}")]
    ParseError(String),

    #[error("Unification failed: {0}")]
    UnificationFailed(String),

    #[error("Proof not found")]
    ProofNotFound,

    #[error("Invalid formula: {0}")]
    InvalidFormula(String),
}

pub type Result<T> = std::result::Result<T, LogicError>;
