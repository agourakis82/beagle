//! Community Simulation – Simula pressão da comunidade científica
//!
//! Modela dogmas, tendências, cancel culture e modas acadêmicas

use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommunityReport {
    pub acceptance_probability: f64, // 0.0 a 1.0
    pub dominant_paradigm: String,
    pub resistance_factors: Vec<String>,
    pub support_factors: Vec<String>,
    pub recommendation: String,
}

pub struct CommunityPressure {
    current_trends: Vec<String>,
    dominant_dogmas: Vec<String>,
}

impl CommunityPressure {
    pub fn new() -> Self {
        Self {
            current_trends: vec![
                "Open science".to_string(),
                "Reproducibility crisis".to_string(),
                "AI/ML integration".to_string(),
            ],
            dominant_dogmas: vec![
                "P-hacking is unethical".to_string(),
                "Large sample sizes required".to_string(),
                "Pre-registration is essential".to_string(),
            ],
        }
    }

    /// Avalia aceitação pela comunidade científica
    pub async fn assess_acceptance(
        &self,
        research_question: &str,
        methodology: &str,
    ) -> anyhow::Result<CommunityReport> {
        info!("COMMUNITY PRESSURE: Avaliando aceitação");

        // Análise simples baseada em palavras-chave
        let text_lower = format!("{} {}", research_question, methodology).to_lowercase();

        let mut acceptance_prob: f64 = 0.7; // Base
        let mut resistance_factors = Vec::new();
        let mut support_factors = Vec::new();

        // Verifica alinhamento com tendências
        for trend in &self.current_trends {
            if text_lower.contains(&trend.to_lowercase()) {
                acceptance_prob += 0.1;
                support_factors.push(format!("Alinhado com tendência: {}", trend));
            }
        }

        // Verifica conflito com dogmas
        for dogma in &self.dominant_dogmas {
            if text_lower.contains("p-hack") || text_lower.contains("small sample") {
                acceptance_prob -= 0.2;
                resistance_factors.push(format!("Conflito com dogma: {}", dogma));
            }
        }

        // Verifica metodologia robusta
        if text_lower.contains("pre-register") || text_lower.contains("reproduc") {
            acceptance_prob += 0.15;
            support_factors.push("Metodologia robusta".to_string());
        }

        acceptance_prob = acceptance_prob.clamp(0.0f64, 1.0f64);

        let recommendation = if acceptance_prob > 0.8 {
            "High community acceptance expected".to_string()
        } else if acceptance_prob > 0.6 {
            "Moderate acceptance, minor adjustments recommended".to_string()
        } else {
            "Low acceptance, significant changes needed".to_string()
        };

        Ok(CommunityReport {
            acceptance_probability: acceptance_prob,
            dominant_paradigm: "Evidence-based, reproducible science".to_string(),
            resistance_factors,
            support_factors,
            recommendation,
        })
    }
}

impl Default for CommunityPressure {
    fn default() -> Self {
        Self::new()
    }
}

