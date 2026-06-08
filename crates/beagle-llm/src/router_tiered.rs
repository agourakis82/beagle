//! TieredRouter v2 - Grok 3 vs Grok 4 Heavy com critérios explícitos
//!
//! Estratégia:
//! - Grok 3: ~94% dos casos (ilimitado, custo ≈ 0)
//! - Grok 4 Heavy: vacina anti-viés para:
//!   * temas com alto risco de viés/alucinação
//!   * métodos críticos (Methods, Results)
//!   * proofs matemáticas/KEC/PBPK

use crate::{LlmClient, RequestMeta};
use beagle_config::BeagleConfig;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, info, warn};

/// Tier de provider LLM
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProviderTier {
    /// Claude CLI - Tier -2: Local Claude Code CLI (no API key needed!)
    ClaudeCli,
    /// GitHub Copilot - Tier -1: Uses existing subscription (Claude/GPT-4o/o1)
    Copilot,
    /// Cursor AI - Tier -1: Uses existing subscription (Claude/GPT-4)
    Cursor,
    /// Claude Direct - Tier 0: Direct Anthropic API (Claude MAX subscription)
    ClaudeDirect,
    /// Grok 3 - Tier 1: Default, ~94% dos casos (unlimited)
    Grok3,
    /// Grok 4 Heavy - Tier 2a: Anti-bias vaccine, critical methods
    Grok4Heavy,
    /// DeepSeek Math - Tier 2b: Mathematical reasoning, proofs, symbolic math
    DeepSeekMath,
    /// Cloud Math - legacy alias for DeepSeekMath
    CloudMath,
    /// Local Fallback - Gemma 9B local
    LocalFallback,
}

impl ProviderTier {
    pub fn as_str(&self) -> &'static str {
        match self {
            ProviderTier::ClaudeCli => "claude-cli",
            ProviderTier::Copilot => "copilot",
            ProviderTier::Cursor => "cursor",
            ProviderTier::ClaudeDirect => "claude-direct",
            ProviderTier::Grok3 => "grok-3",
            ProviderTier::Grok4Heavy => "grok-4-heavy",
            ProviderTier::DeepSeekMath => "deepseek-math",
            ProviderTier::CloudMath => "deepseek-math", // legacy alias
            ProviderTier::LocalFallback => "local-fallback",
        }
    }

    /// Cost per million tokens (approximate)
    pub fn cost_per_million_tokens(&self) -> f64 {
        match self {
            ProviderTier::ClaudeCli => 0.0,     // Free (no API)
            ProviderTier::Copilot => 0.0,       // Subscription
            ProviderTier::Cursor => 0.0,        // Subscription
            ProviderTier::ClaudeDirect => 15.0, // ~$15/M tokens
            ProviderTier::Grok3 => 5.0,         // ~$5/M tokens
            ProviderTier::Grok4Heavy => 25.0,   // ~$25/M tokens
            ProviderTier::DeepSeekMath => 14.0, // ~$14/M tokens
            ProviderTier::CloudMath => 14.0,    // alias
            ProviderTier::LocalFallback => 0.0, // Local compute only
        }
    }

    /// Estimated USD cost of a request of `approx_tokens` at this tier's price.
    /// (#13) Used to enforce `RequestMeta::max_cost_usd`.
    pub fn estimated_cost_usd(&self, approx_tokens: usize) -> f64 {
        self.cost_per_million_tokens() * (approx_tokens as f64 / 1_000_000.0)
    }

    /// (#13) True if this tier's estimated cost for `approx_tokens` is within `max_cost_usd`.
    /// `None` ceiling always passes; free tiers (cost 0) always pass.
    pub fn within_budget(&self, approx_tokens: usize, max_cost_usd: Option<f64>) -> bool {
        match max_cost_usd {
            Some(ceiling) => self.estimated_cost_usd(approx_tokens) <= ceiling,
            None => true,
        }
    }

    /// Whether this tier supports mathematical reasoning
    pub fn supports_math(&self) -> bool {
        matches!(
            self,
            ProviderTier::DeepSeekMath
                | ProviderTier::CloudMath
                | ProviderTier::ClaudeCli
                | ProviderTier::ClaudeDirect
        )
    }
}

/// Configuração de roteamento LLM
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmRoutingConfig {
    /// Habilita uso de Grok 4 Heavy
    pub enable_heavy: bool,
    /// Máximo de chamadas Heavy por run (0 = ilimitado)
    pub heavy_max_calls_per_run: u32,
    /// Máximo de tokens Heavy por run (0 = ilimitado)
    pub heavy_max_tokens_per_run: u32,
    /// Máximo de chamadas Heavy por dia (0 = ilimitado)
    pub heavy_max_calls_per_day: u32,

    /// Habilita uso de DeepSeek Math (Tier 2b)
    pub enable_deepseek_math: bool,
    /// Máximo de chamadas DeepSeek por run (0 = ilimitado)
    pub deepseek_max_calls_per_run: u32,
    /// Máximo de tokens DeepSeek por run (0 = ilimitado)
    pub deepseek_max_tokens_per_run: u32,
    /// Máximo de chamadas DeepSeek por dia (0 = ilimitado)
    pub deepseek_max_calls_per_day: u32,
}

