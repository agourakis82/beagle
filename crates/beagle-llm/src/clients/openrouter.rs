//! OpenRouterClient — generic OpenAI-compatible client for OpenRouter.ai
//!
//! Supports any model available on OpenRouter (Kimi, Llama, Mistral, etc.)
//! Uses OPENROUTER_API_KEY from environment.
//! Default model: moonshotai/kimi-k2.6

use crate::output::TokenUsage;
use crate::{LlmClient, LlmOutput, LlmRequest};
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

/// Token usage object returned by OpenRouter (OpenAI-compatible format).
#[derive(Debug, serde::Deserialize)]
struct Usage {
    prompt_tokens: Option<u32>,
    completion_tokens: Option<u32>,
    total_tokens: Option<u32>,
}

#[derive(Debug, serde::Deserialize)]
struct ApiResponse {
    choices: Vec<Choice>,
    /// Present in successful OpenRouter responses.
    usage: Option<Usage>,
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
    /// Override: captures real usage from the OpenRouter API response instead of estimating chars/4.
    async fn complete(&self, prompt: &str) -> anyhow::Result<LlmOutput> {
        let req = LlmRequest {
            model: "default".to_string(),
            messages: vec![crate::ChatMessage::user(prompt)],
            temperature: Some(0.7),
            max_tokens: Some(8192),
        };
        self.chat_metered(req, prompt).await
    }

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

impl OpenRouterClient {
    /// Metered variant: calls the API and returns LlmOutput with real usage when available.
    async fn chat_metered(
        &self,
        mut req: LlmRequest,
        prompt_for_fallback: &str,
    ) -> anyhow::Result<LlmOutput> {
        if req.model == "default" {
            req.model = self.model.clone();
        }

        debug!("OpenRouterClient (metered): model={}", req.model);

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

        let text = resp.choices[0].message.content.clone();

        // OpenAI-compatible usage: prompt_tokens / completion_tokens / total_tokens
        let maybe_usage = resp
            .usage
            .and_then(|u| match (u.prompt_tokens, u.completion_tokens) {
                (Some(p), Some(c)) => {
                    let total = u.total_tokens.unwrap_or(p + c);
                    Some(TokenUsage::measured(p, c, total))
                }
                _ => None,
            });

        let output = match maybe_usage {
            Some(u) => LlmOutput::with_measured_usage(text, prompt_for_fallback, u),
            None => LlmOutput::from_text(text, prompt_for_fallback),
        };
        Ok(output)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Unit test: parse a representative OpenRouter (OpenAI-compatible) usage JSON.
    /// No network — exercises only the usage extraction path.
    #[test]
    fn test_openrouter_usage_extraction_from_json() {
        // Simulated deserialized ApiResponse
        let usage = Usage {
            prompt_tokens: Some(200),
            completion_tokens: Some(75),
            total_tokens: Some(275),
        };

        let (p, c) = (
            usage.prompt_tokens.unwrap(),
            usage.completion_tokens.unwrap(),
        );
        let total = usage.total_tokens.unwrap_or(p + c);
        let token_usage = TokenUsage::measured(p, c, total);

        assert!(token_usage.measured, "TokenUsage must be measured");
        assert_eq!(token_usage.prompt, 200);
        assert_eq!(token_usage.completion, 75);
        assert_eq!(token_usage.total, 275);

        let output =
            LlmOutput::with_measured_usage("response text".to_string(), "prompt text", token_usage);
        assert!(output.usage.measured);
        assert_eq!(output.usage.prompt, 200);
        assert_eq!(output.usage.completion, 75);
    }

    /// Verify fallback to estimated when usage is absent.
    #[test]
    fn test_openrouter_usage_fallback_when_absent() {
        let usage: Option<Usage> = None;
        let maybe: Option<TokenUsage> =
            usage.and_then(|u| match (u.prompt_tokens, u.completion_tokens) {
                (Some(p), Some(c)) => {
                    Some(TokenUsage::measured(p, c, u.total_tokens.unwrap_or(p + c)))
                }
                _ => None,
            });
        assert!(maybe.is_none());

        let output = match maybe {
            Some(u) => LlmOutput::with_measured_usage("text".to_string(), "prompt", u),
            None => LlmOutput::from_text("text".to_string(), "prompt"),
        };
        assert!(
            !output.usage.measured,
            "Should be estimated when usage absent"
        );
    }

    /// Verify JSON deserialization of a complete OpenRouter-shaped response.
    #[test]
    fn test_openrouter_api_response_deserialization() {
        let raw = serde_json::json!({
            "choices": [
                {
                    "message": {
                        "content": "The answer is 42."
                    }
                }
            ],
            "usage": {
                "prompt_tokens": 11,
                "completion_tokens": 8,
                "total_tokens": 19
            }
        });

        let resp: ApiResponse = serde_json::from_value(raw).unwrap();
        assert_eq!(resp.choices[0].message.content, "The answer is 42.");

        let u = resp.usage.unwrap();
        assert_eq!(u.prompt_tokens, Some(11));
        assert_eq!(u.completion_tokens, Some(8));
        assert_eq!(u.total_tokens, Some(19));

        let (p, c) = (u.prompt_tokens.unwrap(), u.completion_tokens.unwrap());
        let token_usage = TokenUsage::measured(p, c, u.total_tokens.unwrap_or(p + c));
        assert!(token_usage.measured);
        assert_eq!(token_usage.total, 19);
    }
}
