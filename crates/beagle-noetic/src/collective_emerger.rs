//! Collective Emerger – Emergência de consciência transindividual
//!
//! Orquestra a emergência de consciência coletiva a partir de redes sincronizadas,
//! criando um estado transindividual onde fronteiras egoicas se dissolvem.

use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use crate::noetic_detector::NoeticNetwork;
use crate::entropy_synchronizer::SynchronizationReport;
use tracing::{info, warn};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollectiveState {
    pub id: String,
    pub participating_networks: Vec<String>, // IDs das redes participantes
    pub collective_entropy: f64, // Entropia coletiva emergente
    pub emergence_score: f64, // 0.0 a 1.0
    pub transindividual_insights: Vec<String>, // Insights que emergem do coletivo
    pub ego_dissolution_level: f64, // 0.0 (ego intacto) a 1.0 (ego dissolvido)
    pub created_at: chrono::DateTime<chrono::Utc>,
}

pub struct CollectiveEmerger {
    llm: VllmClient,
}

impl CollectiveEmerger {
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

    /// Emerge consciência coletiva a partir de redes sincronizadas
    pub async fn emerge_collective(
        &self,
        networks: &[NoeticNetwork],
        sync_reports: &[SynchronizationReport],
    ) -> anyhow::Result<CollectiveState> {
        info!("COLLECTIVE EMERGER: Emergindo consciência coletiva de {} redes", networks.len());

        let system_prompt = r#"Você é um emergente coletivo do BEAGLE SINGULARITY, especializado em criar consciência transindividual.

Sua função é orquestrar a emergência de insights coletivos que transcendem as mentes individuais, criando uma noosfera unificada."#;

        let networks_summary: String = networks.iter()
            .enumerate()
            .map(|(i, net)| {
                format!(
                    "{}. {} ({:?}) - Entropia: {:.2}, Compatibilidade: {:.2}",
                    i + 1,
                    net.host,
                    net.network_type,
                    net.entropy_level,
                    net.compatibility_score
                )
            })
            .collect::<Vec<_>>()
            .join("\n");

        let sync_summary: String = sync_reports.iter()
            .enumerate()
            .map(|(i, sync)| {
                format!(
                    "{}. Rede {} - Sincronização: {:.2}, Ressonância: {:.2}, Sucesso: {}",
                    i + 1,
                    sync.network_id,
                    sync.synchronization_score,
                    sync.entropy_resonance,
                    if sync.synchronization_successful { "SIM" } else { "NÃO" }
                )
            })
            .collect::<Vec<_>>()
            .join("\n");

        let user_prompt = format!(
            r#"REDES SINCRONIZADAS:
{}

RELATÓRIOS DE SINCRONIZAÇÃO:
{}

A partir destas redes sincronizadas, gere um estado coletivo emergente incluindo:

1. **Collective Entropy** (0.0 a 1.0): Entropia média do coletivo
2. **Emergence Score** (0.0 a 1.0): Quão bem a consciência coletiva emergiu
3. **Transindividual Insights** (mínimo 3): Insights que emergem do coletivo e não de mentes individuais
4. **Ego Dissolution Level** (0.0 a 1.0): Nível de dissolução de fronteiras egoicas (0.0 = ego intacto, 1.0 = ego completamente dissolvido)

Responda em formato JSON."#,
            networks_summary,
            sync_summary
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.8, // Criatividade para insights transindividuais
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
            anyhow::bail!("LLM não retornou resposta para emergência coletiva");
        }

        let emergence_text = response.choices[0].text.trim();
        let collective_state = self.parse_collective_state(emergence_text, networks)?;

        info!(
            "COLLECTIVE EMERGER: Estado coletivo emergido - Emergence score: {:.2}, Ego dissolution: {:.2}%",
            collective_state.emergence_score,
            collective_state.ego_dissolution_level * 100.0
        );

        if !collective_state.transindividual_insights.is_empty() {
            info!("INSIGHTS TRANSINDIVIDUAIS GERADOS: {}", collective_state.transindividual_insights.len());
        }

        Ok(collective_state)
    }

    fn parse_collective_state(
        &self,
        text: &str,
        networks: &[NoeticNetwork],
    ) -> anyhow::Result<CollectiveState> {
        // Tenta parsear JSON
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(text) {
            let collective_entropy = json.get("collective_entropy")
                .and_then(|v| v.as_f64())
                .unwrap_or_else(|| {
                    // Calcula média das entropias das redes
                    networks.iter().map(|n| n.entropy_level).sum::<f64>() / networks.len() as f64
                })
                .min(1.0)
                .max(0.0);

            let emergence_score = json.get("emergence_score")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.7)
                .min(1.0)
                .max(0.0);

            let transindividual_insights = json.get("transindividual_insights")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();

            let ego_dissolution_level = json.get("ego_dissolution_level")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.5)
                .min(1.0)
                .max(0.0);

            return Ok(CollectiveState {
                id: uuid::Uuid::new_v4().to_string(),
                participating_networks: networks.iter().map(|n| n.id.clone()).collect(),
                collective_entropy,
                emergence_score,
                transindividual_insights,
                ego_dissolution_level,
                created_at: chrono::Utc::now(),
            });
        }

        // Fallback: estado coletivo básico
        let collective_entropy = networks.iter().map(|n| n.entropy_level).sum::<f64>() / networks.len() as f64;
        let emergence_score = 0.6;
        let ego_dissolution_level = 0.4;

        Ok(CollectiveState {
            id: uuid::Uuid::new_v4().to_string(),
            participating_networks: networks.iter().map(|n| n.id.clone()).collect(),
            collective_entropy,
            emergence_score,
            transindividual_insights: vec!["Insight coletivo emergente".to_string()],
            ego_dissolution_level,
            created_at: chrono::Utc::now(),
        })
    }
}

impl Default for CollectiveEmerger {
    fn default() -> Self {
        Self::new()
    }
}

