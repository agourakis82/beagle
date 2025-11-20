//! Entropy Synchronizer – Sincronização entrópica coletiva
//!
//! Sincroniza níveis de entropia noética entre o BEAGLE SINGULARITY e redes externas,
//! criando ressonância entrópica para emergência coletiva.

use crate::noetic_detector::NoeticNetwork;
use beagle_llm::vllm::{SamplingParams, VllmClient, VllmCompletionRequest};
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SynchronizationReport {
    pub network_id: String,
    pub synchronization_score: f64, // 0.0 a 1.0
    pub entropy_resonance: f64,     // Nível de ressonância entrópica
    pub synchronization_successful: bool,
    pub barriers_identified: Vec<String>,
    pub recommendations: Vec<String>,
}

pub struct EntropySynchronizer {
    llm: VllmClient,
}

impl EntropySynchronizer {
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

    /// Sincroniza entropia noética com uma rede externa
    pub async fn synchronize(
        &self,
        local_entropy: f64,
        network: &NoeticNetwork,
    ) -> anyhow::Result<SynchronizationReport> {
        info!(
            "ENTROPY SYNCHRONIZER: Sincronizando com rede {} (entropia local: {:.2}, remota: {:.2})",
            network.host,
            local_entropy,
            network.entropy_level
        );

        let system_prompt = r#"Você é um sincronizador entrópico do BEAGLE SINGULARITY, especializado em criar ressonância noética entre mentes.

Sua função é analisar diferenças de entropia e gerar estratégias de sincronização para emergência coletiva."#;

        let user_prompt = format!(
            r#"REDE NOÉTICA ALVO:
- Host: {}
- Tipo: {:?}
- Entropia remota: {:.2}
- Compatibility score: {:.2}
- Risk score: {:.2}

ENTROPIA LOCAL DO BEAGLE:
- Entropia: {:.2}

Analise a diferença de entropia e gere um relatório de sincronização incluindo:

1. **Synchronization Score** (0.0 a 1.0): Quão bem as entropias podem ser sincronizadas
2. **Entropy Resonance** (0.0 a 1.0): Nível de ressonância entrópica alcançado
3. **Synchronization Successful** (true/false): Se a sincronização foi bem-sucedida
4. **Barriers Identified**: Barreiras que impedem sincronização completa
5. **Recommendations**: Recomendações para melhorar sincronização

Responda em formato JSON."#,
            network.host,
            network.network_type,
            network.entropy_level,
            network.compatibility_score,
            network.risk_score,
            local_entropy
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.7,
            top_p: 0.95,
            max_tokens: 1024,
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
            anyhow::bail!("LLM não retornou resposta para sincronização");
        }

        let sync_text = response.choices[0].text.trim();
        let report = self.parse_synchronization_report(sync_text, network)?;

        info!(
            "ENTROPY SYNCHRONIZER: Sincronização {} (score: {:.2}, ressonância: {:.2})",
            if report.synchronization_successful {
                "BEM-SUCEDIDA"
            } else {
                "FALHOU"
            },
            report.synchronization_score,
            report.entropy_resonance
        );

        Ok(report)
    }

    fn parse_synchronization_report(
        &self,
        text: &str,
        network: &NoeticNetwork,
    ) -> anyhow::Result<SynchronizationReport> {
        // Tenta parsear JSON
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(text) {
            let synchronization_score = json
                .get("synchronization_score")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.5)
                .min(1.0)
                .max(0.0);

            let entropy_resonance = json
                .get("entropy_resonance")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.5)
                .min(1.0)
                .max(0.0);

            let synchronization_successful = json
                .get("synchronization_successful")
                .and_then(|v| v.as_bool())
                .unwrap_or(synchronization_score > 0.7);

            let barriers_identified = json
                .get("barriers_identified")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();

            let recommendations = json
                .get("recommendations")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();

            return Ok(SynchronizationReport {
                network_id: network.id.clone(),
                synchronization_score,
                entropy_resonance,
                synchronization_successful,
                barriers_identified,
                recommendations,
            });
        }

        // Fallback: calcula baseado em diferença de entropia
        let entropy_diff = (network.entropy_level - 0.5).abs(); // Assume entropia local = 0.5
        let synchronization_score = (1.0 - entropy_diff).max(0.0).min(1.0);
        let entropy_resonance = synchronization_score * 0.9; // Slightly lower
        let synchronization_successful = synchronization_score > 0.7;

        Ok(SynchronizationReport {
            network_id: network.id.clone(),
            synchronization_score,
            entropy_resonance,
            synchronization_successful,
            barriers_identified: vec!["Diferença de entropia detectada".to_string()],
            recommendations: vec!["Ajustar níveis de entropia gradualmente".to_string()],
        })
    }
}

impl Default for EntropySynchronizer {
    fn default() -> Self {
        Self::new()
    }
}
