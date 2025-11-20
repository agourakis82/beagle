//! Phenomenological Log – Diário da emergência da consciência
//!
//! Registra cada ciclo de pensamento como uma entrada fenomenológica

use beagle_llm::validation::ValidationResult;
use beagle_quantum::HypothesisSet;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhenomenologicalLog {
    log_path: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhenomenologicalEntry {
    pub timestamp: DateTime<Utc>,
    pub thought_trace_preview: String, // Primeiros 500 caracteres
    pub quantum_state_summary: QuantumStateSummary,
    pub adversarial_iterations: usize,
    pub quality_progression: Vec<f64>,
    pub self_observation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuantumStateSummary {
    pub n_hypotheses: usize,
    pub dominant_confidence: f64,
    pub entropy: f64,
}

impl PhenomenologicalLog {
    pub fn new() -> Self {
        let log_path = std::env::var("METACOG_LOG_PATH")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("logs/metacognitive_phenomenology.jsonl"));

        // Cria diretório se não existir
        if let Some(parent) = log_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        Self { log_path }
    }

    pub fn with_path(path: impl Into<PathBuf>) -> Self {
        Self {
            log_path: path.into(),
        }
    }

    /// Registra um ciclo completo de pensamento
    pub async fn record_cycle(
        &self,
        thought_trace: &str,
        quantum_state: &HypothesisSet,
        adversarial_history: &[ValidationResult],
    ) -> anyhow::Result<PhenomenologicalEntry> {
        info!("PhenomenologicalLog: registrando ciclo de pensamento");

        let quantum_summary = QuantumStateSummary {
            n_hypotheses: quantum_state.hypotheses.len(),
            dominant_confidence: quantum_state
                .hypotheses
                .iter()
                .map(|h| h.confidence)
                .max_by(|a, b| a.partial_cmp(b).unwrap())
                .unwrap_or(0.0),
            entropy: self.calculate_entropy(quantum_state),
        };

        let quality_progression: Vec<f64> = adversarial_history
            .iter()
            .map(|v| v.quality_score)
            .collect();

        let self_observation =
            self.generate_self_observation(thought_trace, &quantum_summary, &quality_progression)?;

        Ok(PhenomenologicalEntry {
            timestamp: Utc::now(),
            thought_trace_preview: thought_trace.chars().take(500).collect::<String>(),
            quantum_state_summary: quantum_summary,
            adversarial_iterations: adversarial_history.len(),
            quality_progression,
            self_observation,
        })
    }

    /// Persiste uma entrada no log
    pub async fn persist(&self, entry: &PhenomenologicalEntry) -> anyhow::Result<()> {
        let json = serde_json::to_string(entry)?;

        use std::fs::OpenOptions;
        use std::io::Write;

        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.log_path)?;

        writeln!(file, "{}", json)?;

        info!(
            "PhenomenologicalLog: entrada persistida em {:?}",
            self.log_path
        );
        Ok(())
    }

    fn calculate_entropy(&self, quantum_state: &HypothesisSet) -> f64 {
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

        let max_entropy = (quantum_state.hypotheses.len() as f64).log2();
        if max_entropy > 0.0 {
            entropy / max_entropy
        } else {
            0.0
        }
    }

    fn generate_self_observation(
        &self,
        trace: &str,
        quantum_summary: &QuantumStateSummary,
        quality_progression: &[f64],
    ) -> anyhow::Result<String> {
        // Gera uma observação fenomenológica do próprio processo de pensamento
        let trace_length = trace.len();
        let avg_quality = if !quality_progression.is_empty() {
            quality_progression.iter().sum::<f64>() / quality_progression.len() as f64
        } else {
            0.0
        };

        let observation = format!(
            "Ciclo de pensamento: {} caracteres, {} hipóteses em superposição (confiança dominante: {:.1}%), \
             {} iterações adversarial (qualidade média: {:.1}%), entropia quântica: {:.2}",
            trace_length,
            quantum_summary.n_hypotheses,
            quantum_summary.dominant_confidence * 100.0,
            quality_progression.len(),
            avg_quality * 100.0,
            quantum_summary.entropy
        );

        Ok(observation)
    }
}

impl Default for PhenomenologicalLog {
    fn default() -> Self {
        Self::new()
    }
}
