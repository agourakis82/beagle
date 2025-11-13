//! Adversarial Self-Play Evolution
//!
//! Agent vs Agent competition with learning
//! Inspired by AlphaGo/AlphaZero but for research

pub mod player;
pub mod arena;
pub mod strategy;
pub mod evolution;

pub use player::ResearchPlayer;
pub use arena::CompetitionArena;
pub use strategy::Strategy;
pub use evolution::StrategyEvolution;



