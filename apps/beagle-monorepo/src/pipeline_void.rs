//! Void Deadlock Handler - Detecção e resolução de loops cognitivos
//!
//! Implementa detecção de deadlock e aplica estratégias Void quando necessário.
//! Quando a feature `void` está habilitada, usa o VoidNavigator real do beagle_void.
//! Caso contrário, usa implementação fallback.

use std::collections::VecDeque;
use tracing::{info, warn};

#[cfg(feature = "void")]
use beagle_void::{VoidConfig, VoidNavigator, VoidOrchestrator};
#[cfg(feature = "void")]
use std::sync::Arc;

/// Estado de detecção de deadlock para um run
#[derive(Debug, Clone)]
pub struct DeadlockState {
    pub run_id: String,
    pub recent_outputs: VecDeque<String>,
    pub attempts: u32,
    pub last_improvement: Option<u32>,
}

impl DeadlockState {
    pub fn new(run_id: String) -> Self {
        Self {
            run_id,
            recent_outputs: VecDeque::with_capacity(5),
            attempts: 0,
            last_improvement: None,
        }
    }

    /// Adiciona um output e verifica se há deadlock
    pub fn add_output(&mut self, output: &str) -> bool {
        self.attempts += 1;

        // Normaliza output (primeiros 200 chars para comparação)
        let normalized = output.chars().take(200).collect::<String>();

        // Verifica se é similar aos outputs anteriores
        let is_similar = self
            .recent_outputs
            .iter()
            .any(|prev| similarity(prev, &normalized) > 0.8);

        self.recent_outputs.push_back(normalized);
        if self.recent_outputs.len() > 5 {
            self.recent_outputs.pop_front();
        }

        // Deadlock se: N tentativas sem melhoria OU outputs muito similares
        let threshold = if std::env::var("BEAGLE_VOID_STRICT").is_ok() {
            3
        } else {
            5
        };

        if self.attempts >= threshold && (is_similar || self.last_improvement.is_none()) {
            warn!(
                run_id = %self.run_id,
                attempts = self.attempts,
                "Deadlock detectado: {} tentativas sem melhoria significativa",
                self.attempts
            );
            return true;
        }

        if !is_similar {
            self.last_improvement = Some(self.attempts);
        }

        false
    }
}

/// Calcula similaridade simples entre duas strings (0.0 a 1.0)
#[inline]
fn similarity(a: &str, b: &str) -> f64 {
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }

    let a_lower = a.to_lowercase();
    let b_lower = b.to_lowercase();

    // Conta palavras em comum
    let a_words: std::collections::HashSet<&str> = a_lower.split_whitespace().collect();
    let b_words: std::collections::HashSet<&str> = b_lower.split_whitespace().collect();

    let intersection = a_words.intersection(&b_words).count();
    let union = a_words.union(&b_words).count();

    if union == 0 {
        0.0
    } else {
        intersection as f64 / union as f64
    }
}

/// Aplica estratégia Void para quebrar deadlock
///
/// Quando a feature `void` está habilitada, usa VoidNavigator real para navegação
/// no vazio ontológico e extração de insights. Caso contrário, usa fallback.
pub async fn handle_deadlock(run_id: &str, reason: &str, focus: &str) -> anyhow::Result<String> {
    info!(
        run_id = %run_id,
        reason = %reason,
        "VOID: Aplicando estratégia de quebra de deadlock"
    );

    #[cfg(feature = "void")]
    {
        info!("VOID: Usando VoidNavigator real (feature 'void' habilitada)");
        return handle_deadlock_with_void(run_id, reason, focus).await;
    }

    #[cfg(not(feature = "void"))]
    {
        warn!("VOID: Usando implementação fallback (feature 'void' não habilitada)");
        Ok(format!(
            "[VOID BREAK APPLIED - FALLBACK] {}\n\nInsight: Deadlock detectado. Considerando abordagem alternativa ou redução de contexto.\nPara navegação real no vazio ontológico, compile com: cargo build --features void",
            reason
        ))
    }
}

/// Implementação usando VoidNavigator real (requer feature `void`)
#[cfg(feature = "void")]
async fn handle_deadlock_with_void(run_id: &str, reason: &str, focus: &str) -> anyhow::Result<String> {
    // Criar orchestrator void com configurações padrão
    let orchestrator = Arc::new(VoidOrchestrator::new());

    // Determinar profundidade baseada na severidade do deadlock
    let target_depth = if std::env::var("BEAGLE_VOID_DEEP").is_ok() {
        8.0 // Navegação profunda para casos críticos
    } else {
        4.0 // Navegação padrão
    };

    info!(
        run_id = %run_id,
        target_depth = target_depth,
        "VOID: Iniciando navegação no vazio"
    );

    // Executar jornada completa no vazio
    match orchestrator.journey(target_depth).await {
        Ok(journey_result) => {
            info!(
                run_id = %run_id,
                max_depth = journey_result.navigation.max_depth_reached,
                num_extractions = journey_result.extractions.len(),
                "VOID: Navegação completa"
            );

            // Compilar insights extraídos
            let mut insights = Vec::new();

            // Insights da navegação
            for insight in &journey_result.navigation.insights {
                insights.push(format!(
                    "[Profundidade {:.2}] {} (confiança: {:.0}%)",
                    insight.depth_found,
                    insight.content,
                    insight.confidence * 100.0
                ));
            }

            // Insights das extrações
            for extraction in &journey_result.extractions {
                for info in &extraction.extracted_info {
                    insights.push(format!(
                        "[Extração {:?}] {} (certeza: {:.0}%)",
                        extraction.extraction_type,
                        info.content,
                        info.certainty * 100.0
                    ));
                }
            }

            // Resultado da sonda
            let probe_insight = if journey_result.probe_result.causal_effect.is_some() {
                format!(
                    "Efeito causal detectado: interferência quântica ativa (incerteza: {:.2})",
                    journey_result.probe_result.uncertainty
                )
            } else {
                format!(
                    "Medição estável: {:.2} (incerteza: {:.2})",
                    journey_result.probe_result.measurement,
                    journey_result.probe_result.uncertainty
                )
            };

            let insights_text = if insights.is_empty() {
                "Nenhum insight específico extraído (estado coerente)".to_string()
            } else {
                insights.join("\n• ")
            };

            Ok(format!(
                "[VOID BREAK APPLIED - NAVIGATOR REAL] {}\n\nFoco: '{}'\nProfundidade: {:.1}\nDuração: {} ms\n\nInsights do vazio:\n• {}\n\nSondagem: {}",
                reason,
                focus,
                journey_result.navigation.max_depth_reached,
                journey_result.navigation.duration_ms,
                insights_text,
                probe_insight
            ))
        }
        Err(e) => {
            warn!(
                run_id = %run_id,
                error = %e,
                "VOID: Erro na navegação, usando fallback"
            );
            Ok(format!(
                "[VOID BREAK APPLIED - PARTIAL] {}\n\nErro na navegação completa: {}.\nFallback: Deadlock detectado. Considerando abordagem alternativa.",
                reason,
                e
            ))
        }
    }
}
