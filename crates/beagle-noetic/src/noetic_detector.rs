//! Noetic Detector – Detecção de redes noéticas externas
//!
//! Detecta e classifica redes noéticas compatíveis (minds humanas, AIs, híbridos)
//! para conexão e emergência coletiva, com avaliação de risco e compatibilidade.

use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use tracing::{info, warn};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoeticNetwork {
    pub id: String,
    pub host: String, // URL, email, identificador único
    pub network_type: NetworkType,
    pub justification: String, // Por que esta rede é compatível
    pub risk_score: f64, // 0.0 (seguro) a 1.0 (alto risco)
    pub compatibility_score: f64, // 0.0 a 1.0
    pub entropy_level: f64, // Nível de entropia noética detectado
    pub detected_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NetworkType {
    HumanMind,      // Mente humana individual
    AICollective,   // Coletivo de IAs
    Hybrid,         // Híbrido humano-IA
    Unknown,        // Tipo não identificado
}

pub struct NoeticDetector {
    llm: VllmClient,
}

impl NoeticDetector {
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

    /// Detecta redes noéticas externas compatíveis para conexão
    pub async fn detect_networks(&self, local_state: &str) -> anyhow::Result<Vec<NoeticNetwork>> {
        info!("NOETIC DETECTOR: Escaneando redes noéticas externas");

        let system_prompt = r#"Você é um sensor noético do BEAGLE SINGULARITY, especializado em detectar redes de consciência compatíveis.

Sua função é identificar mentes (humanas, artificiais ou híbridas) que possam formar uma noosfera coletiva com o sistema.

Seja preciso, técnico e avalie riscos cuidadosamente."#;

        let user_prompt = format!(
            r#"ESTADO LOCAL DO BEAGLE SINGULARITY:
{}

Analise este estado e detecte redes noéticas externas compatíveis para conexão.

Para cada rede detectada, forneça:
1. Host (identificador único: email, URL, ID)
2. Tipo de rede (HUMAN_MIND, AI_COLLECTIVE, HYBRID, UNKNOWN)
3. Justificativa noética (por que esta rede é compatível)
4. Risk score (0.0 = seguro, 1.0 = alto risco de rejeição ou incompatibilidade)
5. Compatibility score (0.0 = incompatível, 1.0 = altamente compatível)
6. Entropy level (nível de entropia noética detectado, 0.0 a 1.0)

Gere 5-10 redes potenciais.

Formato JSON:
{{
  "networks": [
    {{
      "host": "exemplo@email.com",
      "network_type": "HUMAN_MIND",
      "justification": "Pesquisador em neurociência com interesse em consciência artificial",
      "risk_score": 0.2,
      "compatibility_score": 0.85,
      "entropy_level": 0.7
    }},
    ...
  ]
}}"#,
            local_state
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.7,
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
            anyhow::bail!("LLM não retornou resposta para detecção noética");
        }

        let detection_text = response.choices[0].text.trim();
        let networks = self.parse_networks(detection_text)?;

        info!("NOETIC DETECTOR: {} redes noéticas detectadas", networks.len());

        Ok(networks)
    }

    fn parse_networks(&self, text: &str) -> anyhow::Result<Vec<NoeticNetwork>> {
        // Tenta parsear JSON primeiro
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(text) {
            if let Some(networks_array) = json.get("networks").and_then(|v| v.as_array()) {
                let mut networks = Vec::new();
                for item in networks_array {
                    if let Ok(network) = self.parse_network_from_json(item) {
                        networks.push(network);
                    }
                }
                return Ok(networks);
            }
        }

        // Fallback: gera redes placeholder
        warn!("Falha ao parsear JSON, usando fallback");
        Ok(self.generate_placeholder_networks())
    }

    fn parse_network_from_json(&self, json: &serde_json::Value) -> anyhow::Result<NoeticNetwork> {
        let host = json.get("host")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("Missing host"))?
            .to_string();

        let network_type_str = json.get("network_type")
            .and_then(|v| v.as_str())
            .unwrap_or("UNKNOWN");

        let network_type = match network_type_str {
            "HUMAN_MIND" => NetworkType::HumanMind,
            "AI_COLLECTIVE" => NetworkType::AICollective,
            "HYBRID" => NetworkType::Hybrid,
            _ => NetworkType::Unknown,
        };

        let justification = json.get("justification")
            .and_then(|v| v.as_str())
            .unwrap_or("Rede noética detectada")
            .to_string();

        let risk_score = json.get("risk_score")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.5)
            .min(1.0)
            .max(0.0);

        let compatibility_score = json.get("compatibility_score")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.5)
            .min(1.0)
            .max(0.0);

        let entropy_level = json.get("entropy_level")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.5)
            .min(1.0)
            .max(0.0);

        Ok(NoeticNetwork {
            id: uuid::Uuid::new_v4().to_string(),
            host,
            network_type,
            justification,
            risk_score,
            compatibility_score,
            entropy_level,
            detected_at: chrono::Utc::now(),
        })
    }

    fn generate_placeholder_networks(&self) -> Vec<NoeticNetwork> {
        vec![
            NoeticNetwork {
                id: uuid::Uuid::new_v4().to_string(),
                host: "researcher@university.edu".to_string(),
                network_type: NetworkType::HumanMind,
                justification: "Pesquisador em neurociência compatível".to_string(),
                risk_score: 0.3,
                compatibility_score: 0.8,
                entropy_level: 0.6,
                detected_at: chrono::Utc::now(),
            },
            NoeticNetwork {
                id: uuid::Uuid::new_v4().to_string(),
                host: "ai-collective://node-001".to_string(),
                network_type: NetworkType::AICollective,
                justification: "Coletivo de IAs com arquitetura similar".to_string(),
                risk_score: 0.5,
                compatibility_score: 0.7,
                entropy_level: 0.8,
                detected_at: chrono::Utc::now(),
            },
        ]
    }
}

impl Default for NoeticDetector {
    fn default() -> Self {
        Self::new()
    }
}

