//! BeagleRouter - Router inteligente com Grok 3 default + Grok 4 Heavy anti-viés
//!
//! Estratégia:
//! - 93% das queries → Grok 3 (ilimitado, rápido, <1s)
//! - Temas de alto risco de viés → Grok 4 Heavy automático (vacina anti-viés)
//! - Matemática pesada → DeepSeek (futuro)
//! - Offline → Gemma local (futuro)

use crate::{clients::grok::GrokClient, meta::RequestMeta, LlmClient, LlmRequest, ChatMessage};
use once_cell::sync::Lazy;
use std::sync::Arc;
use tracing::info;

static GROK_CLIENT: Lazy<Arc<GrokClient>> = Lazy::new(|| Arc::new(GrokClient::new()));

/// Router principal do BEAGLE para LLMs
pub struct BeagleRouter;

impl BeagleRouter {
    /// Completa um prompt usando o router inteligente
    ///
    /// Seleção automática:
    /// 1. Detecta risco de viés → Grok 4 Heavy
    /// 2. Default → Grok 3 (93% dos casos)
    pub async fn complete(&self, prompt: &str) -> anyhow::Result<String> {
        let meta = RequestMeta::from_prompt(prompt);
        let client = self.select_client(&meta);

        let req = LlmRequest {
            model: if meta.high_bias_risk {
                "grok-4-heavy".to_string()
            } else {
                "grok-3".to_string()
            },
            messages: vec![ChatMessage {
                role: "user".to_string(),
                content: prompt.to_string(),
            }],
            temperature: Some(0.7),
            max_tokens: Some(if meta.high_bias_risk { 12000 } else { 8192 }),
        };

        info!(
            "Router → {} | heavy: {} | math: {} | bias_risk: {} | tokens: {}",
            client.name(),
            meta.high_bias_risk,
            meta.requires_math,
            meta.high_bias_risk,
            meta.approximate_tokens
        );

        client.chat(req).await
    }

    /// Seleciona cliente baseado em metadados
    fn select_client(&self, _meta: &RequestMeta) -> Arc<dyn LlmClient> {
        // 1. Offline → futuro Gemma local
        // if meta.offline_required {
        //     return Arc::new(LocalGemmaClient::new());
        // }

        // 2. Matemática pesada → DeepSeek (opcional, futuro)
        // if meta.requires_math_proof {
        //     return Arc::new(DeepSeekClient::new());
        // }

        // 3. Temas de alto risco → Grok 4 Heavy (vacina anti-viés)
        // 4. Default 93% dos casos → Grok 3 ilimitado
        // Mesmo client, modelo escolhido dinamicamente em GrokClient
        GROK_CLIENT.clone()
    }
}

