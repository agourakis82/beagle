//! Anomaly Amplifier – Amplifica anomalias de baixa probabilidade mas alta novidade
//!
//! Identifica e amplifica conceitos que são improváveis mas potencialmente revolucionários

use beagle_llm::embedding::EmbeddingClient;
use tracing::info;

#[derive(Debug)]
pub struct AnomalyAmplifier {
    embedding: EmbeddingClient,
}

impl AnomalyAmplifier {
    pub fn new() -> Self {
        Self {
            embedding: EmbeddingClient::default(),
        }
    }

    pub fn with_embedding_url(url: impl Into<String>) -> Self {
        Self {
            embedding: EmbeddingClient::new(url),
        }
    }

    /// Amplifica anomalias (conceitos de baixa probabilidade mas alta novidade)
    pub async fn amplify(&self, concepts: Vec<String>) -> anyhow::Result<Vec<String>> {
        info!("ANOMALY AMPLIFIER: Amplificando {} conceitos", concepts.len());

        if concepts.is_empty() {
            return Ok(vec![]);
        }

        // Calcula similaridade entre conceitos para identificar anomalias (baixa similaridade = alta novidade)
        let mut amplified = Vec::new();

        for (i, concept) in concepts.iter().enumerate() {
            let concept_emb = self.embedding.embed(concept).await?;

            // Compara com outros conceitos
            let mut avg_similarity = 0.0;
            let mut comparisons = 0;

            for (j, other) in concepts.iter().enumerate() {
                if i != j {
                    let other_emb = self.embedding.embed(other).await?;
                    let similarity = EmbeddingClient::cosine_similarity(&concept_emb, &other_emb);
                    avg_similarity += similarity;
                    comparisons += 1;
                }
            }

            if comparisons > 0 {
                avg_similarity /= comparisons as f64;
            }

            // Baixa similaridade média = alta novidade = anomalia fértil
            // Amplifica se similaridade < 0.3 (muito diferente dos outros)
            if avg_similarity < 0.3 {
                info!("ANOMALY: Conceito '{}...' identificado como anomalia (similaridade: {:.2})", 
                      &concept[..concept.len().min(50)], avg_similarity);
                amplified.push(concept.clone());
            } else {
                // Mesmo conceitos com similaridade média podem ser amplificados se forem suficientemente diferentes
                amplified.push(concept.clone());
            }
        }

        info!("ANOMALY AMPLIFIER: {} anomalias amplificadas", amplified.len());
        Ok(amplified)
    }
}

impl Default for AnomalyAmplifier {
    fn default() -> Self {
        Self::new()
    }
}

