//! OpenRouterClient — generic OpenAI-compatible client for OpenRouter.ai
//!
//! Supports any model available on OpenRouter (Kimi, Llama, Mistral, etc.)
//! Uses OPENROUTER_API_KEY from environment.
//! Default model: moonshotai/kimi-k2.6

use crate::{LlmClient, LlmRequest};
use async_trait::async_trait;
use reqwest::Client;
use std::env;
use tracing::{debug, warn};

#[derive(Clone)]
pub struct OpenRouterClient {
    client: Client,
    api_key: String,
    model: String,
    base_url: String,
}

#[derive(Debug, serde::Deserialize)]
struct ChoiceMessage {
    content: String,
}

#[derive(Debug, serde::Deserialize)]
struct Choice {
    message: ChoiceMessage,
}

#[derive(Debug, serde::Deserialize)]
struct ApiResponse {
    choices: Vec<Choice>,
}

impl OpenRouterClient {
    /// Create with default Kimi K2.6 model
    pub fn new() -> Self {
        Self::with_model("moonshotai/kimi-k2.6")
    }

    /// Create with a specific OpenRouter model
    pub fn with_model(model: &str) -> Self {
        let api_key = env::var("OPENROUTER_API_KEY").unwrap_or_else(|_| {
            warn!("OPENROUTER_API_KEY not set, will fail at runtime");
            String::new()
        });

        Self {
            client: Client::new(),
            api_key,
            model: model.to_string(),
            base_url: "https://openrouter.ai/api/v1/chat/completions".to_string(),
        }
    }

    pub fn check_available() -> bool {
        !env::var("OPENROUTER_API_KEY")
            .unwrap_or_default()
            .is_empty()
    }
}

#[async_trait]
impl LlmClient for OpenRouterClient {
    async fn chat(&self, mut req: LlmRequest) -> anyhow::Result<String> {
        if req.model == "default" {
            req.model = self.model.clone();
        }

        debug!("OpenRouterClient: model={}", req.model);

        let request_body = serde_json::json!({
            "model": req.model,
            "messages": req.messages,
            "temperature": req.temperature.unwrap_or(0.7),
            "max_tokens": req.max_tokens.unwrap_or(8192),
        });

        let response = self
            .client
            .post(&self.base_url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .header("HTTP-Referer", "https://beagle.chiuratto.ai")
            .header("X-Title", "Beagle Exocortex")
            .json(&request_body)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            anyhow::bail!("OpenRouter API error {}: {}", status, error_text);
        }

        let resp: ApiResponse = response.json().await?;

        if resp.choices.is_empty() {
            anyhow::bail!("OpenRouter returned empty response");
        }

        Ok(resp.choices[0].message.content.clone())
    }

    fn name(&self) -> &'static str {
        "openrouter"
    }

    fn tier(&self) -> crate::Tier {
        crate::Tier::CloudMath
    }

    fn prefers_heavy(&self) -> bool {
        false
    }
}
