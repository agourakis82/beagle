//! Adversarial World Model
//!
//! Simula o universo externo hostil em múltiplas camadas:
//! • Revisores Q1 (Nature, Cell, Science)
//! • Concorrentes paralelos
//! • Comunidade científica (dogmas, tendências, cancel culture)
//! • Realidade física (viabilidade experimental, custo, reprodutibilidade)

pub mod community_sim;
pub mod competitor_sim;
pub mod reality_check;
pub mod reviewer_sim;

pub use community_sim::{CommunityPressure, CommunityReport};
pub use competitor_sim::{CompetitorAgent, CompetitorReport};
pub use reality_check::{PhysicalRealityEnforcer, RealityCheckReport};
pub use reviewer_sim::{Q1Reviewer, ReviewVerdict, ReviewerReport};
