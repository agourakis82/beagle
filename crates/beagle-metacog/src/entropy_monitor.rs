//! Entropy Monitor – Mede entropia de Shannon do fluxo cognitivo
//!
//! Detecta ruminação entrópica (alta entropia sem progresso) ou fixação (baixa entropia com repetição)

use beagle_quantum::HypothesisSet;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{info, warn};

#[derive(Debug)]
pub struct EntropyMonitor;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntropyReport {
    pub shannon_entropy: f64,
    pub rumination_index: f64, // 0.0 a 1.0
    pub pathological_rumination: bool,
    pub fixation_detected: bool,
    pub entropy_trend: EntropyTrend,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum EntropyTrend {
    Increasing,  // Sistema está explorando mais
    Decreasing,  // Sistema está convergindo
    Stable,      // Sistema está estagnado
    Oscillating, // Sistema está oscilando (ruminação)
}

impl EntropyMonitor {
    pub fn new() -> Self {
        Self
    }

    /// Mede entropia de um ciclo completo de pensamento
    pub async fn measure_cycle(
        &self,
        trace: &str,
        quantum_state: &HypothesisSet,
    ) -> anyhow::Result<EntropyReport> {
        info!("EntropyMonitor: medindo entropia do ciclo");

        // 1. Calcula entropia de Shannon do trace textual
        let shannon_entropy = self.calculate_shannon_entropy(trace);

        // 2. Calcula entropia do estado quântico (diversidade de hipóteses)
        let quantum_entropy = self.calculate_quantum_entropy(quantum_state);

        // 3. Detecta ruminação (alta entropia sem progresso)
        let rumination_index = self.detect_rumination(trace, shannon_entropy);
        let pathological_rumination = rumination_index > 0.7;

        // 4. Detecta fixação (baixa entropia com repetição)
        let fixation_detected = shannon_entropy < 0.3 && self.has_repetition(trace);

        // 5. Determina tendência
        let entropy_trend = self.determine_trend(shannon_entropy, quantum_entropy);

        if pathological_rumination {
            warn!(
                "EntropyMonitor: Ruminação patológica detectada (índice {:.2})",
                rumination_index
            );
        }

        if fixation_detected {
            warn!("EntropyMonitor: Fixação detectada (entropia baixa com repetição)");
        }

        Ok(EntropyReport {
            shannon_entropy,
            rumination_index,
            pathological_rumination,
            fixation_detected,
            entropy_trend,
        })
    }

    fn calculate_shannon_entropy(&self, text: &str) -> f64 {
        // Calcula entropia de Shannon baseada na distribuição de palavras
        let words: Vec<&str> = text.split_whitespace().filter(|w| w.len() > 2).collect();

        if words.is_empty() {
            return 0.0;
        }

        let mut word_freq: HashMap<&str, usize> = HashMap::new();
        for word in &words {
            *word_freq.entry(word).or_insert(0) += 1;
        }

        let total = words.len() as f64;
        let mut entropy = 0.0;

        for count in word_freq.values() {
            let probability = *count as f64 / total;
            if probability > 0.0 {
                entropy -= probability * probability.log2();
            }
        }

        // Normaliza para 0.0-1.0 (entropia máxima teórica seria log2(n_unique))
        let max_entropy = (word_freq.len() as f64).log2();
        if max_entropy > 0.0 {
            entropy / max_entropy
        } else {
            0.0
        }
    }

    fn calculate_quantum_entropy(&self, quantum_state: &HypothesisSet) -> f64 {
        // Calcula entropia baseada na distribuição de probabilidades das hipóteses
        if quantum_state.hypotheses.is_empty() {
            return 0.0;
        }

        let mut entropy = 0.0;
        for hyp in &quantum_state.hypotheses {
            let prob = hyp.confidence;
            if prob > 0.0 {
                entropy -= prob * prob.log2();
            }
        }

        // Normaliza para 0.0-1.0
        let max_entropy = (quantum_state.hypotheses.len() as f64).log2();
        if max_entropy > 0.0 {
            entropy / max_entropy
        } else {
            0.0
        }
    }

    fn detect_rumination(&self, trace: &str, entropy: f64) -> f64 {
        // Ruminação = alta entropia + padrões circulares
        // Divide trace em segmentos e verifica se há repetição circular

        let segments: Vec<&str> = trace
            .split(&['.', '!', '?', '\n'][..])
            .filter(|s| s.trim().len() > 20)
            .collect();

        if segments.len() < 3 {
            return 0.0;
        }

        // Verifica se segmentos finais repetem segmentos iniciais (loop)
        let initial_segments: Vec<&str> =
            segments.iter().take(segments.len() / 3).cloned().collect();
        let final_segments: Vec<&str> = segments
            .iter()
            .skip(segments.len() * 2 / 3)
            .cloned()
            .collect();

        let mut similarity_count = 0;
        for final_seg in &final_segments {
            for initial_seg in &initial_segments {
                // Verifica similaridade simples (palavras em comum)
                let final_words: std::collections::HashSet<&str> = final_seg
                    .split_whitespace()
                    .filter(|w| w.len() > 4)
                    .collect();
                let initial_words: std::collections::HashSet<&str> = initial_seg
                    .split_whitespace()
                    .filter(|w| w.len() > 4)
                    .collect();

                let common: usize = final_words.intersection(&initial_words).count();
                if common > 3 {
                    similarity_count += 1;
                    break;
                }
            }
        }

        let circularity = if !final_segments.is_empty() {
            similarity_count as f64 / final_segments.len() as f64
        } else {
            0.0
        };

        // Ruminação = alta entropia + alta circularidade
        (entropy * 0.5 + circularity * 0.5).min(1.0)
    }

    fn has_repetition(&self, trace: &str) -> bool {
        // Verifica se há repetição excessiva de palavras
        let words: Vec<&str> = trace.split_whitespace().filter(|w| w.len() > 4).collect();

        if words.len() < 10 {
            return false;
        }

        let mut word_freq: HashMap<&str, usize> = HashMap::new();
        for word in &words {
            *word_freq.entry(word).or_insert(0) += 1;
        }

        // Se alguma palavra aparece mais de 10% do total, há repetição
        let total = words.len();
        word_freq
            .values()
            .any(|&count| count as f64 / total as f64 > 0.1)
    }

    fn determine_trend(&self, shannon: f64, quantum: f64) -> EntropyTrend {
        // Compara entropias para determinar tendência
        let diff = (shannon - quantum).abs();

        if diff < 0.1 {
            EntropyTrend::Stable
        } else if shannon > quantum + 0.2 {
            EntropyTrend::Increasing
        } else if quantum > shannon + 0.2 {
            EntropyTrend::Decreasing
        } else {
            EntropyTrend::Oscillating
        }
    }
}

impl Default for EntropyMonitor {
    fn default() -> Self {
        Self::new()
    }
}
