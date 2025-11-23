//! Cursor AI Client
//!
//! Uses your Cursor subscription to access premium models:
//! - Claude 3.5 Sonnet
//! - GPT-4
//! - GPT-4 Turbo
//!
//! Requires: Cursor Pro subscription + Authentication token
//! Setup: export CURSOR_API_KEY=your_token_here
//!
//! Note: Cursor uses a custom API that's similar to OpenAI but with its own authentication.
//! The exact endpoint and auth mechanism may vary based on Cursor version.

use crate::{ChatMessage, LlmClient, LlmRequest};
use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::{debug, warn};

// Cursor API endpoint (may vary - check Cursor's network traffic for exact endpoint)
const CURSOR_API_URL: &str = "https://api.cursor.sh/v1/chat/completions";

/// Cursor model selection
#[derive(Debug, Clone)]
pub enum CursorModel {
    /// Claude 3.5 Sonnet (best for research, analysis)
    Claude35Sonnet,
    /// GPT-4 Turbo (fast, high-quality)
    Gpt4Turbo,
    /// GPT-4 (reliable, proven)
    Gpt4,
}

impl CursorModel {
    fn as_str(&self) -> &str {
        match self {
            CursorModel::Claude35Sonnet => "claude-3.5-sonnet",
            CursorModel::Gpt4Turbo => "gpt-4-turbo",
            CursorModel::Gpt4 => "gpt-4",
        }
    }
}

/// Cursor AI client
pub struct CursorClient {
    http: Client,
    api_key: String,
    model: CursorModel,
}

impl CursorClient {
    /// Create new client from environment variable CURSOR_API_KEY
    pub fn from_env() -> anyhow::Result<Self> {
        let api_key = std::env::var("CURSOR_API_KEY")
            .or_else(|_| std::env::var("CURSOR_TOKEN"))
            .map_err(|_| anyhow::anyhow!("CURSOR_API_KEY not set"))?;

        Ok(Self::new(api_key, CursorModel::Claude35Sonnet))
    }

    /// Create new client with specific API key and model
    pub fn new(api_key: String, model: CursorModel) -> Self {
        Self {
            http: Client::new(),
            api_key,
            model,
        }
    }

    /// Change the model for future requests
    pub fn with_model(mut self, model: CursorModel) -> Self {
        self.model = model;
        self
    }
}

#[async_trait]
impl LlmClient for CursorClient {
    fn name(&self) -> &'static str {
        "cursor"
    }

    async fn chat(&self, request: LlmRequest) -> anyhow::Result<String> {
        let body = CursorRequest {
            model: self.model.as_str().to_string(),
            messages: request.messages,
            temperature: request.temperature,
            max_tokens: request.max_tokens,
            stream: false,
        };

        debug!(
            "Sending request to Cursor AI (model: {})",
            self.model.as_str()
        );

        let response = self
            .http
            .post(CURSOR_API_URL)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            warn!("Cursor AI error {}: {}", status, error_text);
            anyhow::bail!("Cursor AI returned status {}: {}", status, error_text);
        }

        let cursor_response: CursorResponse = response.json().await?;

        if let Some(choice) = cursor_response.choices.first() {
            Ok(choice.message.content.clone())
        } else {
            anyhow::bail!("No response from Cursor AI")
        }
    }
}

// ============================================================================
// Request/Response Types (OpenAI-compatible format)
// ============================================================================

#[derive(Debug, Serialize)]
struct CursorRequest {
    model: String,
    messages: Vec<ChatMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<i32>,
    stream: bool,
}

#[derive(Debug, Deserialize)]
struct CursorResponse {
    choices: Vec<CursorChoice>,
}

#[derive(Debug, Deserialize)]
struct CursorChoice {
    message: CursorMessage,
}

#[derive(Debug, Deserialize)]
struct CursorMessage {
    content: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Only run with --ignored (requires CURSOR_API_KEY)
    async fn test_cursor_client() {
        let client = CursorClient::from_env().unwrap();

        let request = LlmRequest {
            model: "claude-3.5-sonnet".to_string(),
            messages: vec![ChatMessage::user("What is 2+2?")],
            temperature: Some(0.7),
            max_tokens: Some(100),
        };

        let response = client.chat(request).await.unwrap();
        println!("Response: {}", response);
        assert!(!response.is_empty());
    }
}
