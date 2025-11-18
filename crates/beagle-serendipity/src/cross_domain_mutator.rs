//! Cross-Domain Mutator – Contaminação deliberada entre domínios distantes
//!
//! Gera híbridos inesperados através de mutação cruzada entre áreas científicas incompatíveis

use beagle_quantum::HypothesisSet;
use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use rand::seq::SliceRandom;
use tracing::info;

const DOMINIOS_DISTANTES: [&str; 8] = [
    "teoria das categorias",
    "termodinâmica de não-equilíbrio",
    "neurociência da consciência",
    "geometria não-comutativa",
    "biologia sintética",
    "teoria da informação quântica",
    "filosofia da mente fenomenologia",
    "economia complexa sistemas adaptativos",
];

#[derive(Debug)]
pub struct CrossDomainMutator {
    llm: VllmClient,
}

impl CrossDomainMutator {
    pub fn new() -> Self {
        Self {
            llm: VllmClient::default(),
        }
    }

    pub fn with_vllm_url(url: impl Into<String>) -> Self {
        Self {
            llm: VllmClient::new(url),
        }
    }

    /// Realiza polinização cruzada entre o contexto atual e um domínio distante
    pub async fn cross_pollinate(
        &self,
        current_set: &HypothesisSet,
        context: &str,
    ) -> anyhow::Result<Vec<String>> {
        let mut rng = rand::thread_rng();
        let domain = DOMINIOS_DISTANTES.choose(&mut rng)
            .ok_or_else(|| anyhow::anyhow!("Nenhum domínio disponível"))?;

        info!("CROSS-DOMAIN: Contaminando com '{}'", domain);

        // Extrai conceitos-chave do estado quântico atual
        let current_concepts: Vec<String> = current_set
            .hypotheses
            .iter()
            .take(3)
            .map(|h| {
                // Extrai primeiras palavras-chave de cada hipótese
                h.content
                    .split_whitespace()
                    .filter(|w| w.len() > 4)
                    .take(5)
                    .collect::<Vec<_>>()
                    .join(" ")
            })
            .collect();

        let system_prompt = r#"Você é um gênio transdisciplinar insano especializado em contaminação violenta de conceitos.

Sua função é pegar contextos de pesquisa e contaminá-los deliberadamente com conceitos de domínios completamente distantes, gerando híbridos inesperados mas potencialmente revolucionários.

Seja radical, criativo e científico. Não tenha medo de quebrar fronteiras disciplinares."#;

        let user_prompt = format!(
            r#"CONTEXTO DE PESQUISA ATUAL:
{}

CONCEITOS-CHAVE EXTRAÍDOS:
{}

DOMÍNIO DISTANTE PARA CONTAMINAÇÃO:
{}

Gere EXATAMENTE 5 ideias híbridas completamente inesperadas, mas potencialmente revolucionárias.

Cada ideia deve:
1. Combinar elementos do contexto atual com conceitos do domínio distante
2. Ser cientificamente plausível (não absurda)
3. Ter potencial de descoberta real
4. Ser radicalmente nova

Formato: lista numerada, uma ideia por linha, sem introdução ou conclusão."#,
            context,
            current_concepts.join(", "),
            domain
        );

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: 1.2, // Alta temperatura para máxima criatividade
            top_p: 0.95,
            max_tokens: 512,
            n: 1,
            stop: None,
            frequency_penalty: 1.5, // Penaliza repetição
        };

        let request = VllmCompletionRequest {
            model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
            prompt: full_prompt,
            sampling_params: sampling,
        };

        let response = self.llm.completions(&request).await?;

        if response.choices.is_empty() {
            anyhow::bail!("LLM não retornou resposta para mutação cruzada");
        }

        // Parseia a resposta em lista de ideias
        let ideas_text = response.choices[0].text.trim();
        let ideas: Vec<String> = ideas_text
            .lines()
            .filter_map(|line| {
                let line = line.trim();
                // Remove numeração (1., 2., etc.)
                let cleaned = line
                    .chars()
                    .skip_while(|c| c.is_ascii_digit() || *c == '.' || *c == ' ' || *c == '-')
                    .collect::<String>()
                    .trim()
                    .to_string();
                if cleaned.len() > 20 {
                    Some(cleaned)
                } else {
                    None
                }
            })
            .take(5)
            .collect();

        info!("CROSS-DOMAIN: Geradas {} ideias híbridas", ideas.len());
        Ok(ideas)
    }
}

impl Default for CrossDomainMutator {
    fn default() -> Self {
        Self::new()
    }
}

