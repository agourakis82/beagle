//! Measurement Operator - deterministic collapse plus optional LLM critic.
//!
//! Implements different collapse strategies. `CriticGuided` can use an external
//! LLM when available, but always falls back to a deterministic local decision.

use crate::superposition::HypothesisSet;
use beagle_llm::vllm::{SamplingParams, VllmClient, VllmCompletionRequest};
use tracing::{info, warn};

#[derive(Debug, Clone, Copy)]
pub enum CollapseStrategy {
    /// Colapsa sempre para a melhor hipótese (maior confiança)
    Greedy,
    /// Colapsa probabilisticamente baseado nas amplitudes
    Probabilistic,
    /// Mantém superposição se confiança máxima < threshold
    Delayed(f64),
    /// Uses an optional LLM critic to choose or synthesize the collapse.
    CriticGuided,
}

pub struct MeasurementOperator {
    llm: VllmClient,
    min_confidence: f64,
}

impl MeasurementOperator {
    pub fn new() -> Self {
        let llm = VllmClient::new("http://t560.local:8000/v1");
        Self {
            llm,
            min_confidence: 0.3,
        }
    }

    pub fn with_url(url: impl Into<String>) -> Self {
        let llm = VllmClient::new(url);
        Self {
            llm,
            min_confidence: 0.3,
        }
    }

    pub fn with_min_confidence(mut self, min_confidence: f64) -> Self {
        self.min_confidence = min_confidence.clamp(0.0, 1.0);
        self
    }

    /// Colapsa a superposição para uma única resposta
    pub async fn collapse(
        &self,
        set: HypothesisSet,
        strategy: CollapseStrategy,
    ) -> anyhow::Result<String> {
        info!("📊 Medindo superposição com estratégia: {:?}", strategy);

        if set.hypotheses.is_empty() {
            anyhow::bail!("HypothesisSet vazio - nada para medir");
        }

        match strategy {
            CollapseStrategy::Greedy => Ok(self.greedy_collapse(&set)),
            CollapseStrategy::Probabilistic => Ok(self.probabilistic_collapse(&set)),
            CollapseStrategy::Delayed(threshold) => match self.delayed_collapse(&set, threshold) {
                Some(answer) => Ok(answer),
                None => {
                    warn!("⚠️  Colapso adiado - confiança insuficiente");
                    Ok(set.best().content.clone())
                }
            },
            CollapseStrategy::CriticGuided => self.critic_guided_collapse(set).await,
        }
    }

    /// Método de compatibilidade com API antiga
    pub async fn measure(
        &self,
        set: HypothesisSet,
        strategy: CollapseStrategy,
    ) -> anyhow::Result<String> {
        self.collapse(set, strategy).await
    }

    fn greedy_collapse(&self, set: &HypothesisSet) -> String {
        set.best().content.clone()
    }

    fn probabilistic_collapse(&self, set: &HypothesisSet) -> String {
        // Usa rand::random() que é thread-safe (Send + Sync)
        let random: f64 = rand::random();

        let mut cumulative = 0.0;
        for hypothesis in &set.hypotheses {
            cumulative += hypothesis.confidence;
            if random <= cumulative {
                return hypothesis.content.clone();
            }
        }

        // Fallback para a melhor se nenhuma foi selecionada
        set.best().content.clone()
    }

    fn delayed_collapse(&self, set: &HypothesisSet, threshold: f64) -> Option<String> {
        let best = set.best();

        if best.confidence >= threshold {
            Some(best.content.clone())
        } else {
            // Mantém superposição - retorna None para indicar que não colapsou
            None
        }
    }