impl Default for LlmRoutingConfig {
    fn default() -> Self {
        Self {
            enable_heavy: true,
            heavy_max_calls_per_run: 10,
            heavy_max_tokens_per_run: 200_000,
            heavy_max_calls_per_day: 500,
            // DeepSeek Math defaults
            enable_deepseek_math: true,
            deepseek_max_calls_per_run: 5,
            deepseek_max_tokens_per_run: 100_000,
            deepseek_max_calls_per_day: 200,
        }
    }
}

impl LlmRoutingConfig {
    /// Carrega configuração de roteamento de variáveis de ambiente
    pub fn from_env() -> Self {
        Self {
            enable_heavy: env_bool("BEAGLE_HEAVY_ENABLE", true),
            heavy_max_calls_per_run: env_u32("BEAGLE_HEAVY_MAX_CALLS_PER_RUN", 10),
            heavy_max_tokens_per_run: env_u32("BEAGLE_HEAVY_MAX_TOKENS_PER_RUN", 200_000),
            heavy_max_calls_per_day: env_u32("BEAGLE_HEAVY_MAX_CALLS_PER_DAY", 500),
            // DeepSeek Math from env
            enable_deepseek_math: env_bool("BEAGLE_DEEPSEEK_ENABLE", true),
            deepseek_max_calls_per_run: env_u32("BEAGLE_DEEPSEEK_MAX_CALLS_PER_RUN", 5),
            deepseek_max_tokens_per_run: env_u32("BEAGLE_DEEPSEEK_MAX_TOKENS_PER_RUN", 100_000),
            deepseek_max_calls_per_day: env_u32("BEAGLE_DEEPSEEK_MAX_CALLS_PER_DAY", 200),
        }
    }

    /// Carrega configuração baseada em perfil (dev/lab/prod)
    pub fn from_profile(profile: &str) -> Self {
        match profile {
            "prod" => Self {
                enable_heavy: true,
                heavy_max_calls_per_run: 10,
                heavy_max_tokens_per_run: 200_000,
                heavy_max_calls_per_day: 500,
                // DeepSeek Math - production limits
                enable_deepseek_math: true,
                deepseek_max_calls_per_run: 10,
                deepseek_max_tokens_per_run: 200_000,
                deepseek_max_calls_per_day: 500,
            },
            "lab" => Self {
                enable_heavy: true,
                heavy_max_calls_per_run: 5,
                heavy_max_tokens_per_run: 100_000,
                heavy_max_calls_per_day: 200,
                // DeepSeek Math - lab limits
                enable_deepseek_math: true,
                deepseek_max_calls_per_run: 5,
                deepseek_max_tokens_per_run: 100_000,
                deepseek_max_calls_per_day: 200,
            },
            _ => Self {
                // dev - conservative limits
                enable_heavy: false,
                heavy_max_calls_per_run: 0,
                heavy_max_tokens_per_run: 0,
                heavy_max_calls_per_day: 0,
                // DeepSeek Math - dev disabled by default
                enable_deepseek_math: false,
                deepseek_max_calls_per_run: 0,
                deepseek_max_tokens_per_run: 0,
                deepseek_max_calls_per_day: 0,
            },
        }
    }
}

fn env_bool(key: &str, default: bool) -> bool {
    std::env::var(key)
        .ok()
        .and_then(|v| match v.to_lowercase().as_str() {
            "1" | "true" | "yes" | "y" => Some(true),
            "0" | "false" | "no" | "n" => Some(false),
            _ => None,
        })
        .unwrap_or(default)
}

fn env_u32(key: &str, default: u32) -> u32 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

/// Router com sistema de Tiers completo
#[derive(Clone)]
pub struct TieredRouter {
    pub claude_cli: Option<Arc<dyn LlmClient>>,
    pub copilot: Option<Arc<dyn LlmClient>>,
    pub cursor: Option<Arc<dyn LlmClient>>,
    pub claude: Option<Arc<dyn LlmClient>>,
    pub grok3: Arc<dyn LlmClient>,
    pub grok4_heavy: Option<Arc<dyn LlmClient>>,
    pub math: Option<Arc<dyn LlmClient>>,
    pub local: Option<Arc<dyn LlmClient>>,
    /// In-cluster local LLM fleet (LiteLLM/vLLM, OpenAI-compatible). When present this is the
    /// default workhorse tier instead of Grok — see `LocalFleetClient::from_env`.
    pub fleet: Option<Arc<dyn LlmClient>>,
    /// Per-tier circuit breaker (#13): a tier that fails repeatedly is skipped for a cooldown so a
    /// dead provider isn't retried on every request.
    pub breaker: Arc<crate::resilience::CircuitBreaker>,
    /// Per-identity token-bucket rate limiter (#13): one noisy consumer can't starve the fleet.
    /// Keyed by `RequestMeta::identity` (or "anon"). Disabled (always allow) when capacity ≤ 0,
    /// which is the default unless `BEAGLE_LLM_RATE_CAPACITY` is set.
    pub limiter: Arc<crate::resilience::RateLimit>,
    /// Gateway exact-match response cache (#14): opt-in bounded LRU+TTL cache checked before
    /// calling any provider. Disabled when capacity=0 (default unless BEAGLE_CACHE_SIZE is set).
    pub cache: Arc<crate::cache::ResponseCache>,
    pub cfg: LlmRoutingConfig,
}

