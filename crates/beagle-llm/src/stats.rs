//! LlmCallsStats - Estatísticas de chamadas LLM

use serde::{Deserialize, Serialize};

/// Estatísticas de chamadas LLM
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct LlmCallsStats {
    pub grok3_calls: u32,
    pub grok3_tokens_in: u32,
    pub grok3_tokens_out: u32,
    pub grok4_calls: u32,
    pub grok4_tokens_in: u32,
    pub grok4_tokens_out: u32,
}

impl LlmCallsStats {
    pub fn new() -> Self {
        Self::default()
    }
    
    /// Total de tokens Grok 3
    pub fn grok3_total_tokens(&self) -> u32 {
        self.grok3_tokens_in + self.grok3_tokens_out
    }
    
    /// Total de tokens Grok 4 Heavy
    pub fn grok4_total_tokens(&self) -> u32 {
        self.grok4_tokens_in + self.grok4_tokens_out
    }
    
    /// Total de chamadas
    pub fn total_calls(&self) -> u32 {
        self.grok3_calls + self.grok4_calls
    }
    
    /// Total de tokens
    pub fn total_tokens(&self) -> u32 {
        self.grok3_total_tokens() + self.grok4_total_tokens()
    }
}
