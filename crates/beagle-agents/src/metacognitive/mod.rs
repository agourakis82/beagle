//! Meta-Cognitive Self-Improvement
//!
//! System that:
//! 1. Monitors its own performance
//! 2. Identifies weaknesses and failure patterns
//! 3. Evolves architecture autonomously
//! 4. Creates specialized agents on-demand

pub mod analyzer;
pub mod evolver;
pub mod monitor;
pub mod specialized;

pub use analyzer::{FailurePattern, WeaknessAnalyzer};
pub use evolver::{AgentSpecification, ArchitectureEvolver, EvolutionResult};
pub use monitor::PerformanceMonitor;
pub use specialized::SpecializedAgentFactory;
