use crate::tool_bridge_ledger::{append_ledger_entry, BridgeLedgerEntry};
use crate::tool_bridge_types::{
    BridgeHealth, BridgeKind, BridgeMode, BridgeProvider, BridgeProviderInfo, BridgeRequest,
    BridgeResponse, BridgeStatus, BridgeTokenUsage,
};
use anyhow::Context;
use beagle_config::BeagleConfig;
use chrono::Utc;
use reqwest::Client;
use serde::Deserialize;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::time::{Duration, Instant};
use tracing::{info, warn};

#[derive(Clone)]
pub struct ToolBridge {
    cfg: ToolBridgeRuntimeConfig,
    safe_mode: bool,
    data_dir: PathBuf,
    http: Client,
}

#[derive(Debug, Clone)]
struct ToolBridgeRuntimeConfig {
    deepseek_api_key: Option<String>,
    zai_api_key: Option<String>,
    groq_api_key: Option<String>,
    xai_api_key: Option<String>,
    minimax_api_key: Option<String>,
    deepseek_base_url: String,
    zai_base_url: String,
    groq_base_url: String,
    xai_base_url: String,
    minimax_base_url: String,
    grok_fast_model: String,
    kimi_model: String,
    default_timeout_seconds: u64,
    ledger_enabled: bool,
    dry_run: bool,
}

#[derive(Debug, Deserialize)]
struct DeepSeekChoiceMessage {
    content: String,
}

#[derive(Debug, Deserialize)]
struct DeepSeekChoice {
    message: DeepSeekChoiceMessage,
}

