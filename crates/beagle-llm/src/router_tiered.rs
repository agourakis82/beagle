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
use tracing::{info, warn};

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
    /// MiniMax - Tier 1: Default (MiniMax 2.1)
    MiniMax,
    /// Z.ai - Tier 1: Default (GLM-4.7, subscription/high rate)
    Zai,
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
            ProviderTier::MiniMax => "minimax",
            ProviderTier::Zai => "zai",
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
            ProviderTier::MiniMax => 0.0,       // Unknown; see BEAGLE_MINIMAX_COST_PER_MILLION
            ProviderTier::Zai => 0.0,           // Unknown/subscription; see BEAGLE_ZAI_COST_PER_MILLION
            ProviderTier::Grok3 => 5.0,         // ~$5/M tokens
            ProviderTier::Grok4Heavy => 25.0,   // ~$25/M tokens
            ProviderTier::DeepSeekMath => 14.0, // ~$14/M tokens
            ProviderTier::CloudMath => 14.0,    // alias
            ProviderTier::LocalFallback => 0.0, // Local compute only
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
                | ProviderTier::Zai
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

fn limit_allows(current: u32, max: u32) -> bool {
    max == 0 || current < max
}

/// Router com sistema de Tiers completo
#[derive(Clone)]
pub struct TieredRouter {
    pub claude_cli: Option<Arc<dyn LlmClient>>,
    pub copilot: Option<Arc<dyn LlmClient>>,
    pub cursor: Option<Arc<dyn LlmClient>>,
    pub claude: Option<Arc<dyn LlmClient>>,
    pub minimax: Option<Arc<dyn LlmClient>>,
    pub zai: Option<Arc<dyn LlmClient>>,
    pub grok3: Arc<dyn LlmClient>,
    pub grok4_heavy: Option<Arc<dyn LlmClient>>,
    pub math: Option<Arc<dyn LlmClient>>,
    pub local: Option<Arc<dyn LlmClient>>,
    pub cfg: LlmRoutingConfig,
}

impl TieredRouter {
    fn choose_premium_subscription(&self, meta: &RequestMeta) -> Option<(Arc<dyn LlmClient>, ProviderTier)> {
        if !(meta.requires_phd_level_reasoning || meta.critical_section) {
            return None;
        }

        // Priority: Claude CLI > Claude Direct > Copilot > Cursor
        if let Some(claude_cli) = &self.claude_cli {
            info!(
                "Router → Claude CLI (premium: phd_reasoning={}, critical={})",
                meta.requires_phd_level_reasoning, meta.critical_section
            );
            return Some((claude_cli.clone(), ProviderTier::ClaudeCli));
        }

        if let Some(claude) = &self.claude {
            info!(
                "Router → Claude Direct (premium: phd_reasoning={}, critical={})",
                meta.requires_phd_level_reasoning, meta.critical_section
            );
            return Some((claude.clone(), ProviderTier::ClaudeDirect));
        }

        if let Some(copilot) = &self.copilot {
            info!(
                "Router → Copilot (premium: phd_reasoning={}, critical={})",
                meta.requires_phd_level_reasoning, meta.critical_section
            );
            return Some((copilot.clone(), ProviderTier::Copilot));
        }

        if let Some(cursor) = &self.cursor {
            info!(
                "Router → Cursor (premium: phd_reasoning={}, critical={})",
                meta.requires_phd_level_reasoning, meta.critical_section
            );
            return Some((cursor.clone(), ProviderTier::Cursor));
        }

        None
    }

    fn zai_policy_enabled() -> bool {
        let policy = std::env::var("BEAGLE_ROUTING_POLICY")
            .unwrap_or_default()
            .trim()
            .to_lowercase();
        matches!(
            policy.as_str(),
            "zai"
                | "zai-glm-4.7"
                | "zai_glm_4.7"
                | "zai-grok-deepseek"
                | "zai_grok_deepseek"
        )
    }

    fn minimax_policy_enabled() -> bool {
        let policy = std::env::var("BEAGLE_ROUTING_POLICY")
            .unwrap_or_default()
            .trim()
            .to_lowercase();
        matches!(
            policy.as_str(),
            "minimax" | "minimax-2.1" | "minimax-grok-deepseek" | "minimax_grok_deepseek"
        )
    }

