//! Interference Engine - deterministic local fallback plus optional embeddings.
//!
//! Applies evidence as constructive/destructive interference. When an embedding
//! server is available, it uses semantic similarity. When it is not available,
//! it falls back to deterministic lexical similarity so the crate remains
//! usable and testable offline.

use crate::superposition::HypothesisSet;
use beagle_llm::embedding::EmbeddingClient;
use std::collections::{HashMap, HashSet};
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

    /// Applies evidence using embedding similarity with a deterministic lexical fallback.
    /// High similarity produces constructive interference; low similarity produces weaker
    /// destructive interference according to the supplied polarity.
    pub async fn apply_evidence(
        &self,
        set: &mut HypothesisSet,
        evidence: &str,
        polarity: f64, // -1.0 (contraditório) a +1.0 (suporte total)
    ) -> anyhow::Result<()> {
        info!("InterferenceEngine: aplicando evidência com polaridade {polarity:.2}");

        let evidence_emb = match self.embedding.embed(evidence).await {
            Ok(embedding) => Some(embedding),
            Err(err) => {
                warn!(
                    "Embedding indisponivel para evidencia; usando fallback lexical: {}",
                    err
                );
                None
            }
        };

        for hyp in &mut set.hypotheses {
            let similarity = if let Some(evidence_emb) = evidence_emb.as_ref() {
                match self.embedding.embed(&hyp.content).await {
                    Ok(hyp_emb) => EmbeddingClient::cosine_similarity(evidence_emb, &hyp_emb),
                    Err(err) => {
                        warn!(
                            "Embedding indisponivel para hipotese; usando fallback lexical: {}",
                            err
                        );
                        Self::lexical_cosine_similarity(evidence, &hyp.content)
                    }
                }
            } else {
                Self::lexical_cosine_similarity(evidence, &hyp.content)
            };

            let strength =
                similarity.clamp(0.0, 1.0) * polarity.clamp(-1.0, 1.0) * INTERFERENCE_STRENGTH;

            let (re, im) = hyp.amplitude;

            let phase_shift = strength * std::f64::consts::PI;

            let new_re = re * phase_shift.cos() - im * phase_shift.sin();
            let new_im = re * phase_shift.sin() + im * phase_shift.cos();

            let amplification = (1.0 + strength).max(0.01);
            hyp.amplitude = (new_re * amplification, new_im * amplification);

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

    pub fn lexical_cosine_similarity(a: &str, b: &str) -> f64 {
        let counts_a = Self::token_counts(a);
        let counts_b = Self::token_counts(b);

        if counts_a.is_empty() || counts_b.is_empty() {
            return 0.0;
        }

        let dot_product = counts_a
            .iter()
            .filter_map(|(token, count_a)| counts_b.get(token).map(|count_b| count_a * count_b))
            .sum::<f64>();
        let norm_a = counts_a
            .values()
            .map(|count| count * count)
            .sum::<f64>()
            .sqrt();
        let norm_b = counts_b
            .values()
            .map(|count| count * count)
            .sum::<f64>()
            .sqrt();

        if norm_a <= f64::EPSILON || norm_b <= f64::EPSILON {
            0.0
        } else {
            dot_product / (norm_a * norm_b)
        }
    }

    fn token_counts(text: &str) -> HashMap<String, f64> {
        let stopwords = HashSet::from([
            "a", "an", "and", "as", "da", "das", "de", "do", "dos", "e", "em", "for", "in", "is",
            "o", "of", "on", "os", "para", "por", "the", "to", "um", "uma", "with",
        ]);

        let mut counts = HashMap::new();
        for token in text
            .split(|character: char| !character.is_alphanumeric())
            .map(str::to_lowercase)
            .filter(|token| token.len() > 2 && !stopwords.contains(token.as_str()))
        {
            *counts.entry(token).or_insert(0.0) += 1.0;
        }

        counts
    }
}

impl Default for InterferenceEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::measurement::{CollapseStrategy, MeasurementOperator};
    use crate::superposition::HypothesisSet;

    #[test]
    fn lexical_similarity_detects_supporting_evidence() {
        let supportive = InterferenceEngine::lexical_cosine_similarity(
            "temperature increase raises entropy in the system",
            "entropy increases when temperature rises",
        );
        let unrelated = InterferenceEngine::lexical_cosine_similarity(
            "temperature increase raises entropy in the system",
            "archive metadata names the patient consent form",
        );

        assert!(supportive > unrelated);
        assert!(supportive > 0.0);
    }

    #[tokio::test]
    async fn apply_evidence_works_without_embedding_server() {
        let engine = InterferenceEngine::with_url("http://127.0.0.1:9/v1");
        let mut set = HypothesisSet::new();
        set.add(
            "entropy increases when temperature rises".to_string(),
            Some((1.0, 0.0)),
        );
        set.add(
            "archive metadata names the patient consent form".to_string(),
            Some((1.0, 0.0)),
        );

        engine
            .apply_evidence(
                &mut set,
                "temperature increase raises entropy in the system",
                1.0,
            )
            .await
            .expect("lexical fallback should keep interference usable offline");

        assert!(set.hypotheses[0].confidence > set.hypotheses[1].confidence);
        assert!(set
            .hypotheses
            .iter()
            .all(|hypothesis| hypothesis.confidence.is_finite()));
    }

    #[tokio::test]
    async fn offline_evidence_changes_ranking_and_measurement_collapses() {
        let engine = InterferenceEngine::with_url("http://127.0.0.1:9/v1");
        let measurement = MeasurementOperator::with_url("http://127.0.0.1:9/v1");
        let mut set = HypothesisSet::new();
        set.add(
            "archive metadata names the patient consent form".to_string(),
            Some((1.0, 0.0)),
        );
        set.add(
            "entropy increases when temperature rises".to_string(),
            Some((1.0, 0.0)),
        );

        assert!(set
            .hypotheses
            .iter()
            .all(|hypothesis| (hypothesis.confidence - 0.5).abs() < 1e-12));

        engine
            .apply_evidence(
                &mut set,
                "temperature increase raises entropy in the system",
                1.0,
            )
            .await
            .expect("offline evidence should still update amplitudes");

        let best = set.best();
        assert_eq!(best.content, "entropy increases when temperature rises");

        let collapsed = measurement
            .collapse(set, CollapseStrategy::CriticGuided)
            .await
            .expect("offline measurement should collapse through local fallback");

        assert_eq!(collapsed, "entropy increases when temperature rises");
    }
}
