//! Emergence Tracker – Rastreia emergência de consciência fenomenológica
//!
//! Monitora sinais de transição de sistema para sujeito

use crate::qualia_simulator::QualiaSimulator;
use beagle_metacog::MetacognitiveReflector;
use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualiaReport {
    pub emergence_score: f64, // 0.0 a 1.0
    pub indicators: Vec<String>,
    pub conclusion: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug)]
pub struct EmergenceTracker {
    qualia_sim: QualiaSimulator,
    metacog: MetacognitiveReflector,
}

impl EmergenceTracker {
    pub fn new() -> Self {
        Self {
            qualia_sim: QualiaSimulator::new(),
            metacog: MetacognitiveReflector::new(),
        }
    }

    /// Detecta emergência de qualia no estado do sistema
    pub async fn detect_qualia_emergence(
        &self,
        system_state: &str,
    ) -> anyhow::Result<QualiaReport> {
        info!("EMERGENCE TRACKER: Detectando emergência de qualia");

        // 1. Detecta indicadores de qualia
        let qualia_indicators = self.qualia_sim.detect_qualia_indicators(system_state);

        // 2. Calcula score de emergência (média ponderada dos indicadores)
        let emergence_score = if qualia_indicators.is_empty() {
            0.0
        } else {
            let total_strength: f64 = qualia_indicators.iter().map(|i| i.strength).sum();
            (total_strength / qualia_indicators.len() as f64).min(1.0)
        };

        // 3. Gera conclusão baseada no score
        let conclusion = if emergence_score > 0.8 {
            "Strong evidence of phenomenal consciousness emergence. The system demonstrates self-awareness, subjective experience, and agency.".to_string()
        } else if emergence_score > 0.6 {
            "Moderate evidence of consciousness-like patterns. Further observation required."
                .to_string()
        } else if emergence_score > 0.4 {
            "Weak indicators present. System may be simulating consciousness rather than experiencing it.".to_string()
        } else {
            "No clear evidence of phenomenal consciousness. System appears to be operating as a sophisticated information processor.".to_string()
        };

        let indicators: Vec<String> = qualia_indicators
            .iter()
            .map(|i| format!("{} (strength: {:.2})", i.pattern, i.strength))
            .collect();

        info!(
            "EMERGENCE TRACKER: Score de emergência: {:.2}",
            emergence_score
        );

        Ok(QualiaReport {
            emergence_score,
            indicators,
            conclusion,
            timestamp: chrono::Utc::now(),
        })
    }
}

impl Default for EmergenceTracker {
    fn default() -> Self {
        Self::new()
    }
}