impl TieredRouter {
    /// Cria um TieredRouter com mocks para testes
    pub fn new_with_mocks() -> anyhow::Result<Self> {
        use crate::clients::mock::MockLlmClient;
        Ok(Self {
            claude_cli: None,
            copilot: None,
            cursor: None,
            claude: None,
            grok3: MockLlmClient::new(),
            grok4_heavy: Some(MockLlmClient::new()),
            math: None,
            local: Some(MockLlmClient::new()),
            fleet: None,
            breaker: Arc::new(crate::resilience::CircuitBreaker::new(
                5,
                std::time::Duration::from_secs(30),
            )),
            limiter: Arc::new(crate::resilience::RateLimit::disabled()),
            cache: Arc::new(crate::cache::ResponseCache::new(
                0,
                std::time::Duration::from_secs(300),
            )),
            cfg: LlmRoutingConfig::default(),
        })
    }

    /// Cria router com Grok 3 como default
    pub fn new() -> anyhow::Result<Self> {
        // Claude CLI client (auto-detect if `claude` command available)
        let claude_cli: Option<Arc<dyn LlmClient>> =
            match crate::clients::claude_cli::ClaudeCliClient::new() {
                Ok(client) => {
                    info!("Claude CLI detected (no API key needed!)");
                    Some(Arc::new(client))
                }
                Err(e) => {
                    info!("Claude CLI not available: {}", e);
                    None
                }
            };

        // GitHub Copilot client (se GITHUB_TOKEN disponível)
        let copilot: Option<Arc<dyn LlmClient>> =
            if std::env::var("GITHUB_TOKEN").is_ok() || std::env::var("GH_TOKEN").is_ok() {
                match crate::clients::copilot::CopilotClient::from_env() {
                    Ok(client) => {
                        info!("GitHub Copilot habilitado (usa subscrição existente)");
                        Some(Arc::new(client))
                    }
                    Err(e) => {
                        warn!(
                            "GitHub Copilot configurado mas falhou ao inicializar: {}",
                            e
                        );
                        None
                    }
                }
            } else {
                None
            };

        // Cursor AI client (se CURSOR_API_KEY disponível)
        let cursor: Option<Arc<dyn LlmClient>> =
            if std::env::var("CURSOR_API_KEY").is_ok() || std::env::var("CURSOR_TOKEN").is_ok() {
                match crate::clients::cursor::CursorClient::from_env() {
                    Ok(client) => {
                        info!("Cursor AI habilitado (usa subscrição existente)");
                        Some(Arc::new(client))
                    }
                    Err(e) => {
                        warn!("Cursor AI configurado mas falhou ao inicializar: {}", e);
                        None
                    }
                }
            } else {
                None
            };

        // Claude Direct (se ANTHROPIC_API_KEY disponível - Claude MAX subscription)
        let claude: Option<Arc<dyn LlmClient>> = if std::env::var("ANTHROPIC_API_KEY").is_ok() {
            match crate::clients::claude::ClaudeClient::from_env() {
                Ok(client) => {
                    info!("Claude Direct habilitado (usa subscrição Claude MAX)");
                    Some(Arc::new(client))
                }
                Err(e) => {
                    warn!("Claude Direct configurado mas falhou ao inicializar: {}", e);
                    None
                }
            }
        } else {
            None
        };

        let grok3: Arc<dyn LlmClient> = Arc::new(crate::clients::grok::GrokClient::new());

        // Escalation / "Heavy" tier — a genuinely STRONGER model, not a Grok-3 clone.
        // Priority:
        //   1. Claude (strong non-Grok) when available — best cross-model anti-bias guarantee.
        //   2. A dedicated GrokClient whose `choose_model` will always select "grok-4-heavy"
        //      (because `complete_chosen` passes model="grok-4-heavy" for Grok4Heavy tier).
        //      This is distinct from the grok3 workhorse client; do NOT clone it.
        let grok4_heavy: Option<Arc<dyn LlmClient>> = if let Some(ref c) = claude {
            info!("Heavy/escalation tier → Claude (strong non-Grok model)");
            Some(c.clone())
        } else {
            // Construct a fresh GrokClient so it is a distinct instance from grok3.
            // complete_chosen() will pass model="grok-4-heavy" which choose_model() honours.
            info!("Heavy/escalation tier → GrokClient (grok-4-heavy model via complete_chosen)");
            Some(Arc::new(crate::clients::grok::GrokClient::new()))
        };

        // DeepSeek Math client (se API key disponível)
        let math: Option<Arc<dyn LlmClient>> = if std::env::var("DEEPSEEK_API_KEY").is_ok() {
            Some(Arc::new(
                crate::clients::deepseek::DeepSeekClient::new_math(),
            ))
        } else {
            warn!("DEEPSEEK_API_KEY não configurada, CloudMath desabilitado");
            None
        };

        // Local Gemma client (Tier 3 - offline fallback)
        let local: Option<Arc<dyn LlmClient>> = if env_bool("BEAGLE_LOCAL_ENABLE", false) {
            match crate::clients::local_gemma::LocalGemmaClient::from_env() {
                Ok(client) => {
                    info!("LocalGemma habilitado (offline fallback)");
                    Some(Arc::new(client))
                }
                Err(e) => {
                    warn!("LocalGemma configurado mas falhou ao inicializar: {}", e);
                    None
                }
            }
        } else {
            None
        };

        // Local LLM fleet (LiteLLM/vLLM, OpenAI-compatible) — first-class default workhorse
        // when configured, so the router is not hard-wired to Grok.
        let fleet: Option<Arc<dyn LlmClient>> =
            match crate::clients::local_fleet::LocalFleetClient::from_env() {
                Some(client) => {
                    info!("LocalFleet habilitado (default workhorse: LiteLLM/vLLM fleet)");
                    Some(Arc::new(client))
                }
                None => None,
            };

        Ok(Self {
            claude_cli,
            copilot,
            cursor,
            claude,
            grok3,
            grok4_heavy,
            math,
            local,
            fleet,
            breaker: Arc::new(crate::resilience::CircuitBreaker::new(
                5,
                std::time::Duration::from_secs(30),
            )),
            limiter: Arc::new(crate::resilience::RateLimit::from_env()),
            cache: Arc::new(crate::cache::ResponseCache::from_env()),
            cfg: LlmRoutingConfig::default(),
        })
    }

