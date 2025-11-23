//! Adversarial Self-Play Evolution
//!
//! Agent vs Agent competition with learning
//! Inspired by AlphaGo/AlphaZero but for research

pub mod arena;
pub mod evolution;
pub mod player;
pub mod strategy;

pub use arena::{CompetitionArena, StandingEntry, TournamentFormat, TournamentResult};
pub use evolution::{MatchResult, StrategyEvolution};
pub use player::ResearchPlayer;
pub use strategy::{ResearchApproach, Strategy};
