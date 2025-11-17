//! Swarm Intelligence - Emergent collective reasoning
//!
//! 10-50 simple agents with stigmergy (indirect communication)
//! No central coordinator - behavior emerges from local interactions

pub mod agent;
pub mod emergence;
pub mod pheromone;
pub mod swarm;

pub use agent::SwarmAgent;
pub use emergence::EmergentBehavior;
pub use pheromone::{Pheromone, PheromoneField};
pub use swarm::SwarmOrchestrator;
