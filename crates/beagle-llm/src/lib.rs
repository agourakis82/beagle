//! Camada de integração com provedores LLM para o ecossistema Beagle.
//!
//! Router inteligente com:
//! - Grok 3 default (93% dos casos, ilimitado, rápido)
//! - Grok 4 Heavy automático para temas de alto risco de viés
//! - Detecção automática de keywords de alto risco

use async_trait::async_trait;
use serde::{Deserialize, Serialize};

pub mod router;
pub mod router_tiered;
pub mod clients;
pub mod meta;
pub mod tier;

pub use router::BeagleRouter;
pub use router_tiered::TieredRouter;
pub use tier::{Tier, RequestMeta};

// Módulos legados (mantidos para compatibilidade)
pub mod anthropic;
pub mod embedding;
pub mod gemini;
pub mod models;
pub mod validation;
pub mod vertex;
pub mod vllm;

pub use router::BeagleRouter;
pub use clients::grok::GrokClient;
// RequestMeta agora está em tier.rs
pub use meta::HIGH_BIAS_KEYWORDS;

// Re-exports legados
pub use anthropic::AnthropicClient;
pub use embedding::{Embedding, EmbeddingClient};
pub use gemini::GeminiClient;
pub use models::{CompletionRequest, CompletionResponse, Message, ModelType};
pub use validation::{CitationValidity, Issue, IssueType, Severity, ValidationResult};
pub use vertex::VertexAIClient;
pub use vllm::{SamplingParams, VllmClient, VllmCompletionRequest};

// Re-export Grok client se disponível (crate separado, mantido para compatibilidade)
#[cfg(feature = "grok")]
pub use beagle_grok_api::{GrokClient as LegacyGrokClient, GrokError, GrokModel};

/// Alias canônico para resultados com `anyhow`.
pub type Result<T> = anyhow::Result<T>;

// ============================================================================
// NOVA API - Router e Traits
// ============================================================================

/// Mensagem de chat
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

impl ChatMessage {
    pub fn user(content: impl Into<String>) -> Self {
        Self {
            role: "user".to_string(),
            content: content.into(),
        }
    }

    pub fn assistant(content: impl Into<String>) -> Self {
        Self {
            role: "assistant".to_string(),
            content: content.into(),
        }
    }

    pub fn system(content: impl Into<String>) -> Self {
        Self {
            role: "system".to_string(),
            content: content.into(),
        }
    }
}

/// Request para LLM
#[derive(Debug, Clone, Serialize)]
pub struct LlmRequest {
    pub model: String,
    pub messages: Vec<ChatMessage>,
    pub temperature: Option<f32>,
    pub max_tokens: Option<i32>,
}

/// Trait para clientes LLM
#[async_trait]
pub trait LlmClient: Send + Sync {
    /// Completa um prompt simples
    async fn complete(&self, prompt: &str) -> anyhow::Result<String> {
        let req = LlmRequest {
            model: "default".to_string(),
            messages: vec![ChatMessage::user(prompt)],
            temperature: Some(0.7),
            max_tokens: Some(2048),
        };
        self.chat(req).await
    }

    /// Chat com múltiplas mensagens
    async fn chat(&self, req: LlmRequest) -> anyhow::Result<String>;
    
    /// Nome do cliente
    fn name(&self) -> &'static str;
    
    /// Tier preferido
    fn tier(&self) -> Tier {
        Tier::CloudGrokMain
    }
    
    /// Prefere Grok 4 Heavy (legado, mantido para compatibilidade)
    fn prefers_heavy(&self) -> bool {
        false
    }
}

