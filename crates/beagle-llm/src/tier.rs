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

// NOTE: RequestMeta was previously defined here but has been consolidated into
// crates/beagle-llm/src/meta.rs (canonical definition used by all routers).
// Use `beagle_llm::RequestMeta` or `crate::meta::RequestMeta` instead.
