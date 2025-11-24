//! Sistema de Tiers para roteamento inteligente de LLMs
//!
//! Estratégia Cloud-First:
//! - Tier 1: Grok 3 (default, cloud, não trava GPU)
//! - Tier 2: DeepSeek Math (cloud, matemática pesada)
//! - Tier 3: Local Fallback (Gemma 9B, offline)

use serde::{Deserialize, Serialize};

/// Tier de LLM disponível
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Tier {
    /// Grok 3 - Tier 1 principal (cloud, ilimitado, rápido)
    CloudGrokMain,
    /// DeepSeek Math - Matemática pesada (cloud)
    CloudMath,
    /// Gemma 9B / DeepSeek Math local - Fallback offline
    LocalFallback,
}

impl Tier {
    pub fn as_str(&self) -> &'static str {
        match self {
            Tier::CloudGrokMain => "grok-3",
            Tier::CloudMath => "deepseek-math",
            Tier::LocalFallback => "gemma-9b-local",
        }
    }
}

/// Metadados da requisição para roteamento inteligente
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestMeta {
    /// Requer processamento offline
    pub offline_required: bool,
    /// Requer matemática rigorosa
    pub requires_math: bool,
    /// Requer visão (multimodal)
    pub requires_vision: bool,
    /// Estimativa de tokens
    pub approximate_tokens: usize,
    /// Requer qualidade máxima (usa Grok 4 Heavy se disponível)
    pub requires_high_quality: bool,
}

impl RequestMeta {
    /// Analisa prompt e extrai metadados
    pub fn from_prompt(prompt: &str) -> Self {
        let lower = prompt.to_lowercase();

        let requires_math = lower.contains("proof")
            || lower.contains("derive")
            || lower.contains("theorem")
            || lower.contains("mathematical")
            || lower.contains("equation")
            || lower.contains("calculate")
            || lower.contains("solve");

        let requires_vision =
            lower.contains("image") || lower.contains("picture") || lower.contains("visual");

        let approximate_tokens = prompt.len() / 4;

        // Alta qualidade para prompts longos ou complexos
        let requires_high_quality = approximate_tokens > 4000
            || lower.contains("review")
            || lower.contains("analyze")
            || lower.contains("synthesize");

        Self {
            offline_required: false, // Futuro: detecção de necessidade offline
            requires_math,
            requires_vision,
            approximate_tokens,
            requires_high_quality,
        }
    }
}
