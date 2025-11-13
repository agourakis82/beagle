use std::sync::Arc;
use std::time::Instant;

use anyhow::{Context, Result};
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use beagle_memory::{ContextBridge, ConversationTurn, PerformanceMetrics, RetrievedContext};
use beagle_personality::PersonalityEngine;
use tracing::{info, warn};
use uuid::Uuid;

use crate::models::{ResearchMetrics, ResearchResult, ResearchStep};

/// Agente sequencial (baseline) responsável pela execução Self-RAG em série.
pub struct ResearcherAgent {
    anthropic: Arc<AnthropicClient>,
    personality: Arc<PersonalityEngine>,
    context_bridge: Arc<ContextBridge>,
}

impl ResearcherAgent {
    pub fn new(
        anthropic: Arc<AnthropicClient>,
        personality: Arc<PersonalityEngine>,
        context_bridge: Arc<ContextBridge>,
    ) -> Self {
        Self {
            anthropic,
            personality,
            context_bridge,
        }
    }

    pub async fn research(&self, query: &str, session_id: Option<Uuid>) -> Result<ResearchResult> {
        let total_start = Instant::now();
        let mut steps = Vec::new();
        let mut step_number = 1;

        // 1) Detecção de domínio
        let detect_start = Instant::now();
        let domain = self.personality.detect_domain(query);
        steps.push(ResearchStep {
            step_number,
            action: "Detect domain".to_string(),
            result: format!("{:?}", domain),
            duration_ms: detect_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 2) Garantir sessão
        let session_start = Instant::now();
        let (session_id, created) = match session_id {
            Some(id) => (id, false),
            None => {
                let session = self
                    .context_bridge
                    .create_session(None)
                    .await
                    .context("Failed to create conversation session")?;
                (session.id, true)
            }
        };
        steps.push(ResearchStep {
            step_number,
            action: "Select session".to_string(),
            result: if created {
                format!("Created session {}", session_id)
            } else {
                format!("Using session {}", session_id)
            },
            duration_ms: session_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 3) Recuperar contexto
        let context_start = Instant::now();
        let mut retrieved = match self
            .context_bridge
            .retrieve_similar_context(query, 6, 0.35)
            .await
        {
            Ok(mut context) => {
                context.truncate_to_budget(1800);
                context
            }
            Err(err) => {
                warn!("⚠️ Failed to retrieve semantic context: {}", err);
                RetrievedContext {
                    turns: vec![],
                    relevance_scores: vec![],
                    total_tokens: 0,
                }
            }
        };

        if retrieved.turns.is_empty() {
            match self.context_bridge.get_session_history(session_id, 5).await {
                Ok(history) if !history.is_empty() => {
                    let token_estimate: usize =
                        history.iter().map(|turn| turn.char_count() / 4).sum();
                    retrieved.turns = history;
                    retrieved.relevance_scores = vec![1.0; retrieved.turns.len()];
                    retrieved.total_tokens = token_estimate;
                }
                Ok(_) => {}
                Err(err) => warn!("⚠️ Failed to load session history: {}", err),
            }
        }

        let context_string = self.context_bridge.build_context_string(&retrieved);
        steps.push(ResearchStep {
            step_number,
            action: "Retrieve context".to_string(),
            result: format!(
                "{} chunks ({} tokens)",
                retrieved.turns.len(),
                retrieved.total_tokens
            ),
            duration_ms: context_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 4) Montar prompt
        let prompt_start = Instant::now();
        let mut system_prompt = self.personality.system_prompt_for_domain(domain);
        if !context_string.is_empty() {
            system_prompt.push_str("\n\n");
            system_prompt.push_str(&context_string);
        }
        steps.push(ResearchStep {
            step_number,
            action: "Compose system prompt".to_string(),
            result: format!("{} chars", system_prompt.len()),
            duration_ms: prompt_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 5) Geração
        let llm_start = Instant::now();
        let completion = self
            .anthropic
            .complete(CompletionRequest {
                model: ModelType::ClaudeHaiku45,
                messages: vec![Message::user(query)],
                max_tokens: 1200,
                temperature: 0.8,
                system: Some(system_prompt.clone()),
            })
            .await
            .context("Anthropic completion failed")?;
        steps.push(ResearchStep {
            step_number,
            action: "Generate answer".to_string(),
            result: format!("{} chars", completion.content.len()),
            duration_ms: llm_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 6) Persistir na memória
        let store_start = Instant::now();
        let mut turn = ConversationTurn::new(
            session_id,
            query.to_string(),
            completion.content.clone(),
            domain,
            completion.model.clone(),
        );
        turn.metadata.metrics = PerformanceMetrics {
            latency_ms: llm_start.elapsed().as_millis() as u64,
            tokens_input: None,
            tokens_output: None,
            cost_usd: None,
        };
        turn.metadata.system_prompt_preview = Some(
            system_prompt
                .chars()
                .take(200)
                .collect::<String>()
                .replace('\n', " "),
        );

        if let Err(err) = self.context_bridge.store_turn(turn).await {
            warn!("⚠️ Failed to persist conversation turn: {}", err);
        }
        steps.push(ResearchStep {
            step_number,
            action: "Persist turn".to_string(),
            result: "Stored in contextual memory".to_string(),
            duration_ms: store_start.elapsed().as_millis() as u64,
        });

        let total_duration = total_start.elapsed();
        let answer_len = completion.content.len();
        let quality_score = (answer_len as f32 / 2400.0).clamp(0.35, 0.95);

        let metrics = ResearchMetrics {
            total_duration_ms: total_duration.as_millis() as u64,
            llm_calls: 1,
            context_chunks_retrieved: retrieved.turns.len(),
            refinement_iterations: 0,
            quality_score,
        };

        info!(
            "ResearcherAgent (sequential) finished in {} ms (quality {:.2})",
            metrics.total_duration_ms, metrics.quality_score
        );

        Ok(ResearchResult {
            answer: completion.content,
            domain,
            steps,
            metrics,
            session_id,
            sources: None,
        })
    }
}
