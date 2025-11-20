//! Adversarial Self-Play Engine – Week 2
//!
//! Loop fechado de evolução: HERMES gera → ARGOS ataca → HERMES refina → LoRA aprende
//! Continua até quality_score ≥ 98.5% ou max_iters = 6

use crate::agents::{HermesAgent, ArgosAgent, ValidationResult, Draft};
use crate::agents::athena::Paper;
use crate::Result;
use tracing::{info, warn, error};
use std::sync::Arc;

const TARGET_QUALITY: f64 = 0.985; // 98.5%
const MAX_ITERATIONS: usize = 6;

/// Adversarial Self-Play Engine para evolução contínua de drafts
pub struct AdversarialSelfPlayEngine {
    hermes: Arc<HermesAgent>,
    argos: Arc<ArgosAgent>,
}

impl AdversarialSelfPlayEngine {
    /// Cria novo engine com agents configurados
    pub async fn new(hermes: Arc<HermesAgent>, argos: Arc<ArgosAgent>) -> Result<Self> {
        Ok(Self { hermes, argos })
    }

    /// Loop adversarial completo – retorna draft final + métricas de evolução
    pub async fn evolve_draft(
        &self,
        initial_draft: Draft,
        papers: &[Paper],
    ) -> Result<EvolvedDraft> {
        let mut draft = initial_draft;
        let mut best_quality = 0.0;
        let mut iteration = 0;
        let mut evolution_history = Vec::new();

        loop {
            iteration += 1;
            info!("🔬 Adversarial Iteration {}/{}", iteration, MAX_ITERATIONS);

            // 1. ARGOS ataca com força máxima (modo ultra-crítico)
            let ValidationResult {
                quality_score,
                issues,
                ..
            } = self.argos.validate_ultra_critical(&draft, papers).await?;

            info!("ARGOS quality score: {:.1}%", quality_score * 100.0);

            evolution_history.push(IterationMetrics {
                iteration,
                quality_score,
                issues_count: issues.len(),
            });

            if quality_score >= TARGET_QUALITY || iteration >= MAX_ITERATIONS {
                info!(
                    "✅ Adversarial loop concluído – qualidade alvo atingida ou max iterações"
                );
                break;
            }

            // 2. Gera crítica estruturada pro HERMES
            let critique = self.argos.generate_structured_critique(&issues).await?;

            // 3. HERMES refina com crítica
            let previous_draft = draft.clone();
            draft = self.hermes.refine_with_critique(&draft, &critique).await?;

            // 4. Online LoRA training com o par (draft anterior → novo)
            if quality_score > best_quality {
                best_quality = quality_score;
                let bad = previous_draft.content.clone();
                let good = draft.content.clone();

                tokio::spawn(async move {
                    if let Err(e) = beagle_lora_auto::train_and_update_voice(&bad, &good).await {
                        error!("LoRA auto falhou: {e}");
                    } else {
                        info!("Voz atualizada — o BEAGLE fala mais como tu agora");
                    }
                });
            }
        }

        Ok(EvolvedDraft {
            final_draft: draft,
            final_quality: best_quality,
            iterations: iteration,
            evolution_history,
        })
    }
}

/// Resultado do processo adversarial com métricas completas
#[derive(Debug, Clone)]
pub struct EvolvedDraft {
    pub final_draft: Draft,
    pub final_quality: f64,
    pub iterations: usize,
    pub evolution_history: Vec<IterationMetrics>,
}

/// Métricas de uma iteração do loop adversarial
#[derive(Debug, Clone)]
pub struct IterationMetrics {
    pub iteration: usize,
    pub quality_score: f64,
    pub issues_count: usize,
}

