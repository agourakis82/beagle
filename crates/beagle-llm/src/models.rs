use std::fmt::{self, Display};

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Conjunto de modelos suportados pelos provedores Anthropic/Gemini.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum ModelType {
    #[serde(alias = "haiku", alias = "claude-3-5-haiku")]
    ClaudeHaiku45,
    #[serde(alias = "sonnet", alias = "claude-3-5-sonnet")]
    ClaudeSonnet45,
    #[serde(alias = "sonnet-4")]
    ClaudeSonnet4,
}

impl Default for ModelType {
    fn default() -> Self {
        Self::ClaudeHaiku45
    }
}

impl Display for ModelType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ModelType::ClaudeHaiku45 => write!(f, "claude-haiku-4.5"),
            ModelType::ClaudeSonnet45 => write!(f, "claude-sonnet-4.5"),
            ModelType::ClaudeSonnet4 => write!(f, "claude-sonnet-4"),
        }
    }
}

/// Mensagem compatível com a API Anthropic/Gemini.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: String,
    pub content: String,
}

impl Message {
    pub fn user(content: impl Into<String>) -> Self {
        Self {
            role: "user".to_owned(),
            content: content.into(),
        }
    }
}

/// Estrutura de request enviada aos provedores.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompletionRequest {
    pub model: ModelType,
    pub messages: Vec<Message>,
    pub max_tokens: u32,
    #[serde(default = "default_temperature")]
    pub temperature: f32,
    /// System prompt adaptativo (quando disponível).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system: Option<String>,
}

impl CompletionRequest {
    pub fn single_turn(model: ModelType, prompt: impl Into<String>) -> Self {
        Self {
            model,
            messages: vec![Message::user(prompt)],
            max_tokens: 1024,
            temperature: default_temperature(),
            system: None,
        }
    }
}

const fn default_temperature() -> f32 {
    0.7
}

/// Estrutura simplificada de resposta.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompletionResponse {
    pub content: String,
    pub model: String,
    pub usage: Value,
}


