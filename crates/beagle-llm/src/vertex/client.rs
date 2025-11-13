use std::sync::Arc;

use anyhow::{Context, Result};
use gcp_auth::AuthenticationManager;
use reqwest::{Client, Response};
use serde_json::{json, Value};
use tracing::{debug, info, warn};

use crate::models::{CompletionRequest, CompletionResponse, ModelType};

const CLOUD_PLATFORM_SCOPE: &str = "https://www.googleapis.com/auth/cloud-platform";

/// Cliente autenticado para invocar modelos Anthropic disponibilizados via Vertex AI.
pub struct VertexAIClient {
    http: Client,
    authenticator: Arc<AuthenticationManager>,
    project_id: String,
    location: String,
}

impl VertexAIClient {
    /// Constrói novo cliente com Application Default Credentials.
    pub async fn new(project_id: impl Into<String>, location: impl Into<String>) -> Result<Self> {
        let authenticator = AuthenticationManager::new()
            .await
            .context("Falha ao inicializar AuthenticationManager do Google Cloud")?;

        let project_id = project_id.into();
        let location = location.into();

        info!(
            project_id = %project_id,
            location = %location,
            "Cliente Vertex AI inicializado"
        );

        Ok(Self {
            http: Client::builder()
                .build()
                .context("Falha ao construir cliente HTTP")?,
            authenticator: Arc::new(authenticator),
            project_id,
            location,
        })
    }

    /// Executa completion síncrona utilizando o endpoint `streamRawPredict`.
    pub async fn complete(&self, request: CompletionRequest) -> Result<CompletionResponse> {
        let CompletionRequest {
            model,
            messages,
            max_tokens,
            temperature,
            system,
        } = request;

        let token = self
            .authenticator
            .get_token(&[CLOUD_PLATFORM_SCOPE])
            .await
            .context("Falha ao obter token OAuth2 para Vertex AI")?;

        let model_endpoint = self.resolve_model_endpoint(&model);
        let base_url = format!("https://{}-aiplatform.googleapis.com/v1", self.location);
        let url = format!(
            "{base}/projects/{project}/locations/{location}/publishers/anthropic/models/{endpoint}:streamRawPredict",
            base = base_url,
            project = self.project_id,
            location = self.location,
            endpoint = model_endpoint
        );

        let mut body = json!({
            "anthropic_version": "vertex-2023-10-16",
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        });

        if let Some(system_prompt) = system {
            body["system"] = json!(system_prompt);
        }

        debug!(
            url = %url,
            model = %model_endpoint,
            max_tokens = max_tokens,
            "Disparando requisição Vertex AI"
        );

        let response = self
            .http
            .post(url)
            .bearer_auth(token.as_str())
            .json(&body)
            .send()
            .await
            .context("Falha ao enviar requisição ao Vertex AI")?;

        let status = response.status();
        let payload = collect_response_body(response).await?;

        if !status.is_success() {
            warn!(%status, body = %payload, "Vertex AI retornou erro HTTP");
            anyhow::bail!("Vertex AI respondeu status {}: {}", status, payload);
        }

        let (content, usage) = parse_vertex_payload(&payload)
            .with_context(|| "Falha ao interpretar payload do Vertex AI")?;

        Ok(CompletionResponse {
            content,
            model: model.to_string(),
            usage,
        })
    }

    fn resolve_model_endpoint(&self, model: &ModelType) -> &str {
        match model {
            ModelType::ClaudeHaiku45 => "claude-3-5-haiku@20241022",
            ModelType::ClaudeSonnet45 => "claude-3-5-sonnet@20241022",
            ModelType::ClaudeSonnet4 => "claude-3-5-sonnet@20240620",
        }
    }
}

async fn collect_response_body(response: Response) -> Result<String> {
    let bytes = response
        .bytes()
        .await
        .context("Falha ao receber corpo da resposta Vertex AI")?;
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

fn parse_vertex_payload(payload: &str) -> Result<(String, Value)> {
    if payload.trim().is_empty() {
        anyhow::bail!("Payload vazio retornado pelo Vertex AI");
    }

    // Primeiro: tentar interpretar como JSON singular.
    if let Ok(value) = serde_json::from_str::<Value>(payload) {
        let content = extract_content_from_value(&value);
        let usage = value.get("usage").cloned().unwrap_or(Value::Null);
        return Ok((content, usage));
    }

    // Caso contrário, presumimos SSE (eventos 'data: {}').
    let mut content = String::new();
    let mut usage = Value::Null;

    for line in payload.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed == "data: [DONE]" {
            continue;
        }

        let json_fragment = trimmed.strip_prefix("data: ").unwrap_or(trimmed);
        let Ok(value) = serde_json::from_str::<Value>(json_fragment) else {
            continue;
        };

        if usage == Value::Null {
            if let Some(u) = value.get("usage") {
                usage = u.clone();
            }
        }

        if let Some(delta) = value.get("delta") {
            if delta
                .get("type")
                .and_then(Value::as_str)
                .map(|kind| kind == "content_block_delta")
                .unwrap_or(false)
            {
                if let Some(text) = delta
                    .get("text_delta")
                    .and_then(|td| td.get("text"))
                    .and_then(Value::as_str)
                {
                    content.push_str(text);
                }
            }
        }

        if let Some(message) = value.get("message") {
            content.push_str(&extract_content_from_value(message));
        }
    }

    if content.is_empty() {
        anyhow::bail!("Não foi possível extrair conteúdo textual do payload SSE");
    }

    Ok((content, usage))
}

fn extract_content_from_value(value: &Value) -> String {
    if let Some(text) = value.get("text").and_then(Value::as_str) {
        return text.to_owned();
    }

    if let Some(array) = value.get("content").and_then(Value::as_array) {
        let mut aggregated = String::new();
        for item in array {
            if let Some(text) = item.get("text").and_then(Value::as_str) {
                aggregated.push_str(text);
            }
        }
        if !aggregated.is_empty() {
            return aggregated;
        }
    }

    // Fallback: se o próprio valor for string.
    value.as_str().unwrap_or_default().to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_single_json_payload() {
        let payload = json!({
            "content": [
                { "type": "text", "text": "Hello, Vertex!" }
            ],
            "usage": {
                "input_tokens": 10,
                "output_tokens": 20
            }
        })
        .to_string();

        let (content, usage) = parse_vertex_payload(&payload).expect("payload deve ser válido");
        assert_eq!(content, "Hello, Vertex!");
        assert_eq!(usage["input_tokens"], 10);
        assert_eq!(usage["output_tokens"], 20);
    }

    #[test]
    fn parse_sse_payload() {
        let payload = r#"
data: {"type":"message_start","message":{"id":"msg_01","content":[]}}
data: {"type":"content_block_start","content_block":{"type":"text","text":""}}
data: {"type":"content_block_delta","delta":{"type":"content_block_delta","text_delta":{"text":"Olá "}}}
data: {"type":"content_block_delta","delta":{"type":"content_block_delta","text_delta":{"text":"Vertex!"}}}
data: {"type":"content_block_stop"}
data: {"type":"message_delta","usage":{"input_tokens":5,"output_tokens":7}}
data: {"type":"message_stop","message":{"content":[{"type":"text","text":"Final"}]}}
data: [DONE]
"#;

        let (content, usage) = parse_vertex_payload(payload).expect("payload SSE deve ser válido");
        assert!(content.contains("Olá Vertex!"));
        assert_eq!(usage["output_tokens"], 7);
    }
}