    /// Cria router a partir de config
    pub fn from_config(cfg: &BeagleConfig) -> anyhow::Result<Self> {
        let mut router = Self::new()?;

        // Carrega configuração baseada em perfil ou env
        router.cfg = if let Ok(env_cfg) = std::env::var("BEAGLE_ROUTING_CONFIG") {
            // Se houver config explícita no env, usa ela
            serde_json::from_str(&env_cfg)
                .unwrap_or_else(|_| LlmRoutingConfig::from_profile(&cfg.profile))
        } else {
            // Senão, usa perfil
            LlmRoutingConfig::from_profile(&cfg.profile)
        };

        // Permite override via env
        router.cfg.enable_heavy = env_bool("BEAGLE_HEAVY_ENABLE", router.cfg.enable_heavy);

        Ok(router)
    }

    /// Escolhe cliente com checagem de limites
    pub fn choose_with_limits(
        &self,
        meta: &RequestMeta,
        stats: &crate::stats::LlmCallsStats,
    ) -> (Arc<dyn LlmClient>, ProviderTier) {
        // 0) Explicit tier hint (#13) wins on the metered path too (parity with `choose`),
        //    so an HrvTierHint isn't overridden by capability routing. Offline still wins.
        if !meta.offline_required {
            if let Some(hint) = meta.tier_hint {
                if let Some(client) = self.client_for_tier(hint) {
                    info!("Router(limits) → {:?} (explicit tier_hint)", hint);
                    return (client, hint);
                }
            }
        }

        // 1) Math specialist - DeepSeek Math (Tier 2b) - check BEFORE Heavy
        if meta.requires_math && self.cfg.enable_deepseek_math {
            if stats.deepseek_calls < self.cfg.deepseek_max_calls_per_run
                && stats.deepseek_total_tokens() < self.cfg.deepseek_max_tokens_per_run
            {
                if let Some(math) = &self.math {
                    info!(
                        "Router → DeepSeekMath (dentro dos limites: {}/{} calls, {}/{} tokens)",
                        stats.deepseek_calls,
                        self.cfg.deepseek_max_calls_per_run,
                        stats.deepseek_total_tokens(),
                        self.cfg.deepseek_max_tokens_per_run
                    );
                    return (math.clone(), ProviderTier::DeepSeekMath);
                }
            } else {
                warn!(
                    "Router → fallback (limites DeepSeek atingidos: {}/{} calls ou {}/{} tokens)",
                    stats.deepseek_calls,
                    self.cfg.deepseek_max_calls_per_run,
                    stats.deepseek_total_tokens(),
                    self.cfg.deepseek_max_tokens_per_run
                );
            }
        }

        // 2) Heavy (Tier 2a) - anti-bias, critical sections
        if meta.high_bias_risk || meta.requires_phd_level_reasoning || meta.critical_section {
            if self.cfg.enable_heavy {
                // Checa limites por run
                if stats.grok4_calls < self.cfg.heavy_max_calls_per_run
                    && stats.grok4_total_tokens() < self.cfg.heavy_max_tokens_per_run
                {
                    if let Some(heavy) = &self.grok4_heavy {
                        info!(
                            "Router → Grok4Heavy (dentro dos limites: {}/{} calls, {}/{} tokens)",
                            stats.grok4_calls,
                            self.cfg.heavy_max_calls_per_run,
                            stats.grok4_total_tokens(),
                            self.cfg.heavy_max_tokens_per_run
                        );
                        return (heavy.clone(), ProviderTier::Grok4Heavy);
                    }
                } else {
                    warn!(
                        "Router → Grok3 (limites Heavy atingidos: {}/{} calls ou {}/{} tokens)",
                        stats.grok4_calls,
                        self.cfg.heavy_max_calls_per_run,
                        stats.grok4_total_tokens(),
                        self.cfg.heavy_max_tokens_per_run
                    );
                }
            }
        }

        // 3) Fallback para lógica normal
        self.choose(meta)
    }

