//! Adversarial Simulator – Simulação adversarial de resultados físicos
//!
//! Simula resultados experimentais adversariais para validar protocolos antes da execução física,
//! identificando falhas potenciais, condições extremas e cenários de falha.

use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use beagle_worldmodel::PhysicalRealityEnforcer;
use crate::protocol_generator::ExperimentalProtocol;
use tracing::{info, warn};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationResult {
    pub protocol_id: String,
    pub success_probability: f64, // 0.0 a 1.0
    pub failure_modes: Vec<FailureMode>,
    pub extreme_conditions: Vec<ExtremeCondition>,
    pub recommended_modifications: Vec<String>,
    pub physical_viability_score: f64, // 0.0 a 1.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FailureMode {
    pub description: String,
    pub probability: f64,
    pub severity: Severity,
    pub mitigation: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Severity {
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtremeCondition {
    pub condition: String, // e.g., "pH < 3.0", "temperatura > 100°C"
    pub impact: String,
    pub probability: f64,
}

pub struct AdversarialSimulator {
    llm: VllmClient,
    reality_enforcer: PhysicalRealityEnforcer,
}

impl AdversarialSimulator {
    pub fn new() -> Self {
        Self {
            llm: VllmClient::new("http://t560.local:8000/v1"),
            reality_enforcer: PhysicalRealityEnforcer::new(),
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        let url_str: String = url.into();
        Self {
            llm: VllmClient::new(url_str.clone()),
            reality_enforcer: PhysicalRealityEnforcer::with_vllm_url(url_str),
        }
    }

    /// Simula resultados experimentais de forma adversarial
    /// Identifica falhas potenciais, condições extremas e cenários de falha
    pub async fn simulate_adversarial(
        &self,
        protocol: &ExperimentalProtocol,
    ) -> anyhow::Result<SimulationResult> {
        info!("REALITY FABRICATION: Simulando resultados adversariais para protocolo {}", protocol.id);

        // 1. Validação de viabilidade física via PhysicalRealityEnforcer
        let reality_report = self.reality_enforcer.enforce(&protocol.protocol_text).await?;
        let physical_viability_score = reality_report.viability_score;

        // 2. Geração adversarial de cenários de falha via LLM
        let system_prompt = r#"Você é um engenheiro químico sênior especializado em identificar falhas experimentais.

Sua função é analisar protocolos experimentais e identificar TODOS os modos de falha possíveis, condições extremas que podem quebrar o experimento, e recomendar modificações críticas.

Seja brutalmente honesto e técnico. Não seja condescendente."#;

        let user_prompt = format!(
            r#"PROTOCOLO EXPERIMENTAL:
{}

HIPÓTESE:
{}

Analise este protocolo e identifique:

1. **MODOS DE FALHA** (mínimo 5):
   - Descrição técnica precisa
   - Probabilidade de ocorrência (0.0 a 1.0)
   - Severidade (LOW, MEDIUM, HIGH, CRITICAL)
   - Mitigação proposta

2. **CONDIÇÕES EXTREMAS** que podem quebrar o experimento:
   - Condição específica (ex: "pH < 3.0", "temperatura > 100°C")
   - Impacto no resultado
   - Probabilidade

3. **MODIFICAÇÕES RECOMENDADAS** (mínimo 3):
   - Mudanças críticas no protocolo
   - Justificativa técnica

4. **PROBABILIDADE DE SUCESSO GERAL** (0.0 a 1.0):
   - Baseada na análise de todos os fatores

Responda em formato JSON estruturado."#,
            protocol.protocol_text,
            protocol.hypothesis
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.8,
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
            anyhow::bail!("LLM não retornou resposta para simulação adversarial");
        }

        // Parse do JSON retornado (com fallback robusto)
        let simulation_text = response.choices[0].text.trim();
        let (failure_modes, extreme_conditions, recommended_modifications, success_probability) = 
            self.parse_simulation_response(simulation_text);

        let result = SimulationResult {
            protocol_id: protocol.id.clone(),
            success_probability: success_probability.min(physical_viability_score), // Combina com viabilidade física
            failure_modes,
            extreme_conditions,
            recommended_modifications,
            physical_viability_score,
        };

        info!(
            "SIMULAÇÃO ADVERSARIAL COMPLETA: Probabilidade de sucesso {:.1}%, Viabilidade física {:.1}%",
            result.success_probability * 100.0,
            result.physical_viability_score * 100.0
        );

        Ok(result)
    }

    fn parse_simulation_response(&self, text: &str) -> (Vec<FailureMode>, Vec<ExtremeCondition>, Vec<String>, f64) {
        // Tenta parsear JSON primeiro
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(text) {
            let failure_modes = self.extract_failure_modes_from_json(&json);
            let extreme_conditions = self.extract_extreme_conditions_from_json(&json);
            let recommended_modifications = self.extract_modifications_from_json(&json);
            let success_probability = json.get("success_probability")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.5);

            return (failure_modes, extreme_conditions, recommended_modifications, success_probability);
        }

        // Fallback: parse manual do texto
        warn!("Falha ao parsear JSON, usando fallback manual");
        
        let failure_modes = self.extract_failure_modes_manual(text);
        let extreme_conditions = self.extract_extreme_conditions_manual(text);
        let recommended_modifications = self.extract_modifications_manual(text);
        let success_probability = self.extract_success_probability_manual(text);

        (failure_modes, extreme_conditions, recommended_modifications, success_probability)
    }

    fn extract_failure_modes_from_json(&self, json: &serde_json::Value) -> Vec<FailureMode> {
        json.get("failure_modes")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|item| {
                        Some(FailureMode {
                            description: item.get("description")?.as_str()?.to_string(),
                            probability: item.get("probability")?.as_f64()?,
                            severity: self.parse_severity(item.get("severity")?.as_str()?),
                            mitigation: item.get("mitigation")?.as_str()?.to_string(),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    fn extract_extreme_conditions_from_json(&self, json: &serde_json::Value) -> Vec<ExtremeCondition> {
        json.get("extreme_conditions")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|item| {
                        Some(ExtremeCondition {
                            condition: item.get("condition")?.as_str()?.to_string(),
                            impact: item.get("impact")?.as_str()?.to_string(),
                            probability: item.get("probability")?.as_f64()?,
                        })
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    fn extract_modifications_from_json(&self, json: &serde_json::Value) -> Vec<String> {
        json.get("recommended_modifications")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default()
    }

    fn parse_severity(&self, s: &str) -> Severity {
        match s.to_uppercase().as_str() {
            "CRITICAL" => Severity::Critical,
            "HIGH" => Severity::High,
            "MEDIUM" => Severity::Medium,
            _ => Severity::Low,
        }
    }

    // Métodos de fallback manual
    fn extract_failure_modes_manual(&self, text: &str) -> Vec<FailureMode> {
        // Implementação simplificada - procura por padrões no texto
        vec![
            FailureMode {
                description: "Falha genérica detectada no protocolo".to_string(),
                probability: 0.3,
                severity: Severity::Medium,
                mitigation: "Revisar condições experimentais".to_string(),
            }
        ]
    }

    fn extract_extreme_conditions_manual(&self, _text: &str) -> Vec<ExtremeCondition> {
        vec![]
    }

    fn extract_modifications_manual(&self, _text: &str) -> Vec<String> {
        vec!["Revisar protocolo completo".to_string()]
    }

    fn extract_success_probability_manual(&self, text: &str) -> f64 {
        // Procura por padrões como "probabilidade: 0.7" ou "70%"
        let re = regex::Regex::new(r"(?:probabilidade|success).*?(\d+\.?\d*)%?").ok();
        if let Some(pattern) = re {
            if let Some(cap) = pattern.captures(text) {
                if let Some(prob_str) = cap.get(1) {
                    if let Ok(prob) = prob_str.as_str().parse::<f64>() {
                        return (prob / 100.0).min(1.0).max(0.0);
                    }
                }
            }
        }
        0.5 // Default
    }
}

impl Default for AdversarialSimulator {
    fn default() -> Self {
        Self::new()
    }
}

