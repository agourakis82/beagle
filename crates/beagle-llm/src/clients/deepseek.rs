//! DeepSeekClient - Cliente para Deep Seek API
//!
//! Suporta Deep Seek Chat e Deep Seek Math
//! Usa formato similar ao OpenAI API (chat/completions)

use crate::output::TokenUsage;
use crate::{LlmClient, LlmOutput, LlmRequest};
use async_trait::async_trait;
use reqwest::Client;
use std::env;
use tracing::{debug, warn};

#[derive(Clone)]
pub struct DeepSeekClient {
    client: Client,
    api_key: String,
    model: String,
}

#[derive(Debug, serde::Deserialize)]
struct ChoiceMessage {
    content: String,
}

#[derive(Debug, serde::Deserialize)]
struct Choice {
    message: ChoiceMessage,
    finish_reason: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
struct Usage {
    prompt_tokens: Option<u32>,
    completion_tokens: Option<u32>,
    total_tokens: Option<u32>,
}

#[derive(Debug, serde::Deserialize)]
struct ApiResponse {
    choices: Vec<Choice>,
    usage: Option<Usage>,
}

impl DeepSeekClient {
    pub fn new() -> Self {
        let api_key = env::var("DEEPSEEK_API_KEY").unwrap_or_else(|_| {
            warn!("DEEPSEEK_API_KEY não configurada, usando valor vazio (falhará em runtime)");
            String::new()
        });

        Self {
            client: Client::new(),
            api_key,
            model: "deepseek-chat".to_string(),
        }
    }

    /// Cria cliente para Deep Seek Math
    pub fn new_math() -> Self {
        let mut client = Self::new();
        // DeepSeek retired "deepseek-math"; the API now accepts deepseek-v4-pro / deepseek-v4-flash.
        // A stale model id makes the API 400 → recall synthesis failed → 502. Use the supported one.
        client.model = "deepseek-v4-pro".to_string();
        client
    }
}

#[async_trait]
impl LlmClient for DeepSeekClient {
    /// Override: captures real usage from the DeepSeek API response instead of estimating chars/4.
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
        // Se o modelo já foi especificado, usa; senão, usa o default do cliente
        if req.model == "default" {
            req.model = self.model.clone();
        }

        debug!("DeepSeekClient: usando modelo {}", req.model);

        let request_body = serde_json::json!({
            "model": req.model,
            "messages": req.messages,
            "temperature": req.temperature.unwrap_or(0.7),
            "max_tokens": req.max_tokens.unwrap_or(8192),
        });

        let response = self
            .client
            .post("https://api.deepseek.com/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&request_body)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            anyhow::bail!("DeepSeek API error {}: {}", status, error_text);
        }

        let resp: ApiResponse = response.json().await?;

        if resp.choices.is_empty() {
            anyhow::bail!("DeepSeek API retornou resposta vazia");
        }

        Ok(resp.choices[0].message.content.clone())
    }

    fn name(&self) -> &'static str {
        "deepseek"
    }

    fn tier(&self) -> crate::Tier {
        crate::Tier::CloudMath
    }

    fn prefers_heavy(&self) -> bool {
        false // Deep Seek é para math, não "heavy" no sentido Grok
    }
}

impl DeepSeekClient {
    /// Metered variant: calls the API and returns LlmOutput with real usage when available.
    async fn chat_metered(
        &self,
        mut req: LlmRequest,
        prompt_for_fallback: &str,
    ) -> anyhow::Result<LlmOutput> {
        if req.model == "default" {
            req.model = self.model.clone();
        }

        debug!("DeepSeekClient (metered): usando modelo {}", req.model);

        let request_body = serde_json::json!({
            "model": req.model,
            "messages": req.messages,
            "temperature": req.temperature.unwrap_or(0.7),
            "max_tokens": req.max_tokens.unwrap_or(8192),
        });

        let response = self
            .client
            .post("https://api.deepseek.com/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&request_body)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            anyhow::bail!("DeepSeek API error {}: {}", status, error_text);
        }

        let resp: ApiResponse = response.json().await?;

        if resp.choices.is_empty() {
            anyhow::bail!("DeepSeek API retornou resposta vazia");
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

    /// Unit test: parse a representative DeepSeek (OpenAI-compatible) usage JSON.
    /// No network — exercises only the usage extraction path.
    #[test]
    fn test_deepseek_usage_extraction_from_json() {
        // Simulated deserialized ApiResponse usage field
        let usage = Usage {
            prompt_tokens: Some(100),
            completion_tokens: Some(50),
            total_tokens: Some(150),
        };

        let (p, c) = (
            usage.prompt_tokens.unwrap(),
            usage.completion_tokens.unwrap(),
        );
        let total = usage.total_tokens.unwrap_or(p + c);
        let token_usage = TokenUsage::measured(p, c, total);

        assert!(token_usage.measured, "TokenUsage must be measured");
        assert_eq!(token_usage.prompt, 100);
        assert_eq!(token_usage.completion, 50);
        assert_eq!(token_usage.total, 150);

        let output = LlmOutput::with_measured_usage("answer".to_string(), "question", token_usage);
        assert!(output.usage.measured);
        assert_eq!(output.usage.prompt, 100);
        assert_eq!(output.usage.completion, 50);
    }

    /// Verify fallback to estimated when usage is absent.
    #[test]
    fn test_deepseek_usage_fallback_when_absent() {
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

    /// Verify JSON deserialization of a complete DeepSeek-shaped response.
    #[test]
    fn test_deepseek_api_response_deserialization() {
        let raw = serde_json::json!({
            "choices": [
                {
                    "message": { "content": "Beagle is alive." },
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": 30,
                "completion_tokens": 10,
                "total_tokens": 40
            }
        });

        let resp: ApiResponse = serde_json::from_value(raw).unwrap();
        assert_eq!(resp.choices[0].message.content, "Beagle is alive.");
        assert_eq!(resp.choices[0].finish_reason.as_deref(), Some("stop"));

        let u = resp.usage.unwrap();
        let (p, c) = (u.prompt_tokens.unwrap(), u.completion_tokens.unwrap());
        let token_usage = TokenUsage::measured(p, c, u.total_tokens.unwrap_or(p + c));
        assert!(token_usage.measured);
        assert_eq!(token_usage.prompt, 30);
        assert_eq!(token_usage.completion, 10);
        assert_eq!(token_usage.total, 40);
    }
}
