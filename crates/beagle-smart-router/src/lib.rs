//! Smart LLM Router — thin compatibility layer over the single routing brain.
//!
//! This crate used to hold a SECOND, parallel routing algorithm (a Grok-first cascade over its own
//! `beagle-grok-api` client stack + a direct `beagle_llm::vllm` fallback) that duplicated and
//! contradicted `beagle_llm::TieredRouter`. The router has been collapsed: every entry point here
//! now delegates to a shared `TieredRouter`, which is **fleet-first** (local LiteLLM/vLLM by
//! default, Grok only as a configured fallback) and carries the budget, escalation, fallback and
//! resilience (circuit breaker + bounded backoff) logic. Signatures are unchanged so existing call
//! sites are untouched.

use anyhow::Result;
use beagle_llm::{RequestMeta, TieredRouter};
use once_cell::sync::Lazy;
use tracing::debug;

/// The one shared routing brain. `TieredRouter::default()` builds clients from the environment
/// (local fleet when configured, Claude/Grok as available); it panics only if construction is
/// impossible — the router is a hard dependency of every query path.
static ROUTER: Lazy<TieredRouter> = Lazy::new(TieredRouter::default);

fn meta_for(prompt: &str, context_tokens: usize) -> RequestMeta {
    let mut m = RequestMeta::from_prompt(prompt);
    m.approximate_tokens = context_tokens + prompt.len() / 4;
    m
}

/// Main global entry point for LLM queries in BEAGLE. Routes through the unified `TieredRouter`
/// (fleet-first, with cross-tier fallback + bounded backoff). Returns the answer, or an error
/// string if every backend fails.
pub async fn query_beagle(prompt: &str, context_tokens: usize) -> String {
    let meta = meta_for(prompt, context_tokens);
    debug!("query_beagle: approx_tokens={}", meta.approximate_tokens);
    ROUTER.complete_robust(prompt, &meta).await
}

/// Intelligent LLM router — kept for API compatibility; now a thin delegator to the shared
/// `TieredRouter` (the former per-instance Grok/vLLM client fields are gone — one brain).
#[derive(Debug, Clone, Default)]
pub struct SmartRouter;

impl SmartRouter {
    pub fn new() -> Self {
        SmartRouter
    }

    /// Retained for source compatibility. Provider selection is centralized in the shared router
    /// (configure providers via env), so an explicit key here is a no-op.
    pub fn with_grok(_api_key: &str) -> Self {
        SmartRouter
    }

    /// Retained for source compatibility. To force the local fleet, set `BEAGLE_LLM_FLEET_URL`
    /// (the router is fleet-first by default).
    pub fn with_vllm_only(_url: impl Into<String>) -> Self {
        SmartRouter
    }

    /// Query with explicit sampling via the unified router. `top_p` is not carried by the
    /// `LlmClient` trait and is ignored (temperature/max_tokens are honored).
    pub async fn query_smart(
        &self,
        prompt: &str,
        context_tokens: usize,
        temperature: Option<f32>,
        max_tokens: Option<u32>,
        _top_p: Option<f32>,
    ) -> Result<String> {
        let meta = meta_for(prompt, context_tokens);
        Ok(ROUTER
            .complete_robust_params(prompt, &meta, temperature, max_tokens.map(|m| m as i32))
            .await)
    }

    /// Simple query with default params.
    pub async fn query(&self, prompt: &str, context_tokens: usize) -> Result<String> {
        Ok(query_beagle(prompt, context_tokens).await)
    }
}

/// String-returning convenience alias for [`query_beagle`].
pub async fn query_smart(prompt: &str, context_tokens: usize) -> String {
    query_beagle(prompt, context_tokens).await
}

/// Robust query: cross-tier fallback + bounded jittered backoff + clean error string. Now identical
/// to [`query_beagle`] — the unified router already provides the fallback chain (the bespoke cascade
/// this used to hand-roll has been removed).
pub async fn query_robust(prompt: &str, context_tokens: usize) -> String {
    query_beagle(prompt, context_tokens).await
}

/// Convenience entry with full sampling params (delegates to the shared router).
pub async fn query_smart_with_params(
    prompt: &str,
    context_tokens: usize,
    temperature: Option<f32>,
    max_tokens: Option<u32>,
    top_p: Option<f32>,
) -> Result<String> {
    SmartRouter::new()
        .query_smart(prompt, context_tokens, temperature, max_tokens, top_p)
        .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smartrouter_constructs() {
        let _ = SmartRouter::new();
        let _ = SmartRouter::with_vllm_only("http://localhost:8000/v1");
        let _ = SmartRouter::with_grok("k");
    }
}
