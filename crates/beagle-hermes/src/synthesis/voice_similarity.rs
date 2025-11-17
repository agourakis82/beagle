//! Voice similarity computation using stylometric analysis

use crate::Result;
use std::collections::HashMap;
use tracing::debug;

pub struct VoiceSimilarityAnalyzer {
    // Stylometric features to track
    feature_weights: HashMap<String, f64>,
}

impl VoiceSimilarityAnalyzer {
    pub fn new() -> Self {
        let mut weights = HashMap::new();
        // Feature weights (sum to 1.0)
        weights.insert("avg_sentence_length".to_string(), 0.15);
        weights.insert("avg_word_length".to_string(), 0.10);
        weights.insert("punctuation_density".to_string(), 0.10);
        weights.insert("transition_word_usage".to_string(), 0.15);
        weights.insert("vocabulary_richness".to_string(), 0.20);
        weights.insert("passive_voice_ratio".to_string(), 0.10);
        weights.insert("citation_frequency".to_string(), 0.10);
        weights.insert("technical_term_density".to_string(), 0.10);

        Self {
            feature_weights: weights,
        }
    }

    /// Compute voice similarity between draft and reference corpus
    pub fn compute_similarity(&self, draft: &str, reference_corpus: &[String]) -> Result<f64> {
        if reference_corpus.is_empty() {
            return Ok(0.5); // Neutral score if no reference
        }

        // Extract features from draft
        let draft_features = self.extract_features(draft);

        // Extract features from reference corpus
        let corpus_text: String = reference_corpus.join(" ");
        let reference_features = self.extract_features(&corpus_text);

        // Compute similarity for each feature
        let mut total_similarity = 0.0;
        let mut total_weight = 0.0;

        for (feature_name, weight) in &self.feature_weights {
            let draft_value = draft_features.get(feature_name).copied().unwrap_or(0.0);
            let reference_value = reference_features.get(feature_name).copied().unwrap_or(0.0);

            // Normalize values to [0, 1] range for comparison
            let similarity = self.feature_similarity(draft_value, reference_value);
            total_similarity += similarity * weight;
            total_weight += weight;
        }

        let final_similarity = if total_weight > 0.0 {
            total_similarity / total_weight
        } else {
            0.5
        };

        debug!(
            "Voice similarity computed: {:.2}%",
            final_similarity * 100.0
        );
        Ok(final_similarity)
    }

    fn extract_features(&self, text: &str) -> HashMap<String, f64> {
        let mut features = HashMap::new();

        // 1. Average sentence length
        let sentences: Vec<&str> = text
            .split(&['.', '!', '?'][..])
            .filter(|s| !s.trim().is_empty())
            .collect();
        let avg_sentence_length = if !sentences.is_empty() {
            sentences
                .iter()
                .map(|s| s.split_whitespace().count())
                .sum::<usize>() as f64
                / sentences.len() as f64
        } else {
            0.0
        };
        features.insert("avg_sentence_length".to_string(), avg_sentence_length);

        // 2. Average word length
        let words: Vec<&str> = text.split_whitespace().collect();
        let avg_word_length = if !words.is_empty() {
            words.iter().map(|w| w.len()).sum::<usize>() as f64 / words.len() as f64
        } else {
            0.0
        };
        features.insert("avg_word_length".to_string(), avg_word_length);

        // 3. Punctuation density
        let punct_chars: usize = text
            .chars()
            .filter(|c| matches!(c, '.' | ',' | ';' | ':' | '!' | '?'))
            .count();
        let punct_density = if !text.is_empty() {
            punct_chars as f64 / text.len() as f64
        } else {
            0.0
        };
        features.insert("punctuation_density".to_string(), punct_density);

        // 4. Transition word usage
        let transition_words = [
            "however",
            "furthermore",
            "moreover",
            "additionally",
            "consequently",
            "therefore",
            "thus",
            "hence",
            "nevertheless",
            "nonetheless",
            "in contrast",
            "on the other hand",
            "similarly",
            "likewise",
            "firstly",
            "secondly",
            "finally",
            "in conclusion",
        ];
        let transition_count = text
            .to_lowercase()
            .split_whitespace()
            .filter(|w| transition_words.contains(w))
            .count();
        let transition_density = if !words.is_empty() {
            transition_count as f64 / words.len() as f64
        } else {
            0.0
        };
        features.insert("transition_word_usage".to_string(), transition_density);

        // 5. Vocabulary richness (unique words / total words)
        let unique_words: std::collections::HashSet<String> =
            words.iter().map(|w| w.to_lowercase()).collect();
        let vocabulary_richness = if !words.is_empty() {
            unique_words.len() as f64 / words.len() as f64
        } else {
            0.0
        };
        features.insert("vocabulary_richness".to_string(), vocabulary_richness);

        // 6. Passive voice ratio (simple heuristic: "is/was/were + past participle")
        let passive_patterns = [" is ", " was ", " were ", " are ", " been "];
        let passive_count = passive_patterns
            .iter()
            .map(|pattern| text.to_lowercase().matches(pattern).count())
            .sum::<usize>();
        let passive_ratio = if !words.is_empty() {
            passive_count as f64 / words.len() as f64
        } else {
            0.0
        };
        features.insert("passive_voice_ratio".to_string(), passive_ratio);

        // 7. Citation frequency
        let citation_count = text.matches('[').count();
        let citation_frequency = if !words.is_empty() {
            citation_count as f64 / words.len() as f64
        } else {
            0.0
        };
        features.insert("citation_frequency".to_string(), citation_frequency);

        // 8. Technical term density (words > 8 chars, excluding common words)
        let common_words: std::collections::HashSet<&str> =
            ["therefore", "furthermore", "nevertheless", "additionally"]
                .into_iter()
                .collect();
        let technical_count = words
            .iter()
            .filter(|w| {
                let lower = w.to_lowercase();
                w.len() > 8 && !common_words.contains(lower.as_str())
            })
            .count();
        let technical_density = if !words.is_empty() {
            technical_count as f64 / words.len() as f64
        } else {
            0.0
        };
        features.insert("technical_term_density".to_string(), technical_density);

        features
    }

    fn feature_similarity(&self, value1: f64, value2: f64) -> f64 {
        if value1 == 0.0 && value2 == 0.0 {
            return 1.0; // Both zero = perfect match
        }

        let max_val = value1.max(value2);
        if max_val == 0.0 {
            return 1.0;
        }

        let diff = (value1 - value2).abs();
        let similarity = 1.0 - (diff / max_val).min(1.0);
        similarity.max(0.0)
    }
}

impl Default for VoiceSimilarityAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}
