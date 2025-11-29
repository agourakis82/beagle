//! LlmCallsStats - Estatísticas de chamadas LLM

use serde::{Deserialize, Serialize};

/// Estatísticas de chamadas LLM
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct LlmCallsStats {
    /// Grok 3 (Tier 1) stats
    pub grok3_calls: u32,
    pub grok3_tokens_in: u32,
    pub grok3_tokens_out: u32,

    /// Grok 4 Heavy (Tier 2a) stats
    pub grok4_calls: u32,
    pub grok4_tokens_in: u32,
    pub grok4_tokens_out: u32,

    /// DeepSeek Math (Tier 2b) stats
    pub deepseek_calls: u32,
    pub deepseek_tokens_in: u32,
    pub deepseek_tokens_out: u32,

    /// Local fallback (Tier 3) stats
    pub local_calls: u32,
    pub local_tokens_in: u32,
    pub local_tokens_out: u32,
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

    /// Total de tokens DeepSeek Math
    pub fn deepseek_total_tokens(&self) -> u32 {
        self.deepseek_tokens_in + self.deepseek_tokens_out
    }

    /// Total de tokens Local
    pub fn local_total_tokens(&self) -> u32 {
        self.local_tokens_in + self.local_tokens_out
    }

    /// Total de chamadas
    pub fn total_calls(&self) -> u32 {
        self.grok3_calls + self.grok4_calls + self.deepseek_calls + self.local_calls
    }

    /// Total de tokens
    pub fn total_tokens(&self) -> u32 {
        self.grok3_total_tokens()
            + self.grok4_total_tokens()
            + self.deepseek_total_tokens()
            + self.local_total_tokens()
    }

    /// Record a call to specific tier
    pub fn record_call(&mut self, tier: &str, tokens_in: u32, tokens_out: u32) {
        match tier {
            "grok-3" | "grok3" => {
                self.grok3_calls += 1;
                self.grok3_tokens_in += tokens_in;
                self.grok3_tokens_out += tokens_out;
            }
            "grok-4-heavy" | "grok4" => {
                self.grok4_calls += 1;
                self.grok4_tokens_in += tokens_in;
                self.grok4_tokens_out += tokens_out;
            }
            "deepseek-math" | "deepseek" => {
                self.deepseek_calls += 1;
                self.deepseek_tokens_in += tokens_in;
                self.deepseek_tokens_out += tokens_out;
            }
            "local-fallback" | "local" | "gemma" => {
                self.local_calls += 1;
                self.local_tokens_in += tokens_in;
                self.local_tokens_out += tokens_out;
            }
            _ => {
                // Default to grok3 for unknown tiers
                self.grok3_calls += 1;
                self.grok3_tokens_in += tokens_in;
                self.grok3_tokens_out += tokens_out;
            }
        }
    }

    /// Get cost estimate in USD
    pub fn estimated_cost_usd(&self) -> f64 {
        let grok3_cost = self.grok3_total_tokens() as f64 * 5.0 / 1_000_000.0;
        let grok4_cost = self.grok4_total_tokens() as f64 * 25.0 / 1_000_000.0;
        let deepseek_cost = self.deepseek_total_tokens() as f64 * 14.0 / 1_000_000.0;
        // Local is free
        grok3_cost + grok4_cost + deepseek_cost
    }
}
