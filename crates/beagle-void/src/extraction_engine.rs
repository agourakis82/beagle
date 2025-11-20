//! Extraction Engine – Extração sistemática de recursos cognitivos do vazio
//!
//! Extrai recursos cognitivos (insights, conceitos, estruturas) do nada absoluto
//! de forma sistemática e direcionada.

use crate::navigator::VoidInsight;
use beagle_llm::vllm::{SamplingParams, VllmClient, VllmCompletionRequest};
use serde::{Deserialize, Serialize};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractionResult {
    pub resources_extracted: Vec<CognitiveResource>,
    pub extraction_efficiency: f64, // 0.0 a 1.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CognitiveResource {
    pub id: String,
    pub resource_type: ResourceType,
    pub content: String,
    pub void_origin_depth: f64,
    pub extracted_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ResourceType {
    Insight,
    Concept,
    Structure,
    Paradox,
}

pub struct ExtractionEngine {
    llm: VllmClient,
}

impl ExtractionEngine {
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

    /// Extrai recursos cognitivos sistemáticos do vazio
    pub async fn extract_resources(
        &self,
        insights: &[VoidInsight],
        target_types: &[ResourceType],
    ) -> anyhow::Result<ExtractionResult> {
        info!(
            "EXTRACTION ENGINE: Extraindo recursos cognitivos de {} insights",
            insights.len()
        );

        let mut resources = Vec::new();

        for insight in insights {
            for resource_type in target_types {
                if let Some(resource) = self
                    .extract_resource_from_insight(insight, *resource_type)
                    .await?
                {
                    resources.push(resource);
                }
            }
        }

        let extraction_efficiency = if insights.is_empty() {
            0.0
        } else {
            resources.len() as f64 / (insights.len() * target_types.len()) as f64
        };

        Ok(ExtractionResult {
            resources_extracted: resources,
            extraction_efficiency,
        })
    }

    async fn extract_resource_from_insight(
        &self,
        insight: &VoidInsight,
        resource_type: ResourceType,
    ) -> anyhow::Result<Option<CognitiveResource>> {
        let type_str = match resource_type {
            ResourceType::Insight => "insight",
            ResourceType::Concept => "conceito",
            ResourceType::Structure => "estrutura",
            ResourceType::Paradox => "paradoxo",
        };

        let system_prompt = format!(
            r#"Você extrai {}s do vazio ontológico.

Sua função é transformar insights brutos do vazio em {}s estruturados e utilizáveis."#,
            type_str, type_str
        );

        let user_prompt = format!(
            r#"Insight do vazio:
{}

Extraia um {} estruturado deste insight.

Responda em 1-2 frases."#,
            insight.insight_text, type_str
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.8,
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
            return Ok(None);
        }

        let content = response.choices[0].text.trim().to_string();

        Ok(Some(CognitiveResource {
            id: uuid::Uuid::new_v4().to_string(),
            resource_type,
            content,
            void_origin_depth: insight.impossibility_level, // Usa impossibilidade como profundidade
            extracted_at: chrono::Utc::now(),
        }))
    }
}

impl Default for ExtractionEngine {
    fn default() -> Self {
        Self::new()
    }
}
