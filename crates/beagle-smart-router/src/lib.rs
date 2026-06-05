//! Smart LLM Router — thin compatibility layer over the single routing brain.
//!
//! Historically this crate held a SECOND, parallel routing algorithm (its own Grok-first
//! cascade with a separate `beagle-grok-api` client stack + `beagle_llm::vllm` fallback). That
//! duplicated — and contradicted — `beagle_llm::TieredRouter`. The router has now been collapsed:
//! every entry point here delegates to a shared `TieredRouter`, which is **fleet-first** (local
//! LiteLLM/vLLM by default, Grok only as a configured fallback) and carries the budget,
//! escalation and resilience logic. These functions keep their original signatures so existing
//! call sites are untouched; `HrvTierHint` is preserved and mapped onto `RequestMeta`.

use anyhow::Result;
use beagle_llm::{RequestMeta, TieredRouter};
use once_cell::sync::Lazy;
use tracing::debug;

/// The one shared routing brain. `TieredRouter::default()` builds clients from the environment
/// (local fleet when configured, Claude/Grok as available) and panics only if construction is
/// impossible — the router is a hard dependency of every query path.
static ROUTER: Lazy<TieredRouter> = Lazy::new(TieredRouter::default);

/// Build a `RequestMeta` from a prompt + an estimated extra-context size and an optional flow hint.
fn meta_for(prompt: &str, context_tokens: usize, hint: HrvTierHint) -> RequestMeta {
    let mut m = RequestMeta::from_prompt(prompt);
    m.approximate_tokens = context_tokens + prompt.len() / 4;
    // Flow → prefer the deeper escalation tier; Stress/Normal keep the fast default path.
    if matches!(hint, HrvTierHint::Flow) {
        m.requires_phd_level_reasoning = true;
    }
    m
}

/// Main global entry point for LLM queries in BEAGLE.
///
/// Routes through the unified `TieredRouter` (fleet-first, with cross-tier fallback + bounded
/// backoff). Returns the model's answer, or an error string if every backend fails.
pub async fn query_beagle(prompt: &str, context_tokens: usize) -> String {
    let meta = meta_for(prompt, context_tokens, HrvTierHint::Normal);
    debug!("query_beagle: approx_tokens={}", meta.approximate_tokens);
    ROUTER.complete_robust(prompt, &meta).await
}

/// HRV-aware flow state. Derived from the physio observer's `flow_state` / `hrv_level`. High HRV
/// (Flow) → prefer deeper reasoning + more exploratory sampling; low HRV (Stress) → fast +
/// conservative; Normal → default.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HrvTierHint {
    Flow,
    Stress,
    Normal,
}

impl HrvTierHint {
    /// `flow`/`high` → Flow, `stress`/`low` → Stress, otherwise Normal.
    pub fn from_flow_state(s: Option<&str>) -> Self {
        match s.map(|x| x.to_ascii_lowercase()).as_deref() {
            Some("flow") | Some("high") => HrvTierHint::Flow,
            Some("stress") | Some("low") => HrvTierHint::Stress,
            _ => HrvTierHint::Normal,
        }
    }

    /// Sampling shaping for this hint: (temperature, max_tokens).
    fn sampling(self) -> (Option<f32>, Option<i32>) {
        match self {
            HrvTierHint::Flow => (Some(0.9), Some(4096)),
            HrvTierHint::Stress => (Some(0.3), Some(1024)),
            HrvTierHint::Normal => (None, None),
        }
    }
}

/// HRV-aware variant of [`query_beagle`]. The hint shifts tier preference (Flow escalates) and
/// sampling (temperature/max_tokens) — all on the same unified router + fallback chain.
pub async fn query_beagle_with_hrv(prompt: &str, context_tokens: usize, hint: HrvTierHint) -> String {
    let meta = meta_for(prompt, context_tokens, hint);
    let (temperature, max_tokens) = hint.sampling();
    debug!("query_beagle_with_hrv: hint={:?}", hint);
    ROUTER
        .complete_robust_params(prompt, &meta, temperature, max_tokens)
        .await
}

/// Intelligent LLM router — kept for API compatibility; now a thin delegator to the shared
/// `TieredRouter`. The former per-instance Grok/vLLM client fields are gone (one brain).
#[derive(Debug, Clone, Default)]
pub struct SmartRouter;

impl SmartRouter {
    pub fn new() -> Self {
        SmartRouter
    }

    /// Retained for source compatibility. Provider selection is now centralized in the shared
    /// router (configure providers via env), so an explicit key here is a no-op.
    pub fn with_grok(_api_key: &str) -> Self {
        SmartRouter
    }

    /// Retained for source compatibility. To force the local fleet, set `BEAGLE_LLM_FLEET_URL`
    /// (the router is fleet-first by default).
    pub fn with_vllm_only(_url: impl Into<String>) -> Self {
        SmartRouter
    }

    /// Query with explicit sampling params via the unified router. `top_p` is not carried by the
    /// `LlmClient` trait and is ignored (temperature/max_tokens are honored).
    pub async fn query_smart(
        &self,
        prompt: &str,
        context_tokens: usize,
        temperature: Option<f32>,
        max_tokens: Option<u32>,
        _top_p: Option<f32>,
    ) -> Result<String> {
        let meta = meta_for(prompt, context_tokens, HrvTierHint::Normal);
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

/// Robust query: cross-tier fallback + bounded jittered backoff + clean error string.
/// Now identical to [`query_beagle`] because the unified router already provides the fallback
/// chain and bounded backoff (the bespoke cascade this used to hand-roll has been removed).
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
    fn test_router_creation() {
        // SmartRouter is now a zero-field delegator; construction is infallible.
        let _ = SmartRouter::new();
        let _ = SmartRouter::with_vllm_only("http://localhost:8000/v1");
    }

    #[test]
    fn test_hrv_hint_parse() {
        assert_eq!(HrvTierHint::from_flow_state(Some("flow")), HrvTierHint::Flow);
        assert_eq!(HrvTierHint::from_flow_state(Some("LOW")), HrvTierHint::Stress);
        assert_eq!(HrvTierHint::from_flow_state(None), HrvTierHint::Normal);
    }
}