    /// Uses an LLM as an external critic. If the critic is unavailable, the
    /// operator returns a deterministic local fallback instead of failing the
    /// workflow.
    async fn critic_guided_collapse(&self, set: HypothesisSet) -> anyhow::Result<String> {
        info!("🎯 CriticGuided: usando crítico externo quando disponível");

        let hypotheses_text = set
            .hypotheses
            .iter()
            .enumerate()
            .map(|(i, h)| {
                format!(
                    "Hipótese {} (confiança {:.1}%):\n{}\n",
                    i + 1,
                    h.confidence * 100.0,
                    h.content
                )
            })
            .collect::<Vec<_>>()
            .join("\n---\n\n");

        let system_prompt = r#"Você é um crítico científico rigoroso.

Analise estas hipóteses concorrentes e escolha a melhor hipótese atual, ou crie uma síntese mais forte.

Considere confiança, coerência interna, poder explicativo e riscos de evidência insuficiente.

Responda APENAS com o texto final selecionado ou sintetizado."#;

        let user_prompt = format!(
            "Hipóteses em superposição:\n\n{}\n\nQual é a realidade colapsada?",
            hypotheses_text
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.7,
            top_p: 0.95,
            max_tokens: 1024,
            n: 1,
            stop: None,
            frequency_penalty: 0.0,
        };

        let request = VllmCompletionRequest {
            model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
            prompt: full_prompt,
            sampling_params: sampling,
        };

        let response = match self.llm.completions(&request).await {
            Ok(response) => response,
            Err(err) => {
                warn!("CriticGuided indisponível; usando fallback local: {}", err);
                return Ok(self.local_critic_fallback(&set));
            }
        };

        if response.choices.is_empty() {
            warn!("LLM não retornou resposta, usando fallback greedy");
            return Ok(self.local_critic_fallback(&set));
        }

        let collapsed = response.choices[0].text.trim().to_string();
        if collapsed.is_empty() {
            warn!("LLM retornou resposta vazia, usando fallback local");
            return Ok(self.local_critic_fallback(&set));
        }

        info!(
            "✅ CriticGuided colapsou para resposta de {} caracteres",
            collapsed.len()
        );
        Ok(collapsed)
    }

    fn local_critic_fallback(&self, set: &HypothesisSet) -> String {
        let best = set.best();
        if best.confidence >= self.min_confidence {
            return best.content.clone();
        }

        let mut ranked = set.hypotheses.clone();
        ranked.sort_by(|a, b| b.confidence.total_cmp(&a.confidence));

        ranked
            .into_iter()
            .take(3)
            .map(|hypothesis| {
                format!(
                    "- {:.1}% confidence: {}",
                    hypothesis.confidence * 100.0,
                    hypothesis.content
                )
            })
            .collect::<Vec<_>>()
            .join("\n")
    }
}

impl Default for MeasurementOperator {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::superposition::HypothesisSet;

    #[tokio::test]
    async fn critic_guided_falls_back_when_llm_is_offline() {
        let operator = MeasurementOperator::with_url("http://127.0.0.1:9/v1");
        let mut set = HypothesisSet::new();
        set.add("supported hypothesis".to_string(), Some((2.0, 0.0)));
        set.add("weaker hypothesis".to_string(), Some((0.5, 0.0)));

        let collapsed = operator
            .collapse(set, CollapseStrategy::CriticGuided)
            .await
            .expect("critic-guided collapse should have a local fallback");

        assert_eq!(collapsed, "supported hypothesis");
    }

    #[tokio::test]
    async fn critic_guided_low_confidence_fallback_preserves_candidates() {
        let operator =
            MeasurementOperator::with_url("http://127.0.0.1:9/v1").with_min_confidence(0.9);
        let mut set = HypothesisSet::new();
        set.add("candidate alpha".to_string(), Some((1.0, 0.0)));
        set.add("candidate beta".to_string(), Some((1.0, 0.0)));

        let collapsed = operator
            .collapse(set, CollapseStrategy::CriticGuided)
            .await
            .expect("low-confidence fallback should preserve ranked candidates");

        assert!(collapsed.contains("candidate alpha") || collapsed.contains("candidate beta"));
        assert!(collapsed.contains("confidence"));
    }
}
