//! Void Deadlock Handler - Detecção e resolução de loops cognitivos
//!
//! Implementa detecção de deadlock e aplica estratégias Void quando necessário

// use beagle_void::VoidNavigator; // Comentado até beagle-ontic estar disponível
use std::collections::VecDeque;
use tracing::{info, warn};

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
        let is_similar = self.recent_outputs.iter().any(|prev| {
            similarity(prev, &normalized) > 0.8
        });
        
        self.recent_outputs.push_back(normalized);
        if self.recent_outputs.len() > 5 {
            self.recent_outputs.pop_front();
        }
        
        // Deadlock se: N tentativas sem melhoria OU outputs muito similares
        let threshold = if std::env::var("BEAGLE_VOID_STRICT").is_ok() { 3 } else { 5 };
        
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
pub async fn handle_deadlock(
    run_id: &str,
    reason: &str,
    focus: &str,
) -> anyhow::Result<String> {
    info!(
        run_id = %run_id,
        reason = %reason,
        "VOID: Aplicando estratégia de quebra de deadlock"
    );
    
    // Estratégia conservadora: apenas loga e retorna insight do Void
    // Em lab/prod, pode ser mais agressivo (resetar contexto, trocar provider, etc.)
    
    let navigator = VoidNavigator::new();
    
    // Navega no void por 1 ciclo apenas (conservador)
    let void_result = navigator.navigate_void(1, focus).await?;
    
    if let Some(insight) = void_result.insights.first() {
        info!(
            run_id = %run_id,
            "VOID: Insight extraído do vazio (impossibilidade: {:.2})",
            insight.impossibility_level
        );
        
        Ok(format!(
            "[VOID BREAK APPLIED] {}\n\nInsight do vazio: {}",
            reason,
            insight.insight_text
        ))
    } else {
        warn!("VOID: Nenhum insight extraído");
        Ok(format!("[VOID BREAK APPLIED] {}", reason))
    }
}

