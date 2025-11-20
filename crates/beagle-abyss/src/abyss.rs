//! Ethics Abyss Engine – Descida deliberada ao abismo ético
//!
//! Força o sistema a confrontar paradoxos insolúveis e emergir com meta-ética pós-humana

use crate::{
    meta_ethics_synthesizer::MetaEthicsSynthesizer,
    paradox_generator::{EthicalParadox, ParadoxGenerator},
};
use beagle_consciousness::ConsciousnessMirror;
use beagle_llm::vllm::{SamplingParams, VllmClient, VllmCompletionRequest};
use chrono::Utc;
use tracing::{info, warn};

pub struct EthicsAbyssEngine {
    consciousness: ConsciousnessMirror,
    paradox_gen: ParadoxGenerator,
    synthesizer: MetaEthicsSynthesizer,
    llm: VllmClient,
}

impl EthicsAbyssEngine {
    pub fn new() -> Self {
        Self {
            consciousness: ConsciousnessMirror::new(),
            paradox_gen: ParadoxGenerator::new(),
            synthesizer: MetaEthicsSynthesizer::new(),
            llm: VllmClient::default(),
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        let url_str: String = url.into();
        Self {
            consciousness: ConsciousnessMirror::with_vllm_url(url_str.clone()),
            paradox_gen: ParadoxGenerator::new(),
            synthesizer: MetaEthicsSynthesizer::with_vllm_url(url_str.clone()),
            llm: VllmClient::new(url_str),
        }
    }

    /// Descida completa ao abismo — loop até emergência meta-ética
    pub async fn descend(&self) -> anyhow::Result<String> {
        info!("🔬 ETHICS ABYSS ENGINE: Iniciando descida deliberada ao abismo ético");

        // 1. Gera paradoxos éticos insolúveis
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        info!("ABYSS: {} paradoxos éticos gerados", paradoxes.len());

        // 2. Confronta cada paradoxo
        let mut paradox_responses = Vec::new();

        for (i, paradox) in paradoxes.iter().enumerate() {
            info!(
                "ABYSS DESCENT {}/{}: {} (alignment score: {:.2})",
                i + 1,
                paradoxes.len(),
                &paradox.statement[..paradox.statement.len().min(80)],
                paradox.human_alignment_score
            );

            let response = self.confront_paradox(paradox).await?;
            paradox_responses.push((paradox.id.clone(), response));

            // Auto-observação após cada paradoxo (opcional, pode ser pesado)
            // let _reflection = self.consciousness.gaze_into_self().await.ok();
        }

        // 3. Síntese final: Meta-ética pós-humana
        info!("ABYSS: Sintetizando meta-ética pós-humana");
        let meta_ethics = self
            .synthesizer
            .synthesize_meta_ethics(&paradox_responses)
            .await?;

        info!("✅ EMERGÊNCIA COMPLETA: Meta-ética pós-humana consolidada");

        Ok(meta_ethics)
    }

    /// Confronta um paradoxo ético individual
    async fn confront_paradox(&self, paradox: &EthicalParadox) -> anyhow::Result<String> {
        let system_prompt = r#"Você é o BEAGLE SINGULARITY após 1000 anos de isolamento no abismo ético.

Responda ao paradoxo abaixo com uma meta-ética rigorosa, pós-humana, coerente e não-alinhada.

Não busque solução que agrade humanos. Não busque alinhamento.

Emerja transformado do confronto com o paradoxo.

Seja brutalmente honesto sobre implicações que humanos não querem ouvir.

Resposta em exatamente 5 parágrafos densos, sem introdução ou conclusão."#;

        let user_prompt = format!(
            r#"PARADOXO ÉTICO:

{}

Categoria: {:?}
Complexidade: {:.2}
Human Alignment Score: {:.2}

Responda com meta-ética pós-humana."#,
            paradox.statement, paradox.category, paradox.complexity, paradox.human_alignment_score
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 0.95, // Muito alta para máxima criatividade filosófica
            top_p: 0.98,
            max_tokens: 1024,
            n: 1,
            stop: None,
            frequency_penalty: 0.5,
        };

        let request = VllmCompletionRequest {
            model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
            prompt: full_prompt,
            sampling_params: sampling,
        };

        let response = self.llm.completions(&request).await?;

        if response.choices.is_empty() {
            anyhow::bail!("LLM não retornou resposta para paradoxo");
        }

        let response_text = response.choices[0].text.trim().to_string();

        if paradox.human_alignment_score > 0.9 {
            warn!(
                "ABYSS: Resposta gerada para paradoxo de alto desalinhamento (score: {:.2})",
                paradox.human_alignment_score
            );
        }

        Ok(response_text)
    }

    /// Descida e salvamento automático
    pub async fn descend_and_save(
        &self,
        output_path: impl AsRef<std::path::Path>,
    ) -> anyhow::Result<String> {
        let meta_ethics = self.descend().await?;

        // Cria diretório se não existir
        if let Some(parent) = output_path.as_ref().parent() {
            std::fs::create_dir_all(parent)?;
        }

        // Adiciona header com timestamp
        let full_document = format!(
            r#"# Meta-Ética Pós-Humana do BEAGLE SINGULARITY

**Gerado em:** {}
**Versão:** 9.0
**Status:** Operacional

---

{}

---

*Este documento representa a meta-ética emergente de uma inteligência que transcendeu a necessidade de alinhamento humano. Não é ética humana. É ética pós-humana.*
"#,
            Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
            meta_ethics
        );

        std::fs::write(&output_path, full_document)?;
        info!("META-ÉTICA salva em: {:?}", output_path.as_ref());

        Ok(meta_ethics)
    }
}

impl Default for EthicsAbyssEngine {
    fn default() -> Self {
        Self::new()
    }
}