    /// Cria um TieredRouter com mocks para testes
    pub fn new_with_mocks() -> anyhow::Result<Self> {
        use crate::clients::mock::MockLlmClient;
        Ok(Self {
            claude_cli: None,
            copilot: None,
            cursor: None,
            claude: None,
            minimax: Some(MockLlmClient::new()),
            zai: Some(MockLlmClient::new()),
            grok3: MockLlmClient::new(),
            grok4_heavy: Some(MockLlmClient::new()),
            math: None,
            local: Some(MockLlmClient::new()),
            cfg: LlmRoutingConfig::default(),
        })
    }

    /// Cria router com Grok 3 como default
    pub fn new() -> anyhow::Result<Self> {
        let enable_minimax =
            env_bool("BEAGLE_MINIMAX_ENABLE", std::env::var("MINIMAX_API_KEY").is_ok());
        let enable_zai = env_bool("BEAGLE_ZAI_ENABLE", std::env::var("ZAI_API_KEY").is_ok());

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

        // MiniMax (Tier 1 primary) - requires MINIMAX_API_KEY
        let minimax: Option<Arc<dyn LlmClient>> = if enable_minimax {
            match crate::clients::minimax::MiniMaxClient::from_env() {
                Ok(client) => {
                    info!("MiniMax habilitado (Tier 1 primary)");
                    Some(Arc::new(client))
                }
                Err(e) => {
                    warn!("MiniMax configurado mas falhou ao inicializar: {}", e);
                    None
                }
            }
        } else {
            None
        };

        // Z.ai (Tier 1 primary) - requires ZAI_API_KEY
        let zai: Option<Arc<dyn LlmClient>> = if enable_zai {
            match crate::clients::zai::ZaiClient::from_env() {
                Ok(client) => {
                    info!("Z.ai habilitado (Tier 1 primary)");
                    Some(Arc::new(client))
                }
                Err(e) => {
                    warn!("Z.ai configurado mas falhou ao inicializar: {}", e);
                    None
                }
            }
        } else {
            None
        };

        let grok3: Arc<dyn LlmClient> = Arc::new(crate::clients::grok::GrokClient::new());

        // Grok 4 Heavy usa o mesmo client, mas com modelo diferente
        // Por enquanto, usamos o mesmo client (GrokClient escolhe modelo dinamicamente)
        let grok4_heavy: Option<Arc<dyn LlmClient>> = Some(grok3.clone());

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

        Ok(Self {
            claude_cli,
            copilot,
            cursor,
            claude,
            minimax,
            zai,
            grok3,
            grok4_heavy,
            math,
            local,
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
        if Self::zai_policy_enabled() {
            // In zai policy, use a strict order:
            // offline → deepseek(math) → (bias→grok heavy) → (critical→subscriptions) → zai(default) → grok(default)
            if meta.offline_required {
                if let Some(ref local) = self.local {
                    info!("Router → LocalFallback (offline required)");
                    return (local.clone(), ProviderTier::LocalFallback);
                }
            }

            if meta.requires_math && self.cfg.enable_deepseek_math {
                if limit_allows(stats.deepseek_calls, self.cfg.deepseek_max_calls_per_run)
                    && limit_allows(stats.deepseek_total_tokens(), self.cfg.deepseek_max_tokens_per_run)
                {
                    if let Some(math) = &self.math {
                        info!("Router → DeepSeekMath (zai policy)");
                        return (math.clone(), ProviderTier::DeepSeekMath);
                    }
                }
            }

            // Bias-risk tasks should prioritize Grok4Heavy if available (anti-bias "vaccine").
            if meta.high_bias_risk && self.cfg.enable_heavy {
                if limit_allows(stats.grok4_calls, self.cfg.heavy_max_calls_per_run)
                    && limit_allows(stats.grok4_total_tokens(), self.cfg.heavy_max_tokens_per_run)
                {
                    if let Some(heavy) = &self.grok4_heavy {
                        info!("Router → Grok4Heavy (zai policy; bias risk)");
                        return (heavy.clone(), ProviderTier::Grok4Heavy);
                    }
                }
            }

            // Critical/phd tasks can use existing subscriptions if configured.
            if let Some((client, tier)) = self.choose_premium_subscription(meta) {
                return (client, tier);
            }

            // Fallback: Grok4Heavy for critical tasks if within limits.
            if (meta.requires_phd_level_reasoning || meta.critical_section) && self.cfg.enable_heavy {
                if limit_allows(stats.grok4_calls, self.cfg.heavy_max_calls_per_run)
                    && limit_allows(stats.grok4_total_tokens(), self.cfg.heavy_max_tokens_per_run)
                {
                    if let Some(heavy) = &self.grok4_heavy {
                        info!("Router → Grok4Heavy (zai policy; critical fallback)");
                        return (heavy.clone(), ProviderTier::Grok4Heavy);
                    }
                }
            }

            if let Some(zai) = &self.zai {
                info!("Router → Z.ai (default)");
                return (zai.clone(), ProviderTier::Zai);
            }

            info!("Router → Grok3 (fallback)");
            return (self.grok3.clone(), ProviderTier::Grok3);
        }

        if Self::minimax_policy_enabled() {
            // In minimax policy, use a strict order:
            // offline → deepseek(math) → (bias→grok heavy) → (critical→subscriptions) → minimax(default) → grok(default)
            if meta.offline_required {
                if let Some(ref local) = self.local {
                    info!("Router → LocalFallback (offline required)");
                    return (local.clone(), ProviderTier::LocalFallback);
                }
            }

            if meta.requires_math && self.cfg.enable_deepseek_math {
                if limit_allows(stats.deepseek_calls, self.cfg.deepseek_max_calls_per_run)
                    && limit_allows(stats.deepseek_total_tokens(), self.cfg.deepseek_max_tokens_per_run)
                {
                    if let Some(math) = &self.math {
                        info!("Router → DeepSeekMath (minimax policy)");
                        return (math.clone(), ProviderTier::DeepSeekMath);
                    }
                }
            }

            // Bias-risk tasks should prioritize Grok4Heavy if available (anti-bias "vaccine").
            if meta.high_bias_risk && self.cfg.enable_heavy {
                if limit_allows(stats.grok4_calls, self.cfg.heavy_max_calls_per_run)
                    && limit_allows(stats.grok4_total_tokens(), self.cfg.heavy_max_tokens_per_run)
                {
                    if let Some(heavy) = &self.grok4_heavy {
                        info!("Router → Grok4Heavy (minimax policy; bias risk)");
                        return (heavy.clone(), ProviderTier::Grok4Heavy);
                    }
                }
            }

            // Critical/phd tasks can use existing subscriptions if configured.
            if let Some((client, tier)) = self.choose_premium_subscription(meta) {
                return (client, tier);
            }

            // Fallback: Grok4Heavy for critical tasks if within limits.
            if (meta.requires_phd_level_reasoning || meta.critical_section) && self.cfg.enable_heavy {
                if limit_allows(stats.grok4_calls, self.cfg.heavy_max_calls_per_run)
                    && limit_allows(stats.grok4_total_tokens(), self.cfg.heavy_max_tokens_per_run)
                {
                    if let Some(heavy) = &self.grok4_heavy {
                        info!("Router → Grok4Heavy (minimax policy; critical fallback)");
                        return (heavy.clone(), ProviderTier::Grok4Heavy);
                    }
                }
            }

            if let Some(minimax) = &self.minimax {
                info!("Router → MiniMax (default)");
                return (minimax.clone(), ProviderTier::MiniMax);
            }

            info!("Router → Grok3 (fallback)");
            return (self.grok3.clone(), ProviderTier::Grok3);
        }

        // 1) Math specialist - DeepSeek Math (Tier 2b) - check BEFORE Heavy
        if meta.requires_math && self.cfg.enable_deepseek_math {
            if limit_allows(stats.deepseek_calls, self.cfg.deepseek_max_calls_per_run)
                && limit_allows(stats.deepseek_total_tokens(), self.cfg.deepseek_max_tokens_per_run)
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
                if limit_allows(stats.grok4_calls, self.cfg.heavy_max_calls_per_run)
                    && limit_allows(stats.grok4_total_tokens(), self.cfg.heavy_max_tokens_per_run)
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

    /// Escolhe cliente baseado em metadados
    /// Retorna (client, tier) para logging
    pub fn choose(&self, meta: &RequestMeta) -> (Arc<dyn LlmClient>, ProviderTier) {
        if Self::zai_policy_enabled() {
            if meta.offline_required {
                if let Some(ref local) = self.local {
                    info!("Router → LocalFallback (offline required)");
                    return (local.clone(), ProviderTier::LocalFallback);
                }
            }

            if meta.requires_math {
                if let Some(math) = &self.math {
                    info!("Router → CloudMath (zai policy)");
                    return (math.clone(), ProviderTier::CloudMath);
                }
            }

            if meta.high_bias_risk && self.cfg.enable_heavy {
                if let Some(heavy) = &self.grok4_heavy {
                    info!("Router → Grok4Heavy (zai policy; bias risk)");
                    return (heavy.clone(), ProviderTier::Grok4Heavy);
                }
            }

            if let Some((client, tier)) = self.choose_premium_subscription(meta) {
                return (client, tier);
            }

            if (meta.requires_phd_level_reasoning || meta.critical_section) && self.cfg.enable_heavy {
                if let Some(heavy) = &self.grok4_heavy {
                    info!("Router → Grok4Heavy (zai policy; critical fallback)");
                    return (heavy.clone(), ProviderTier::Grok4Heavy);
                }
            }

            if let Some(zai) = &self.zai {
                info!("Router → Z.ai (default)");
                return (zai.clone(), ProviderTier::Zai);
            }

            info!("Router → Grok3 (fallback)");
            return (self.grok3.clone(), ProviderTier::Grok3);
        }

        if Self::minimax_policy_enabled() {
            if meta.offline_required {
                if let Some(ref local) = self.local {
                    info!("Router → LocalFallback (offline required)");
                    return (local.clone(), ProviderTier::LocalFallback);
                }
            }

            if meta.requires_math {
                if let Some(math) = &self.math {
                    info!("Router → CloudMath (minimax policy)");
                    return (math.clone(), ProviderTier::CloudMath);
                }
            }

            if meta.high_bias_risk && self.cfg.enable_heavy {
                if let Some(heavy) = &self.grok4_heavy {
                    info!("Router → Grok4Heavy (minimax policy; bias risk)");
                    return (heavy.clone(), ProviderTier::Grok4Heavy);
                }
            }

            if let Some((client, tier)) = self.choose_premium_subscription(meta) {
                return (client, tier);
            }

            if (meta.requires_phd_level_reasoning || meta.critical_section) && self.cfg.enable_heavy {
                if let Some(heavy) = &self.grok4_heavy {
                    info!("Router → Grok4Heavy (minimax policy; critical fallback)");
                    return (heavy.clone(), ProviderTier::Grok4Heavy);
                }
            }

            if let Some(minimax) = &self.minimax {
                info!("Router → MiniMax (default)");
                return (minimax.clone(), ProviderTier::MiniMax);
            }

            info!("Router → Grok3 (fallback)");
            return (self.grok3.clone(), ProviderTier::Grok3);
        }

        // 1) Offline sempre força local
        if meta.offline_required {
            if let Some(ref local) = self.local {
                info!("Router → LocalFallback (offline required)");
                return (local.clone(), ProviderTier::LocalFallback);
            }
        }

        // 2) Premium quality tasks → Use existing subscriptions
        if let Some((client, tier)) = self.choose_premium_subscription(meta) {
            return (client, tier);
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

        // 5) Default absoluto: Grok 3 (unlimited, fast)
        info!("Router → Grok3 (default)");
        (self.grok3.clone(), ProviderTier::Grok3)
    }

    /// Completa prompt usando router inteligente
    pub async fn complete(&self, prompt: &str) -> anyhow::Result<String> {
        let meta = RequestMeta::from_prompt(prompt);
        let (client, tier) = self.choose(&meta);

        // Se Heavy foi escolhido, passa flag para o client
        if tier == ProviderTier::Grok4Heavy {
            // GrokClient detecta automaticamente via choose_model
            // Por enquanto, passamos via LlmRequest
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
}

impl Default for TieredRouter {
    fn default() -> Self {
        Self::new().expect("Falha ao criar TieredRouter")
    }
}
