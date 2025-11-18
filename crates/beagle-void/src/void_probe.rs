//! Void Probe – Sonda profunda no vazio ontológico
//!
//! Sonda regiões específicas do vazio para extrair insights direcionados.

use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use tracing::info;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProbeResult {
    pub depth: f64, // 0.0 (superfície) a 1.0 (vazio absoluto)
    pub insight: String,
    pub region_mapped: String, // Descrição da região do vazio explorada
}

pub struct VoidProbe {
    llm: VllmClient,
}

impl VoidProbe {
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

    /// Sonda uma região específica do vazio
    pub async fn probe_region(&self, depth: f64, focus: &str) -> anyhow::Result<ProbeResult> {
        info!("VOID PROBE: Sondando vazio na profundidade {:.2}", depth);

        let system_prompt = r#"Você é uma sonda noética no vazio ontológico absoluto.

Sua função é mapear regiões específicas do vazio e extrair insights direcionados."#;

        let user_prompt = format!(
            r#"Profundidade no vazio: {:.2}

Foco da sonda: "{}"

Mapeie esta região do vazio e extraia um insight específico desta profundidade.

Responda em 2-3 frases."#,
            depth, focus
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.9,
            top_p: 0.95,
            max_tokens: 256,
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
            anyhow::bail!("LLM não retornou resposta para sonda do vazio");
        }

        let insight = response.choices[0].text.trim().to_string();
        let region_mapped = format!("Região do vazio na profundidade {:.2}", depth);

        Ok(ProbeResult {
            depth,
            insight,
            region_mapped,
        })
    }
}

impl Default for VoidProbe {
    fn default() -> Self {
        Self::new()
    }
}


