//! ZaiClient - Cliente para Z.ai / GLM-4.7 (OpenAI-like)
//!
//! Objetivo: oferecer um provider cloud de alta taxa (subscription),
//! configurável via env, com API OpenAI-compatible.
//!
//! Variáveis de ambiente:
//! - `ZAI_API_KEY` (obrigatório)
//! - `ZAI_API_BASE` (default: https://open.bigmodel.cn/api/paas/v4)
//! - `ZAI_CHAT_PATH` (default: inferido a partir de `ZAI_API_BASE`)
//! - `ZAI_MODEL` (default: GLM-4.7)
//! - `ZAI_TIMEOUT_SECS` (default: 120)
//! - `ZAI_API_KEY_HEADER` (default: Authorization)
//! - `ZAI_API_KEY_PREFIX` (default: Bearer)

use crate::{LlmClient, LlmRequest};
use anyhow::Context;
use async_trait::async_trait;
use reqwest::Client;
use serde_json::Value as JsonValue;
use std::env;
use std::time::Duration;
use tracing::debug;

#[derive(Clone)]
pub struct ZaiClient {
    client: Client,
    api_key: String,
    base_url: String,
    path: String,
    model: String,
    api_key_header: String,
    api_key_prefix: String,
}

impl ZaiClient {
    pub fn from_env() -> anyhow::Result<Self> {
        let api_key = env::var("ZAI_API_KEY").map_err(|_| anyhow::anyhow!("ZAI_API_KEY não configurada"))?;

        let base_url = env::var("ZAI_API_BASE")
            .unwrap_or_else(|_| "https://open.bigmodel.cn/api/paas/v4".to_string());
        let base_url = base_url.trim_end_matches('/').to_string();

        let path = env::var("ZAI_CHAT_PATH").unwrap_or_else(|_| infer_default_chat_path(&base_url));
        let path = if path.starts_with('/') {
            path
        } else {
            format!("/{}", path)
        };

        let model = env::var("ZAI_MODEL").unwrap_or_else(|_| "GLM-4.7".to_string());

        let timeout_secs: u64 = env::var("ZAI_TIMEOUT_SECS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(120);

        let api_key_header =
            env::var("ZAI_API_KEY_HEADER").unwrap_or_else(|_| "Authorization".to_string());
        let api_key_prefix =
            env::var("ZAI_API_KEY_PREFIX").unwrap_or_else(|_| "Bearer".to_string());

        let client = Client::builder()
            .timeout(Duration::from_secs(timeout_secs.max(1)))
            .build()
            .context("failed to build reqwest client for Z.ai")?;

        Ok(Self {
            client,
            api_key,
            base_url,
            path,
            model,
            api_key_header,
            api_key_prefix,
        })
    }

    fn endpoint(&self) -> String {
        format!("{}{}", self.base_url, self.path)
    }

    fn auth_header_value(&self) -> String {
        let prefix = self.api_key_prefix.trim();
        if prefix.is_empty() {
            self.api_key.clone()
        } else {
            format!("{} {}", prefix, self.api_key)
        }
    }

    fn extract_text_from_json(resp: &JsonValue) -> anyhow::Result<String> {
        // OpenAI-like:
        // { "choices": [ { "message": { "content": "..." } } ] }
        if let Some(choices) = resp.get("choices").and_then(|v| v.as_array()) {
            if let Some(first) = choices.first() {
                if let Some(content) = first
                    .get("message")
                    .and_then(|m| m.get("content"))
                    .and_then(|c| c.as_str())
                {
                    if !content.trim().is_empty() {
                        return Ok(content.to_string());
                    }
                }
                if let Some(text) = first.get("text").and_then(|t| t.as_str()) {
                    if !text.trim().is_empty() {
                        return Ok(text.to_string());
                    }
                }
            }
        }

        anyhow::bail!("Z.ai API retornou resposta sem texto utilizável: {resp}")
    }
}

fn infer_default_chat_path(base_url: &str) -> String {
    let base = base_url.trim_end_matches('/').to_lowercase();

    // Common Zhipu (BigModel) base: https://open.bigmodel.cn/api/paas/v4
    if base.contains("/api/paas/v4") || base.ends_with("/v4") {
        return "/chat/completions".to_string();
    }

    // If base already ends in /v1, assume OpenAI-like base prefix.
    if base.ends_with("/v1") {
        return "/chat/completions".to_string();
    }

    "/v1/chat/completions".to_string()
}

#[async_trait]
impl LlmClient for ZaiClient {
    async fn chat(&self, mut req: LlmRequest) -> anyhow::Result<String> {
        if req.model == "default" {
            req.model = self.model.clone();
        }

        debug!(
            "ZaiClient: model={} base={} path={}",
            req.model, self.base_url, self.path
        );

        let request_body = serde_json::json!({
            "model": req.model,
            "messages": req.messages,
            "temperature": req.temperature.unwrap_or(0.7),
            "max_tokens": req.max_tokens.unwrap_or(8192),
        });

        let response = self
            .client
            .post(self.endpoint())
            .header(&self.api_key_header, self.auth_header_value())
            .header("Content-Type", "application/json")
            .json(&request_body)
            .send()
            .await?;

        let status = response.status();
        let resp_text = response.text().await.unwrap_or_default();
        if !status.is_success() {
            anyhow::bail!("Z.ai API error {}: {}", status, resp_text);
        }

        let resp_json: JsonValue =
            serde_json::from_str(&resp_text).context("failed to parse Z.ai JSON response")?;
        Self::extract_text_from_json(&resp_json)
    }

    fn name(&self) -> &'static str {
        "zai"
    }

    fn tier(&self) -> crate::Tier {
        crate::Tier::CloudGrokMain
    }

    fn prefers_heavy(&self) -> bool {
        false
    }
}