    /// Resolve the client backing a specific tier, if that tier is currently available.
    /// (#13) Backs `tier_hint` resolution and is reusable by callers wanting a named tier.
    pub fn client_for_tier(&self, tier: ProviderTier) -> Option<Arc<dyn LlmClient>> {
        match tier {
            ProviderTier::ClaudeCli => self.claude_cli.clone(),
            ProviderTier::Copilot => self.copilot.clone(),
            ProviderTier::Cursor => self.cursor.clone(),
            ProviderTier::ClaudeDirect => self.claude.clone(),
            ProviderTier::Grok3 => Some(self.grok3.clone()),
            ProviderTier::Grok4Heavy => self.grok4_heavy.clone(),
            ProviderTier::DeepSeekMath | ProviderTier::CloudMath => self.math.clone(),
            // LocalFallback names two possible backends; prefer the in-cluster fleet, then offline local.
            ProviderTier::LocalFallback => self.fleet.clone().or_else(|| self.local.clone()),
        }
    }

    /// Escolhe cliente baseado em metadados
    /// Retorna (client, tier) para logging
    pub fn choose(&self, meta: &RequestMeta) -> (Arc<dyn LlmClient>, ProviderTier) {
        // 0) Explicit tier hint (#13): honor an external routing preference (e.g. HrvTierHint)
        //    when that tier is available. Offline still wins over a hint below if required.
        if !meta.offline_required {
            if let Some(hint) = meta.tier_hint {
                if let Some(client) = self.client_for_tier(hint) {
                    info!("Router → {:?} (explicit tier_hint)", hint);
                    return (client, hint);
                }
                debug!(
                    "Router: tier_hint {:?} unavailable, falling back to capability routing",
                    hint
                );
            }
        }

        // 1) Offline sempre força local
        if meta.offline_required {
            if let Some(ref local) = self.local {
                info!("Router → LocalFallback (offline required)");
                return (local.clone(), ProviderTier::LocalFallback);
            }
        }

        // 2) Premium quality tasks → Use existing subscriptions
        // Priority: Claude CLI > Claude Direct > Copilot > Cursor
        if meta.requires_phd_level_reasoning || meta.critical_section {
            // First choice: Claude CLI (if installed - no API key needed!)
            if let Some(claude_cli) = &self.claude_cli {
                info!(
                    "Router → Claude CLI (premium: phd_reasoning={}, critical={})",
                    meta.requires_phd_level_reasoning, meta.critical_section
                );
                return (claude_cli.clone(), ProviderTier::ClaudeCli);
            }

            // Second choice: Claude Direct (if Claude MAX subscription available)
            // Best for: Research analysis, paper understanding, critical reasoning
            if let Some(claude) = &self.claude {
                info!(
                    "Router → Claude Direct (premium: phd_reasoning={}, critical={})",
                    meta.requires_phd_level_reasoning, meta.critical_section
                );
                return (claude.clone(), ProviderTier::ClaudeDirect);
            }

            // Second choice: Copilot (has o1-preview for complex reasoning)
            if let Some(copilot) = &self.copilot {
                info!(
                    "Router → Copilot (premium quality: phd_reasoning={}, critical={})",
                    meta.requires_phd_level_reasoning, meta.critical_section
                );
                return (copilot.clone(), ProviderTier::Copilot);
            }

            // Third choice: Cursor
            if let Some(cursor) = &self.cursor {
                info!(
                    "Router → Cursor (premium quality: phd_reasoning={}, critical={})",
                    meta.requires_phd_level_reasoning, meta.critical_section
                );
                return (cursor.clone(), ProviderTier::Cursor);
            }
        }

        // 3) Heavy – só se habilitado e disponível (anti-bias)
        if self.cfg.enable_heavy {
            if let Some(heavy) = &self.grok4_heavy {
                if meta.high_bias_risk || meta.requires_phd_level_reasoning || meta.critical_section
                {
                    info!(
                        "Router → Grok4Heavy (bias_risk={}, phd_reasoning={}, critical={})",
                        meta.high_bias_risk,
                        meta.requires_phd_level_reasoning,
                        meta.critical_section
                    );
                    // GrokClient precisa saber que deve usar Heavy
                    // Por enquanto, retornamos o mesmo client (ele escolhe dinamicamente)
                    return (heavy.clone(), ProviderTier::Grok4Heavy);
                }
            }
        }

        // 4) Math specialist (futuro)
        if meta.requires_math {
            if let Some(math) = &self.math {
                info!("Router → CloudMath (math required)");
                return (math.clone(), ProviderTier::CloudMath);
            }
        }

        // 5) Default workhorse: the in-cluster local fleet (LiteLLM/vLLM) when configured —
        //    keeps the router from being hard-wired to Grok. Falls back to Grok 3 otherwise.
        if let Some(ref fleet) = self.fleet {
            info!("Router → LocalFleet (default workhorse: LiteLLM/vLLM)");
            return (fleet.clone(), ProviderTier::LocalFallback);
        }

        info!("Router → Grok3 (default)");
        (self.grok3.clone(), ProviderTier::Grok3)
    }

    /// Completa prompt usando router inteligente.
    /// NOTE: this convenience path uses the non-limit-aware `choose()`. On the hot HTTP
    /// path use `choose_with_limits()` then `complete_chosen()` so per-run budgets are enforced.
    pub async fn complete(&self, prompt: &str) -> anyhow::Result<String> {
        let meta = RequestMeta::from_prompt(prompt);
        let (client, tier) = self.choose(&meta);
        self.complete_chosen(&client, tier, prompt).await
    }

