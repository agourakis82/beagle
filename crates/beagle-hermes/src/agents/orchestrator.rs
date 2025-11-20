//! Multi-agent orchestrator with parallel execution

use super::{ArgosAgent, AthenaAgent, HermesAgent};
use crate::{knowledge::ConceptCluster, synthesis::VoiceProfile, Result};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::task::JoinSet;
use tracing::{info, warn};

fn extract_citations_from_text(text: &str) -> Vec<String> {
    let re = Regex::new(r"\[(\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*)\]").ok();
    if let Some(pattern) = re {
        pattern
            .captures_iter(text)
            .filter_map(|cap| cap.get(1))
            .map(|m| m.as_str().to_string())
            .collect()
    } else {
        Vec::new()
    }
}

pub struct MultiAgentOrchestrator {
    athena: Arc<AthenaAgent>,
    hermes: Arc<HermesAgent>,
    argos: Arc<ArgosAgent>,
}

impl MultiAgentOrchestrator {
    pub async fn new(voice_profile: VoiceProfile) -> Result<Self> {
        let athena = Arc::new(AthenaAgent::new().await?);
        let hermes = Arc::new(HermesAgent::new(voice_profile).await?);
        let argos = Arc::new(ArgosAgent::new().await?);

        Ok(Self {
            athena,
            hermes,
            argos,
        })
    }

    /// Search papers using Athena agent
    pub async fn search_papers(
        &self,
        cluster: &ConceptCluster,
    ) -> Result<Vec<super::athena::Paper>> {
        self.athena.search_papers(cluster).await
    }

    /// Synthesize section using multi-agent collaboration with parallel execution
    pub async fn synthesize_section(
        &self,
        cluster: &ConceptCluster,
        section_type: String,
        target_words: usize,
    ) -> Result<SynthesisOutput> {
        info!(
            "🚀 Multi-Agent Synthesis for cluster: {}",
            cluster.concept_name
        );

        // Stage 1: ATHENA - Literature review (can run in parallel for multiple queries)
        info!("📚 ATHENA: Searching literature...");
        let papers = self.athena.search_papers(cluster).await?;
        info!("📚 ATHENA: Found {} relevant papers", papers.len());

        // Stage 2: HERMES - Draft generation (can generate multiple sections in parallel)
        info!("✍️  HERMES: Generating draft...");
        let insights: Vec<String> = cluster.insights.iter().map(|i| i.content.clone()).collect();
        let context_text = insights.join("\n");
        let context = super::hermes_agent::GenerationContext {
            section_type: section_type.clone(),
            target_words,
            papers: papers.clone(),
            insights: insights.clone(),
        };
        let draft = self.hermes.generate_section(context).await?;
        info!("✍️  HERMES: Draft generated ({} words)", draft.word_count);

        // Stage 3: ARGOS - Validation (parallel validation of different aspects)
        info!("✅ ARGOS: Validating draft...");
        let validation = self.argos.validate(&draft, &papers).await?;
        info!(
            "✅ ARGOS: Quality score: {:.1}%",
            validation.quality_score * 100.0
        );

        // Stage 4: Iterative refinement (if needed)
        let mut final_draft = draft.content;
        if !validation.approved {
            warn!("⚠️  ARGOS: Draft not approved, requesting refinement...");

            use crate::synthesis::RefinementEngine;
            // Get llm_client from hermes agent (need to expose it or create new one)
            // For now, create a new AnthropicClient
            let api_key = std::env::var("ANTHROPIC_API_KEY").map_err(|_| {
                crate::HermesError::ConfigError("ANTHROPIC_API_KEY not set".to_string())
            })?;
            let llm_client = beagle_llm::AnthropicClient::new(api_key)
                .map_err(|e| crate::HermesError::LLMError(e))?;
            let refinement_engine = RefinementEngine::new(Arc::new(llm_client));

            // For now, do a single refinement pass
            match refinement_engine
                .refine(&final_draft, &validation.issues, &context_text)
                .await
            {
                Ok(refined) => {
                    final_draft = refined;
                    info!("✅ Refinement completed");
                }
                Err(e) => {
                    warn!("Refinement failed: {}", e);
                }
            }
        }

        let word_count = final_draft.split_whitespace().count();
        Ok(SynthesisOutput {
            draft: final_draft,
            word_count,
            papers_cited: papers.len(),
            quality_score: validation.quality_score,
            validation,
        })
    }

    /// Process multiple clusters in parallel
    pub async fn synthesize_multiple_clusters(
        &self,
        clusters: Vec<ConceptCluster>,
        section_type: String,
        target_words: usize,
    ) -> Result<Vec<SynthesisOutput>> {
        info!("🚀 Processing {} clusters in parallel", clusters.len());

        let mut join_set = JoinSet::new();

        // Spawn parallel synthesis tasks for each cluster
        for cluster in clusters {
            let orchestrator = self.clone();
            let section_type = section_type.clone();
            join_set.spawn(async move {
                orchestrator
                    .synthesize_section(&cluster, section_type, target_words)
                    .await
            });
        }

        // Collect results
        let mut results = Vec::new();
        while let Some(result) = join_set.join_next().await {
            match result {
                Ok(Ok(output)) => results.push(output),
                Ok(Err(e)) => warn!("Synthesis failed: {}", e),
                Err(e) => warn!("Task join error: {}", e),
            }
        }

        info!("✅ Completed {} synthesis tasks", results.len());
        Ok(results)
    }
}

impl Clone for MultiAgentOrchestrator {
    fn clone(&self) -> Self {
        Self {
            athena: Arc::clone(&self.athena),
            hermes: Arc::clone(&self.hermes),
            argos: Arc::clone(&self.argos),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SynthesisOutput {
    pub draft: String,
    pub word_count: usize,
    pub papers_cited: usize,
    pub quality_score: f64,
    pub validation: beagle_llm::validation::ValidationResult,
}
