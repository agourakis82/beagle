//! Mock LLM Client para testes

use crate::{ChatMessage, LlmClient, LlmOutput, LlmRequest};
use async_trait::async_trait;
use std::sync::Arc;

/// Mock LLM Client para testes
/// Retorna respostas sintéticas sem chamar APIs reais
pub struct MockLlmClient;

impl MockLlmClient {
    pub fn new() -> Arc<Self> {
        Arc::new(Self)
    }
}

#[async_trait]
impl LlmClient for MockLlmClient {
    async fn complete(&self, prompt: &str) -> anyhow::Result<LlmOutput> {
        let text = format!("MOCK_ANSWER for: {}", prompt);
        Ok(LlmOutput::from_text(text, prompt))
    }

    async fn chat(&self, req: LlmRequest) -> anyhow::Result<String> {
        let content: String = req
            .messages
            .iter()
            .map(|m| m.content.clone())
            .collect::<Vec<_>>()
            .join("\n");
        Ok(format!("MOCK_CHAT response for: {}", content))
    }

    fn name(&self) -> &'static str {
        "mock"
    }

    fn tier(&self) -> crate::Tier {
        crate::Tier::LocalFallback
    }

    fn prefers_heavy(&self) -> bool {
        false
    }
}