    /// Complete using an ALREADY-CHOSEN (limit-aware) client+tier — does NOT re-route,
    /// so the per-run Heavy/token budgets from `choose_with_limits` are actually enforced.
    /// (P0 #2: the HTTP handler previously chose a limit-aware client then discarded it by
    /// calling `complete()`, which re-ran `choose()` uncapped and re-derived meta from text.)
    pub async fn complete_chosen(
        &self,
        client: &Arc<dyn LlmClient>,
        tier: ProviderTier,
        prompt: &str,
    ) -> anyhow::Result<String> {
        // Only the actual Grok client needs the explicit "grok-4-heavy" model nudge. When the
        // escalation tier is a non-Grok strong model (Claude, or the local fleet), use its normal
        // completion path — otherwise we'd send a Grok model id to a non-Grok backend.
        if tier == ProviderTier::Grok4Heavy && client.name() == "grok" {
            use crate::{ChatMessage, LlmRequest};
            let req = LlmRequest {
                model: "grok-4-heavy".to_string(),
                messages: vec![ChatMessage::user(prompt)],
                temperature: Some(0.7),
                max_tokens: Some(8192),
            };
            client.chat(req).await
        } else {
            client.complete(prompt).await.map(|o| o.text)
        }
    }

    /// Like `complete_chosen` but returns `(String, TokenUsage)` so callers can record MEASURED
    /// token counts rather than estimating via chars/4.
    ///
    /// For the Grok client (normal tier) the real usage is captured via its `complete()` override.
    /// For the Grok4Heavy path we call `chat()` (which cannot easily surface usage from the trait)
    /// and fall back to a chars/4 estimate with `measured=false`.
    /// For all other clients we call `complete()` which returns the `LlmOutput` with usage.
    pub async fn complete_chosen_metered(
        &self,
        client: &Arc<dyn LlmClient>,
        tier: ProviderTier,
        prompt: &str,
    ) -> anyhow::Result<(String, crate::output::TokenUsage)> {
        if tier == ProviderTier::Grok4Heavy && client.name() == "grok" {
            // Grok heavy path: the trait `chat()` returns String only. Estimate usage.
            use crate::{ChatMessage, LlmRequest};
            let req = LlmRequest {
                model: "grok-4-heavy".to_string(),
                messages: vec![ChatMessage::user(prompt)],
                temperature: Some(0.7),
                max_tokens: Some(8192),
            };
            let text = client.chat(req).await?;
            let usage = crate::output::TokenUsage::estimated(prompt.len(), text.len());
            Ok((text, usage))
        } else {
            // All other clients: `complete()` returns `LlmOutput` which carries usage.
            // GrokClient overrides `complete()` to capture real measured usage from the API.
            let output = client.complete(prompt).await?;
            Ok((output.text, output.usage))
        }
    }

    /// Single-brain robust completion: pick the best tier for `meta`, try it, and on failure
    /// fall back across the remaining tiers (local fleet → Grok 3 → offline local) with bounded
    /// jittered backoff between attempts. Returns the text, or an error string if everything
    /// fails. This is the unified replacement for beagle-smart-router's parallel cascade —
    /// one routing algorithm, fleet-first.
    pub async fn complete_robust(&self, prompt: &str, meta: &RequestMeta) -> String {
        self.complete_robust_params(prompt, meta, None, None).await
    }

