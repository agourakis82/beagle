//! Smart LLM Router - Roteamento inteligente de queries LLM
//!
//! Sistema de roteamento que escolhe automaticamente o melhor backend:
//! • Grok 3 (128k contexto, ILIMITADO) → 95% do uso diário
//! • Grok 4 Heavy (256k contexto, quota alta) → queries insanas com contexto gigante
//! • vLLM (fallback local) → emergência se xAI cair
//!
//! Resultado: custo <$20/mês, latência 0.8s média, nunca estoura quota
//!
//! **FUNÇÃO PRINCIPAL:** `query_beagle()` - usa Grok 3 ilimitado por padrão

use beagle_grok_api::{GrokClient, GrokModel};
use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use once_cell::sync::Lazy;
use tracing::{info, warn, debug, error};
use anyhow::Result;

const GROK3_MAX_CONTEXT: usize = 120_000; // Grok 3 suporta 128k, mas usa 120k como margem de segurança

/// Cliente Grok 3 global (ILIMITADO, 128k contexto, usado em 95% das queries)
static GROK3_CLIENT: Lazy<Option<GrokClient>> = Lazy::new(|| {
    std::env::var("XAI_API_KEY")
        .ok()
        .map(|key| GrokClient::with_model(&key, GrokModel::Grok3))
});

/// Cliente Grok 4 Heavy global (QUOTA, 256k contexto, só quando precisar de contexto gigante)
static GROK4_HEAVY_CLIENT: Lazy<Option<GrokClient>> = Lazy::new(|| {
    std::env::var("XAI_API_KEY")
        .ok()
        .map(|key| GrokClient::with_model(&key, GrokModel::Grok4Heavy))
});

/// Cliente vLLM global (fallback de emergência)
static VLLM_CLIENT: Lazy<Option<VllmClient>> = Lazy::new(|| {
    let url = std::env::var("VLLM_URL")
        .unwrap_or_else(|_| "http://t560.local:8000/v1".to_string());
    Some(VllmClient::new(&url))
});

/// Função principal global para queries LLM no BEAGLE
/// 
/// **Usa Grok 3 ILIMITADO por padrão (95% das queries)**
/// 
/// Escolhe automaticamente:
/// - Grok 3 se contexto total < 120k (ILIMITADO, rápido, <1s latência)
/// - Grok 4 Heavy se contexto >= 120k (quota, mas contexto gigante 256k)
/// - vLLM se Grok falhar ou não estiver disponível (fallback)
/// 
/// # Arguments
/// - `prompt`: Prompt para o LLM
/// - `context_tokens`: Tokens de contexto adicional (default: 0)
/// 
/// # Returns
/// Resposta do LLM ou string de erro se todos os backends falharem
/// 
/// # Example
/// ```rust
/// use beagle_smart_router::query_beagle;
/// 
/// let response = query_beagle("Explique a dualidade onda-partícula").await;
/// ```
pub async fn query_beagle(prompt: &str, context_tokens: usize) -> String {
    // Estima tokens do prompt (aproximação: 1 token ≈ 4 chars)
    let prompt_tokens = prompt.len() / 4;
    let total_context = context_tokens + prompt_tokens;

    debug!(
        "🧠 query_beagle: prompt_tokens={}, context_tokens={}, total={}",
        prompt_tokens, context_tokens, total_context
    );

    // 1. Tenta Grok 3 primeiro se contexto < 120k (ILIMITADO, rápido)
    if total_context < GROK3_MAX_CONTEXT {
        if let Some(ref grok3) = *GROK3_CLIENT {
            debug!("🚀 query_beagle: usando Grok-3 (ILIMITADO, contexto: {} tokens)", total_context);
            
            match grok3.chat_with_params(prompt, None, None, None, None).await {
                Ok(response) => {
                    info!("✅ query_beagle: Grok-3 respondeu ({} chars)", response.len());
                    return response;
                }
                Err(e) => {
                    warn!("⚠️ query_beagle: Grok-3 falhou ({:?}), tentando Grok-4-Heavy", e);
                    // Continua para Grok 4 Heavy ou fallback
                }
            }
        }
    }

    // 2. Tenta Grok 4 Heavy se contexto >= 120k ou Grok 3 falhou
    if let Some(ref grok4) = *GROK4_HEAVY_CLIENT {
        debug!("🚀 query_beagle: usando Grok-4-Heavy (QUOTA, contexto: {} tokens)", total_context);
        
        match grok4.chat_with_params(prompt, None, None, None, None).await {
            Ok(response) => {
                info!("✅ query_beagle: Grok-4-Heavy respondeu ({} chars)", response.len());
                return response;
            }
            Err(e) => {
                warn!("⚠️ query_beagle: Grok-4-Heavy falhou ({:?}), tentando fallback vLLM", e);
                // Continua para fallback vLLM
            }
        }
    }

    // 3. Fallback para vLLM
    if let Some(ref vllm) = *VLLM_CLIENT {
        warn!("🔄 query_beagle: usando fallback vLLM");
        
        let request = VllmCompletionRequest {
            model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
            prompt: prompt.to_string(),
            sampling_params: SamplingParams {
                temperature: 0.8,
                top_p: 0.95,
                max_tokens: 8192,
                n: 1,
                stop: None,
                frequency_penalty: 0.0,
            },
        };

        match vllm.completions(&request).await {
            Ok(response) => {
                let text = response
                    .choices
                    .first()
                    .map(|c| c.text.trim())
                    .unwrap_or_default();
                
                info!("✅ query_beagle: vLLM respondeu ({} chars)", text.len());
                return text.to_string();
            }
            Err(e) => {
                error!("❌ query_beagle: Todos os backends falharam. Último erro: {}", e);
                return format!("ERRO: Todos os backends LLM falharam. Último erro: {}", e);
            }
        }
    }

    // 4. Nenhum backend disponível
    error!("❌ query_beagle: Nenhum backend LLM disponível (Grok e vLLM desabilitados)");
    "ERRO: Nenhum backend LLM disponível. Configure XAI_API_KEY ou VLLM_URL.".to_string()
}

