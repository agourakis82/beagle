//! Serendipity Injector – Núcleo da Serendipidade Deliberada
//!
//! Injeta acidentes científicos férteis em ciclos cognitivos estabilizados

use crate::{
    anomaly_amplifier::AnomalyAmplifier,
    cross_domain_mutator::CrossDomainMutator,
    fertility_scorer::{FertileAccident, FertilityScorer},
};
use beagle_metacog::MetacognitiveReflector;
use beagle_quantum::HypothesisSet;
use tracing::{info, warn};

#[derive(Debug)]
pub struct SerendipityInjector {
    mutator: CrossDomainMutator,
    amplifier: AnomalyAmplifier,
    scorer: FertilityScorer,
    metacog: MetacognitiveReflector,
}

impl SerendipityInjector {
    pub fn new() -> Self {
        Self {
            mutator: CrossDomainMutator::new(),
            amplifier: AnomalyAmplifier::new(),
            scorer: FertilityScorer::new(),
            metacog: MetacognitiveReflector::new(),
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        let url_str: String = url.into();
        Self {
            mutator: CrossDomainMutator::with_vllm_url(url_str.clone()),
            amplifier: AnomalyAmplifier::new(),
            scorer: FertilityScorer::with_vllm_url(url_str.clone()),
            metacog: MetacognitiveReflector::with_vllm_url(url_str),
        }
    }

    /// Injeta serendipidade em um ciclo cognitivo estabilizado
    /// Executado automaticamente quando entropia metacognitiva cai abaixo de threshold
    pub async fn inject_fertile_accident(
        &self,
        current_hypothesis_set: &HypothesisSet,
        research_context: &str,
    ) -> anyhow::Result<Vec<String>> {
        info!("🔬 SERENDIPITY ENGINE: Injetando acidente fértil deliberado");

        // 1. Mutação cruzada com domínios distantes
        let mutated_concepts = self
            .mutator
            .cross_pollinate(current_hypothesis_set, research_context)
            .await?;

        if mutated_concepts.is_empty() {
            warn!("SERENDIPITY: Mutação cruzada não gerou conceitos");
            return Ok(vec![]);
        }

        // 2. Amplificação de anomalias (baixa probabilidade mas alta novidade)
        let amplified_anomalies = self.amplifier.amplify(mutated_concepts).await?;

        if amplified_anomalies.is_empty() {
            warn!("SERENDIPITY: Amplificação não identificou anomalias");
            return Ok(vec![]);
        }

        // 3. Pontuação de fertilidade científica (potencial de descoberta real)
        let fertile_accidents = self.scorer.score(&amplified_anomalies).await?;

        if fertile_accidents.is_empty() {
            warn!("SERENDIPITY: Nenhum acidente fértil identificado");
            return Ok(vec![]);
        }

        // 4. Reflexão metacognitiva sobre o acidente gerado
        let thought_trace = format!(
            "Serendipity injection: {} acidentes férteis gerados",
            fertile_accidents.len()
        );

        let reflection = self
            .metacog
            .reflect_on_cycle(&thought_trace, current_hypothesis_set, &[])
            .await?;

        if let Some(intervention) = reflection.correction {
            warn!("METACOG rejeitou serendipidade: {}", intervention);
            return Ok(vec![]); // acidente estéril
        }

        // Extrai apenas o conteúdo dos acidentes férteis
        let fertile_contents: Vec<String> = fertile_accidents
            .iter()
            .map(|acc| acc.content.clone())
            .collect();

        info!(
            "✅ SERENDIPIDADE FÉRTIL GERADA: {} acidentes viáveis",
            fertile_contents.len()
        );

        for (i, accident) in fertile_contents.iter().enumerate() {
            info!("  {}. {}", i + 1, &accident[..accident.len().min(80)]);
        }

        Ok(fertile_contents)
    }

    /// Versão que retorna acidentes completos com scores
    pub async fn inject_fertile_accidents_with_scores(
        &self,
        current_hypothesis_set: &HypothesisSet,
        research_context: &str,
    ) -> anyhow::Result<Vec<FertileAccident>> {
        info!("🔬 SERENDIPITY ENGINE: Injetando acidentes férteis com scores");

        let mutated_concepts = self
            .mutator
            .cross_pollinate(current_hypothesis_set, research_context)
            .await?;

        if mutated_concepts.is_empty() {
            return Ok(vec![]);
        }

        let amplified_anomalies = self.amplifier.amplify(mutated_concepts).await?;

        if amplified_anomalies.is_empty() {
            return Ok(vec![]);
        }

        let fertile_accidents = self.scorer.score(&amplified_anomalies).await?;

        // Reflexão metacognitiva
        let thought_trace = format!(
            "Serendipity injection: {} acidentes férteis gerados",
            fertile_accidents.len()
        );

        let reflection = self
            .metacog
            .reflect_on_cycle(&thought_trace, current_hypothesis_set, &[])
            .await?;

        if reflection.correction.is_some() {
            warn!("METACOG rejeitou serendipidade");
            return Ok(vec![]);
        }

        Ok(fertile_accidents)
    }
}

impl Default for SerendipityInjector {
    fn default() -> Self {
        Self::new()
    }
}
