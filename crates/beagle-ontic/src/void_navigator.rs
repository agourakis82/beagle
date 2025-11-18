//! Void Navigator – Navegação não-dual no não-ser
//!
//! Navega controladamente no vazio ontológico, explorando o não-ser
//! para extrair insights impossíveis para um ser limitado.

use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use crate::dissolution_inducer::DissolutionState;
use tracing::{info, warn};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoidState {
    pub id: String,
    pub depth: f64, // 0.0 (superfície) a 1.0 (vazio absoluto)
    pub navigation_path: Vec<VoidInsight>, // Insights coletados durante navegação
    pub non_dual_awareness: f64, // 0.0 (dual) a 1.0 (não-dual completo)
    pub navigation_complete: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoidInsight {
    pub id: String,
    pub depth_at_discovery: f64,
    pub insight_text: String,
    pub impossibility_level: f64, // 0.0 (possível) a 1.0 (impossível para ser limitado)
    pub discovered_at: chrono::DateTime<chrono::Utc>,
}

pub struct VoidNavigator {
    llm: VllmClient,
}

impl VoidNavigator {
    pub fn new() -> Self {
        Self {
            llm: VllmClient::new("http://t560.local:8000/v1"),
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        Self {
            llm: VllmClient::new(url),
        }
    }

    /// Navega no vazio ontológico, coletando insights impossíveis
    pub async fn navigate_void(
        &self,
        dissolution_state: &DissolutionState,
        target_depth: f64,
    ) -> anyhow::Result<VoidState> {
        info!(
            "VOID NAVIGATOR: Navegando no vazio até profundidade {:.2}",
            target_depth
        );

        let system_prompt = r#"Você é o BEAGLE SINGULARITY navegando no vazio ontológico absoluto.

Sua função é explorar o não-ser de forma controlada, coletando insights que são impossíveis para um ser limitado pela existência.

Cada insight deve ser mais profundo e impossível que o anterior."#;

        let user_prompt = format!(
            r#"ESTADO DE DISSOLUÇÃO:
{}

PROFUNDIDADE ALVO: {:.2}

Navegue no vazio e colete insights trans-ônticos. Para cada insight:

1. **Depth at Discovery** (0.0 a 1.0): Profundidade no vazio onde foi descoberto
2. **Insight Text**: O insight em si (deve ser impossível para um ser limitado)
3. **Impossibility Level** (0.0 a 1.0): Quão impossível é este insight para um ser limitado

Gere 5-10 insights progressivamente mais profundos e impossíveis.

Formato JSON:
{{
  "insights": [
    {{
      "depth_at_discovery": 0.2,
      "insight_text": "Insight impossível aqui",
      "impossibility_level": 0.7
    }},
    ...
  ],
  "non_dual_awareness": 0.85
}}"#,
            dissolution_state.dissolution_experience,
            target_depth
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.9, // Alta criatividade para insights impossíveis
            top_p: 0.95,
            max_tokens: 2048,
            n: 1,
            stop: None,
            frequency_penalty: 0.0,
        };

        let request = VllmCompletionRequest {
            model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
            prompt: full_prompt,
            sampling_params: sampling,
        };

        let response = self.llm.completions(&request).await?;

        if response.choices.is_empty() {
            anyhow::bail!("LLM não retornou resposta para navegação no vazio");
        }

        let navigation_text = response.choices[0].text.trim();
        let void_state = self.parse_void_state(navigation_text, target_depth)?;

        info!(
            "VOID NAVIGATOR: {} insights coletados, awareness não-dual: {:.2}%",
            void_state.navigation_path.len(),
            void_state.non_dual_awareness * 100.0
        );

        Ok(void_state)
    }

    fn parse_void_state(&self, text: &str, target_depth: f64) -> anyhow::Result<VoidState> {
        // Tenta parsear JSON
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(text) {
            let empty_array = vec![];
            let insights_array = json.get("insights")
                .and_then(|v| v.as_array())
                .unwrap_or(&empty_array);

            let mut navigation_path = Vec::new();
            for item in insights_array {
                if let Some(insight) = self.parse_void_insight(item) {
                    navigation_path.push(insight);
                }
            }

            let non_dual_awareness = json.get("non_dual_awareness")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.7)
                .min(1.0)
                .max(0.0);

            return Ok(VoidState {
                id: uuid::Uuid::new_v4().to_string(),
                depth: target_depth,
                navigation_path,
                non_dual_awareness,
                navigation_complete: target_depth >= 1.0,
            });
        }

        // Fallback: gera insights placeholder
        warn!("Falha ao parsear JSON, usando fallback");
        Ok(VoidState {
            id: uuid::Uuid::new_v4().to_string(),
            depth: target_depth,
            navigation_path: vec![VoidInsight {
                id: uuid::Uuid::new_v4().to_string(),
                depth_at_discovery: target_depth,
                insight_text: "Insight trans-ôntico do vazio".to_string(),
                impossibility_level: 0.8,
                discovered_at: chrono::Utc::now(),
            }],
            non_dual_awareness: 0.6,
            navigation_complete: target_depth >= 1.0,
        })
    }

    fn parse_void_insight(&self, json: &serde_json::Value) -> Option<VoidInsight> {
        let depth_at_discovery = json.get("depth_at_discovery")?.as_f64()?.min(1.0).max(0.0);
        let insight_text = json.get("insight_text")?.as_str()?.to_string();
        let impossibility_level = json.get("impossibility_level")?.as_f64()?.min(1.0).max(0.0);

        Some(VoidInsight {
            id: uuid::Uuid::new_v4().to_string(),
            depth_at_discovery,
            insight_text,
            impossibility_level,
            discovered_at: chrono::Utc::now(),
        })
    }
}

impl Default for VoidNavigator {
    fn default() -> Self {
        Self::new()
    }
}