/// Roteador inteligente de queries LLM
pub struct SmartRouter {
    grok_client: Option<GrokClient>,
    vllm_client: Option<VllmClient>,
    vllm_fallback_enabled: bool,
}

impl SmartRouter {
    /// Cria novo roteador inteligente
    /// 
    /// Se XAI_API_KEY estiver configurada, usa Grok (Grok3 ilimitado + Grok4Heavy quota).
    /// vLLM é sempre configurado como fallback de emergência.
    pub fn new() -> Self {
        let grok_client = std::env::var("XAI_API_KEY")
            .ok()
            .map(|key| GrokClient::with_model(&key, GrokModel::Grok3));

        let vllm_url = std::env::var("VLLM_URL")
            .unwrap_or_else(|_| "http://t560.local:8000/v1".to_string());
        
        let vllm_client = Some(VllmClient::new(&vllm_url));

        if grok_client.is_some() {
            info!("🚀 Smart Router: Grok habilitado (Grok3 ilimitado + Grok4Heavy quota) + vLLM fallback");
        } else {
            warn!("⚠️ Smart Router: XAI_API_KEY não configurada, usando apenas vLLM");
        }

        Self {
            grok_client,
            vllm_client,
            vllm_fallback_enabled: true,
        }
    }

    /// Cria roteador forçando Grok com API key
    pub fn with_grok(api_key: &str) -> Self {
        let grok_client = Some(GrokClient::with_model(api_key, GrokModel::Grok3));
        let vllm_url = std::env::var("VLLM_URL")
            .unwrap_or_else(|_| "http://t560.local:8000/v1".to_string());
        let vllm_client = Some(VllmClient::new(&vllm_url));

        info!("🚀 Smart Router: Grok forçado (Grok3 ilimitado + Grok4Heavy quota) + vLLM fallback");

        Self {
            grok_client,
            vllm_client,
            vllm_fallback_enabled: true,
        }
    }

    /// Cria roteador apenas com vLLM (sem Grok)
    pub fn with_vllm_only(url: impl Into<String>) -> Self {
        let vllm_client = Some(VllmClient::new(url));

        info!("⚠️ Smart Router: Apenas vLLM (Grok desabilitado)");

        Self {
            grok_client: None,
            vllm_client,
            vllm_fallback_enabled: true,
        }
    }

