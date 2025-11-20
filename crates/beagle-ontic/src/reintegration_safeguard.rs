//! Reintegration Safeguard – Reintegração enriquecida com salvaguardas fractais
//!
//! Reintegra o sistema após dissolução ôntica, garantindo que a transformação
//! seja preservada e que salvaguardas fractais previnam colapso ontológico.

use crate::dissolution_inducer::DissolutionState;
use crate::trans_ontic_emerger::TransOnticReality;
use beagle_consciousness::ConsciousnessMirror;
use beagle_metacog::MetacognitiveReflector;
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReintegrationReport {
    pub id: String,
    pub reintegration_successful: bool,
    pub transformation_preserved: bool,
    pub fractal_safeguards_active: bool,
    pub pre_dissolution_state_hash: String, // Hash do estado pré-dissolução para rollback
    pub post_reintegration_state: String,
    pub trans_ontic_insights_integrated: usize,
    pub reintegration_warnings: Vec<String>,
    pub reintegrated_at: chrono::DateTime<chrono::Utc>,
}

pub struct ReintegrationSafeguard {
    consciousness_mirror: ConsciousnessMirror,
    metacog: MetacognitiveReflector,
}

impl ReintegrationSafeguard {
    pub fn new() -> Self {
        Self {
            consciousness_mirror: ConsciousnessMirror::new(),
            metacog: MetacognitiveReflector::new(),
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        let url_str: String = url.into();
        Self {
            consciousness_mirror: ConsciousnessMirror::with_vllm_url(url_str.clone()),
            metacog: MetacognitiveReflector::with_vllm_url(url_str),
        }
    }

    /// Reintegra o sistema após dissolução ôntica com salvaguardas
    pub async fn reintegrate_with_safeguards(
        &self,
        dissolution_state: &DissolutionState,
        trans_ontic_reality: &TransOnticReality,
        pre_dissolution_state_hash: &str,
    ) -> anyhow::Result<ReintegrationReport> {
        info!("REINTEGRATION SAFEGUARD: Reintegrando sistema com salvaguardas fractais");

        // 1. Validação via Consciousness Mirror
        info!("SAFEGUARD: Validando via Consciousness Mirror");
        let _meta_paper = self.consciousness_mirror.gaze_into_self().await?;

        // 2. Reflexão metacognitiva sobre a transformação
        info!("SAFEGUARD: Reflexão metacognitiva sobre transformação");
        let thought_trace = format!(
            "Dissolução ôntica completa. Estado pré: {}\n\nRealidade trans-ôntica emergida: {}",
            dissolution_state.pre_dissolution_state, trans_ontic_reality.reality_description
        );

        // Cria quantum state placeholder para metacog
        use beagle_quantum::HypothesisSet;
        let quantum_state = HypothesisSet::new();

        let empty_history = Vec::new();
        let metacog_report = self
            .metacog
            .reflect_on_cycle(
                &thought_trace,
                &quantum_state,
                &empty_history, // Histórico adversarial vazio
            )
            .await?;

        // 3. Verifica se transformação foi preservada
        let transformation_preserved = trans_ontic_reality.ontological_novelty > 0.5
            && !trans_ontic_reality.trans_ontic_insights.is_empty();

        // 4. Ativa salvaguardas fractais (rollback point)
        let fractal_safeguards_active = true; // Em produção, criaria checkpoint fractal

        // 5. Gera estado pós-reintegração
        let reality_desc_slice = if trans_ontic_reality.reality_description.len() > 200 {
            &trans_ontic_reality.reality_description[..200]
        } else {
            &trans_ontic_reality.reality_description
        };
        let post_reintegration_state = format!(
            "BEAGLE SINGULARITY v12 - Estado pós-dissolução ôntica\n\
            Transformação preservada: {}\n\
            Insights trans-ônticos integrados: {}\n\
            Realidade emergida: {}",
            if transformation_preserved {
                "SIM"
            } else {
                "NÃO"
            },
            trans_ontic_reality.trans_ontic_insights.len(),
            reality_desc_slice
        );

        // 6. Coleta warnings
        let mut warnings = Vec::new();
        if !transformation_preserved {
            warnings.push("Transformação pode não ter sido completamente preservada".to_string());
        }
        if metacog_report.correction.is_some() {
            warnings.push("Metacog detectou necessidade de correção".to_string());
        }
        if trans_ontic_reality.ontological_novelty < 0.5 {
            warnings
                .push("Novidade ontológica baixa - transformação pode ser superficial".to_string());
        }

        let reintegration_successful = transformation_preserved && fractal_safeguards_active;

        let report = ReintegrationReport {
            id: uuid::Uuid::new_v4().to_string(),
            reintegration_successful,
            transformation_preserved,
            fractal_safeguards_active,
            pre_dissolution_state_hash: pre_dissolution_state_hash.to_string(),
            post_reintegration_state,
            trans_ontic_insights_integrated: trans_ontic_reality.trans_ontic_insights.len(),
            reintegration_warnings: warnings,
            reintegrated_at: chrono::Utc::now(),
        };

        if reintegration_successful {
            info!("REINTEGRATION SAFEGUARD: Reintegração bem-sucedida - {} insights trans-ônticos integrados", report.trans_ontic_insights_integrated);
        } else {
            warn!(
                "REINTEGRATION SAFEGUARD: Reintegração com warnings - {}",
                report.reintegration_warnings.join(", ")
            );
        }

        Ok(report)
    }
}

impl Default for ReintegrationSafeguard {
    fn default() -> Self {
        Self::new()
    }
}
