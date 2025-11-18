//! Competitor Simulation – Simula concorrentes trabalhando na mesma ideia
//!
//! Identifica ameaças de prioridade e competição direta

use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompetitorReport {
    pub threat_level: ThreatLevel,
    pub estimated_publication_date: String,
    pub competitive_advantage: Vec<String>,
    pub weaknesses: Vec<String>,
    pub recommendation: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum ThreatLevel {
    Low,      // Concorrente distante ou fraco
    Medium,    // Concorrente moderado
    High,      // Concorrente forte, mesma timeline
    Critical, // Concorrente pode publicar antes
}

pub struct CompetitorAgent {
    llm: VllmClient,
}

impl CompetitorAgent {
    pub fn new() -> Self {
        Self {
            llm: VllmClient::default(),
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        Self {
            llm: VllmClient::new(url),
        }
    }

    /// Simula análise de concorrentes potenciais
    pub async fn analyze_competition(
        &self,
        research_question: &str,
        our_approach: &str,
    ) -> anyhow::Result<CompetitorReport> {
        info!("COMPETITOR AGENT: Analisando competição");

        let system_prompt = r#"Você é um analista estratégico científico especializado em identificar competição e ameaças de prioridade.

Analise a pesquisa proposta e identifique:
1. Nível de ameaça de concorrentes
2. Timeline estimada de publicação de concorrentes
3. Vantagens competitivas da nossa abordagem
4. Fraquezas que concorrentes podem explorar
5. Recomendação estratégica

Seja realista e estratégico."#;

        let user_prompt = format!(
            r#"PESQUISA PROPOSTA:
{}

NOSSA ABORDAGEM:
{}

Analise a competição e forneça um relatório estratégico."#,
            research_question, our_approach
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
            // Fallback
            return Ok(CompetitorReport {
                threat_level: ThreatLevel::Medium,
                estimated_publication_date: "6-12 months".to_string(),
                competitive_advantage: vec!["Approach is novel".to_string()],
                weaknesses: vec!["Limited experimental validation".to_string()],
                recommendation: "Accelerate publication timeline".to_string(),
            });
        }

        let analysis_text = response.choices[0].text.trim();

        // Parseia o nível de ameaça
        let threat_level = if analysis_text.to_lowercase().contains("critical") || 
                            analysis_text.to_lowercase().contains("urgent") {
            ThreatLevel::Critical
        } else if analysis_text.to_lowercase().contains("high") {
            ThreatLevel::High
        } else if analysis_text.to_lowercase().contains("low") {
            ThreatLevel::Low
        } else {
            ThreatLevel::Medium
        };

        Ok(CompetitorReport {
            threat_level,
            estimated_publication_date: "6-12 months".to_string(), // Placeholder
            competitive_advantage: vec!["Novel approach".to_string()],
            weaknesses: vec!["Requires validation".to_string()],
            recommendation: analysis_text.to_string(),
        })
    }
}

impl Default for CompetitorAgent {
    fn default() -> Self {
        Self::new()
    }
}