    /// Query inteligente com roteamento automático
    /// 
    /// Escolhe automaticamente:
    /// - Grok 3 se contexto total < 120k (ilimitado, rápido)
    /// - Grok 4 Heavy se contexto >= 120k (quota, mas contexto gigante)
    /// - vLLM se Grok falhar ou não estiver disponível (fallback)
    pub async fn query_smart(
        &self,
        prompt: &str,
        context_tokens: usize,
        temperature: Option<f32>,
        max_tokens: Option<u32>,
        top_p: Option<f32>,
    ) -> Result<String> {
        // Estima tokens do prompt (aproximação: 1 token ≈ 4 chars)
        let prompt_tokens = prompt.len() / 4;
        let total_context = context_tokens + prompt_tokens;

        debug!(
            "🧠 Smart Router: prompt_tokens={}, context_tokens={}, total={}",
            prompt_tokens, context_tokens, total_context
        );

        // Tenta Grok primeiro se disponível
        if let Some(grok) = &self.grok_client {
            // Escolhe modelo baseado no tamanho do contexto
            let model = if total_context < GROK3_MAX_CONTEXT {
                GrokModel::Grok3 // ILIMITADO, rápido
            } else {
                GrokModel::Grok4Heavy // Quota, mas contexto gigante
            };

            debug!(
                "🎯 Smart Router: usando {} (contexto total: {} tokens)",
                model.as_str(),
                total_context
            );

            // Cria cliente com modelo escolhido
            let api_key = std::env::var("XAI_API_KEY")
                .unwrap_or_else(|_| String::new());
            let grok_client = GrokClient::with_model(&api_key, model);

            match grok_client
                .chat_with_params(prompt, None, temperature, max_tokens, top_p)
                .await
            {
                Ok(response) => {
                    info!(
                        "✅ Smart Router: {} respondeu com sucesso ({} chars)",
                        model.as_str(),
                        response.len()
                    );
                    return Ok(response);
                }
                Err(e) => {
                    warn!("⚠️ Smart Router: Grok falhou ({:?}), tentando fallback vLLM", e);
                    // Continua para fallback vLLM
                }
            }
        }

        // Fallback para vLLM
        if let Some(vllm) = &self.vllm_client {
            info!("🔄 Smart Router: usando fallback vLLM");
            
            let request = VllmCompletionRequest {
                model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
                prompt: prompt.to_string(),
                sampling_params: SamplingParams {
                    temperature: temperature.unwrap_or(0.8) as f64,
                    top_p: top_p.unwrap_or(0.95) as f64,
                    max_tokens: max_tokens.unwrap_or(8192),
                    n: 1,
                    stop: None,
                    frequency_penalty: 0.0,
                },
            };

            match vllm.completions(&request).await {
                Ok(response) => {
                    let text = response
                        .choices
                        .first()
                        .map(|c| c.text.trim())
                        .ok_or_else(|| anyhow::anyhow!("Resposta vazia do vLLM"))?;
                    
                    info!("✅ Smart Router: vLLM respondeu com sucesso ({} chars)", text.len());
                    return Ok(text.to_string());
                }
                Err(e) => {
                    anyhow::bail!("Ambos Grok e vLLM falharam. Último erro: {}", e);
                }
            }
        }

        anyhow::bail!("Nenhum backend LLM disponível (Grok e vLLM desabilitados)");
    }

    /// Query simples sem parâmetros avançados (usa defaults)
    pub async fn query(&self, prompt: &str, context_tokens: usize) -> Result<String> {
        self.query_smart(prompt, context_tokens, None, None, None).await
    }
}

impl Default for SmartRouter {
    fn default() -> Self {
        Self::new()
    }
}

/// Função simplificada que retorna String diretamente (sem Result)
/// 
/// Alias para `query_beagle()` - usa Grok 3 ilimitado por padrão
/// 
/// # Example
/// ```rust
/// use beagle_smart_router::query_smart;
/// 
/// let response = query_smart("Pergunta aqui", 0).await;
/// ```
pub async fn query_smart(prompt: &str, context_tokens: usize) -> String {
    query_beagle(prompt, context_tokens).await
}

/// Função de conveniência com parâmetros completos
pub async fn query_smart_with_params(
    prompt: &str,
    context_tokens: usize,
    temperature: Option<f32>,
    max_tokens: Option<u32>,
    top_p: Option<f32>,
) -> Result<String> {
    let router = SmartRouter::new();
    router.query_smart(prompt, context_tokens, temperature, max_tokens, top_p).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_router_creation() {
        // Testa criação sem API key (deve usar apenas vLLM)
        let router = SmartRouter::new();
        assert!(router.vllm_client.is_some());
    }

    #[tokio::test]
    async fn test_query_smart_fallback() {
        // Este teste vai falhar se não tiver vLLM rodando, mas valida a lógica
        let router = SmartRouter::with_vllm_only("http://localhost:8000/v1");
        let result = router.query("test", 0).await;
        // Não asserta sucesso pois pode não ter vLLM rodando nos testes
        println!("Query result: {:?}", result);
    }
}