    /// Like [`complete_robust`] but honors per-call sampling. NOTE: the `LlmClient` trait does not
    /// carry `top_p`, so only `temperature`/`max_tokens` are propagated (callers passing top_p have
    /// it dropped — was previously only honored by the now-removed direct grok-api/vLLM clients).
    pub async fn complete_robust_params(
        &self,
        prompt: &str,
        meta: &RequestMeta,
        temperature: Option<f32>,
        max_tokens: Option<i32>,
    ) -> String {
        use crate::{ChatMessage, LlmRequest};

        // ── #14 Cache check ─────────────────────────────────────────────────────────
        // Primary tier drives the key so different tier choices for the same prompt are
        // cached independently (they may return different outputs).
        let (pc, pt) = self.choose(meta);
        let cache_key =
            crate::cache::ResponseCache::make_key(pt.as_str(), prompt, temperature, max_tokens);
        if let Some(cached) = self.cache.get(cache_key) {
            debug!(
                "Router: cache hit for tier={} prompt_len={}",
                pt.as_str(),
                prompt.len()
            );
            return cached;
        }

        // ── #13 per-identity rate limit ─────────────────────────────────────────────
        // Applied only on cache miss (real provider work). Disabled by default, so this is a
        // no-op unless BEAGLE_LLM_RATE_CAPACITY is set. Keyed by the caller identity so one
        // noisy consumer can't starve the shared fleet.
        let identity = meta.identity.as_deref().unwrap_or("anon");
        if !self.limiter.allow(identity) {
            warn!("Router: rate limit hit for identity={}", identity);
            return format!(
                "ERRO: limite de taxa atingido para identidade '{}' (token bucket esgotado)",
                identity
            );
        }

        // Ordered attempt chain: the meta-chosen primary, then the standard fallbacks. Dedup so
        // we never retry the identical client instance back-to-back.
        let mut chain: Vec<(Arc<dyn LlmClient>, ProviderTier)> = vec![(pc, pt)];
        if let Some(ref f) = self.fleet {
            chain.push((f.clone(), ProviderTier::LocalFallback));
        }
        chain.push((self.grok3.clone(), ProviderTier::Grok3));
        if let Some(ref l) = self.local {
            chain.push((l.clone(), ProviderTier::LocalFallback));
        }

        // #13 max_cost: estimate tokens for the budget check. The caller's `approximate_tokens`
        // is authoritative when set, but `RequestMeta::default()` leaves it 0 — which would make
        // every tier look free and silently void the ceiling. The router holds the prompt, so fall
        // back to a chars/4 estimate rather than letting an unset field defeat enforcement.
        let approx_tokens = if meta.approximate_tokens > 0 {
            meta.approximate_tokens
        } else {
            prompt.len() / 4
        };

        let mut last_err = String::new();
        let mut budget_skipped = false;
        let mut breaker_skipped = false;
        for (i, (client, tier)) in chain.iter().enumerate() {
            // #13 max_cost: skip any tier whose estimated cost exceeds the request's ceiling.
            if !tier.within_budget(approx_tokens, meta.max_cost_usd) {
                budget_skipped = true;
                warn!(
                    "Router robust: tier {:?} skipped (est ${:.4} > max_cost ${:.4})",
                    tier,
                    tier.estimated_cost_usd(approx_tokens),
                    meta.max_cost_usd.unwrap_or(f64::INFINITY)
                );
                continue;
            }

            // #13 circuit breaker: skip a tier that recently failed repeatedly (cooldown).
            let bkey = tier.as_str();
            if !self.breaker.allow(bkey) {
                breaker_skipped = true;
                warn!("Router robust: tier {:?} skipped (circuit open)", tier);
                continue;
            }
            if i > 0 {
                if Arc::ptr_eq(client, &chain[0].0) {
                    continue; // same instance as the primary we already tried
                }
                // #13 bounded jittered exponential backoff via resilience helper (base 250ms, cap 30s)
                let delay = crate::resilience::backoff_duration(i as u32, 250, 30_000);
                tokio::time::sleep(delay).await;
            }

            let res = if temperature.is_some() || max_tokens.is_some() {
                let model = if *tier == ProviderTier::Grok4Heavy && client.name() == "grok" {
                    "grok-4-heavy".to_string()
                } else {
                    "default".to_string()
                };
                client
                    .chat(LlmRequest {
                        model,
                        messages: vec![ChatMessage::user(prompt)],
                        temperature,
                        max_tokens,
                    })
                    .await
            } else {
                self.complete_chosen(client, *tier, prompt).await
            };

            match res {
                Ok(t) => {
                    self.breaker.record_success(bkey);
                    // #14 Populate cache on success.
                    self.cache.insert(cache_key, t.clone());
                    return t;
                }
                Err(e) => {
                    self.breaker.record_failure(bkey);
                    warn!("Router robust: tier {:?} failed: {}", tier, e);
                    last_err = e.to_string();
                }
            }
        }
        // If a backend actually ran and failed, report that. Otherwise nothing executed — explain
        // *why* honestly (budget ceiling and/or open circuit) instead of implying a provider outage.
        if last_err.is_empty() {
            let mut reasons: Vec<String> = Vec::new();
            if budget_skipped {
                reasons.push(format!(
                    "acima do limite de custo (max_cost_usd={:?}, ~{} tokens)",
                    meta.max_cost_usd, approx_tokens
                ));
            }
            if breaker_skipped {
                reasons.push("circuito aberto (falhas recentes)".to_string());
            }
            if reasons.is_empty() {
                reasons.push("nenhum backend disponível".to_string());
            }
            return format!("ERRO: nenhum backend executado: {}", reasons.join(" / "));
        }
        format!(
            "ERRO: todos os backends LLM falharam. Último erro: {}",
            last_err
        )
    }

    /// Per-request model override (#13): route to the default workhorse client but force an explicit
    /// model id (e.g. a caller picking a specific fleet/provider model), bypassing tier model logic.
    pub async fn complete_with_model(&self, prompt: &str, model: &str) -> anyhow::Result<String> {
        use crate::{ChatMessage, LlmRequest};
        let meta = RequestMeta::from_prompt(prompt);
        let (client, _tier) = self.choose(&meta);
        client
            .chat(LlmRequest {
                model: model.to_string(),
                messages: vec![ChatMessage::user(prompt)],
                temperature: Some(0.7),
                max_tokens: Some(2048),
            })
            .await
    }
}

