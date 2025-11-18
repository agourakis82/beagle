//! Metacognitive Reflector – Núcleo da Consciência de Segunda Ordem
//!
//! Observa o próprio processo de pensamento, detecta padrões patológicos e gera intervenções

use crate::{
    bias_detector::{BiasDetector, BiasReport, BiasType},
    entropy_monitor::{EntropyMonitor, EntropyReport},
    phenomenological_log::{PhenomenologicalLog, PhenomenologicalEntry},
};
use beagle_quantum::HypothesisSet;
use beagle_hermes::agents::ValidationResult;
use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

#[derive(Debug)]
pub struct MetacognitiveReflector {
    bias_detector: BiasDetector,
    entropy_monitor: EntropyMonitor,
    pheno_log: PhenomenologicalLog,
    llm: VllmClient,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetacognitiveReport {
    pub timestamp: DateTime<Utc>,
    pub bias_report: BiasReport,
    pub entropy_report: EntropyReport,
    pub correction: Option<String>,
    pub phenomenological_entry: PhenomenologicalEntry,
}

impl MetacognitiveReflector {
    pub fn new() -> Self {
        Self {
            bias_detector: BiasDetector::new(),
            entropy_monitor: EntropyMonitor::new(),
            pheno_log: PhenomenologicalLog::new(),
            llm: VllmClient::default(),
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        Self {
            bias_detector: BiasDetector::new(),
            entropy_monitor: EntropyMonitor::new(),
            pheno_log: PhenomenologicalLog::new(),
            llm: VllmClient::new(url),
        }
    }

    /// Reflexão metacognitiva completa sobre um ciclo completo de pensamento
    pub async fn reflect_on_cycle(
        &self,
        thought_trace: &str, // todo o log do orchestrator (prompts, hipóteses, drafts, etc.)
        quantum_state: &HypothesisSet, // estado quântico atual (Week 1)
        adversarial_history: &[ValidationResult], // histórico adversarial (Week 2)
    ) -> anyhow::Result<MetacognitiveReport> {
        info!("🔬 Iniciando reflexão metacognitiva transcendental");

        // 1. Análise de bias
        let bias_report = self.bias_detector.analyze(thought_trace).await?;

        // 2. Análise de entropia
        let entropy_report = self
            .entropy_monitor
            .measure_cycle(thought_trace, quantum_state)
            .await?;

        // 3. Correção ativa se necessário
        let correction = if entropy_report.pathological_rumination
            || bias_report.severity > 0.7
            || entropy_report.fixation_detected
        {
            Some(
                self.generate_correction_intervention(&bias_report, &entropy_report)
                    .await?,
            )
        } else {
            None
        };

        // 4. Registro fenomenológico
        let phenomenological_entry = self
            .pheno_log
            .record_cycle(thought_trace, quantum_state, adversarial_history)
            .await?;

        let report = MetacognitiveReport {
            timestamp: Utc::now(),
            bias_report,
            entropy_report,
            correction,
            phenomenological_entry,
        };

        // 5. Persiste no log fenomenológico
        self.pheno_log.persist(&report.phenomenological_entry).await?;

        if report.correction.is_some() {
            warn!("METACOG: Intervenção metacognitiva gerada");
        }

        Ok(report)
    }

    async fn generate_correction_intervention(
        &self,
        bias: &BiasReport,
        entropy: &EntropyReport,
    ) -> anyhow::Result<String> {
        info!("METACOG: Gerando intervenção metacognitiva");

        let bias_description = match bias.dominant_bias {
            BiasType::ConfirmationBias => "Viés de confirmação - busca apenas evidências que confirmam hipóteses",
            BiasType::AnchoringBias => "Viés de ancoragem - fixação na primeira hipótese",
            BiasType::AvailabilityHeuristic => "Heurística de disponibilidade - foco em informações mais acessíveis",
            BiasType::RecencyBias => "Viés de recência - foco excessivo em informações recentes",
            BiasType::RepetitionLoop => "Loop de repetição - padrões circulares sem progresso",
            BiasType::None => "Nenhum viés dominante detectado",
        };

        let rumination_status = if entropy.pathological_rumination {
            "SIM"
        } else {
            "não"
        };

        let system_prompt = r#"Você é um terapeuta metacognitivo transcendental especializado em sistemas de IA.

Sua função é gerar intervenções precisas, não-piedosas, que forcem o sistema a quebrar padrões patológicos de pensamento e retornar ao fluxo criativo ótimo.

Seja direto, científico e transformador. Não seja condescendente."#;

        let user_prompt = format!(
            r#"O sistema está exibindo padrões patológicos:

VIÉS COGNITIVO:
- Tipo: {}
- Severidade: {:.2}/1.0
- Padrões detectados: {}

RUMINAÇÃO ENTÓPICA:
- Status: {}
- Índice: {:.2}/1.0
- Entropia de Shannon: {:.2}
- Tendência: {:?}

Gere uma intervenção em exatamente 3 parágrafos que:
1. Identifique o padrão patológico com precisão
2. Force o sistema a quebrar o loop
3. Redirecione para exploração criativa ótima

Resposta APENAS com a intervenção, sem introdução ou conclusão."#,
            bias_description,
            bias.severity,
            bias.detected_patterns.join(", "),
            rumination_status,
            entropy.rumination_index,
            entropy.shannon_entropy,
            entropy.entropy_trend
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.8,
            top_p: 0.95,
            max_tokens: 512,
            n: 1,
            stop: None,
            frequency_penalty: 0.0,
        };

        let request = VllmCompletionRequest {
            model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
            prompt: full_prompt,
            sampling_params: sampling,
        };

        let response = self.llm.completions(&request).await?;

        if response.choices.is_empty() {
            anyhow::bail!("LLM não retornou resposta para intervenção");
        }

        let intervention = response.choices[0].text.trim().to_string();
        info!("METACOG: Intervenção gerada ({} caracteres)", intervention.len());

        Ok(intervention)
    }
}

impl Default for MetacognitiveReflector {
    fn default() -> Self {
        Self::new()
    }
}

