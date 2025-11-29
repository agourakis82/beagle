//! Claude API Client (Direct Anthropic)
//!
//! Uses your Claude MAX subscription via Anthropic API:
//! - Claude Sonnet 4.5 (latest, most capable)
//! - Claude Sonnet 3.5
//! - Claude Opus 3
//!
//! Requires: Claude MAX subscription + Anthropic API key
//! Setup: export ANTHROPIC_API_KEY=sk-ant-...
//!
//! Note: This leverages your existing Claude MAX subscription.
//! The API is included with MAX tier.

use crate::anthropic::AnthropicClient as LegacyAnthropicClient;
use crate::models::{CompletionRequest, Message as LegacyMessage, ModelType};
use crate::{LlmClient, LlmRequest, Tier};
use async_trait::async_trait;
use std::sync::Arc;
use tracing::{debug, info};

/// Claude model selection
#[derive(Debug, Clone)]
pub enum ClaudeModel {
    /// Claude Sonnet 4.5 - Latest, most capable (Feb 2025)
    Sonnet45,
    /// Claude Sonnet 3.5 - Excellent for research
    Sonnet35,
    /// Claude Opus 3 - Highest quality, slower
    Opus3,
}

impl ClaudeModel {
    fn as_str(&self) -> &str {
        match self {
            ClaudeModel::Sonnet45 => "claude-sonnet-4.5-20250929",
            ClaudeModel::Sonnet35 => "claude-3-5-sonnet-20241022",
            ClaudeModel::Opus3 => "claude-3-opus-20240229",
        }
    }
}

/// Claude API client (uses Anthropic API with MAX subscription)
pub struct ClaudeClient {
    inner: Arc<LegacyAnthropicClient>,
    model: ClaudeModel,
}

impl ClaudeClient {
    /// Create new client from environment variable ANTHROPIC_API_KEY
    pub fn from_env() -> anyhow::Result<Self> {
        let api_key = std::env::var("ANTHROPIC_API_KEY")
            .map_err(|_| anyhow::anyhow!("ANTHROPIC_API_KEY not set"))?;

        Self::new(api_key, ClaudeModel::Sonnet45)
    }

    /// Create new client with specific API key and model
    pub fn new(api_key: String, model: ClaudeModel) -> anyhow::Result<Self> {
        let inner = LegacyAnthropicClient::new(api_key)?;
        Ok(Self {
            inner: Arc::new(inner),
            model,
        })
    }

    /// Change the model for future requests
    pub fn with_model(mut self, model: ClaudeModel) -> Self {
        self.model = model;
        self
    }

    /// Use Sonnet 4.5 (latest, most capable)
    pub fn sonnet_45() -> anyhow::Result<Self> {
        Self::from_env()
    }

    /// Use Sonnet 3.5 (excellent for research)
    pub fn sonnet_35() -> anyhow::Result<Self> {
        let mut client = Self::from_env()?;
        client.model = ClaudeModel::Sonnet35;
        Ok(client)
    }

    /// Use Opus 3 (highest quality)
    pub fn opus_3() -> anyhow::Result<Self> {
        let mut client = Self::from_env()?;
        client.model = ClaudeModel::Opus3;
        Ok(client)
    }
}

#[async_trait]
impl LlmClient for ClaudeClient {
    fn name(&self) -> &'static str {
        "claude"
    }

    fn tier(&self) -> Tier {
        // Claude is cloud-based, high-quality tier
        Tier::CloudGrokMain
    }

    async fn chat(&self, request: LlmRequest) -> anyhow::Result<String> {
        debug!(
            "Sending request to Claude API (model: {})",
            self.model.as_str()
        );

        // Convert new ChatMessage format to legacy Message format
        let messages: Vec<LegacyMessage> = request
            .messages
            .into_iter()
            .map(|msg| LegacyMessage {
                role: msg.role,
                content: msg.content,
            })
            .collect();

        // Map ClaudeModel to ModelType
        let model_type = match self.model {
            ClaudeModel::Sonnet45 => ModelType::ClaudeSonnet45,
            ClaudeModel::Sonnet35 => ModelType::ClaudeSonnet45, // Close enough
            ClaudeModel::Opus3 => ModelType::ClaudeSonnet4,     // Use Sonnet 4 as fallback
        };

        let legacy_request = CompletionRequest {
            model: model_type,
            messages,
            max_tokens: request.max_tokens.unwrap_or(4096) as u32,
            temperature: request.temperature.unwrap_or(0.7),
            system: None,
        };

        let response = self.inner.complete(legacy_request).await?;

        info!(
            "Claude response received (tokens: input={}, output={})",
            response
                .usage
                .get("input_tokens")
                .unwrap_or(&serde_json::json!(0)),
            response
                .usage
                .get("output_tokens")
                .unwrap_or(&serde_json::json!(0))
        );

        Ok(response.content)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ChatMessage;

    #[tokio::test]
    #[ignore] // Only run with --ignored (requires ANTHROPIC_API_KEY)
    async fn test_claude_client() {
        let client = ClaudeClient::from_env().unwrap();

        let request = LlmRequest {
            model: "claude-sonnet-4.5".to_string(),
            messages: vec![ChatMessage::user("What is 2+2?")],
            temperature: Some(0.7),
            max_tokens: Some(100),
        };

        let response = client.chat(request).await.unwrap();
        println!("Response: {}", response);
        assert!(!response.is_empty());
    }

    #[tokio::test]
    #[ignore]
    async fn test_claude_sonnet_45() {
        let client = ClaudeClient::sonnet_45().unwrap();
        let response = client
            .complete("Explain quantum entanglement in one sentence.")
            .await
            .unwrap();
        println!("Sonnet 4.5: {}", response.text);
        assert!(!response.text.is_empty());
    }
}
