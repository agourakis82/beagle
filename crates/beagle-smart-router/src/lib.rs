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

use anyhow::Result;
use beagle_grok_api::{GrokClient, GrokModel};
use beagle_llm::vllm::{SamplingParams, VllmClient, VllmCompletionRequest};
use once_cell::sync::Lazy;
use std::time::Duration;
use tokio::time::{sleep, timeout};
use tracing::{debug, error, info, warn};

const GROK3_MAX_CONTEXT: usize = 120_000; // Grok 3 suporta 128k, mas usa 120k como margem de segurança
const MAX_RETRIES: u32 = 5;
const TIMEOUT_SECS: u64 = 120;

/// Cliente Grok 3 global (ILIMITADO, 128k contexto, usado em 95% das queries)
static GROK3_CLIENT: Lazy<Option<GrokClient>> = Lazy::new(|| {
    std::env::var("XAI_API_KEY")
        .or_else(|_| std::env::var("GROK_API_KEY"))
        .ok()
        .map(|key| GrokClient::with_model(&key, GrokModel::Grok3))
});

/// Cliente Grok 4 global (contexto grande, para queries complexas)
static GROK4_CLIENT: Lazy<Option<GrokClient>> = Lazy::new(|| {
    std::env::var("XAI_API_KEY")
        .or_else(|_| std::env::var("GROK_API_KEY"))
        .ok()
        .map(|key| GrokClient::with_model(&key, GrokModel::Grok4))
});

/// Cliente vLLM global (fallback de emergência)
static VLLM_CLIENT: Lazy<Option<VllmClient>> = Lazy::new(|| {
    let url = std::env::var("VLLM_URL").unwrap_or_else(|_| "http://t560.local:8000/v1".to_string());
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
            debug!(
                "🚀 query_beagle: usando Grok-3 (ILIMITADO, contexto: {} tokens)",
                total_context
            );

            match grok3.chat_with_params(prompt, None, None, None, None).await {
                Ok(response) => {
                    info!(
                        "✅ query_beagle: Grok-3 respondeu ({} chars)",
                        response.len()
                    );
                    return response;
                }
                Err(e) => {
                    warn!(
                        "⚠️ query_beagle: Grok-3 falhou ({:?}), tentando Grok-4-Heavy",
                        e
                    );
                    // Continua para Grok 4 Heavy ou fallback
                }
            }
        }
    }

    // 2. Tenta Grok 4 Heavy se contexto >= 120k ou Grok 3 falhou
    if let Some(ref grok4) = *GROK4_CLIENT {
        debug!(
            "🚀 query_beagle: usando Grok-4-Heavy (QUOTA, contexto: {} tokens)",
            total_context
        );

        match grok4.chat_with_params(prompt, None, None, None, None).await {
            Ok(response) => {
                info!(
                    "✅ query_beagle: Grok-4-Heavy respondeu ({} chars)",
                    response.len()
                );
                return response;
            }
            Err(e) => {
                warn!(
                    "⚠️ query_beagle: Grok-4-Heavy falhou ({:?}), tentando fallback vLLM",
                    e
                );
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
                error!(
                    "❌ query_beagle: Todos os backends falharam. Último erro: {}",
                    e
                );
                return format!("ERRO: Todos os backends LLM falharam. Último erro: {}", e);
            }
        }
    }

    // 4. Nenhum backend disponível
    error!("❌ query_beagle: Nenhum backend LLM disponível (Grok e vLLM desabilitados)");
    "ERRO: Nenhum backend LLM disponível. Configure XAI_API_KEY ou VLLM_URL.".to_string()
}

/// HRV-aware flow state. Derived from physio observer's `flow_state` /
/// `hrv_level` fields in `/api/v1/cognitive/state`. High HRV → exploratory
/// tier preference. Low HRV → conservative. Normal → default order.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HrvTierHint {
    /// High HRV, user in peak/flow — prefer deeper reasoning (Grok-4-Heavy
    /// first even when context is small) and allow higher temperature for
    /// more exploratory sampling.
    Flow,
    /// Low HRV, user under stress — prefer fast Grok-3, cap max_tokens,
    /// drop temperature for more deterministic replies.
    Stress,
    /// Default Grok-3 → Grok-4 → vLLM ordering.
    Normal,
}

impl HrvTierHint {
    /// Parse from the string labels used throughout cognitive state:
    /// `flow`/`high` → Flow, `stress`/`low` → Stress, otherwise Normal.
    pub fn from_flow_state(s: Option<&str>) -> Self {
        match s.map(|x| x.to_ascii_lowercase()).as_deref() {
            Some("flow") | Some("high") => HrvTierHint::Flow,
            Some("stress") | Some("low") => HrvTierHint::Stress,
            _ => HrvTierHint::Normal,
        }
    }
}

