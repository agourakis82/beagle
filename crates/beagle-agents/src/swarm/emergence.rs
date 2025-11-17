use serde::{Deserialize, Serialize};

/// Emergent behavior detection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmergentBehavior {
    pub has_converged: bool,
    pub dominant_concept: Option<String>,
    pub consensus_strength: f64,
}