#[derive(Debug, Deserialize)]
struct DeepSeekUsage {
    prompt_tokens: Option<u64>,
    completion_tokens: Option<u64>,
    total_tokens: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct DeepSeekResponse {
    choices: Vec<DeepSeekChoice>,
    #[serde(default)]
    usage: Option<DeepSeekUsage>,
}

#[derive(Debug, Deserialize)]
struct AnthropicContentBlock {
    #[serde(rename = "type")]
    block_type: Option<String>,
    #[serde(default)]
    text: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AnthropicUsage {
    input_tokens: Option<u64>,
    output_tokens: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct AnthropicResponse {
    #[serde(default)]
    content: Vec<AnthropicContentBlock>,
    #[serde(default)]
    usage: Option<AnthropicUsage>,
}

impl ToolBridge {
    pub fn from_config(cfg: &BeagleConfig) -> anyhow::Result<Self> {
        let runtime_cfg = ToolBridgeRuntimeConfig {
            deepseek_api_key: cfg.llm.deepseek_api_key.clone(),
            zai_api_key: cfg.llm.zai_api_key.clone(),
            groq_api_key: cfg.llm.groq_api_key.clone(),
            xai_api_key: cfg.llm.xai_api_key.clone(),
            minimax_api_key: cfg.llm.minimax_api_key.clone(),
            deepseek_base_url: cfg
                .llm
                .deepseek_base_url
                .clone()
                .unwrap_or_else(|| "https://api.deepseek.com".to_string()),
            zai_base_url: cfg
                .llm
                .zai_base_url
                .clone()
                .unwrap_or_else(|| "https://open.bigmodel.cn/api/paas/v4".to_string()),
            groq_base_url: cfg
                .llm
                .groq_base_url
                .clone()
                .unwrap_or_else(|| "https://api.groq.com/openai/v1".to_string()),
            xai_base_url: cfg
                .llm
                .xai_base_url
                .clone()
                .unwrap_or_else(|| "https://api.x.ai/v1".to_string()),
            minimax_base_url: cfg
                .llm
                .minimax_base_url
                .clone()
                .unwrap_or_else(|| "https://api.minimax.io/anthropic".to_string()),
            grok_fast_model: if cfg.llm.grok_model == "grok-3" {
                "grok-4-1-fast-reasoning".to_string()
            } else {
                cfg.llm.grok_model.clone()
            },
            kimi_model: cfg.llm.kimi_model.clone(),
            default_timeout_seconds: cfg.tool_bridge.default_timeout_seconds,
            ledger_enabled: cfg.tool_bridge.ledger_enabled,
            dry_run: cfg.tool_bridge.dry_run,
        };

        let http = Client::builder()
            .timeout(Duration::from_secs(runtime_cfg.default_timeout_seconds))
            .build()
            .context("failed to build tool bridge HTTP client")?;

        Ok(Self {
            cfg: runtime_cfg,
            safe_mode: cfg.safe_mode,
            data_dir: PathBuf::from(&cfg.storage.data_dir),
            http,
        })
    }

    pub fn health(&self) -> BridgeHealth {
        let providers = self.providers();
        BridgeHealth {
            status: "ok".to_string(),
            safe_mode: self.safe_mode,
            dry_run: self.cfg.dry_run,
            ledger_enabled: self.cfg.ledger_enabled,
            data_dir: self.data_dir.display().to_string(),
            implemented_providers: providers.iter().filter(|p| p.implemented).count(),
            configured_providers: providers.iter().filter(|p| p.configured).count(),
        }
    }

    pub fn providers(&self) -> Vec<BridgeProviderInfo> {
        vec![
            BridgeProviderInfo {
                provider: BridgeProvider::Deepseek,
                bridge_kind: BridgeKind::CheapApi,
                bridge_mode: BridgeMode::ApiOptional,
                implemented: true,
                configured: self.cfg.deepseek_api_key.is_some(),
                cluster_callable: true,
                default_model: Some("deepseek-chat".to_string()),
                notes: vec!["cheap API lane".to_string()],
            },
            BridgeProviderInfo {
                provider: BridgeProvider::Glm5,
                bridge_kind: BridgeKind::CheapApi,
                bridge_mode: BridgeMode::ApiOptional,
                implemented: true,
                configured: self.cfg.zai_api_key.is_some(),
                cluster_callable: true,
                default_model: Some("glm-5".to_string()),
                notes: vec!["cheap API lane via ZAI".to_string()],
            },
            BridgeProviderInfo {
                provider: BridgeProvider::GrokFast,
                bridge_kind: BridgeKind::CheapApi,
                bridge_mode: BridgeMode::ApiOptional,
                implemented: true,
                configured: self.cfg.xai_api_key.is_some(),
                cluster_callable: true,
                default_model: Some(self.cfg.grok_fast_model.clone()),
                notes: vec!["cheap API lane via xAI".to_string()],
            },
            BridgeProviderInfo {
                provider: BridgeProvider::Minimax,
                bridge_kind: BridgeKind::CheapApi,
                bridge_mode: BridgeMode::ApiOptional,
                implemented: true,
                configured: self.cfg.minimax_api_key.is_some(),
                cluster_callable: true,
                default_model: Some("MiniMax-M2.7".to_string()),
                notes: vec!["cheap API lane via MiniMax Anthropic-compatible API".to_string()],
            },
            BridgeProviderInfo {
                provider: BridgeProvider::Kimi,
                bridge_kind: BridgeKind::CheapApi,
                bridge_mode: BridgeMode::ApiOptional,
                implemented: true,
                configured: self.cfg.groq_api_key.is_some(),
                cluster_callable: true,
                default_model: Some(self.cfg.kimi_model.clone()),
                notes: vec!["cheap API lane via Groq".to_string()],
            },
            BridgeProviderInfo {
                provider: BridgeProvider::CodexHuman,
                bridge_kind: BridgeKind::HumanPremium,
                bridge_mode: BridgeMode::HumanSession,
                implemented: true,
                configured: false,
                cluster_callable: false,
                default_model: None,
                notes: vec!["represented in contract; never executed automatically by cluster".to_string()],
            },
            BridgeProviderInfo {
                provider: BridgeProvider::ClaudeHuman,
                bridge_kind: BridgeKind::HumanPremium,
                bridge_mode: BridgeMode::HumanSession,
                implemented: true,
                configured: false,
                cluster_callable: false,
                default_model: None,
                notes: vec!["represented in contract; never executed automatically by cluster".to_string()],
            },
            BridgeProviderInfo {
                provider: BridgeProvider::McpGeneric,
                bridge_kind: BridgeKind::McpConnector,
                bridge_mode: BridgeMode::McpServer,
                implemented: false,
                configured: false,
                cluster_callable: false,
                default_model: None,
                notes: vec!["MCP lane reserved for later bridge materialization".to_string()],
            },
        ]
    }

    pub async fn execute(&self, request: BridgeRequest) -> BridgeResponse {
        let started = Instant::now();
        let (provider, model) = match self.resolve_provider(&request) {
            Ok(resolved) => resolved,
            Err(error) => {
                return self.finalize_response(
                    request,
                    None,
                    None,
                    BridgeStatus::Error,
                    started.elapsed().as_millis(),
                    None,
                    None,
                    json!({}),
                    Some(error),
                    vec![],
                );
            }
        };

        if matches!(provider, BridgeProvider::CodexHuman | BridgeProvider::ClaudeHuman)
            || request.bridge_mode == BridgeMode::HumanSession
            || request.bridge_kind == BridgeKind::HumanPremium
        {
            return self.finalize_response(
                request,
                Some(provider),
                Some(model),
                BridgeStatus::Deferred,
                started.elapsed().as_millis(),
                None,
                None,
                json!({
                    "message": "human premium lane is representable but never executed automatically by the cluster"
                }),
                None,
                vec!["operator action required".to_string()],
            );
        }

        if matches!(provider, BridgeProvider::McpGeneric)
            || request.bridge_mode == BridgeMode::McpServer
            || request.bridge_kind == BridgeKind::McpConnector
        {
            return self.finalize_response(
                request,
                Some(provider),
                Some(model),
                BridgeStatus::Deferred,
                started.elapsed().as_millis(),
                None,
                None,
                json!({}),
                Some("mcp bridge lane is not wired yet in B12.2b".to_string()),
                vec!["contract ready; runtime bridge still pending".to_string()],
            );
        }

        if self.cfg.dry_run {
            return self.finalize_response(
                request,
                Some(provider),
                Some(model),
                BridgeStatus::Deferred,
                started.elapsed().as_millis(),
                None,
                None,
                json!({
                    "message": "tool bridge dry-run enabled; no provider call executed"
                }),
                None,
                vec!["BEAGLE_TOOL_BRIDGE_DRY_RUN=true".to_string()],
            );
        }

        match provider {
            BridgeProvider::Deepseek => {
                match self.execute_deepseek(&request, &model).await {
                    Ok((output, usage, cost)) => self.finalize_response(
                        request,
                        Some(provider),
                        Some(model),
                        BridgeStatus::Success,
                        started.elapsed().as_millis(),
                        usage,
                        cost,
                        output,
                        None,
                        vec![],
                    ),
                    Err(error) => self.finalize_response(
                        request,
                        Some(provider),
                        Some(model),
                        BridgeStatus::Error,
                        started.elapsed().as_millis(),
                        None,
                        None,
                        json!({}),
                        Some(error),
                        vec![],
                    ),
                }
            }
            BridgeProvider::Glm5 => {
                match self.execute_glm5(&request, &model).await {
                    Ok((output, usage, cost)) => self.finalize_response(
                        request,
                        Some(provider),
                        Some(model),
                        BridgeStatus::Success,
                        started.elapsed().as_millis(),
                        usage,
                        cost,
                        output,
                        None,
                        vec![],
                    ),
                    Err(error) => self.finalize_response(
                        request,
                        Some(provider),
                        Some(model),
                        BridgeStatus::Error,
                        started.elapsed().as_millis(),
                        None,
                        None,
                        json!({}),
                        Some(error),
                        vec![],
                    ),
                }
            }
            BridgeProvider::Minimax => {
                match self.execute_minimax(&request, &model).await {
                    Ok((output, usage, cost)) => self.finalize_response(
                        request,
                        Some(provider),
                        Some(model),
                        BridgeStatus::Success,
                        started.elapsed().as_millis(),
                        usage,
                        cost,
                        output,
                        None,
                        vec![],
                    ),
                    Err(error) => self.finalize_response(
                        request,
                        Some(provider),
                        Some(model),
                        BridgeStatus::Error,
                        started.elapsed().as_millis(),
                        None,
                        None,
                        json!({}),
                        Some(error),
                        vec![],
                    ),
                }
            }
            BridgeProvider::Kimi => {
                match self.execute_kimi(&request, &model).await {
                    Ok((output, usage, cost)) => self.finalize_response(
                        request,
                        Some(provider),
                        Some(model),
                        BridgeStatus::Success,
                        started.elapsed().as_millis(),
                        usage,
                        cost,
                        output,
                        None,
                        vec![],
                    ),
                    Err(error) => self.finalize_response(
                        request,
                        Some(provider),
                        Some(model),
                        BridgeStatus::Error,
                        started.elapsed().as_millis(),
                        None,
                        None,
                        json!({}),
                        Some(error),
                        vec![],
                    ),
                }
            }
            BridgeProvider::GrokFast => {
                match self.execute_grok_fast(&request, &model).await {
                    Ok((output, usage, cost)) => self.finalize_response(
                        request,
                        Some(provider),
                        Some(model),
                        BridgeStatus::Success,
                        started.elapsed().as_millis(),
                        usage,
                        cost,
                        output,
                        None,
                        vec![],
                    ),
                    Err(error) => self.finalize_response(
                        request,
                        Some(provider),
                        Some(model),
                        BridgeStatus::Error,
                        started.elapsed().as_millis(),
                        None,
                        None,
                        json!({}),
                        Some(error),
                        vec![],
                    ),
                }
            }
            BridgeProvider::CodexHuman
            | BridgeProvider::ClaudeHuman
            | BridgeProvider::McpGeneric => unreachable!("handled above"),
        }
    }

    fn resolve_provider(
        &self,
        request: &BridgeRequest,
    ) -> Result<(BridgeProvider, String), String> {
        let provider = if let Some(provider) = request.provider {
            provider
        } else if matches!(request.bridge_kind, BridgeKind::CheapApi)
            || matches!(request.bridge_mode, BridgeMode::CheapApi | BridgeMode::ApiOptional)
        {
            if self.cfg.deepseek_api_key.is_some() {
                BridgeProvider::Deepseek
            } else if self.cfg.zai_api_key.is_some() {
                BridgeProvider::Glm5
            } else if self.cfg.xai_api_key.is_some() {
                BridgeProvider::GrokFast
            } else if self.cfg.minimax_api_key.is_some() {
                BridgeProvider::Minimax
            } else if self.cfg.groq_api_key.is_some() {
                BridgeProvider::Kimi
            } else {
                return Err("no cheap API provider is configured".to_string());
            }
        } else {
            return Err("provider is required for non-cheap-api bridge requests".to_string());
        };

        let model = request.model.clone().unwrap_or_else(|| match provider {
            BridgeProvider::Deepseek => "deepseek-chat".to_string(),
            BridgeProvider::Glm5 => "glm-5".to_string(),
            BridgeProvider::GrokFast => self.cfg.grok_fast_model.clone(),
            BridgeProvider::Minimax => "MiniMax-M2.7".to_string(),
            BridgeProvider::Kimi => self.cfg.kimi_model.clone(),
            BridgeProvider::CodexHuman => "codex-human".to_string(),
            BridgeProvider::ClaudeHuman => "claude-human".to_string(),
            BridgeProvider::McpGeneric => "mcp-generic".to_string(),
        });

        Ok((provider, model))
    }

    async fn execute_deepseek(
        &self,
        request: &BridgeRequest,
        model: &str,
    ) -> Result<(Value, Option<BridgeTokenUsage>, Option<f64>), String> {
        let api_key = self
            .cfg
            .deepseek_api_key
            .as_deref()
            .ok_or_else(|| "DEEPSEEK_API_KEY is not configured".to_string())?;

        let input = extract_input(&request.payload);
        if input.trim().is_empty() {
            return Err("payload.input must be a non-empty string".to_string());
        }

        let url = format!(
            "{}/v1/chat/completions",
            self.cfg.deepseek_base_url.trim_end_matches('/')
        );
        let system_prompt = format!(
            "You are the Beagle tool bridge on the cheap API lane. task_type={}. Return a direct, useful response.",
            request.task_type
        );
        let body = json!({
            "model": model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": input}
            ],
            "temperature": 0.2,
            "max_tokens": 2048
        });

        let response = self
            .http
            .post(url)
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("deepseek request failed: {}", e))?;

        let status = response.status();
        if !status.is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(format!("deepseek returned {}: {}", status, text));
        }

