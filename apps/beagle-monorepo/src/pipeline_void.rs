//! Void Deadlock Handler - Detecção e resolução de loops cognitivos
//!
//! Implementa detecção de deadlock e aplica estratégias Void quando necessário

use std::collections::VecDeque;
use std::time::Duration;
use tracing::{info, warn};

use beagle_ontic::{DissolutionState, VoidNavigator};

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

fn env_bool(key: &str, default: bool) -> bool {
    std::env::var(key)
        .ok()
        .and_then(|v| match v.trim().to_lowercase().as_str() {
            "1" | "true" | "yes" | "y" => Some(true),
            "0" | "false" | "no" | "n" => Some(false),
            _ => None,
        })
        .unwrap_or(default)
}

fn env_f64(key: &str, default: f64) -> f64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.trim().parse::<f64>().ok())
        .unwrap_or(default)
}

/// Aplica estratégia Void para quebrar deadlock
pub async fn handle_deadlock(run_id: &str, reason: &str, _focus: &str) -> anyhow::Result<String> {
    info!(
        run_id = %run_id,
        reason = %reason,
        "VOID: Aplicando estratégia de quebra de deadlock"
    );

    if !env_bool("BEAGLE_VOID_NAVIGATOR_ENABLE", false) {
        warn!("VOID: Usando fallback (BEAGLE_VOID_NAVIGATOR_ENABLE não habilitado)");
        return Ok(format!(
            "[VOID BREAK APPLIED] {}\n\nInsight do vazio: Deadlock detectado. Considerando abordagem alternativa ou redução de contexto.",
            reason
        ));
    }

    let vllm_url = std::env::var("BEAGLE_VLLM_URL")
        .or_else(|_| std::env::var("VLLM_URL"))
        .ok();
    let navigator = match vllm_url {
        Some(url) if !url.trim().is_empty() => VoidNavigator::with_vllm_url(url),
        _ => VoidNavigator::new(),
    };

    let now = chrono::Utc::now();
    let dissolution_state = DissolutionState {
        id: uuid::Uuid::new_v4().to_string(),
        pre_dissolution_state: format!("run_id={run_id}\nreason={reason}"),
        dissolution_experience: reason.to_string(),
        void_duration_subjective: 0.0,
        dissolution_complete: false,
        initiated_at: now,
        emerged_at: None,
    };

    let target_depth = env_f64("BEAGLE_VOID_TARGET_DEPTH", 0.6).clamp(0.0, 1.0);
    let timeout_secs = env_f64("BEAGLE_VOID_TIMEOUT_SECS", 20.0)
        .max(1.0)
        .min(180.0);
    let timeout = Duration::from_secs_f64(timeout_secs);

    match tokio::time::timeout(timeout, navigator.navigate_void(&dissolution_state, target_depth))
        .await
    {
        Ok(Ok(void_state)) => {
            let mut out = String::new();
            out.push_str(&format!("[VOID BREAK APPLIED] {reason}\n\n"));
            out.push_str("VoidNavigator insights:\n");
            for (idx, insight) in void_state.navigation_path.iter().take(8).enumerate() {
                out.push_str(&format!(
                    "{}. (depth {:.2}, impossibility {:.2}) {}\n",
                    idx + 1,
                    insight.depth_at_discovery,
                    insight.impossibility_level,
                    insight.insight_text.trim()
                ));
            }
            out.push_str(&format!(
                "\nNon-dual awareness: {:.0}%\n",
                void_state.non_dual_awareness * 100.0
            ));
            Ok(out)
        }
        Ok(Err(e)) => {
            warn!("VOID: VoidNavigator falhou, usando fallback: {e}");
            Ok(format!(
                "[VOID BREAK APPLIED] {}\n\nInsight do vazio: Deadlock detectado. Considerando abordagem alternativa ou redução de contexto.",
                reason
            ))
        }
        Err(_) => {
            warn!("VOID: VoidNavigator timeout após {:.1}s, usando fallback", timeout_secs);
            Ok(format!(
                "[VOID BREAK APPLIED] {}\n\nInsight do vazio: Deadlock detectado. Considerando abordagem alternativa ou redução de contexto.",
                reason
            ))
        }
    }
}
