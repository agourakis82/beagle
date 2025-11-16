//! Deep Research Engine with MCTS + PUCT
//! Discovers novel scientific hypotheses through tree search

pub mod corpus;
pub mod hypothesis;
pub mod mcts;
pub mod puct;
pub mod simulation;

pub use corpus::{EmbeddingEngine, NoveltyScorer, Paper, ScholarAPI};
pub use hypothesis::{Hypothesis, HypothesisNode, HypothesisTree};
pub use mcts::{DeepResearchResult, MCTSEngine};
pub use puct::PUCTSelector;
pub use simulation::{SimulationEngine, SimulationResult};
