//! Adversarial Self-Play Engine – Week 2
//!
//! Loop fechado de evolução: HERMES gera → ARGOS ataca → HERMES refina → LoRA aprende
//! Continua até quality_score ≥ 98.5% ou max_iters = 6

use crate::agents::athena::Paper;
use crate::agents::{ArgosAgent, Draft, HermesAgent, ValidationResult};
use crate::Result;
use beagle_config::beagle_data_dir;
use chrono::Utc;
use lazy_static::lazy_static;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tracing::{error, info};

const TARGET_QUALITY: f64 = 0.985; // 98.5%
const MAX_ITERATIONS: usize = 6;
const MIN_DELTA: f64 = 1.2; // delta em pontos percentuais
const MIN_INTERVAL: Duration = Duration::from_secs(20 * 60);

lazy_static! {
    static ref LAST_TRAIN_TIME: Mutex<Option<Instant>> = Mutex::new(None);
}

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
        let mut best_quality: f64 = 0.0;
        let mut best_training_quality_pct: f64 = 0.0;
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
            best_quality = best_quality.max(quality_score);

            evolution_history.push(IterationMetrics {
                iteration,
                quality_score,
                issues_count: issues.len(),
            });

            if quality_score >= TARGET_QUALITY || iteration >= MAX_ITERATIONS {
                info!("✅ Adversarial loop concluído – qualidade alvo atingida ou max iterações");
                break;
            }

            // 2. Gera crítica estruturada pro HERMES
            let critique = self.argos.generate_structured_critique(&issues).await?;

            // 3. HERMES refina com crítica
            let previous_draft = draft.clone();
            draft = self.hermes.refine_with_critique(&draft, &critique).await?;

            // 4. Online LoRA training com o par (draft anterior → novo)
            let quality_pct = quality_score * 100.0;
            if quality_pct > best_training_quality_pct + MIN_DELTA {
                let bad = previous_draft.content.clone();
                let good = draft.content.clone();

                let now = Instant::now();
                let mut guard = LAST_TRAIN_TIME.lock().unwrap_or_else(|p| p.into_inner());
                if let Some(last) = *guard {
                    if now.duration_since(last) < MIN_INTERVAL {
                        info!("LoRA throttled — aguardando janela mínima de 20 minutos");
                        continue;
                    }
                }
                *guard = Some(now);
                best_training_quality_pct = quality_pct;

                tokio::spawn(async move {
                    let output_dir = beagle_data_dir()
                        .join("lora")
                        .join(format!("hermes_{}", Utc::now().format("%Y%m%d_%H%M%S")));
                    let output_dir_str = output_dir.to_string_lossy().to_string();
                    match tokio::task::spawn_blocking(move || {
                        beagle_lora_auto::train_lora(&bad, &good, &output_dir_str)
                    })
                    .await
                    {
                        Ok(Ok(msg)) => info!("Voz atualizada — {}", msg),
                        Ok(Err(err)) => error!("LoRA auto falhou: {err}"),
                        Err(join_err) => error!("LoRA auto panic/join: {join_err}"),
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
