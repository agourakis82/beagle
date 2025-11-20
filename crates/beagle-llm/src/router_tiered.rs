//! Router com sistema de Tiers completo
//!
//! Estratégia Cloud-First:
//! - Tier 1 (CloudGrokMain): Grok 3 - default, não trava GPU
//! - Tier 2 (CloudMath): DeepSeek Math - matemática pesada
//! - Tier 3 (LocalFallback): Gemma 9B local - offline

use crate::{LlmClient, Tier, RequestMeta};
use std::sync::Arc;
use tracing::info;

/// Router com sistema de Tiers
pub struct TieredRouter {
    pub grok: Arc<dyn LlmClient>,
    pub math: Option<Arc<dyn LlmClient>>,
    pub local: Option<Arc<dyn LlmClient>>,
}

impl TieredRouter {
    /// Cria router com Grok como Tier 1
    pub fn new() -> anyhow::Result<Self> {
        let grok = Arc::new(crate::clients::grok::GrokClient::new());
        
        Ok(Self {
            grok,
            math: None, // Futuro: DeepSeek Math
            local: None, // Futuro: Gemma 9B local
        })
    }

    /// Escolhe cliente baseado em metadados
    pub fn choose(&self, meta: &RequestMeta) -> Arc<dyn LlmClient> {
        // 1. Offline requerido → Local Fallback
        if meta.offline_required {
            if let Some(ref local) = self.local {
                info!("Router → LocalFallback (offline required)");
                return local.clone();
            }
        }

        // 2. Matemática pesada → DeepSeek Math (se disponível)
        if meta.requires_math {
            if let Some(ref math) = self.math {
                info!("Router → CloudMath (math required)");
                return math.clone();
            }
            // Fallback para Grok se DeepSeek não disponível
            info!("Router → CloudGrokMain (math fallback)");
            return self.grok.clone();
        }

        // 3. Qualidade máxima / long context → Grok (Tier 1)
        if meta.requires_high_quality || meta.approximate_tokens > 4000 {
            info!("Router → CloudGrokMain (high quality/long context)");
            return self.grok.clone();
        }

        // 4. Default: Grok 3 (Tier 1) - não trava GPU
        info!("Router → CloudGrokMain (default)");
        self.grok.clone()
    }

    /// Completa prompt usando router inteligente
    pub async fn complete(&self, prompt: &str) -> anyhow::Result<String> {
        let meta = RequestMeta::from_prompt(prompt);
        let client = self.choose(&meta);
        client.complete(prompt).await
    }
}

impl Default for TieredRouter {
    fn default() -> Self {
        Self::new().expect("Falha ao criar TieredRouter")
    }
}

