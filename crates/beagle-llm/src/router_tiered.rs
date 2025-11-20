//! TieredRouter v2 - Grok 3 vs Grok 4 Heavy com critérios explícitos
//!
//! Estratégia:
//! - Grok 3: ~94% dos casos (ilimitado, custo ≈ 0)
//! - Grok 4 Heavy: vacina anti-viés para:
//!   * temas com alto risco de viés/alucinação
//!   * métodos críticos (Methods, Results)
//!   * proofs matemáticas/KEC/PBPK

use crate::{LlmClient, RequestMeta, Tier};
use beagle_config::BeagleConfig;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::info;

/// Tier de provider LLM
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProviderTier {
    /// Grok 3 - default, ~94% dos casos
    Grok3,
    /// Grok 4 Heavy - vacina anti-viés, métodos críticos
    Grok4Heavy,
    /// Cloud Math - futuro (DeepSeek etc.)
    CloudMath,
    /// Local Fallback - Gemma/DeepSeek local
    LocalFallback,
}

impl ProviderTier {
    pub fn as_str(&self) -> &'static str {
        match self {
            ProviderTier::Grok3 => "grok-3",
            ProviderTier::Grok4Heavy => "grok-4-heavy",
            ProviderTier::CloudMath => "cloud-math",
            ProviderTier::LocalFallback => "local-fallback",
        }
    }
}

/// Configuração de roteamento LLM
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmRoutingConfig {
    /// Habilita uso de Grok 4 Heavy
    pub enable_heavy: bool,
    /// Máximo de chamadas Heavy por run (0 = ilimitado)
    pub heavy_max_calls_per_run: usize,
    /// Máximo de tokens Heavy por run (0 = ilimitado)
    pub heavy_max_tokens_per_run: usize,
}

impl Default for LlmRoutingConfig {
    fn default() -> Self {
        Self {
            enable_heavy: true,
            heavy_max_calls_per_run: 0, // Ilimitado por padrão
            heavy_max_tokens_per_run: 0, // Ilimitado por padrão
        }
    }
}

/// Router com sistema de Tiers completo
pub struct TieredRouter {
    pub grok3: Arc<dyn LlmClient>,
    pub grok4_heavy: Option<Arc<dyn LlmClient>>,
    pub math: Option<Arc<dyn LlmClient>>,
    pub local: Option<Arc<dyn LlmClient>>,
    pub cfg: LlmRoutingConfig,
}

impl TieredRouter {
    /// Cria router com Grok 3 como default
    pub fn new() -> anyhow::Result<Self> {
        let grok3: Arc<dyn LlmClient> = Arc::new(crate::clients::grok::GrokClient::new());
        
        // Grok 4 Heavy usa o mesmo client, mas com modelo diferente
        // Por enquanto, usamos o mesmo client (GrokClient escolhe modelo dinamicamente)
        let grok4_heavy: Option<Arc<dyn LlmClient>> = Some(grok3.clone());
        
        Ok(Self {
            grok3,
            grok4_heavy,
            math: None, // Futuro: DeepSeek Math
            local: None, // Futuro: Gemma 9B local
            cfg: LlmRoutingConfig::default(),
        })
    }
    
    /// Cria router a partir de config
    pub fn from_config(_cfg: &BeagleConfig) -> anyhow::Result<Self> {
        let mut router = Self::new()?;
        
        // Lê configuração de roteamento (futuro: do BeagleConfig)
        router.cfg.enable_heavy = std::env::var("BEAGLE_ENABLE_HEAVY")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(true);
        
        Ok(router)
    }

    /// Escolhe cliente baseado em metadados
    /// Retorna (client, tier) para logging
    pub fn choose(&self, meta: &RequestMeta) -> (Arc<dyn LlmClient>, ProviderTier) {
        // 1) Offline sempre força local
        if meta.offline_required {
            if let Some(ref local) = self.local {
                info!("Router → LocalFallback (offline required)");
                return (local.clone(), ProviderTier::LocalFallback);
            }
        }

        // 2) Heavy – só se habilitado e disponível
        if self.cfg.enable_heavy {
            if let Some(heavy) = &self.grok4_heavy {
                if meta.high_bias_risk 
                    || meta.requires_phd_level_reasoning 
                    || meta.critical_section 
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

        // 3) Math specialist (futuro)
        if meta.requires_math {
            if let Some(math) = &self.math {
                info!("Router → CloudMath (math required)");
                return (math.clone(), ProviderTier::CloudMath);
            }
        }

        // 4) Default absoluto: Grok 3
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
            use crate::{LlmRequest, ChatMessage};
            let req = LlmRequest {
                model: "grok-4-heavy".to_string(),
                messages: vec![ChatMessage::user(prompt)],
                temperature: Some(0.7),
                max_tokens: Some(8192),
            };
            client.chat(req).await
        } else {
            client.complete(prompt).await
        }
    }
}

impl Default for TieredRouter {
    fn default() -> Self {
        Self::new().expect("Falha ao criar TieredRouter")
    }
}
