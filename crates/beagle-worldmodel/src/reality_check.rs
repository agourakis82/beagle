//! Physical Reality Enforcer – Verifica viabilidade experimental real
//!
//! Avalia custo, tempo, reprodutibilidade e viabilidade técnica

use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RealityCheckReport {
    pub feasibility_score: f64, // 0.0 a 1.0
    pub estimated_cost: String,
    pub estimated_time: String,
    pub reproducibility_risk: f64, // 0.0 a 1.0
    pub technical_barriers: Vec<String>,
    pub recommendations: Vec<String>,
}

pub struct PhysicalRealityEnforcer {
    vllm_url: Option<String>,
}

impl PhysicalRealityEnforcer {
    pub fn new() -> Self {
        Self {
            vllm_url: None,
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        Self {
            vllm_url: Some(url.into()),
        }
    }

    /// Enforce reality check (alias para check_feasibility com interface simplificada)
    pub async fn enforce(&self, protocol_text: &str) -> anyhow::Result<RealityCheckReport> {
        // Extrai metodologia e equipamentos do protocolo (simplificado)
        let equipment: Vec<String> = Vec::new(); // TODO: extrair do protocol_text
        self.check_feasibility(protocol_text, &equipment).await
    }

    /// Verifica viabilidade experimental
    pub async fn check_feasibility(
        &self,
        methodology: &str,
        required_equipment: &[String],
    ) -> anyhow::Result<RealityCheckReport> {
        info!("REALITY CHECK: Verificando viabilidade experimental");

        let mut feasibility_score: f64 = 0.8; // Base otimista
        let mut technical_barriers = Vec::new();
        let mut recommendations = Vec::new();

        let methodology_lower = methodology.to_lowercase();

        // Verifica equipamentos caros/complexos
        for equipment in required_equipment {
            let eq_lower = equipment.to_lowercase();
            if eq_lower.contains("cryo-em") || eq_lower.contains("synchrotron") || eq_lower.contains("supercomputer") {
                feasibility_score -= 0.2;
                technical_barriers.push(format!("Equipmento caro/complexo: {}", equipment));
                recommendations.push("Considerar colaborações ou acesso a facilities".to_string());
            }
        }

        // Verifica metodologias complexas
        if methodology_lower.contains("in vivo") && methodology_lower.contains("human") {
            feasibility_score -= 0.3;
            technical_barriers.push("Estudos em humanos requerem aprovação ética complexa".to_string());
            recommendations.push("Considerar estudos pré-clínicos primeiro".to_string());
        }

        // Verifica reprodutibilidade
        let reproducibility_risk = if methodology_lower.contains("proprietary") || 
                                      methodology_lower.contains("black box") {
            0.7
        } else if methodology_lower.contains("open source") || 
                  methodology_lower.contains("reproduc") {
            0.2
        } else {
            0.5
        };

        feasibility_score = feasibility_score.clamp(0.0f64, 1.0f64);

        let estimated_cost = if feasibility_score < 0.5 {
            "High ($500k+)".to_string()
        } else if feasibility_score < 0.7 {
            "Medium ($100k-500k)".to_string()
        } else {
            "Low (<$100k)".to_string()
        };

        let estimated_time = if feasibility_score < 0.5 {
            "2-5 years".to_string()
        } else if feasibility_score < 0.7 {
            "1-2 years".to_string()
        } else {
            "6-12 months".to_string()
        };

        Ok(RealityCheckReport {
            feasibility_score,
            estimated_cost,
            estimated_time,
            reproducibility_risk,
            technical_barriers,
            recommendations,
        })
    }
}

impl Default for PhysicalRealityEnforcer {
    fn default() -> Self {
        Self::new()
    }
}