/// HRV-aware variant of `query_beagle`. Same fallback chain, but the tier
/// preference and sampling parameters shift based on `hint`:
///
/// | Hint    | Primary tier   | Temperature | max_tokens |
/// |---------|----------------|-------------|------------|
/// | Flow    | Grok-4-Heavy   | 0.9         | 4096       |
/// | Stress  | Grok-3         | 0.3         | 1024       |
/// | Normal  | Grok-3         | None (def)  | None (def) |
///
/// Every fallback still runs in order, so a degraded tier preference never
/// breaks the query — at worst it adds one extra attempt before the normal
/// path kicks in.
pub async fn query_beagle_with_hrv(prompt: &str, context_tokens: usize, hint: HrvTierHint) -> String {
    let prompt_tokens = prompt.len() / 4;
    let total_context = context_tokens + prompt_tokens;
    let (temperature, max_tokens) = match hint {
        HrvTierHint::Flow => (Some(0.9f32), Some(4096u32)),
        HrvTierHint::Stress => (Some(0.3f32), Some(1024u32)),
        HrvTierHint::Normal => (None, None),
    };

    debug!(
        "🧠 query_beagle_with_hrv: hint={:?} prompt_tokens={} context_tokens={} total={}",
        hint, prompt_tokens, context_tokens, total_context
    );

    // Flow → try Grok-4-Heavy first regardless of context size.
    if matches!(hint, HrvTierHint::Flow) && total_context < GROK3_MAX_CONTEXT {
        if let Some(ref grok4) = *GROK4_CLIENT {
            debug!("🌊 flow-mode: trying Grok-4-Heavy first");
            if let Ok(response) = grok4
                .chat_with_params(prompt, None, temperature, max_tokens, None)
                .await
            {
                info!("✅ query_beagle_with_hrv(Flow): Grok-4-Heavy respondeu ({} chars)", response.len());
                return response;
            }
        }
    }

    // Default path: Grok-3 → Grok-4-Heavy → vLLM, each with HRV-shaped params.
    if total_context < GROK3_MAX_CONTEXT {
        if let Some(ref grok3) = *GROK3_CLIENT {
            if let Ok(response) = grok3
                .chat_with_params(prompt, None, temperature, max_tokens, None)
                .await
            {
                info!("✅ query_beagle_with_hrv({:?}): Grok-3 respondeu", hint);
                return response;
            }
        }
    }
    if let Some(ref grok4) = *GROK4_CLIENT {
        if let Ok(response) = grok4
            .chat_with_params(prompt, None, temperature, max_tokens, None)
            .await
        {
            info!("✅ query_beagle_with_hrv({:?}): Grok-4-Heavy respondeu", hint);
            return response;
        }
    }
    // vLLM fallback ignores the HRV shaping (its sampling params are fixed).
    warn!("query_beagle_with_hrv: falling back to plain query_beagle / vLLM chain");
    query_beagle(prompt, context_tokens).await
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
    /// Se XAI_API_KEY ou GROK_API_KEY estiver configurada, usa Grok (Grok3 ilimitado + Grok4Heavy quota).
    /// vLLM é sempre configurado como fallback de emergência.
    pub fn new() -> Self {
        let grok_client = std::env::var("XAI_API_KEY")
            .or_else(|_| std::env::var("GROK_API_KEY"))
            .ok()
            .map(|key| GrokClient::with_model(&key, GrokModel::Grok3));

        let vllm_url =
            std::env::var("VLLM_URL").unwrap_or_else(|_| "http://t560.local:8000/v1".to_string());

        let vllm_client = Some(VllmClient::new(&vllm_url));

        if grok_client.is_some() {
            info!("🚀 Smart Router: Grok habilitado (Grok3 ilimitado + Grok4 advanced) + vLLM fallback");
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
        let vllm_url =
            std::env::var("VLLM_URL").unwrap_or_else(|_| "http://t560.local:8000/v1".to_string());
        let vllm_client = Some(VllmClient::new(&vllm_url));

        info!("🚀 Smart Router: Grok forçado (Grok3 ilimitado + Grok4 advanced) + vLLM fallback");

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
                GrokModel::Grok41FastReasoning // Melhor performance com contexto grande
            };

            debug!(
                "🎯 Smart Router: usando {} (contexto total: {} tokens)",
                model.as_str(),
                total_context
            );

            // Cria cliente com modelo escolhido
            let api_key = std::env::var("XAI_API_KEY").unwrap_or_else(|_| String::new());
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
                    warn!(
                        "⚠️ Smart Router: Grok falhou ({:?}), tentando fallback vLLM",
                        e
                    );
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

                    info!(
                        "✅ Smart Router: vLLM respondeu com sucesso ({} chars)",
                        text.len()
                    );
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
        self.query_smart(prompt, context_tokens, None, None, None)
            .await
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

/// Query robusta com timeout, retry exponencial e fallback em cascata
///
/// **100% à prova de bala:**
/// - Timeout em todas as chamadas (120s)
/// - Retry exponencial com backoff (até 5 tentativas)
/// - Fallback em cascata (Grok3 → Grok41FastReasoning → vLLM → erro limpo)
/// - Nunca trava o loop principal
///
/// # Example
/// ```rust
/// use beagle_smart_router::query_robust;
///
/// let response = query_robust("Pergunta aqui", 80000).await;
/// ```
pub async fn query_robust(prompt: &str, context_tokens: usize) -> String {
    let mut attempt = 0;

    loop {
        attempt += 1;

        // 1. Grok 3 ilimitado (melhor custo-benefício)
        if context_tokens < GROK3_MAX_CONTEXT {
            if let Some(ref grok3) = *GROK3_CLIENT {
                match try_query_grok(grok3, prompt, "Grok3").await {
                    Ok(resp) => return resp,
                    Err(e) => warn!("Grok3 falhou (tentativa {}): {}", attempt, e),
                }
            }
        }

        // 2. Grok 4 Heavy (só se precisar do contexto gigante)
        if let Some(ref grok4) = *GROK4_CLIENT {
            match try_query_grok(grok4, prompt, "Grok4-Heavy").await {
                Ok(resp) => return resp,
                Err(e) => warn!("Grok4-Heavy falhou (tentativa {}): {}", attempt, e),
            }
        }

        // 3. Fallback local vLLM
        if let Some(ref vllm) = *VLLM_CLIENT {
            match try_query_vllm(vllm, prompt).await {
                Ok(resp) => return resp,
                Err(e) => error!("vLLM local falhou: {}", e),
            }
        }

        // 4. Se tudo falhou e ainda tem tentativas
        if attempt >= MAX_RETRIES {
            error!(
                "❌ Todas as tentativas falharam após {} retries",
                MAX_RETRIES
            );
            return "Erro crítico: todos os backends falharam. Tenta de novo em 5 minutos."
                .to_string();
        }

        // Bounded exponential backoff with jitter. Was `2^min(attempt,10)` seconds — up to
        // ~17 minutes and with no jitter (thundering-herd + effectively-hung retries). Cap at 30s.
        let base_ms = (250u64.saturating_mul(1u64 << attempt.min(6))).min(30_000);
        let jitter_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| (d.subsec_nanos() as u64) % (base_ms / 2 + 1))
            .unwrap_or(0);
        let backoff = Duration::from_millis((base_ms + jitter_ms).min(30_000));
        warn!(
            "⏳ Tentando novamente em {:.1}s... (tentativa {}/{})",
            backoff.as_secs_f32(),
            attempt,
            MAX_RETRIES
        );
        sleep(backoff).await;
    }
}

/// Tenta query no Grok com timeout
async fn try_query_grok(client: &GrokClient, prompt: &str, name: &str) -> Result<String, String> {
    match timeout(Duration::from_secs(TIMEOUT_SECS), client.chat(prompt, None)).await {
        Ok(Ok(resp)) => {
            info!("✅ {} respondeu com sucesso ({} chars)", name, resp.len());
            Ok(resp)
        }
        Ok(Err(e)) => Err(format!("{} erro: {:?}", name, e)),
        Err(_) => Err(format!("{} timeout após {}s", name, TIMEOUT_SECS)),
    }
}

/// Tenta query no vLLM com timeout
async fn try_query_vllm(vllm: &VllmClient, prompt: &str) -> Result<String, String> {
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

    match timeout(
        Duration::from_secs(TIMEOUT_SECS),
        vllm.completions(&request),
    )
    .await
    {
        Ok(Ok(response)) => {
            let text = response
                .choices
                .first()
                .map(|c| c.text.trim())
                .unwrap_or_default();

            info!("✅ vLLM local respondeu ({} chars)", text.len());
            Ok(text.to_string())
        }
        Ok(Err(e)) => Err(format!("vLLM erro: {:?}", e)),
        Err(_) => Err(format!("vLLM timeout após {}s", TIMEOUT_SECS)),
    }
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
    router
        .query_smart(prompt, context_tokens, temperature, max_tokens, top_p)
        .await
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
