use rand::Rng;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use beagle_llm::vllm::{VllmClient, VllmCompletionRequest, SamplingParams};
use serde_json;
use tracing::{info, warn};

pub type Amplitude = (f64, f64); // (real, imaginary) → clássico simulado

const DIVERSITY_TEMPERATURE: f64 = 1.3;
const TOP_P: f64 = 0.95;
const MAX_TOKENS: u32 = 512;
const N_HYPOTHESES: usize = 6; // padrão – pode ser configurável

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hypothesis {
    pub content: String,
    pub amplitude: Amplitude,
    pub confidence: f64,
    pub metadata: HashMap<String, String>,
}

impl Hypothesis {
    pub fn probability(&self) -> f64 {
        let (re, im) = self.amplitude;
        re.powi(2) + im.powi(2)
    }

    pub fn normalize_probability(&mut self, total_prob: f64) {
        self.confidence = self.probability() / total_prob;
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HypothesisSet {
    pub hypotheses: Vec<Hypothesis>,
    #[serde(default)]
    total_prob: f64,
}

impl HypothesisSet {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add(&mut self, content: String, initial_amp: Option<Amplitude>) {
        let amp = initial_amp.unwrap_or({
            let mut rng = rand::thread_rng();
            (rng.gen_range(0.3..1.0), rng.gen_range(-0.2..0.2))
        });
        let h = Hypothesis {
            content,
            amplitude: amp,
            confidence: 0.0,
            metadata: HashMap::new(),
        };
        self.hypotheses.push(h);
        self.recalculate_total();
    }

    pub fn recalculate_total(&mut self) {
        self.total_prob = self.hypotheses.iter().map(|h| h.probability()).sum();
        for h in &mut self.hypotheses {
            h.normalize_probability(self.total_prob);
        }
    }

    pub fn best(&self) -> &Hypothesis {
        self.hypotheses
            .iter()
            .max_by(|a, b| a.confidence.partial_cmp(&b.confidence).unwrap())
            .unwrap()
    }

    pub fn is_coherent(&self, threshold: f64) -> bool {
        self.best().confidence > threshold
    }
}

#[derive(Debug)]
pub struct SuperpositionAgent {
    llm: VllmClient,
}

impl SuperpositionAgent {
    pub fn new() -> Self {
        let llm = VllmClient::new("http://t560.local:8000/v1");
        Self { llm }
    }

    pub fn with_url(url: impl Into<String>) -> Self {
        let llm = VllmClient::new(url);
        Self { llm }
    }

    /// Gera múltiplas hipóteses reais via LLM com diversidade máxima
    /// Usa temperature alta + prompt engineering para forçar caminhos radicalmente diferentes
    pub async fn generate_hypotheses(&self, query: &str) -> anyhow::Result<HypothesisSet> {
        info!("SuperpositionAgent: gerando {} hipóteses reais para query: {}", N_HYPOTHESES, query);

        let system_prompt = format!(r#"Você é um pesquisador genial com visões completamente divergentes.

Gere EXATAMENTE {} hipóteses científicas fundamentalmente diferentes (abordagens incompatíveis entre si) para explicar o fenômeno.

Cada hipótese deve ser:

• Radicalmente distinta das outras (ex: uma clássica, uma quântica, uma geométrica, uma biológica, uma informacional, uma emergente)

• 3-5 parágrafos curtos

• Com justificativa científica forte

• Sem introdução ou conclusão – só a hipótese pura



Formato exato (JSON array, nada mais):

[

  {{"hypothesis": "texto completo da hipótese 1"}},

  {{"hypothesis": "texto completo da hipótese 2"}},

  ...

]"#, N_HYPOTHESES);

        let user_prompt = format!("Fenômeno: {}\nGere {} hipóteses.", query, N_HYPOTHESES);

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        let sampling = SamplingParams {
            temperature: DIVERSITY_TEMPERATURE,
            top_p: TOP_P,
            max_tokens: MAX_TOKENS,
            n: N_HYPOTHESES as u32,
            stop: None,
            frequency_penalty: 1.2,
        };

        let request = VllmCompletionRequest {
            model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
            prompt: full_prompt,
            sampling_params: sampling,
        };

        let response = self.llm.completions(&request).await?;

        // Parseia o JSON array gerado pelo LLM
        let hypotheses_texts: Vec<String> = if !response.choices.is_empty() {
            match serde_json::from_str::<Vec<serde_json::Value>>(&response.choices[0].text) {
                Ok(arr) => {
                    arr.into_iter()
                        .filter_map(|v| {
                            v.get("hypothesis")
                                .and_then(|h| h.as_str())
                                .map(|s| s.to_string())
                        })
                        .collect()
                }
                Err(e) => {
                    warn!("LLM não retornou JSON válido, fallback parse manual: {}", e);
                    // Fallback robusto: split por números ou marcadores
                    response.choices[0]
                        .text
                        .split("\n\n")
                        .filter(|s| s.contains("hipótese") || s.len() > 100)
                        .take(N_HYPOTHESES)
                        .map(|s| s.to_string())
                        .collect()
                }
            }
        } else {
            warn!("vLLM retornou choices vazio, usando fallback");
            vec![
                format!("Hipótese 1 para: {query} – abordagem clássica"),
                format!("Hipótese 2 para: {query} – via entropia curva"),
                format!("Hipótese 3 para: {query} – modelo quântico de campo"),
                format!("Hipótese 4 para: {query} – interpretação geométrica"),
            ]
        };

        // Cria HypothesisSet com amplitudes iniciais aleatórias (fase quântica simulada)
        let mut set = HypothesisSet::new();
        let mut rng = rand::thread_rng();

        for text in hypotheses_texts.into_iter().take(N_HYPOTHESES) {
            let amp: Amplitude = (
                rng.gen_range(0.5..1.2),
                rng.gen_range(-0.6..0.6),
            );
            set.add(text.trim().to_string(), Some(amp));
        }

        info!("SuperpositionAgent: gerou {} hipóteses reais em superposição", set.hypotheses.len());
        Ok(set)
    }
}

impl Default for SuperpositionAgent {
    fn default() -> Self {
        Self::new()
    }
}

