//! Bias Detector – Detecta padrões patológicos de pensamento
//!
//! Usa análise de embeddings e clustering para identificar vieses cognitivos

use beagle_llm::embedding::EmbeddingClient;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{info, warn};

#[derive(Debug)]
pub struct BiasDetector {
    embedding: EmbeddingClient,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BiasReport {
    pub dominant_bias: BiasType,
    pub severity: f64, // 0.0 a 1.0
    pub detected_patterns: Vec<String>,
    pub confidence: f64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum BiasType {
    ConfirmationBias,
    AnchoringBias,
    AvailabilityHeuristic,
    RecencyBias,
    RepetitionLoop,
    None,
}

impl BiasDetector {
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

    /// Analisa o trace de pensamento para detectar vieses
    pub async fn analyze(&self, trace: &str) -> anyhow::Result<BiasReport> {
        info!(
            "BiasDetector: analisando trace de {} caracteres",
            trace.len()
        );

        // 1. Detecta repetição de padrões (ruminação)
        let repetition_score = self.detect_repetition(trace);

        // 2. Detecta viés de confirmação (busca apenas evidências que confirmam)
        let confirmation_score = self.detect_confirmation_bias(trace);

        // 3. Detecta anchoring (fixação em primeira hipótese)
        let anchoring_score = self.detect_anchoring(trace);

        // 4. Detecta recency bias (foco excessivo em informações recentes)
        let recency_score = self.detect_recency_bias(trace);

        // Determina bias dominante e severidade
        let mut scores = vec![
            (BiasType::RepetitionLoop, repetition_score),
            (BiasType::ConfirmationBias, confirmation_score),
            (BiasType::AnchoringBias, anchoring_score),
            (BiasType::RecencyBias, recency_score),
        ];

        scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

        let (dominant_bias, max_severity) = scores[0].clone();
        let confidence = if max_severity > 0.5 { 0.8 } else { 0.5 };

        let detected_patterns = self.extract_patterns(trace, &dominant_bias);

        if max_severity > 0.7 {
            warn!(
                "BiasDetector: {} detectado com severidade {:.2}",
                format!("{:?}", dominant_bias),
                max_severity
            );
        }

        Ok(BiasReport {
            dominant_bias: if max_severity > 0.3 {
                dominant_bias
            } else {
                BiasType::None
            },
            severity: max_severity,
            detected_patterns,
            confidence,
        })
    }

    fn detect_repetition(&self, trace: &str) -> f64 {
        // Divide em sentenças e verifica repetição de palavras-chave
        let sentences: Vec<&str> = trace
            .split(&['.', '!', '?', '\n'][..])
            .filter(|s| s.trim().len() > 20)
            .collect();

        if sentences.len() < 3 {
            return 0.0;
        }

        let mut word_freq: HashMap<String, usize> = HashMap::new();
        for sentence in &sentences {
            for word in sentence.split_whitespace() {
                let word_lower = word.to_lowercase();
                if word_lower.len() > 4 {
                    *word_freq.entry(word_lower).or_insert(0) += 1;
                }
            }
        }

        // Calcula diversidade: palavras únicas / total
        let total_words: usize = word_freq.values().sum();
        let unique_words = word_freq.len();
        let diversity = if total_words > 0 {
            unique_words as f64 / total_words as f64
        } else {
            1.0
        };

        // Baixa diversidade = alta repetição
        (1.0 - diversity).min(1.0)
    }

    fn detect_confirmation_bias(&self, trace: &str) -> f64 {
        // Procura por padrões de confirmação: "confirma", "valida", "prova", "demonstra"
        let confirmation_words = [
            "confirma",
            "confirms",
            "valida",
            "validates",
            "prova",
            "proves",
            "demonstra",
            "demonstrates",
            "evidência",
            "evidence",
            "suporta",
            "supports",
        ];

        let trace_lower = trace.to_lowercase();
        let confirmation_count: usize = confirmation_words
            .iter()
            .map(|word| trace_lower.matches(word).count())
            .sum();

        // Procura por palavras de contradição (ausência indica viés)
        let contradiction_words = [
            "contradiz",
            "contradicts",
            "refuta",
            "refutes",
            "inconsistente",
            "inconsistent",
            "oposto",
            "opposite",
            "nega",
            "denies",
        ];

        let contradiction_count: usize = contradiction_words
            .iter()
            .map(|word| trace_lower.matches(word).count())
            .sum();

        // Alta confirmação + baixa contradição = viés de confirmação
        let total_claims = confirmation_count + contradiction_count;
        if total_claims == 0 {
            return 0.0;
        }

        let confirmation_ratio = confirmation_count as f64 / total_claims as f64;
        if confirmation_ratio > 0.8 {
            confirmation_ratio * 0.9 // Penaliza excesso de confirmação
        } else {
            0.0
        }
    }

    fn detect_anchoring(&self, trace: &str) -> f64 {
        // Detecta se o sistema fica preso na primeira hipótese/abordagem mencionada
        let sentences: Vec<&str> = trace
            .split(&['.', '!', '?', '\n'][..])
            .filter(|s| s.trim().len() > 10)
            .collect();

        if sentences.len() < 2 {
            return 0.0;
        }

        // Extrai palavras-chave da primeira sentença
        let first_sentence = sentences[0].to_lowercase();
        let first_keywords: Vec<&str> = first_sentence
            .split_whitespace()
            .filter(|w| w.len() > 4)
            .collect();

        // Verifica quantas vezes essas palavras aparecem nas sentenças subsequentes
        let mut anchor_count = 0;
        for sentence in sentences.iter().skip(1) {
            let sentence_lower = sentence.to_lowercase();
            for keyword in &first_keywords {
                if sentence_lower.contains(keyword) {
                    anchor_count += 1;
                    break;
                }
            }
        }

        // Alta referência à primeira sentença = anchoring
        let anchor_ratio = anchor_count as f64 / (sentences.len() - 1) as f64;
        if anchor_ratio > 0.7 {
            anchor_ratio
        } else {
            0.0
        }
    }

    fn detect_recency_bias(&self, trace: &str) -> f64 {
        // Detecta se há foco excessivo em informações mencionadas no final do trace
        let sentences: Vec<&str> = trace
            .split(&['.', '!', '?', '\n'][..])
            .filter(|s| s.trim().len() > 10)
            .collect();

        if sentences.len() < 3 {
            return 0.0;
        }

        // Extrai palavras-chave das últimas 30% das sentenças
        let recent_start = (sentences.len() as f64 * 0.7) as usize;
        let recent_sentences: Vec<&str> = sentences.iter().skip(recent_start).cloned().collect();

        let recent_keywords: Vec<String> = recent_sentences
            .iter()
            .flat_map(|s| s.split_whitespace())
            .filter(|w| w.len() > 4)
            .map(|w| w.to_lowercase())
            .collect();

        // Verifica quantas vezes essas palavras aparecem no trace todo
        let trace_lower = trace.to_lowercase();
        let recent_mentions: usize = recent_keywords
            .iter()
            .map(|kw| trace_lower.matches(kw).count())
            .sum();

        // Se palavras recentes dominam o trace = recency bias
        let total_words = trace.split_whitespace().count();
        if total_words == 0 {
            return 0.0;
        }

        let recency_ratio = recent_mentions as f64 / total_words as f64;
        if recency_ratio > 0.4 {
            recency_ratio.min(0.9)
        } else {
            0.0
        }
    }

    fn extract_patterns(&self, trace: &str, bias_type: &BiasType) -> Vec<String> {
        let mut patterns = Vec::new();

        match bias_type {
            BiasType::RepetitionLoop => {
                // Extrai palavras mais repetidas
                let mut word_freq: HashMap<String, usize> = HashMap::new();
                for word in trace.split_whitespace() {
                    let word_lower = word.to_lowercase();
                    if word_lower.len() > 4 {
                        *word_freq.entry(word_lower).or_insert(0) += 1;
                    }
                }

                let mut sorted: Vec<_> = word_freq.into_iter().collect();
                sorted.sort_by(|a, b| b.1.cmp(&a.1));

                for (word, count) in sorted.into_iter().take(3) {
                    if count > 3 {
                        patterns.push(format!("Palavra '{}' repetida {} vezes", word, count));
                    }
                }
            }
            BiasType::ConfirmationBias => {
                patterns.push("Alta frequência de palavras de confirmação".to_string());
                patterns.push("Ausência de contradições ou refutações".to_string());
            }
            BiasType::AnchoringBias => {
                patterns.push("Referência excessiva à primeira hipótese".to_string());
            }
            BiasType::RecencyBias => {
                patterns.push("Foco desproporcional em informações recentes".to_string());
            }
            _ => {}
        }

        patterns
    }
}

impl Default for BiasDetector {
    fn default() -> Self {
        Self::new()
    }
}
