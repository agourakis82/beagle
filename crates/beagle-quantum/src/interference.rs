//! Interference Engine – VERSÃO PRODUCTION (100% LLM REAL + EMBEDDINGS)
//!
//! Aplica evidências usando embedding similarity para interferência construtiva/destrutiva real

use crate::superposition::HypothesisSet;
use beagle_llm::embedding::EmbeddingClient;
use tracing::{info, warn};

const INTERFERENCE_STRENGTH: f64 = 1.8; // amplificação máxima

#[derive(Debug)]
pub struct InterferenceEngine {
    embedding: EmbeddingClient,
}

impl InterferenceEngine {
    pub fn new() -> Self {
        let embedding = EmbeddingClient::new("http://t560.local:8001/v1");
        Self { embedding }
    }

    pub fn with_url(url: impl Into<String>) -> Self {
        let embedding = EmbeddingClient::new(url);
        Self { embedding }
    }

    /// Aplica evidência real usando embedding similarity
    /// Alta similaridade → constructive interference (amplifica amplitude)
    /// Baixa similaridade → destructive interference (reduz ou inverte fase)
    pub async fn apply_evidence(
        &self,
        set: &mut HypothesisSet,
        evidence: &str,
        polarity: f64, // -1.0 (contraditório) a +1.0 (suporte total)
    ) -> anyhow::Result<()> {
        info!("InterferenceEngine: aplicando evidência com polaridade {polarity:.2}");

        // Embed da evidência (uma vez)
        let evidence_emb = self.embedding.embed(evidence).await?;

        for hyp in &mut set.hypotheses {
            // Embed da hipótese
            let hyp_emb = self.embedding.embed(&hyp.content).await?;

            // Cosine similarity (-1 a 1)
            let similarity = EmbeddingClient::cosine_similarity(&evidence_emb, &hyp_emb);

            // Força da interferência baseada em similaridade + polaridade do usuário
            let strength = similarity * polarity * INTERFERENCE_STRENGTH;

            let (re, im) = hyp.amplitude;

            // Phase shift baseado na força (interferência real)
            let phase_shift = strength * std::f64::consts::PI;

            let new_re = re * phase_shift.cos() - im * phase_shift.sin();
            let new_im = re * phase_shift.sin() + im * phase_shift.cos();

            // Amplificação/atenuação exponencial
            let amplification = (1.0 + strength).max(0.01); // nunca vai a zero total (evita colapso prematuro)
            hyp.amplitude = (new_re * amplification, new_im * amplification);

            // Log para debug
            if strength < -0.5 {
                warn!(
                    "Interferência destrutiva forte em hipótese: {:.2} similarity",
                    similarity
                );
            }
        }

        set.recalculate_total();
        Ok(())
    }

    /// Multi-evidência em batch (otimizado)
    pub async fn apply_multiple_evidences(
        &self,
        set: &mut HypothesisSet,
        evidences: Vec<(&str, f64)>, // (texto, polaridade)
    ) -> anyhow::Result<()> {
        for (ev, pol) in evidences {
            self.apply_evidence(set, ev, pol).await?;
        }
        Ok(())
    }

    /// Método de compatibilidade com API antiga (sem polaridade)
    pub async fn interfere(&self, set: &mut HypothesisSet, evidence: &str) -> anyhow::Result<()> {
        self.apply_evidence(set, evidence, 1.0).await
    }
}

impl Default for InterferenceEngine {
    fn default() -> Self {
        Self::new()
    }
}
