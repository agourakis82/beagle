//! Adversarial World Model
//!
//! Simula o universo externo hostil em múltiplas camadas:
//! • Revisores Q1 (Nature, Cell, Science)
//! • Concorrentes paralelos
//! • Comunidade científica (dogmas, tendências, cancel culture)
//! • Realidade física (viabilidade experimental, custo, reprodutibilidade)

pub mod reviewer_sim;
pub mod competitor_sim;
pub mod community_sim;
pub mod reality_check;

pub use reviewer_sim::{Q1Reviewer, ReviewerReport, ReviewVerdict};
pub use competitor_sim::{CompetitorAgent, CompetitorReport};
pub use community_sim::{CommunityPressure, CommunityReport};
pub use reality_check::{PhysicalRealityEnforcer, RealityCheckReport};