        let data: DeepSeekResponse = response
            .json()
            .await
            .map_err(|e| format!("failed to parse deepseek response: {}", e))?;

        let content = data
            .choices
            .first()
            .map(|choice| choice.message.content.clone())
            .unwrap_or_default();

        let usage = data.usage.map(|usage| BridgeTokenUsage {
            input_tokens: usage.prompt_tokens,
            output_tokens: usage.completion_tokens,
            total_tokens: usage.total_tokens,
        });

        Ok((json!({ "text": content }), usage, None))
    }

    async fn execute_glm5(
        &self,
        request: &BridgeRequest,
        model: &str,
    ) -> Result<(Value, Option<BridgeTokenUsage>, Option<f64>), String> {
        let api_key = self
            .cfg
            .zai_api_key
            .as_deref()
            .ok_or_else(|| "ZAI_API_KEY is not configured".to_string())?;

        let input = extract_input(&request.payload);
        if input.trim().is_empty() {
            return Err("payload.input must be a non-empty string".to_string());
        }

        let url = format!(
            "{}/chat/completions",
            self.cfg.zai_base_url.trim_end_matches('/')
        );
        let system_prompt = format!(
            "You are the Beagle tool bridge on the cheap API lane. task_type={}. Return a direct, useful response.",
            request.task_type
        );
        let body = json!({
            "model": model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": input}
            ],
            "temperature": 0.2,
            "max_tokens": 2048
        });

