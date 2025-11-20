//! Synthesis engine for generating paper sections

use super::{SynthesisRequest, VoiceProfile};
use crate::{knowledge::KnowledgeGraph, HermesError, Result};
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, info, warn};
use uuid::Uuid;

#[derive(Clone)]
pub struct SynthesisEngine {
    llm_client: Arc<AnthropicClient>,
    config: crate::HermesConfig,
}

impl SynthesisEngine {
    pub async fn new(config: &crate::HermesConfig) -> Result<Self> {
        // Initialize Anthropic client
        let api_key = std::env::var("ANTHROPIC_API_KEY")
            .map_err(|_| HermesError::ConfigError("ANTHROPIC_API_KEY not set".to_string()))?;

        let llm_client = AnthropicClient::new(api_key).map_err(|e| HermesError::LLMError(e))?;

        Ok(Self {
            llm_client: Arc::new(llm_client),
            config: config.clone(),
        })
    }

    pub async fn synthesize(&self, request: SynthesisRequest) -> Result<SynthesisResult> {
        info!(
            "Starting synthesis for cluster: {}",
            request.cluster.concept_name
        );

        // 1. Prepare context from concept cluster
        let context = self.prepare_context(&request).await?;

        // 2. Generate section using LLM
        let draft = self.generate_section(&context, &request).await?;

        // 3. Validate citations
        let validated = self.validate_citations(&draft).await?;

        // 4. Compute voice similarity
        let similarity = self.compute_voice_similarity(&validated, &request.voice_profile)?;
        let word_count = count_words(&validated);

        // 5. Compute confidence
        let confidence = self.compute_confidence(&request, &validated, similarity, word_count);

        // 6. Return result
        Ok(SynthesisResult {
            id: Uuid::new_v4(),
            cluster_name: request.cluster.concept_name.clone(),
            section_type: request.section_type,
            content: validated,
            word_count,
            voice_similarity: similarity,
            generated_at: Utc::now(),
            confidence,
        })
    }

    async fn prepare_context(&self, request: &SynthesisRequest) -> Result<String> {
        let mut context = String::new();

        context.push_str("## CONCEPT CLUSTER INSIGHTS\n\n");
        for insight in &request.cluster.insights {
            context.push_str(&format!(
                "- [{}] {}\n",
                insight.timestamp.format("%Y-%m-%d %H:%M"),
                insight.content
            ));
        }

        context.push_str("\n## SYNTHESIS TARGET\n\n");
        context.push_str(&format!("- Section: {:?}\n", request.section_type));
        context.push_str(&format!(
            "- Target length: {} words\n",
            request.target_words
        ));
        context.push_str(&format!(
            "- Voice similarity target: {:.1}%\n",
            request.voice_profile.similarity_target * 100.0
        ));

        Ok(context)
    }

    async fn generate_section(&self, context: &str, request: &SynthesisRequest) -> Result<String> {
        let prompt = format!(
            r#"You are an expert scientific writer generating a paper section based on research insights.

CONTEXT:

{}

TASK:

Write a high-quality {} section (~{} words) that:

1. Synthesizes the key insights above
2. Maintains academic tone and rigor
3. Includes proper citations [X]
4. Follows standard scientific writing conventions
5. Preserves the author's voice and writing style

OUTPUT (markdown format):
"#,
            context,
            format!("{:?}", request.section_type).to_lowercase(),
            request.target_words
        );

        let llm_request = CompletionRequest {
            model: ModelType::ClaudeSonnet45,
            messages: vec![Message::user(prompt)],
            max_tokens: (request.target_words as f64 * 1.5) as u32, // 1.5x buffer
            temperature: 0.7,
            system: Some(
                "You are an expert scientific writer specializing in biomedical research."
                    .to_string(),
            ),
        };

        let response =
            self.llm_client.complete(llm_request).await.map_err(|e| {
                HermesError::SynthesisError(format!("LLM generation failed: {}", e))
            })?;

        info!("Generated section: {} chars", response.content.len());
        Ok(response.content)
    }

    async fn validate_citations(&self, draft: &str) -> Result<String> {
        use crate::synthesis::citation_validator::CitationValidator;

        let validator = CitationValidator::new()?;

        // For now, we don't have the paper count, so we'll do basic validation
        // In production, this would check against actual papers from ATHENA
        let validation = validator.validate_citations(draft, 100); // Placeholder count

        if !validation.is_valid() {
            warn!(
                "Citation validation issues: {} invalid, {} out of range, completeness: {:.1}%",
                validation.invalid_citations.len(),
                validation.out_of_range.len(),
                validation.completeness * 100.0
            );
        } else {
            debug!("All citations validated successfully");
        }

        // Return draft as-is for now (in production, would fix citations)
        Ok(draft.to_string())
    }

