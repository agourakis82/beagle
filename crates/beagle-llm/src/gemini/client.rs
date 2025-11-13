use std::sync::Arc;

use anyhow::{Context, Result};
use gcp_auth::AuthenticationManager;
use reqwest::Client;
use serde_json::{json, Value};
use tracing::{debug, info, warn};

use crate::models::{CompletionRequest, CompletionResponse, Message};

const CLOUD_PLATFORM_SCOPE: &str = "https://www.googleapis.com/auth/cloud-platform";

/// Cliente para invocar modelos Gemini provisionados via Vertex AI.
pub struct GeminiClient {
    http: Client,
    authenticator: Arc<AuthenticationManager>,
    project_id: String,
    location: String,
    model_id: String,
}

impl GeminiClient {
    /// Constrói novo cliente com credenciais padrão do Google (ADC).
    pub async fn new(
        project_id: impl Into<String>,
        location: impl Into<String>,
        model_id: impl Into<String>,
    ) -> Result<Self> {
        let authenticator = AuthenticationManager::new()
            .await
            .context("Falha ao criar AuthenticationManager para Gemini")?;

        let project_id = project_id.into();
        let location = location.into();
        let model_id = model_id.into();

        info!(
            project = %project_id,
            region = %location,
            model = %model_id,
            "Cliente Gemini inicializado"
        );

        Ok(Self {
            http: Client::builder()
                .build()
                .context("Falha ao construir cliente HTTP")?,
            authenticator: Arc::new(authenticator),
            project_id,
            location,
            model_id,
        })
    }

    /// Executa um ciclo de geração de conteúdo single-turn com Gemini.
    pub async fn complete(&self, request: CompletionRequest) -> Result<CompletionResponse> {
        let CompletionRequest {
            model: _,
            mut messages,
            max_tokens,
            temperature,
            system,
        } = request;

        if let Some(system_prompt) = system {
            messages.insert(
                0,
                Message {
                    role: "user".to_string(),
                    content: format!("System prompt:\n{}", system_prompt),
                },
            );
        }

        let token = self
            .authenticator
            .get_token(&[CLOUD_PLATFORM_SCOPE])
            .await
            .context("Falha ao obter token OAuth2 para Gemini")?;

        let base_url = format!("https://{}-aiplatform.googleapis.com/v1", self.location);
        let url = format!(
            "{base}/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent",
            base = base_url,
            project = self.project_id,
            location = self.location,
            model = self.model_id,
        );

        let contents = normalize_messages(&messages);
        let body = json!({
            "contents": contents,
            "generationConfig": {
                "maxOutputTokens": max_tokens,
                "temperature": temperature,
            }
        });

        debug!(
            url = %url,
            model = %self.model_id,
            max_tokens = max_tokens,
            "Disparando requisição Gemini"
        );
        debug!("Payload Gemini: {}", serde_json::to_string_pretty(&body)?);

        let response = self
            .http
            .post(url)
            .bearer_auth(token.as_str())
            .json(&body)
            .send()
            .await
            .context("Falha ao chamar Gemini API")?;

        let status = response.status();
        let response_data: Value = response
            .json()
            .await
            .context("Falha ao desserializar resposta da Gemini API")?;

        if !status.is_success() {
            warn!(%status, body = %response_data, "Gemini retornou erro HTTP");
            anyhow::bail!("Gemini API error ({}): {}", status, response_data);
        }

        debug!(
            "Resposta Gemini: {}",
            serde_json::to_string_pretty(&response_data)?
        );

        let content = extract_text(&response_data)
            .context("Resposta Gemini não contém campo candidates[0].content")?;
        let usage = response_data.get("usageMetadata").cloned().unwrap_or_else(
            || json!({ "promptTokenCount": 0, "candidatesTokenCount": 0, "totalTokenCount": 0 }),
        );

        Ok(CompletionResponse {
            content,
            model: self.model_id.clone(),
            usage,
        })
    }
}

fn normalize_messages(messages: &[Message]) -> Vec<Value> {
    if messages.is_empty() {
        return vec![json!({
            "role": "user",
            "parts": [{"text": ""}]
        })];
    }

    messages
        .iter()
        .map(|msg| {
            let role = if msg.role.eq_ignore_ascii_case("user") {
                "user"
            } else {
                "model"
            };
            json!({
                "role": role,
                "parts": [{"text": msg.content}]
            })
        })
        .collect()
}

fn extract_text(value: &Value) -> Result<String> {
    let text = value
        .get("candidates")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .and_then(|candidate| candidate.get("content"))
        .and_then(|content| content.get("parts"))
        .and_then(Value::as_array)
        .and_then(|parts| parts.first())
        .and_then(|part| part.get("text"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_owned();

    if text.is_empty() {
        anyhow::bail!("Gemini não retornou texto na primeira candidata");
    }

    Ok(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normaliza_mensagens_usuario_modelo() {
        let messages = vec![
            Message {
                role: "user".into(),
                content: "Olá, Gemini".into(),
            },
            Message {
                role: "assistant".into(),
                content: "Resposta base".into(),
            },
        ];

        let contents = normalize_messages(&messages);
        assert_eq!(contents.len(), 2);
        assert_eq!(contents[0]["role"], "user");
        assert_eq!(contents[1]["role"], "model");
    }

    #[test]
    fn falha_extracao_quando_sem_texto() {
        let payload = json!({});
        let result = extract_text(&payload);
        assert!(result.is_err());
    }

    #[test]
    fn extrai_primeira_resposta() {
        let payload = json!({
            "candidates": [{
                "content": {
                    "parts": [{
                        "text": "Resposta do Gemini"
                    }]
                }
            }]
        });
        let result = extract_text(&payload).expect("texto deve existir");
        assert_eq!(result, "Resposta do Gemini");
    }
}