        let response = self
            .http
            .post(url)
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("glm5 request failed: {}", e))?;

        let status = response.status();
        if !status.is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(format!("glm5 returned {}: {}", status, text));
        }

        let data: DeepSeekResponse = response
            .json()
            .await
            .map_err(|e| format!("failed to parse glm5 response: {}", e))?;

        let content = data
            .choices
            .first()
            .map(|choice| choice.message.content.clone())
            .unwrap_or_default();

        let usage = data.usage.map(|usage| BridgeTokenUsage {
            input_tokens: usage.prompt_tokens,
            output_tokens: usage.completion_tokens,
            total_tokens: usage.total_tokens,
        });

        Ok((json!({ "text": content }), usage, None))
    }

    async fn execute_minimax(
        &self,
        request: &BridgeRequest,
        model: &str,
    ) -> Result<(Value, Option<BridgeTokenUsage>, Option<f64>), String> {
        let api_key = self
            .cfg
            .minimax_api_key
            .as_deref()
            .ok_or_else(|| "MINIMAX_API_KEY is not configured".to_string())?;

        let input = extract_input(&request.payload);
        if input.trim().is_empty() {
            return Err("payload.input must be a non-empty string".to_string());
        }

        let url = format!(
            "{}/v1/messages",
            self.cfg.minimax_base_url.trim_end_matches('/')
        );
        let system_prompt = format!(
            "You are the Beagle tool bridge on the cheap API lane. task_type={}. Return a direct, useful response.",
            request.task_type
        );
        let body = json!({
            "model": model,
            "system": system_prompt,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": input
                        }
                    ]
                }
            ],
            "temperature": 0.2,
            "max_tokens": 2048
        });

        let response = self
            .http
            .post(url)
            .version(reqwest::Version::HTTP_11)
            .header("x-api-key", api_key)
            .header("anthropic-version", "2023-06-01")
            .header("Connection", "close")
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("minimax request failed: {}", e))?;

        let status = response.status();
        if !status.is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(format!("minimax returned {}: {}", status, text));
        }

        let data: AnthropicResponse = response
            .json()
            .await
            .map_err(|e| format!("failed to parse minimax response: {}", e))?;

        let content = extract_anthropic_content(&data);
        let usage = data.usage.map(|usage| {
            let total_tokens = match (usage.input_tokens, usage.output_tokens) {
                (Some(input_tokens), Some(output_tokens)) => Some(input_tokens + output_tokens),
                _ => None,
            };

            BridgeTokenUsage {
                input_tokens: usage.input_tokens,
                output_tokens: usage.output_tokens,
                total_tokens,
            }
        });

        Ok((json!({ "text": content }), usage, None))
    }

    async fn execute_grok_fast(
        &self,
        request: &BridgeRequest,
        model: &str,
    ) -> Result<(Value, Option<BridgeTokenUsage>, Option<f64>), String> {
        let api_key = self
            .cfg
            .xai_api_key
            .as_deref()
            .ok_or_else(|| "XAI_API_KEY is not configured".to_string())?;

        let input = extract_input(&request.payload);
        if input.trim().is_empty() {
            return Err("payload.input must be a non-empty string".to_string());
        }

        let url = format!(
            "{}/chat/completions",
            self.cfg.xai_base_url.trim_end_matches('/')
        );
        let system_prompt = format!(
            "You are the Beagle tool bridge on the cheap API lane. task_type={}. Return a direct, useful response.",
            request.task_type
        );
        let body = json!({
            "model": model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": input}
            ],
            "temperature": 0.2,
            "max_tokens": 2048
        });

        let response = self
            .http
            .post(url)
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("grok_fast request failed: {}", e))?;

        let status = response.status();
        if !status.is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(format!("grok_fast returned {}: {}", status, text));
        }

        let data: DeepSeekResponse = response
            .json()
            .await
            .map_err(|e| format!("failed to parse grok_fast response: {}", e))?;

        let content = data
            .choices
            .first()
            .map(|choice| choice.message.content.clone())
            .unwrap_or_default();

        let usage = data.usage.map(|usage| BridgeTokenUsage {
            input_tokens: usage.prompt_tokens,
            output_tokens: usage.completion_tokens,
            total_tokens: usage.total_tokens,
        });

        Ok((json!({ "text": content }), usage, None))
    }

    async fn execute_kimi(
        &self,
        request: &BridgeRequest,
        model: &str,
    ) -> Result<(Value, Option<BridgeTokenUsage>, Option<f64>), String> {
        let api_key = self
            .cfg
            .groq_api_key
            .as_deref()
            .ok_or_else(|| "GROQ_API_KEY is not configured".to_string())?;

        let input = extract_input(&request.payload);
        if input.trim().is_empty() {
            return Err("payload.input must be a non-empty string".to_string());
        }

        let url = format!(
            "{}/chat/completions",
            self.cfg.groq_base_url.trim_end_matches('/')
        );
        let system_prompt = format!(
            "You are the Beagle tool bridge on the cheap API lane. task_type={}. Return a direct, useful response.",
            request.task_type
        );
        let body = json!({
            "model": model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": input}
            ],
            "temperature": 0.2,
            "max_tokens": 2048
        });

        let response = self
            .http
            .post(url)
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("kimi request failed: {}", e))?;

        let status = response.status();
        if !status.is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(format!("kimi returned {}: {}", status, text));
        }

        let data: DeepSeekResponse = response
            .json()
            .await
            .map_err(|e| format!("failed to parse kimi response: {}", e))?;

        let content = data
            .choices
            .first()
            .map(|choice| choice.message.content.clone())
            .unwrap_or_default();

        let usage = data.usage.map(|usage| BridgeTokenUsage {
            input_tokens: usage.prompt_tokens,
            output_tokens: usage.completion_tokens,
            total_tokens: usage.total_tokens,
        });

        Ok((json!({ "text": content }), usage, None))
    }

    fn finalize_response(
        &self,
        request: BridgeRequest,
        provider: Option<BridgeProvider>,
        model: Option<String>,
        status: BridgeStatus,
        latency_ms: u128,
        token_usage: Option<BridgeTokenUsage>,
        estimated_cost_usd: Option<f64>,
        output: Value,
        error: Option<String>,
        mut warnings: Vec<String>,
    ) -> BridgeResponse {
        let success = matches!(status, BridgeStatus::Success | BridgeStatus::Deferred);

        if self.cfg.ledger_enabled {
            let entry = BridgeLedgerEntry {
                request_id: request.request_id.clone(),
                timestamp: Utc::now(),
                bridge_kind: request.bridge_kind,
                bridge_mode: request.bridge_mode,
                provider,
                model: model.clone(),
                task_type: request.task_type.clone(),
                latency_ms,
                token_usage: token_usage.clone(),
                estimated_cost_usd,
                success,
                error: error.clone(),
            };

            if let Err(ledger_error) = append_ledger_entry(&self.data_dir, &entry) {
                warn!("failed to append tool bridge ledger entry: {}", ledger_error);
                warnings.push(format!("ledger append failed: {}", ledger_error));
            }
        }

        if let Some(provider_name) = provider {
            info!(
                request_id = %request.request_id,
                provider = ?provider_name,
                task_type = %request.task_type,
                latency_ms = latency_ms,
                status = ?status,
                "tool bridge request completed"
            );
        }

        BridgeResponse {
            request_id: request.request_id,
            provider,
            model,
            status,
            latency_ms,
            token_usage,
            estimated_cost_usd,
            output,
            error,
            warnings,
        }
    }
}

fn extract_input(payload: &Value) -> String {
    if let Some(text) = payload.get("input").and_then(Value::as_str) {
        return text.to_string();
    }

    if let Some(text) = payload.as_str() {
        return text.to_string();
    }

    payload.to_string()
}

fn extract_anthropic_content(payload: &AnthropicResponse) -> String {
    payload
        .content
        .iter()
        .filter(|block| matches!(block.block_type.as_deref(), Some("text")))
        .filter_map(|block| block.text.as_deref())
        .collect::<String>()
}