impl Default for TieredRouter {
    fn default() -> Self {
        Self::new().expect("Falha ao criar TieredRouter")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::RequestMeta;

    fn meta() -> RequestMeta {
        RequestMeta::default()
    }

    // ── #13: tier_hint (HrvTierHint socket) ────────────────────────────────────────
    #[test]
    fn tier_hint_is_honored_when_available() {
        let r = TieredRouter::new_with_mocks().unwrap();
        let mut m = meta();
        // new_with_mocks has grok4_heavy = Some(mock); hint must win over default Grok3.
        m.tier_hint = Some(ProviderTier::Grok4Heavy);
        let (_c, tier) = r.choose(&m);
        assert_eq!(
            tier,
            ProviderTier::Grok4Heavy,
            "explicit tier_hint should select that tier"
        );
    }

    #[test]
    fn tier_hint_ignored_when_tier_unavailable() {
        let r = TieredRouter::new_with_mocks().unwrap();
        let mut m = meta();
        // No Copilot client is configured in mocks → hint must be ignored, fall back to default.
        m.tier_hint = Some(ProviderTier::Copilot);
        let (_c, tier) = r.choose(&m);
        assert_ne!(
            tier,
            ProviderTier::Copilot,
            "unavailable hint must not be used"
        );
        assert_eq!(tier, ProviderTier::Grok3, "falls back to default workhorse");
    }

    #[test]
    fn tier_hint_yields_to_offline_requirement() {
        let r = TieredRouter::new_with_mocks().unwrap();
        let mut m = meta();
        m.offline_required = true;
        m.tier_hint = Some(ProviderTier::Grok4Heavy);
        let (_c, tier) = r.choose(&m);
        assert_eq!(
            tier,
            ProviderTier::LocalFallback,
            "offline must win over a tier hint"
        );
    }

    #[test]
    fn tier_hint_honored_on_metered_path_too() {
        let r = TieredRouter::new_with_mocks().unwrap();
        let stats = crate::stats::LlmCallsStats::new();
        let mut m = meta();
        // requires_math would normally route to a math/heavy tier on the metered path;
        // an explicit hint must still win.
        m.requires_math = true;
        m.tier_hint = Some(ProviderTier::Grok4Heavy);
        let (_c, tier) = r.choose_with_limits(&m, &stats);
        assert_eq!(
            tier,
            ProviderTier::Grok4Heavy,
            "tier_hint must win on choose_with_limits"
        );
    }

    // ── #13: max_cost budget helper ────────────────────────────────────────────────
    #[test]
    fn within_budget_enforces_ceiling() {
        // Grok3 = $5/Mtok → 1M tokens ≈ $5.00
        assert!(
            !ProviderTier::Grok3.within_budget(1_000_000, Some(1.0)),
            "over a $1 ceiling"
        );
        assert!(
            ProviderTier::Grok3.within_budget(1_000_000, Some(10.0)),
            "under a $10 ceiling"
        );
        assert!(
            ProviderTier::Grok3.within_budget(1_000_000, None),
            "no ceiling always passes"
        );
        // Free tiers always pass any ceiling.
        assert!(ProviderTier::LocalFallback.within_budget(1_000_000, Some(0.0)));
    }

    // ── #13: max_cost actually skips over-budget tiers in the robust chain ──────────
    #[tokio::test]
    async fn robust_skips_over_budget_tiers_and_uses_free_fallback() {
        let r = TieredRouter::new_with_mocks().unwrap();
        let mut m = meta();
        m.approximate_tokens = 1000;
        m.max_cost_usd = Some(0.0); // forbids every paid tier; only free LocalFallback survives
        let out = r.complete_robust("hello", &m).await;
        assert!(
            out.contains("MOCK_ANSWER"),
            "should fall through to the free tier, got: {out}"
        );
        assert!(
            !out.starts_with("ERRO"),
            "a free tier exists, so it must not error: {out}"
        );
    }

    #[tokio::test]
    async fn robust_reports_budget_exhaustion_distinctly() {
        let mut r = TieredRouter::new_with_mocks().unwrap();
        // Remove every free tier so a $0 ceiling leaves nothing affordable.
        r.local = None;
        r.fleet = None;
        let mut m = meta();
        m.approximate_tokens = 1000;
        m.max_cost_usd = Some(0.0);
        let out = r.complete_robust("hello", &m).await;
        assert!(
            out.contains("limite de custo"),
            "should report budget exhaustion, got: {out}"
        );
    }

    #[tokio::test]
    async fn robust_enforces_budget_even_with_default_tokens() {
        // Regression: RequestMeta::default() leaves approximate_tokens=0, which would make every
        // tier look free and void max_cost_usd. The router must estimate from the prompt instead.
        let mut r = TieredRouter::new_with_mocks().unwrap();
        r.local = None;
        r.fleet = None;
        let mut m = meta();
        assert_eq!(m.approximate_tokens, 0, "default leaves tokens unset");
        m.max_cost_usd = Some(0.0); // any paid tier must be skipped
        let out = r
            .complete_robust(
                "a reasonably long prompt that yields nonzero token estimate",
                &m,
            )
            .await;
        assert!(
            out.contains("limite de custo"),
            "budget must still bind with default tokens: {out}"
        );
    }

    // ── #13: per-identity token-bucket rate limit wired into the live path ──────────
    #[tokio::test]
    async fn robust_rate_limits_per_identity() {
        let mut r = TieredRouter::new_with_mocks().unwrap();
        r.limiter = Arc::new(crate::resilience::RateLimit::enabled(1.0, 0.0)); // 1 token, no refill
        let mut alice = meta();
        alice.identity = Some("alice".to_string());

        let first = r.complete_robust("q1", &alice).await;
        assert!(first.contains("MOCK_ANSWER"), "first call allowed: {first}");
        let second = r.complete_robust("q2", &alice).await;
        assert!(
            second.contains("limite de taxa"),
            "second call for alice throttled: {second}"
        );

        // Bob has an independent bucket.
        let mut bob = meta();
        bob.identity = Some("bob".to_string());
        let bob_out = r.complete_robust("q3", &bob).await;
        assert!(
            bob_out.contains("MOCK_ANSWER"),
            "bob unaffected by alice's limit: {bob_out}"
        );
    }
}
