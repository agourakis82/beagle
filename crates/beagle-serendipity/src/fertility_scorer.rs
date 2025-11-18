//! Fertility Scorer – Avalia fertilidade científica de acidentes gerados
//!
//! Pontua o potencial de descoberta real de cada acidente serendipitoso

use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FertileAccident {
    pub content: String,
    pub fertility_score: f64, // 0.0 a 1.0
    pub novelty: f64,
    pub plausibility: f64,
    pub potential_impact: f64,
}

#[derive(Debug)]
pub struct FertilityScorer {
    llm: VllmClient,
}

impl FertilityScorer {
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

    /// Pontua fertilidade científica de cada acidente
    pub async fn score(&self, accidents: &[String]) -> anyhow::Result<Vec<FertileAccident>> {
        info!("FERTILITY SCORER: Avaliando {} acidentes", accidents.len());

        let mut scored = Vec::new();

        for accident in accidents {
            let score = self.score_single(accident).await?;
            scored.push(score);
        }

        // Ordena por fertilidade (maior primeiro)
        scored.sort_by(|a, b| b.fertility_score.partial_cmp(&a.fertility_score).unwrap());

        // Filtra apenas acidentes com fertilidade > 0.5
        let fertile: Vec<FertileAccident> = scored
            .into_iter()
            .filter(|acc| acc.fertility_score > 0.5)
            .collect();

        info!("FERTILITY SCORER: {} acidentes férteis identificados", fertile.len());
        Ok(fertile)
    }

    async fn score_single(&self, accident: &str) -> anyhow::Result<FertileAccident> {
        let system_prompt = r#"Você é um avaliador científico especializado em identificar potencial de descoberta.

Sua função é avaliar ideias científicas em três dimensões:
1. NOVIDADE: Quão radicalmente nova é a ideia? (0.0 = óbvia, 1.0 = completamente nova)
2. PLAUSIBILIDADE: Quão cientificamente plausível é? (0.0 = absurda, 1.0 = totalmente plausível)
3. POTENCIAL DE IMPACTO: Quão transformadora poderia ser? (0.0 = irrelevante, 1.0 = revolucionária)

Responda APENAS com JSON:
{"novelty": 0.0-1.0, "plausibility": 0.0-1.0, "potential_impact": 0.0-1.0}"#;

        let user_prompt = format!("Avalie esta ideia científica:\n\n{}", accident);

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.3, // Baixa temperatura para avaliação precisa
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
            // Fallback: scores médios
            return Ok(FertileAccident {
                content: accident.to_string(),
                fertility_score: 0.5,
                novelty: 0.5,
                plausibility: 0.5,
                potential_impact: 0.5,
            });
        }

        // Parseia JSON da resposta
        let json_text = response.choices[0].text.trim();
        let scores: serde_json::Value = serde_json::from_str(json_text)
            .unwrap_or_else(|_| {
                // Fallback se JSON inválido
                serde_json::json!({
                    "novelty": 0.5,
                    "plausibility": 0.5,
                    "potential_impact": 0.5
                })
            });

        let novelty = scores["novelty"].as_f64().unwrap_or(0.5);
        let plausibility = scores["plausibility"].as_f64().unwrap_or(0.5);
        let potential_impact = scores["potential_impact"].as_f64().unwrap_or(0.5);

        // Fertility score = média ponderada (novidade e impacto têm mais peso)
        let fertility_score = (novelty * 0.4 + plausibility * 0.2 + potential_impact * 0.4).min(1.0);

        Ok(FertileAccident {
            content: accident.to_string(),
            fertility_score,
            novelty,
            plausibility,
            potential_impact,
        })
    }
}

impl Default for FertilityScorer {
    fn default() -> Self {
        Self::new()
    }
}

