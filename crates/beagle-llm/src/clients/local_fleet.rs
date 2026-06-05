//! LocalFleetClient — first-class OpenAI-compatible backend for the in-cluster LLM fleet.
//!
//! Points at the cluster's LiteLLM router (which fronts the vLLM models: Qwen, Phi-4, the
//! exotic ensemble, etc.) via the standard `/chat/completions` endpoint. This is what lets
//! the [`crate::TieredRouter`] default to the *local fleet* instead of being hard-wired to
//! Grok — the workhorse tier becomes provider-agnostic and self-hosted.
//!
//! Configuration is entirely from the environment so the same binary runs in-cluster, against
//! a local box, or against any OpenAI-compatible endpoint without recompiling:
//!   - `BEAGLE_LLM_FLEET_URL` | `LLM_ROUTER_URL` | `OPENAI_API_BASE` | `OPENAI_BASE_URL` — base URL (must include `/v1`)
//!   - `BEAGLE_LLM_FLEET_ENABLE=1` — opt in to the in-cluster default URL when no URL var is set
//!   - `BEAGLE_LLM_FLEET_MODEL` | `LLM_ROUTER_MODEL` — default model id (router-side friendly key)
//!   - `LLM_ROUTER_API_KEY` | `OPENAI_API_KEY` — optional bearer for the gateway

use crate::{ChatMessage, LlmClient, LlmRequest};
use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::debug;

/// In-cluster LiteLLM router (OpenAI-compatible) fronting the vLLM fleet.
const DEFAULT_URL: &str = "http://router.llm-router.svc.cluster.local:4000/v1";
const DEFAULT_MODEL: &str = "chat-fast";

pub struct LocalFleetClient {
    http: Client,
    base_url: String,
    model: String,
    api_key: Option<String>,
}

#[derive(Serialize)]
struct ChatReq<'a> {
    model: &'a str,
    messages: &'a [ChatMessage],
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<i32>,
}

#[derive(Deserialize)]
struct ChatResp {
    choices: Vec<Choice>,
}
#[derive(Deserialize)]
struct Choice {
    message: Msg,
}
#[derive(Deserialize)]
struct Msg {
    content: String,
}

impl LocalFleetClient {
    pub fn new(base_url: impl Into<String>, model: impl Into<String>) -> Self {
        let http = Client::builder()
            .timeout(Duration::from_secs(120))
            .build()
            .unwrap_or_default();
        Self {
            http,
            base_url: base_url.into().trim_end_matches('/').to_string(),
            model: model.into(),
            api_key: std::env::var("LLM_ROUTER_API_KEY")
                .ok()
                .or_else(|| std::env::var("OPENAI_API_KEY").ok()),
        }
    }

    /// Build from the environment. Returns `None` unless a fleet endpoint is configured (a URL
    /// var, or `BEAGLE_LLM_FLEET_ENABLE` truthy → in-cluster default), so the router only
    /// defaults to the local fleet when the operator has opted in — existing Grok-based setups
    /// are unaffected.
    pub fn from_env() -> Option<Self> {
        let url = std::env::var("BEAGLE_LLM_FLEET_URL")
            .or_else(|_| std::env::var("LLM_ROUTER_URL"))
            .or_else(|_| std::env::var("OPENAI_API_BASE"))
            .or_else(|_| std::env::var("OPENAI_BASE_URL"))
            .ok();
        let enable_default = matches!(
            std::env::var("BEAGLE_LLM_FLEET_ENABLE").as_deref(),
            Ok("1") | Ok("true") | Ok("TRUE") | Ok("yes")
        );
        let base = url.or(if enable_default {
            Some(DEFAULT_URL.to_string())
        } else {
            None
        })?;
        let model = std::env::var("BEAGLE_LLM_FLEET_MODEL")
            .or_else(|_| std::env::var("LLM_ROUTER_MODEL"))
            .unwrap_or_else(|_| DEFAULT_MODEL.to_string());
        Some(Self::new(base, model))
    }
}

#[async_trait]
impl LlmClient for LocalFleetClient {
    fn name(&self) -> &'static str {
        "local-fleet"
    }

    async fn chat(&self, req: LlmRequest) -> anyhow::Result<String> {
        // Honor the caller's model when it names a real model; otherwise use the fleet default.
        let model = if req.model.is_empty() || req.model == "default" {
            self.model.as_str()
        } else {
            req.model.as_str()
        };
        let body = ChatReq {
            model,
            messages: &req.messages,
            temperature: req.temperature,
            max_tokens: req.max_tokens,
        };
        let url = format!("{}/chat/completions", self.base_url);
        let mut rb = self.http.post(&url).json(&body);
        if let Some(k) = &self.api_key {
            rb = rb.bearer_auth(k);
        }
        debug!(target: "beagle_llm::local_fleet", %url, model, "local fleet chat");
        let resp = rb.send().await?;
        if !resp.status().is_success() {
            let st = resp.status();
            let t = resp.text().await.unwrap_or_default();
            anyhow::bail!(
                "local fleet {} error {}: {}",
                self.base_url,
                st,
                t.chars().take(200).collect::<String>()
            );
        }
        let parsed: ChatResp = resp.json().await?;
        parsed
            .choices
            .into_iter()
            .next()
            .map(|c| c.message.content)
            .ok_or_else(|| anyhow::anyhow!("local fleet returned no choices"))
    }
}
