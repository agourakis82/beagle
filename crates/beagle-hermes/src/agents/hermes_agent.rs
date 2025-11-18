//! HERMES: Draft generation and writing agent

use super::athena::Paper;
use crate::{synthesis::VoiceProfile, Result};
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::info;

pub struct HermesAgent {
    llm_client: Arc<AnthropicClient>,
    voice_profile: VoiceProfile,
}

impl HermesAgent {
    pub async fn new(voice_profile: VoiceProfile) -> Result<Self> {
        let api_key = std::env::var("ANTHROPIC_API_KEY").map_err(|_| {
            crate::HermesError::ConfigError("ANTHROPIC_API_KEY not set".to_string())
        })?;

        let llm_client =
            AnthropicClient::new(api_key).map_err(|e| crate::HermesError::LLMError(e))?;

        Ok(Self {
            llm_client: Arc::new(llm_client),
            voice_profile,
        })
    }

    /// Generate section draft from context
    pub async fn generate_section(&self, context: GenerationContext) -> Result<Draft> {
        info!("HERMES: Generating section: {:?}", context.section_type);

        // 1. Prepare prompt with context
        let prompt = self.prepare_prompt(&context)?;

        // 2. Generate with LoRA adapter (placeholder for now)
        let llm_request = CompletionRequest {
            model: ModelType::ClaudeSonnet45,
            messages: vec![Message::user(prompt)],
            max_tokens: (context.target_words * 2) as u32,
            temperature: 0.7,
            system: Some(
                "You are an expert scientific writer specializing in biomedical research."
                    .to_string(),
            ),
        };

        let response = self
            .llm_client
            .complete(llm_request)
            .await
            .map_err(|e| crate::HermesError::LLMError(e))?;

        // 3. Post-process
        let content = response.content.clone();
        let word_count = content.split_whitespace().count();
        let citations = self.extract_citations(&content)?;

        let draft = Draft {
            content,
            word_count,
            citations,
        };

        info!("HERMES: Generated draft with {} words", draft.word_count);
        Ok(draft)
    }

    fn prepare_prompt(&self, context: &GenerationContext) -> Result<String> {
        let mut prompt = String::new();

        prompt.push_str("# SCIENTIFIC WRITING TASK\n\n");
        prompt.push_str(&format!("Section: {}\n", context.section_type));
        prompt.push_str(&format!(
            "Target length: {} words\n\n",
            context.target_words
        ));

        prompt.push_str("## RELEVANT LITERATURE\n\n");
        for paper in &context.papers {
            prompt.push_str(&format!(
                "- {} et al. ({}): {}\n",
                paper.authors.first().unwrap_or(&"Unknown".to_string()),
                paper.year,
                paper.title
            ));
        }

        prompt.push_str("\n## USER INSIGHTS\n\n");
        for insight in &context.insights {
            prompt.push_str(&format!("- {}\n", insight));
        }

        prompt.push_str("\n## TASK\n\n");
        prompt.push_str("Write a high-quality academic section that:\n");
        prompt.push_str("1. Synthesizes the literature above\n");
        prompt.push_str("2. Incorporates user insights naturally\n");
        prompt.push_str("3. Maintains author's voice and style\n");
        prompt.push_str("4. Includes proper citations [X]\n\n");
        prompt.push_str("OUTPUT (markdown):\n");

        Ok(prompt)
    }

    fn extract_citations(&self, text: &str) -> Result<Vec<String>> {
        use regex::Regex;
        let re = Regex::new(r"\[(\d+)\]")
            .map_err(|e| crate::HermesError::SynthesisError(format!("Invalid regex: {}", e)))?;

        let citations = re
            .captures_iter(text)
            .map(|cap| cap[1].to_string())
            .collect();

        Ok(citations)
    }

    /// Refina draft com base em crítica estruturada do ARGOS
    pub async fn refine_with_critique(&self, draft: &Draft, critique: &str) -> Result<Draft> {
        info!("HERMES: Refinando draft com crítica do ARGOS");

        let prompt = format!(
            r#"# REFINAMENTO DE DRAFT CIENTÍFICO

## DRAFT ATUAL

{}

## CRÍTICA DO VALIDADOR

{}

## TAREFA

Refine o draft acima corrigindo todos os problemas identificados na crítica, mantendo:
1. A voz e estilo do autor original
2. Todas as citações existentes
3. A estrutura e fluxo lógico
4. O comprimento aproximado ({} palavras)

Gere APENAS o draft refinado, sem comentários adicionais."#,
            draft.content,
            critique,
            draft.word_count
        );

        let llm_request = CompletionRequest {
            model: ModelType::ClaudeSonnet45,
            messages: vec![Message::user(prompt)],
            max_tokens: (draft.word_count * 2) as u32,
            temperature: 0.6, // Temperatura mais baixa para refinamento preciso
            system: Some(
                "You are an expert scientific editor specializing in refining academic drafts based on structured critiques."
                    .to_string(),
            ),
        };

        let response = self
            .llm_client
            .complete(llm_request)
            .await
            .map_err(|e| crate::HermesError::LLMError(e))?;

        let refined_content = response.content.clone();
        let word_count = refined_content.split_whitespace().count();
        let citations = self.extract_citations(&refined_content)?;

        let refined_draft = Draft {
            content: refined_content,
            word_count,
            citations,
        };

        info!("HERMES: Draft refinado com {} palavras", refined_draft.word_count);
        Ok(refined_draft)
    }
}

#[derive(Debug, Clone)]
pub struct GenerationContext {
    pub section_type: String,
    pub target_words: usize,
    pub papers: Vec<Paper>,
    pub insights: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Draft {
    pub content: String,
    pub word_count: usize,
    pub citations: Vec<String>,
}
