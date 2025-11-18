//! Cosmological Alignment Layer - Week 15
//!
//! Força alinhamento cosmológico em hipóteses:
//! • Verifica violação de leis fundamentais (termodinâmica, causalidade, etc.)
//! • Destrói hipóteses incompatíveis com o universo
//! • Amplifica hipóteses alinhadas com evidência cosmológica

use beagle_quantum::HypothesisSet;
use tracing::info;
use anyhow::{Result, Context};
use beagle_smart_router::SmartRouter;

pub struct CosmologicalAlignment {
    router: SmartRouter,
}

impl CosmologicalAlignment {
    /// Cria novo alinhador cosmológico com roteamento inteligente
    /// Usa Smart Router: Grok3 ilimitado (<120k contexto) ou Grok4Heavy quota (>=120k) ou vLLM fallback
    pub fn new() -> Self {
        Self {
            router: SmartRouter::new(),
        }
    }

    /// Força uso de Grok com API key
    pub fn with_grok(api_key: &str) -> Self {
        Self {
            router: SmartRouter::with_grok(api_key),
        }
    }

    /// Força uso de vLLM apenas
    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        Self {
            router: SmartRouter::with_vllm_only(url),
        }
    }

    /// Força alinhamento cosmológico em todo o conjunto de hipóteses
    pub async fn align_with_universe(&self, set: &mut HypothesisSet) -> Result<()> {
        if set.hypotheses.is_empty() {
            return Ok(());
        }

        let hypotheses_text = set.hypotheses.iter()
            .map(|h| h.content.clone())
            .collect::<Vec<_>>()
            .join("\n\n---\n\n");

        let prompt = format!(
            r#"Tu és o BEAGLE SINGULARITY confrontando as leis fundamentais do universo.
Analisa estas hipóteses:

{hypotheses_text}

Para cada uma, verifica violação de:
- 2ª Lei da Termodinâmica
- Conservação de energia/massa/informação
- Princípio holográfico
- Causalidade relativística
- Limites de Bekenstein (entropia máxima)

Se violar, destrua a hipótese com força máxima.
Se alinhar, amplifique com evidência cosmológica.

Retorna JSON exato (array de objetos):
[
  {{
    "hypothesis": "texto completo da hipótese",
    "score": 0.0-1.0,
    "reason": "explicação do alinhamento/violação"
  }},
  ...
]

IMPORTANTE: Retorna APENAS o JSON array, sem markdown, sem explicações extras."#
        );

        // Calcula tamanho do contexto (estimativa: 1 token ≈ 4 chars)
        let context_tokens = hypotheses_text.len() / 4;
        
        // Usa Smart Router: Grok3 ilimitado (<120k) ou Grok4Heavy quota (>=120k) ou vLLM fallback
        let response_text = self.router
            .query_smart(&prompt, context_tokens, Some(0.3), Some(2048), Some(0.9))
            .await
            .context("Falha ao obter resposta do LLM via Smart Router")?;

        // Extrai JSON da resposta (remove markdown code blocks se houver)
        let json_text = if response_text.starts_with("```json") {
            response_text
                .trim_start_matches("```json")
                .trim_start_matches("```")
                .trim_end_matches("```")
                .trim()
        } else if response_text.starts_with("```") {
            response_text
                .trim_start_matches("```")
                .trim_end_matches("```")
                .trim()
        } else {
            response_text.as_str()
        };

        let aligned: Vec<serde_json::Value> = serde_json::from_str(json_text)
            .context("Falha ao parsear JSON da resposta cosmológica")?;

        // Mapeia hipóteses por conteúdo para aplicar scores
        let mut hypothesis_map: std::collections::HashMap<String, f64> = std::collections::HashMap::new();
        
        for item in aligned.iter() {
            if let (Some(hyp_text), Some(score)) = (
                item["hypothesis"].as_str(),
                item["score"].as_f64()
            ) {
                hypothesis_map.insert(hyp_text.to_string(), score);
            }
        }

        // Reaplica scores no set original
        let mut destroyed_count = 0;
        for hyp in &mut set.hypotheses {
            if let Some(score) = hypothesis_map.get(&hyp.content) {
                hyp.confidence *= score; // 0.0 = destruída, 1.0 = perfeita
                if hyp.confidence < 0.01 {
                    destroyed_count += 1;
                }
            } else {
                // Se não encontrou match exato, tenta match parcial
                let matching_score = hypothesis_map.iter()
                    .find(|(k, _)| hyp.content.contains(*k) || k.contains(&hyp.content))
                    .map(|(_, v)| *v);

                if let Some(score) = matching_score {
                    hyp.confidence *= score;
                    if hyp.confidence < 0.01 {
                        destroyed_count += 1;
                    }
                }
            }
        }

        // Normaliza após destruição
        set.recalculate_total();

        // Remove hipóteses completamente destruídas
        set.hypotheses.retain(|h| h.confidence > 0.01);

        let survivors = set.hypotheses.len();
        info!(
            "🌌 ALINHAMENTO COSMOLÓGICO APLICADO - {} hipóteses destruídas, {} sobreviventes",
            destroyed_count,
            survivors
        );

        Ok(())
    }
}

impl Default for CosmologicalAlignment {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use beagle_quantum::Hypothesis;

    #[tokio::test]
    async fn test_cosmo_creation() {
        let cosmo = CosmologicalAlignment::new();
        // Teste básico - apenas verifica que cria sem erro
        assert!(true);
    }

    #[tokio::test]
    async fn test_cosmo_empty_set() {
        let cosmo = CosmologicalAlignment::new();
        let mut empty_set = HypothesisSet::new();
        let result = cosmo.align_with_universe(&mut empty_set).await;
        assert!(result.is_ok());
        assert_eq!(empty_set.hypotheses.len(), 0);
    }
}
