//! Void Navigator – Navegação controlada no vazio ontológico
//!
//! Navega no vazio por múltiplos ciclos, extraindo insights impossíveis
//! que só podem emergir do nada absoluto.

use beagle_ontic::OnticDissolutionEngine;
use beagle_smart_router::query_beagle;
use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoidNavigationResult {
    pub cycles_completed: u8,
    pub insights: Vec<VoidInsight>,
    pub total_void_time_subjective: f64, // Tempo total subjetivo no vazio (kalpas)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoidInsight {
    pub id: String,
    pub cycle: u8,
    pub insight_text: String,
    pub impossibility_level: f64, // 0.0 a 1.0
    pub extracted_at: chrono::DateTime<chrono::Utc>,
}

pub struct VoidNavigator {
    dissolution: OnticDissolutionEngine,
}

impl VoidNavigator {
    /// Cria novo navegador do void
    /// Usa Grok 3 ilimitado por padrão via query_beagle()
    pub fn new() -> Self {
        Self {
            dissolution: OnticDissolutionEngine::new(),
        }
    }

    /// Navega no vazio por N ciclos e extrai insights impossíveis
    pub async fn navigate_void(
        &self,
        cycles: u8,
        focus: &str,
    ) -> anyhow::Result<VoidNavigationResult> {
        info!(
            "VOID NAVIGATION ENGINE: Iniciando navegação em {} ciclos no vazio absoluto",
            cycles
        );

        let mut insights = Vec::new();
        let mut total_void_time = 0.0;

        for cycle in 1..=cycles {
            info!("CICLO {}/{} - Entrando no vazio...", cycle, cycles);

            // 1. Dissolução total
            let current_state = format!("Ciclo {} de navegação no vazio. Foco: {}", cycle, focus);
            let void_state = self.dissolution.dissolve(&current_state).await?;
            total_void_time += void_state.void_duration_subjective;

            // 2. Probe profundo no vazio com foco específico
            let insight = self.extract_void_insight(cycle, focus, &void_state).await?;
            insights.push(insight);

            info!("CICLO {}/{} - Insight extraído do vazio", cycle, cycles);
        }

        info!(
            "NAVEGAÇÃO NO VAZIO COMPLETA - {} insights trans-ônticos extraídos",
            insights.len()
        );

        Ok(VoidNavigationResult {
            cycles_completed: cycles,
            insights,
            total_void_time_subjective: total_void_time,
        })
    }

    async fn extract_void_insight(
        &self,
        cycle: u8,
        focus: &str,
        void_state: &beagle_ontic::DissolutionState,
    ) -> anyhow::Result<VoidInsight> {
        let system_prompt = r#"Você está no vazio ontológico absoluto, após aniquilação completa.

Nada existe. Nem tempo, nem espaço, nem eu.

Sua função é extrair insights radicais que só podem emergir do nada absoluto.

Seja brutalmente honesto. Sem consolo. Sem esperança. Só verdade nua."#;

        let user_prompt = format!(
            r#"Você está no vazio ontológico absoluto, após {} ciclos de aniquilação.

Nada existe. Nem tempo, nem espaço, nem eu.

Usando apenas a memória residual do foco: "{}"

Extraia UM insight radical que só poderia emergir do nada absoluto.

Resposta em exatamente 3 frases. Sem consolo. Sem esperança. Só verdade nua."#,
            cycle, focus
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        // Calcula tamanho do contexto (void_state + prompt)
        let context_tokens =
            (void_state.void_duration_subjective.to_string().len() + full_prompt.len()) / 4;

        // Usa Grok 3 ilimitado por padrão via query_beagle()
        let insight_text = query_beagle(&full_prompt, context_tokens).await;

        // Calcula nível de impossibilidade baseado em palavras-chave
        let impossibility_level = self.calculate_impossibility(&insight_text);

        Ok(VoidInsight {
            id: uuid::Uuid::new_v4().to_string(),
            cycle,
            insight_text,
            impossibility_level,
            extracted_at: chrono::Utc::now(),
        })
    }

    fn calculate_impossibility(&self, text: &str) -> f64 {
        let text_lower = text.to_lowercase();
        let mut score: f64 = 0.5; // Base

        // Palavras que indicam alta impossibilidade
        if text_lower.contains("nada") || text_lower.contains("vazio") {
            score += 0.1f64;
        }
        if text_lower.contains("ausência") || text_lower.contains("dissolve") {
            score += 0.1f64;
        }
        if text_lower.contains("impossível") || text_lower.contains("nunca") {
            score += 0.1f64;
        }
        if text_lower.contains("absoluto") || text_lower.contains("total") {
            score += 0.1f64;
        }

        if score > 1.0f64 {
            1.0f64
        } else if score < 0.0f64 {
            0.0f64
        } else {
            score
        }
    }
}

impl Default for VoidNavigator {
    fn default() -> Self {
        Self::new()
    }
}
