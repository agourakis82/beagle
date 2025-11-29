//! GitHub Copilot Chat API Client
//!
//! Uses your GitHub Copilot subscription to access:
//! - Claude 3.5 Sonnet
//! - GPT-4o
//! - o1-preview
//!
//! Requires: GitHub Copilot subscription + GitHub Personal Access Token
//! Setup: export GITHUB_TOKEN=ghp_your_token_here

use crate::{ChatMessage, LlmClient, LlmRequest};
use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::{debug, warn};

const COPILOT_API_URL: &str = "https://api.githubcopilot.com/chat/completions";

/// GitHub Copilot model selection
#[derive(Debug, Clone)]
pub enum CopilotModel {
    /// Claude 3.5 Sonnet (best for research, analysis)
    Claude35Sonnet,
    /// GPT-4o (fast, multimodal)
    Gpt4o,
    /// o1-preview (best for complex reasoning)
    O1Preview,
    /// o1-mini (fast reasoning)
    O1Mini,
}

impl CopilotModel {
    fn as_str(&self) -> &str {
        match self {
            CopilotModel::Claude35Sonnet => "claude-3.5-sonnet",
            CopilotModel::Gpt4o => "gpt-4o",
            CopilotModel::O1Preview => "o1-preview",
            CopilotModel::O1Mini => "o1-mini",
        }
    }
}

/// GitHub Copilot Chat client
pub struct CopilotClient {
    http: Client,
    token: String,
    model: CopilotModel,
}

impl CopilotClient {
    /// Create new client from environment variable GITHUB_TOKEN
    pub fn from_env() -> anyhow::Result<Self> {
        let token = std::env::var("GITHUB_TOKEN")
            .or_else(|_| std::env::var("GH_TOKEN"))
            .map_err(|_| anyhow::anyhow!("GITHUB_TOKEN not set"))?;

        Ok(Self::new(token, CopilotModel::Claude35Sonnet))
    }

    /// Create new client with specific token and model
    pub fn new(token: String, model: CopilotModel) -> Self {
        Self {
            http: Client::new(),
            token,
            model,
        }
    }

    /// Change the model for future requests
    pub fn with_model(mut self, model: CopilotModel) -> Self {
        self.model = model;
        self
    }
}

#[async_trait]
impl LlmClient for CopilotClient {
    fn name(&self) -> &'static str {
        "copilot"
    }

    async fn chat(&self, request: LlmRequest) -> anyhow::Result<String> {
        let body = CopilotRequest {
            model: self.model.as_str().to_string(),
            messages: request.messages,
            temperature: request.temperature,
            max_tokens: request.max_tokens,
            stream: false,
        };

        debug!(
            "Sending request to GitHub Copilot (model: {})",
            self.model.as_str()
        );

        let response = self
            .http
            .post(COPILOT_API_URL)
            .header("Authorization", format!("Bearer {}", self.token))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            warn!("GitHub Copilot error {}: {}", status, error_text);
            anyhow::bail!("GitHub Copilot returned status {}: {}", status, error_text);
        }

        let copilot_response: CopilotResponse = response.json().await?;

        if let Some(choice) = copilot_response.choices.first() {
            Ok(choice.message.content.clone())
        } else {
            anyhow::bail!("No response from GitHub Copilot")
        }
    }
}

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Debug, Serialize)]
struct CopilotRequest {
    model: String,
    messages: Vec<ChatMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<i32>,
    stream: bool,
}

#[derive(Debug, Deserialize)]
struct CopilotResponse {
    choices: Vec<CopilotChoice>,
}

#[derive(Debug, Deserialize)]
struct CopilotChoice {
    message: CopilotMessage,
}

#[derive(Debug, Deserialize)]
struct CopilotMessage {
    content: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Only run with --ignored (requires GITHUB_TOKEN)
    async fn test_copilot_client() {
        let client = CopilotClient::from_env().unwrap();

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
