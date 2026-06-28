//! LlmOutput - Output de LLM com telemetria

use serde::{Deserialize, Serialize};

/// Token usage from an LLM provider response.
/// `measured = true` when the counts come directly from the provider's usage object.
/// `measured = false` when counts are estimated (chars / 4 fallback).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenUsage {
    pub prompt: u32,
    pub completion: u32,
    pub total: u32,
    /// Whether these counts were measured from the provider response or estimated.
    pub measured: bool,
}

impl TokenUsage {
    /// Create a measured usage (real counts from provider).
    pub fn measured(prompt: u32, completion: u32, total: u32) -> Self {
        Self {
            prompt,
            completion,
            total,
            measured: true,
        }
    }

    /// Create an estimated usage (chars / 4 fallback).
    pub fn estimated(prompt_chars: usize, completion_chars: usize) -> Self {
        let p = (prompt_chars / 4) as u32;
        let c = (completion_chars / 4) as u32;
        Self {
            prompt: p,
            completion: c,
            total: p + c,
            measured: false,
        }
    }
}

/// Output de uma chamada LLM com metadados de telemetria
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmOutput {
    pub text: String,
    /// Estimated prompt token count (chars/4). Kept for backwards compat; prefer `usage`.
    pub tokens_in_est: usize,
    /// Estimated completion token count (chars/4). Kept for backwards compat; prefer `usage`.
    pub tokens_out_est: usize,
    /// Real or estimated token counts. Always present.
    pub usage: TokenUsage,
}

impl LlmOutput {
    pub fn new(text: String, tokens_in_est: usize, tokens_out_est: usize) -> Self {
        let usage = TokenUsage::estimated(tokens_in_est * 4, tokens_out_est * 4);
        Self {
            text,
            tokens_in_est,
            tokens_out_est,
            usage,
        }
    }

    /// Cria output com estimativa simples baseada em caracteres
    pub fn from_text(text: String, prompt: &str) -> Self {
        let tokens_in_est = prompt.chars().count() / 4;
        let tokens_out_est = text.chars().count() / 4;
        let usage = TokenUsage::estimated(prompt.chars().count(), text.chars().count());
        Self {
            text,
            tokens_in_est,
            tokens_out_est,
            usage,
        }
    }

    /// Cria output com contagens reais vindas do provedor.
    pub fn with_measured_usage(text: String, prompt: &str, usage: TokenUsage) -> Self {
        let tokens_in_est = usage.prompt as usize;
        let tokens_out_est = usage.completion as usize;
        Self {
            text,
            tokens_in_est,
            tokens_out_est,
            usage,
        }
    }

    /// Total de tokens estimados
    pub fn total_tokens(&self) -> usize {
        self.tokens_in_est + self.tokens_out_est
    }
}
