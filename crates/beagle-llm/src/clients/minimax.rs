//! MiniMaxClient - Cliente para MiniMax 2.1 API
//!
//! Objetivo: usar MiniMax como Tier 1 default (quando habilitado),
//! com fallback para Grok e DeepSeek via TieredRouter.
//!
//! A MiniMax expõe um endpoint Anthropic-compatible em:
//! - `https://api.minimax.io/anthropic/v1/messages`
//!
//! Este cliente suporta dois modos:
//! - `anthropic` (default): `POST {MINIMAX_API_BASE}/messages` com `x-api-key`
//! - `openai`: `POST {MINIMAX_API_BASE}{MINIMAX_CHAT_PATH}` com `Authorization: Bearer`
//!
//! Se `MINIMAX_API_COMPAT` não for definido, o modo é inferido a partir de `MINIMAX_API_BASE`.

use crate::{LlmClient, LlmRequest};
use anyhow::Context;
use async_trait::async_trait;
use reqwest::Client;
use serde_json::Value as JsonValue;
use std::env;
use std::time::Duration;
use tracing::debug;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MiniMaxCompat {
    Anthropic,
    OpenAi,
}

#[derive(Clone)]
pub struct MiniMaxClient {
    client: Client,
    api_key: String,
    base_url: String,
    compat: MiniMaxCompat,
    path: String,
    anthropic_version: String,
    model: String,
}

impl MiniMaxClient {
    pub fn from_env() -> anyhow::Result<Self> {
        let api_key = env::var("MINIMAX_API_KEY")
            .or_else(|_| env::var("MINIMAX_KEY"))
            .map_err(|_| anyhow::anyhow!("MINIMAX_API_KEY não configurada"))?;

        let base_url = env::var("MINIMAX_API_BASE")
            .or_else(|_| env::var("MINIMAX_BASE_URL"))
            .unwrap_or_else(|_| "https://api.minimax.io/anthropic/v1".to_string());

        let compat = match env::var("MINIMAX_API_COMPAT")
            .unwrap_or_default()
            .trim()
            .to_lowercase()
            .as_str()
        {
            "openai" | "openai-like" | "openai_compatible" => MiniMaxCompat::OpenAi,
            "anthropic" | "anthropic-like" | "anthropic_compatible" => MiniMaxCompat::Anthropic,
            _ => {
                if base_url.to_lowercase().contains("/anthropic/") {
                    MiniMaxCompat::Anthropic
                } else {
                    MiniMaxCompat::OpenAi
                }
            }
        };

        let anthropic_version = env::var("MINIMAX_ANTHROPIC_VERSION")
            .unwrap_or_else(|_| "2023-06-01".to_string());

        let path = match compat {
            MiniMaxCompat::Anthropic => env::var("MINIMAX_MESSAGES_PATH")
                .unwrap_or_else(|_| "/messages".to_string()),
            MiniMaxCompat::OpenAi => env::var("MINIMAX_CHAT_PATH")
                .unwrap_or_else(|_| "/v1/chat/completions".to_string()),
        };

        // Model names differ by MiniMax account/config. Keep configurable.
        let model = env::var("MINIMAX_MODEL").unwrap_or_else(|_| "MiniMax-M2.1".to_string());

        let client = Client::builder()
            .timeout(Duration::from_secs(90))
            .build()?;

        Ok(Self {
            client,
            api_key,
            base_url: base_url.trim_end_matches('/').to_string(),
            compat,
            path,
            anthropic_version,
            model,
        })
    }

    fn endpoint(&self) -> String {
        let path = if self.path.starts_with('/') {
            self.path.clone()
        } else {
            format!("/{}", self.path)
        };
        format!("{}{}", self.base_url, path)
    }

    fn split_system_messages(
        messages: Vec<crate::ChatMessage>,
    ) -> (Option<String>, Vec<crate::ChatMessage>) {
        let mut system_parts = Vec::new();
        let mut out = Vec::new();
        for msg in messages {
            if msg.role.eq_ignore_ascii_case("system") {
                if !msg.content.trim().is_empty() {
                    system_parts.push(msg.content);
                }
            } else {
                out.push(msg);
            }
        }
        let system = if system_parts.is_empty() {
            None
        } else {
            Some(system_parts.join("\n\n"))
        };
        (system, out)
    }

    fn extract_text_from_json(resp: &JsonValue) -> anyhow::Result<String> {
        // Anthropic Messages response:
        // { "content": [ { "type": "text", "text": "..." }, ... ] }
        if let Some(items) = resp.get("content").and_then(|v| v.as_array()) {
            let mut parts = Vec::new();
            for item in items {
                if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                    if !text.trim().is_empty() {
                        parts.push(text.to_string());
                    }
                }
            }
            if !parts.is_empty() {
                return Ok(parts.join(""));
            }
        }

        // OpenAI-like response:
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

        anyhow::bail!("MiniMax API retornou resposta sem texto utilizável: {resp}")
    }
}

#[async_trait]
impl LlmClient for MiniMaxClient {
    async fn chat(&self, mut req: LlmRequest) -> anyhow::Result<String> {
        if req.model == "default" {
            req.model = self.model.clone();
        }

        debug!(
            "MiniMaxClient: compat={:?} model={} base={}",
            self.compat, req.model, self.base_url
        );

        let (system, messages) = Self::split_system_messages(req.messages);
        if messages.is_empty() {
            anyhow::bail!("MiniMax request has no non-system messages");
        }

        let request_body = match self.compat {
            MiniMaxCompat::Anthropic => {
                let mut body = serde_json::json!({
                    "model": req.model,
                    "messages": messages,
                    "max_tokens": req.max_tokens.unwrap_or(8192).max(1),
                });
                if let Some(t) = req.temperature {
                    body["temperature"] = serde_json::json!(t);
                }
                if let Some(system) = system {
                    body["system"] = serde_json::Value::String(system);
                }
                body
            }
            MiniMaxCompat::OpenAi => {
                serde_json::json!({
                    "model": req.model,
                    "messages": messages,
                    "temperature": req.temperature.unwrap_or(0.7),
                    "max_tokens": req.max_tokens.unwrap_or(8192),
                })
            }
        };

        let mut builder = self.client.post(self.endpoint());
        builder = match self.compat {
            MiniMaxCompat::Anthropic => builder
                .header("x-api-key", &self.api_key)
                .header("anthropic-version", &self.anthropic_version),
            MiniMaxCompat::OpenAi => builder.header("Authorization", format!("Bearer {}", self.api_key)),
        };

        let response = builder
            .header("Content-Type", "application/json")
            .json(&request_body)
            .send()
            .await?;

        let status = response.status();
        let resp_text = response.text().await.unwrap_or_default();
        if !status.is_success() {
            anyhow::bail!("MiniMax API error {}: {}", status, resp_text);
        }

        let resp_json: JsonValue =
            serde_json::from_str(&resp_text).context("failed to parse MiniMax JSON response")?;
        Self::extract_text_from_json(&resp_json)
    }

    fn name(&self) -> &'static str {
        "minimax"
    }

    fn tier(&self) -> crate::Tier {
        crate::Tier::CloudGrokMain
    }
}