    fn compute_voice_similarity(&self, draft: &str, profile: &VoiceProfile) -> Result<f64> {
        use crate::synthesis::voice_similarity::VoiceSimilarityAnalyzer;

        // Load reference corpus from voice profile adapter path directory
        // In production, this would load from a corpus file or database
        let reference_corpus = self.load_reference_corpus(profile)?;

        let analyzer = VoiceSimilarityAnalyzer::new();
        let similarity = analyzer.compute_similarity(draft, &reference_corpus)?;

        // Apply similarity target threshold
        if similarity >= profile.similarity_target {
            debug!(
                "Voice similarity {:.1}% meets target {:.1}%",
                similarity * 100.0,
                profile.similarity_target * 100.0
            );
        } else {
            debug!(
                "Voice similarity {:.1}% below target {:.1}%",
                similarity * 100.0,
                profile.similarity_target * 100.0
            );
        }

        Ok(similarity)
    }

    fn load_reference_corpus(&self, profile: &VoiceProfile) -> Result<Vec<String>> {
        // Try to load corpus from adapter directory
        // Format: models/voice_adapters/corpus.txt or similar
        let adapter_dir = std::path::Path::new(&profile.adapter_path)
            .parent()
            .unwrap_or(std::path::Path::new("models/voice_adapters"));

        let corpus_path = adapter_dir.join("reference_corpus.txt");

        if corpus_path.exists() {
            match std::fs::read_to_string(&corpus_path) {
                Ok(content) => {
                    // Split into paragraphs/sections
                    let sections: Vec<String> = content
                        .split("\n\n")
                        .map(|s| s.trim().to_string())
                        .filter(|s| s.len() > 50) // Filter very short sections
                        .collect();

                    if !sections.is_empty() {
                        debug!("Loaded {} reference sections from corpus", sections.len());
                        return Ok(sections);
                    }
                }
                Err(e) => {
                    debug!("Failed to read corpus file: {}", e);
                }
            }
        }

        // Fallback: return empty corpus (will result in neutral similarity)
        debug!("No reference corpus found, using neutral similarity");
        Ok(Vec::new())
    }

    fn compute_confidence(
        &self,
        request: &SynthesisRequest,
        content: &str,
        voice_similarity: f64,
        word_count: usize,
    ) -> f64 {
        // Confidence based on multiple factors:
        // 1. Voice similarity (40%)
        // 2. Word count vs target (20%)
        // 3. Insight count (20%)
        // 4. Content quality heuristics (20%)

        let voice_score = voice_similarity;

        let word_score = {
            let target = request.target_words as f64;
            let ratio = (word_count as f64 / target).min(1.0);
            if ratio >= 0.8 && ratio <= 1.2 {
                1.0 // Within 20% of target
            } else if ratio >= 0.6 && ratio <= 1.4 {
                0.8 // Within 40% of target
            } else {
                0.5 // Too far from target
            }
        };

        let insight_score = {
            let count = request.cluster.insights.len() as f64;
            if count >= 20.0 {
                1.0
            } else if count >= 10.0 {
                0.8
            } else if count >= 5.0 {
                0.6
            } else {
                0.4
            }
        };

        let quality_score = {
            // Heuristics: check for citations, proper structure
            let has_citations = content.contains('[') && content.contains(']');
            let has_paragraphs = content.matches("\n\n").count() >= 2;
            let has_sentences = content.matches('.').count() >= 3;

            let mut score = 0.0;
            if has_citations {
                score += 0.4;
            }
            if has_paragraphs {
                score += 0.3;
            }
            if has_sentences {
                score += 0.3;
            }
            score
        };

        let confidence =
            voice_score * 0.4 + word_score * 0.2 + insight_score * 0.2 + quality_score * 0.2;

        confidence.min(1.0).max(0.0)
    }

    pub async fn check_trigger(
        &self,
        insight_id: &Uuid,
        _knowledge_graph: &KnowledgeGraph,
    ) -> Result<()> {
        // Check if we have enough insights to trigger synthesis
        // This is a lightweight check - full check happens in scheduler
        debug!("Checking synthesis trigger for insight {}", insight_id);
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SynthesisResult {
    pub id: Uuid,
    pub cluster_name: String,
    pub section_type: crate::SectionType,
    pub content: String,
    pub word_count: usize,
    pub voice_similarity: f64,
    pub generated_at: chrono::DateTime<chrono::Utc>,
    pub confidence: f64,
}

fn count_words(text: &str) -> usize {
    text.split_whitespace().count()
}
