use std::sync::Arc;
use std::time::Instant;

use anyhow::{Context, Result};
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use beagle_memory::{ContextBridge, ConversationTurn, PerformanceMetrics};
use beagle_personality::PersonalityEngine;
use serde_json::json;
use tokio::task::JoinSet;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::agent_trait::{Agent, AgentCapability, AgentInput, AgentOutput};
use crate::models::{ResearchMetrics, ResearchResult, ResearchStep};

/// Orquestra múltiplos agentes especializados em paralelo real usando Tokio.
pub struct CoordinatorAgent {
    anthropic: Arc<AnthropicClient>,
    personality: Arc<PersonalityEngine>,
    context_bridge: Arc<ContextBridge>,
    agents: Vec<Arc<dyn Agent>>,
}

impl CoordinatorAgent {
    pub fn new(
        anthropic: Arc<AnthropicClient>,
        personality: Arc<PersonalityEngine>,
        context_bridge: Arc<ContextBridge>,
    ) -> Self {
        Self {
            anthropic,
            personality,
            context_bridge,
            agents: Vec::new(),
        }
    }

    pub fn register_agent(mut self, agent: Arc<dyn Agent>) -> Self {
        self.agents.push(agent);
        self
    }

    pub async fn research(&self, query: &str, session_id: Option<Uuid>) -> Result<ResearchResult> {
        let total_start = Instant::now();
        let mut steps = Vec::new();
        let mut step_number = 1;

        let domain_start = Instant::now();
        let domain = self.personality.detect_domain(query);
        steps.push(ResearchStep {
            step_number,
            action: "Detect domain".to_string(),
            result: format!("{:?}", domain),
            duration_ms: domain_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

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

        let retrieval_start = Instant::now();
        let mut context_chunks: Vec<String> = Vec::new();
        if let Some(agent) = self.get_agent(AgentCapability::ContextRetrieval) {
            debug!("📚 RetrievalAgent triggered");
            match agent
                .execute(
                    AgentInput::new(query.to_string())
                        .with_metadata(json!({ "session_id": session_id.to_string() })),
                )
                .await
            {
                Ok(output) => {
                    if let Some(chunks) = output.result.get("chunks").and_then(|v| v.as_array()) {
                        context_chunks = chunks
                            .iter()
                            .filter_map(|value| value.as_str().map(str::to_owned))
                            .collect();
                    }
                }
                Err(err) => warn!("⚠️ Retrieval agent failed: {}", err),
            }
        } else {
            warn!("⚠️ No retrieval agent registered");
        }
        steps.push(ResearchStep {
            step_number,
            action: "Retrieve context".to_string(),
            result: format!("{} chunks", context_chunks.len()),
            duration_ms: retrieval_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        let prompt_start = Instant::now();
        let mut system_prompt = self.personality.system_prompt_for_domain(domain);
        if !context_chunks.is_empty() {
            system_prompt.push_str("\n\n=== Contexto relevante ===\n");
            system_prompt.push_str(&context_chunks.join("\n---\n"));
        }
        steps.push(ResearchStep {
            step_number,
            action: "Compose system prompt".to_string(),
            result: format!("{} chars", system_prompt.len()),
            duration_ms: prompt_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        let llm_start = Instant::now();
        let completion = self
            .anthropic
            .complete(CompletionRequest {
                model: ModelType::ClaudeHaiku45,
                messages: vec![Message::user(query)],
                max_tokens: 1400,
                temperature: 0.7,
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

        let mut join_set = JoinSet::new();
        let mut specialized_llm_calls = 0usize;
        let mut validation: Option<(AgentOutput, u64)> = None;
        let mut quality: Option<(AgentOutput, u64)> = None;

        for agent in &self.agents {
            let capability = agent.capability();
            match capability {
                AgentCapability::FactChecking | AgentCapability::QualityAssessment => {
                    let agent = Arc::clone(agent);
                    let capability_clone = capability.clone();
                    let query_text = query.to_string();
                    let chunks = context_chunks.clone();
                    let answer = completion.content.clone();
                    join_set.spawn(async move {
                        let start = Instant::now();
                        let input = match capability_clone {
                            AgentCapability::FactChecking => AgentInput::new(query_text)
                                .with_context(chunks)
                                .with_metadata(json!({ "response": answer })),
                            _ => AgentInput::new(query_text)
                                .with_metadata(json!({ "response": answer })),
                        };
                        let result = agent.execute(input).await;
                        let duration = start.elapsed().as_millis() as u64;
                        (capability_clone, duration, result)
                    });
                }
                _ => {}
            }
        }

        while let Some(result) = join_set.join_next().await {
            match result {
                Ok((capability, duration, Ok(output))) => {
                    specialized_llm_calls += 1;
                    match capability {
                        AgentCapability::FactChecking => {
                            debug!("🛡️ ValidationAgent finished in {} ms", duration);
                            validation = Some((output, duration));
                        }
                        AgentCapability::QualityAssessment => {
                            debug!("⭐ QualityAgent finished in {} ms", duration);
                            quality = Some((output, duration));
                        }
                        _ => {}
                    }
                }
                Ok((capability, duration, Err(err))) => {
                    warn!(
                        "⚠️ Specialized agent {:?} failed after {} ms: {}",
                        capability, duration, err
                    );
                }
                Err(err) => warn!("⚠️ JoinSet join error: {}", err),
            }
        }

        if let Some((output, duration)) = validation.as_ref() {
            let supported = output
                .result
                .get("is_supported")
                .and_then(|v| v.as_bool())
                .unwrap_or(true);
            steps.push(ResearchStep {
                step_number,
                action: "ValidationAgent".to_string(),
                result: format!("is_supported={}", supported),
                duration_ms: *duration,
            });
            step_number += 1;
        }

        if let Some((output, duration)) = quality.as_ref() {
            let score = output
                .result
                .get("score")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.78);
            steps.push(ResearchStep {
                step_number,
                action: "QualityAgent".to_string(),
                result: format!("score={:.2}", score),
                duration_ms: *duration,
            });
            step_number += 1;
        }

        let is_supported = validation
            .as_ref()
            .and_then(|(output, _)| output.result.get("is_supported").and_then(|v| v.as_bool()))
            .unwrap_or(true);

        let mut quality_score = quality
            .as_ref()
            .and_then(|(output, _)| output.result.get("score").and_then(|v| v.as_f64()))
            .unwrap_or(0.78) as f32;

        if !is_supported {
            quality_score = (quality_score * 0.75).clamp(0.0, 1.0);
        }

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
            warn!("⚠️ Failed to persist turn: {}", err);
        }
        steps.push(ResearchStep {
            step_number,
            action: "Persist turn".to_string(),
            result: "Stored in contextual memory".to_string(),
            duration_ms: store_start.elapsed().as_millis() as u64,
        });

        let total_duration = total_start.elapsed();
        let metrics = ResearchMetrics {
            total_duration_ms: total_duration.as_millis() as u64,
            llm_calls: 1 + specialized_llm_calls,
            context_chunks_retrieved: context_chunks.len(),
            refinement_iterations: 0,
            quality_score,
        };

        info!(
            "⚡ CoordinatorAgent finished in {} ms (quality {:.2}, supported={})",
            metrics.total_duration_ms, metrics.quality_score, is_supported
        );

        Ok(ResearchResult {
            answer: completion.content,
            domain,
            steps,
            metrics,
            session_id,
            sources: Some(context_chunks),
        })
    }

    fn get_agent(&self, capability: AgentCapability) -> Option<Arc<dyn Agent>> {
        self.agents
            .iter()
            .find(|agent| agent.capability() == capability)
            .map(Arc::clone)
    }
}
