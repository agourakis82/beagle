use std::sync::Arc;
use std::time::Instant;

use anyhow::Result;
use async_trait::async_trait;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use beagle_memory::ContextBridge;
use serde_json::json;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::agent_trait::{Agent, AgentCapability, AgentInput, AgentOutput};

/// Agente dedicado à recuperação de contexto da memória conversacional.
pub struct RetrievalAgent {
    id: String,
    memory: Arc<ContextBridge>,
}

impl RetrievalAgent {
    pub fn new(memory: Arc<ContextBridge>) -> Self {
        Self {
            id: format!("retrieval-{}", Uuid::new_v4()),
            memory,
        }
    }
}

#[async_trait]
impl Agent for RetrievalAgent {
    fn id(&self) -> &str {
        &self.id
    }

    fn capability(&self) -> AgentCapability {
        AgentCapability::ContextRetrieval
    }

    async fn execute(&self, input: AgentInput) -> Result<AgentOutput> {
        let start = Instant::now();
        debug!("📚 RetrievalAgent executing for: {}", input.query);

        let session_id = input
            .metadata
            .get("session_id")
            .and_then(|value| value.as_str())
            .and_then(|value| Uuid::parse_str(value).ok());

        let mut context_chunks = Vec::new();

        if let Some(sid) = session_id {
            match self.memory.get_session_history(sid, 6).await {
                Ok(turns) => {
                    for turn in turns {
                        context_chunks.push(format!("Q: {}\nA: {}", turn.query, turn.response));
                    }
                    info!("✅ RetrievalAgent: {} chunks", context_chunks.len());
                }
                Err(err) => {
                    warn!("⚠️ RetrievalAgent failed: {}", err);
                }
            }
        }

        Ok(AgentOutput {
            agent_id: self.id.clone(),
            result: json!({
                "chunks": context_chunks,
                "count": context_chunks.len(),
            }),
            confidence: if context_chunks.is_empty() { 0.3 } else { 0.9 },
            duration_ms: start.elapsed().as_millis() as u64,
            metadata: json!({}),
        })
    }
}

/// Agente responsável por validação factual.
pub struct ValidationAgent {
    id: String,
    llm: Arc<AnthropicClient>,
}

impl ValidationAgent {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self {
            id: format!("validation-{}", Uuid::new_v4()),
            llm,
        }
    }
}

#[async_trait]
impl Agent for ValidationAgent {
    fn id(&self) -> &str {
        &self.id
    }

    fn capability(&self) -> AgentCapability {
        AgentCapability::FactChecking
    }

    async fn execute(&self, input: AgentInput) -> Result<AgentOutput> {
        let start = Instant::now();
        debug!("🛡️ ValidationAgent executing");

        let response = input
            .metadata
            .get("response")
            .and_then(|value| value.as_str())
            .unwrap_or_default();

        if response.is_empty() || input.context.is_empty() {
            return Ok(AgentOutput {
                agent_id: self.id.clone(),
                result: json!({
                    "is_supported": true,
                    "reason": "Insufficient context for validation",
                }),
                confidence: 0.4,
                duration_ms: start.elapsed().as_millis() as u64,
                metadata: json!({}),
            });
        }

        let context_text = input.context.join("\n\n");
        let prompt = format!(
            "Contexto:\n{}\n\nResposta:\n{}\n\n\
            A resposta está apoiada pelo contexto? Responda APENAS com YES ou NO.",
            context_text, response
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(prompt)],
            max_tokens: 16,
            temperature: 0.0,
            system: Some("You are an expert fact-checker.".to_string()),
        };

        let llm_response = self.llm.complete(request).await?;
        let normalized = llm_response.content.trim().to_ascii_uppercase();
        let is_supported = normalized.contains("YES");

        info!("🛡️ ValidationAgent: supported={}", is_supported);

        Ok(AgentOutput {
            agent_id: self.id.clone(),
            result: json!({
                "is_supported": is_supported,
                "raw_response": llm_response.content,
            }),
            confidence: 0.85,
            duration_ms: start.elapsed().as_millis() as u64,
            metadata: json!({}),
        })
    }
}

/// Agente que avalia a qualidade da resposta.
pub struct QualityAgent {
    id: String,
    llm: Arc<AnthropicClient>,
}

impl QualityAgent {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self {
            id: format!("quality-{}", Uuid::new_v4()),
            llm,
        }
    }
}

#[async_trait]
impl Agent for QualityAgent {
    fn id(&self) -> &str {
        &self.id
    }

    fn capability(&self) -> AgentCapability {
        AgentCapability::QualityAssessment
    }

    async fn execute(&self, input: AgentInput) -> Result<AgentOutput> {
        let start = Instant::now();
        debug!("⭐ QualityAgent executing");

        let response = input
            .metadata
            .get("response")
            .and_then(|value| value.as_str())
            .unwrap_or_default();

        if response.is_empty() {
            return Ok(AgentOutput {
                agent_id: self.id.clone(),
                result: json!({ "score": 0.0 }),
                confidence: 1.0,
                duration_ms: start.elapsed().as_millis() as u64,
                metadata: json!({}),
            });
        }

        let prompt = format!(
            "Avalie a qualidade da resposta a seguir em uma escala de 0.0 a 1.0.\n\
            Responda apenas com o número.\n\n{}",
            response
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(prompt)],
            max_tokens: 16,
            temperature: 0.0,
            system: Some("You are an expert quality evaluator.".to_string()),
        };

        let llm_response = self.llm.complete(request).await?;
        let score = llm_response
            .content
            .trim()
            .parse::<f32>()
            .unwrap_or(0.7)
            .clamp(0.0, 1.0);

        info!("⭐ QualityAgent score: {:.2}", score);

        Ok(AgentOutput {
            agent_id: self.id.clone(),
            result: json!({ "score": score }),
            confidence: 0.8,
            duration_ms: start.elapsed().as_millis() as u64,
            metadata: json!({}),
        })
    }
}


