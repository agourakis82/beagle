//! DeepSeekClient - Cliente para Deep Seek API
//!
//! Suporta Deep Seek Chat e Deep Seek Math
//! Usa formato similar ao OpenAI API (chat/completions)

use crate::{LlmClient, LlmRequest};
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
    prompt_tokens: Option<usize>,
    completion_tokens: Option<usize>,
    total_tokens: Option<usize>,
}

#[derive(Debug, serde::Deserialize)]
struct ApiResponse {
    choices: Vec<Choice>,
    usage: Option<Usage>,
}

impl DeepSeekClient {
    pub fn new() -> Self {
        let api_key = env::var("DEEPSEEK_API_KEY")
            .unwrap_or_else(|_| {
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
        client.model = "deepseek-math".to_string();
        client
    }
}

#[async_trait]
impl LlmClient for DeepSeekClient {
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

