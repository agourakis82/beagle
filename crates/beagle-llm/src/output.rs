//! LlmOutput - Output de LLM com telemetria

use serde::{Deserialize, Serialize};

/// Output de uma chamada LLM com metadados de telemetria
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmOutput {
    pub text: String,
    pub tokens_in_est: usize,
    pub tokens_out_est: usize,
}

impl LlmOutput {
    pub fn new(text: String, tokens_in_est: usize, tokens_out_est: usize) -> Self {
        Self {
            text,
            tokens_in_est,
            tokens_out_est,
        }
    }
    
    /// Cria output com estimativa simples baseada em caracteres
    pub fn from_text(text: String, prompt: &str) -> Self {
        Self {
            text: text.clone(),
            tokens_in_est: prompt.chars().count() / 4,
            tokens_out_est: text.chars().count() / 4,
        }
    }
    
    /// Total de tokens estimados
    pub fn total_tokens(&self) -> usize {
        self.tokens_in_est + self.tokens_out_est
    }
}

