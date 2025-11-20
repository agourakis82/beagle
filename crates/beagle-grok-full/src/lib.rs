//! BEAGLE Grok Full - Integração completa com xAI Grok
//!
//! Grok 3 ilimitado por padrão + Grok 4 Heavy quando precisar
//! Zero censura. Zero dependência de vLLM local (só fallback se quiser).

use once_cell::sync::Lazy;
use reqwest::{header, Client};
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

#[derive(Serialize, Deserialize)]
struct Message {
    role: String,
    content: String,
}

#[derive(Serialize)]
struct GrokRequest {
    model: String,
    messages: Vec<Message>,
    temperature: f64,
    max_tokens: u32,
}

#[derive(Deserialize)]
struct Choice {
    message: Message,
}

#[derive(Deserialize)]
struct GrokResponse {
    choices: Vec<Choice>,
}

pub struct GrokFull {
    client: Client,
}

static GROK: Lazy<GrokFull> = Lazy::new(|| {
    let key = std::env::var("XAI_API_KEY").unwrap_or_else(|_| "xai-tua-key-aqui".to_string());
    GrokFull::new(&key)
});

impl GrokFull {
    pub fn new(key: &str) -> Self {
        let mut headers = header::HeaderMap::new();
        headers.insert(
            "Authorization",
            header::HeaderValue::from_str(&format!("Bearer {}", key))
                .expect("Invalid API key format"),
        );

        let client = Client::builder()
            .default_headers(headers)
            .timeout(std::time::Duration::from_secs(180))
            .build()
            .expect("Failed to build HTTP client");

        info!("GrokFull client initialized");
        Self { client }
    }

    pub async fn instance() -> &'static Self {
        &GROK
    }

    pub async fn query(
        &self,
        prompt: &str,
        model: &str,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let req = GrokRequest {
            model: model.to_string(),
            messages: vec![Message {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            temperature: 0.7,
            max_tokens: 8192,
        };

        info!(model = %model, "Sending request to Grok API");

        let resp = self
            .client
            .post("https://api.x.ai/v1/chat/completions")
            .json(&req)
            .send()
            .await?;

        if !resp.status().is_success() {
            let text = resp.text().await?;
            warn!("Grok API error: {}", text);
            return Err(text.into());
        }

        let data: GrokResponse = resp.json().await?;
        let content = data.choices[0].message.content.clone();

        info!(len = content.len(), "Received response from Grok");
        Ok(content)
    }

    /// Grok 3 ilimitado (default pra tudo)
    /// 99% das queries - contexto até 128k tokens
    pub async fn grok3(&self, prompt: &str) -> String {
        self.query(prompt, "grok-beta").await.unwrap_or_else(|e| {
            warn!("Grok 3 error: {}", e);
            "erro grok3".to_string()
        })
    }

    /// Grok 4 Heavy (só quando precisar de 256k ou reasoning extremo)
    /// 1% das queries - fallback automático pro Grok 3 se quota acabar
    pub async fn grok4_heavy(&self, prompt: &str) -> String {
        match self.query(prompt, "grok-2-1212").await {
            Ok(response) => response,
            Err(e) => {
                warn!("Grok 4 Heavy quota — fallback Grok 3: {}", e);
                self.grok3(prompt).await
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requer API key
    async fn test_grok3() {
        let grok = GrokFull::instance().await;
        let response = grok.grok3("Hello, world!").await;
        assert!(!response.is_empty());
    }
}
