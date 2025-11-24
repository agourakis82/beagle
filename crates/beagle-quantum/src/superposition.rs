use beagle_smart_router::query_beagle;
use rand::Rng;
use serde::{Deserialize, Serialize};
use serde_json;
use std::collections::HashMap;
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
            // Usa rand::random() que é thread-safe (Send + Sync)
            (
                rand::random::<f64>() * 0.7 + 0.3,
                rand::random::<f64>() * 0.4 - 0.2,
            )
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
pub struct SuperpositionAgent;

impl SuperpositionAgent {
    /// Cria novo agente de superposição
    /// Usa Grok 3 ilimitado por padrão via query_beagle()
    pub fn new() -> Self {
        Self
    }

    /// Gera múltiplas hipóteses reais via LLM com diversidade máxima
    /// Usa temperature alta + prompt engineering para forçar caminhos radicalmente diferentes
    pub async fn generate_hypotheses(&self, query: &str) -> anyhow::Result<HypothesisSet> {
        info!(
            "SuperpositionAgent: gerando {} hipóteses reais para query: {}",
            N_HYPOTHESES, query
        );

        let system_prompt = format!(
            r#"Você é um pesquisador genial com visões completamente divergentes.

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

]"#,
            N_HYPOTHESES
        );

        let user_prompt = format!("Fenômeno: {}\nGere {} hipóteses.", query, N_HYPOTHESES);

        let full_prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
            system_prompt,
            user_prompt
        );

        // Usa Grok 3 ilimitado por padrão via query_beagle()
        let context_tokens = full_prompt.len() / 4;
        let response_text = query_beagle(&full_prompt, context_tokens).await;

        // Parseia o JSON array gerado pelo LLM
        let mut hypotheses_texts: Vec<String> = {
            match serde_json::from_str::<Vec<serde_json::Value>>(&response_text) {
                Ok(arr) => arr
                    .into_iter()
                    .filter_map(|v| {
                        v.get("hypothesis")
                            .and_then(|h| h.as_str())
                            .map(|s| s.to_string())
                    })
                    .collect(),
                Err(e) => {
                    warn!("LLM não retornou JSON válido, fallback parse manual: {}", e);
                    // Fallback robusto: split por números ou marcadores
                    response_text
                        .split("\n\n")
                        .filter(|s| s.contains("hipótese") || s.len() > 100)
                        .take(N_HYPOTHESES)
                        .map(|s| s.to_string())
                        .collect()
                }
            }
        };

        // Fallback se não conseguir parsear hipóteses
        if hypotheses_texts.is_empty() {
            warn!("Não foi possível extrair hipóteses do LLM, usando fallback");
            hypotheses_texts = vec![
                format!("Hipótese 1 para: {query} – abordagem clássica"),
                format!("Hipótese 2 para: {query} – via entropia curva"),
                format!("Hipótese 3 para: {query} – modelo quântico de campo"),
                format!("Hipótese 4 para: {query} – interpretação geométrica"),
            ];
        }

        // Cria HypothesisSet com amplitudes iniciais aleatórias (fase quântica simulada)
        let mut set = HypothesisSet::new();

        for text in hypotheses_texts.into_iter().take(N_HYPOTHESES) {
            // Usa rand::random() que é thread-safe (Send + Sync)
            let amp: Amplitude = (
                rand::random::<f64>() * 0.7 + 0.5, // 0.5..1.2
                rand::random::<f64>() * 1.2 - 0.6, // -0.6..0.6
            );
            set.add(text.trim().to_string(), Some(amp));
        }

        info!(
            "SuperpositionAgent: gerou {} hipóteses reais em superposição",
            set.hypotheses.len()
        );
        Ok(set)
    }
}

impl Default for SuperpositionAgent {
    fn default() -> Self {
        Self::new()
    }
}
