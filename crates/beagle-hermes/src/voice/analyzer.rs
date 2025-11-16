//! Analyze authorial voice patterns from personal corpus

use std::collections::HashMap;
use unicode_segmentation::UnicodeSegmentation;
use regex::Regex;

#[derive(Debug, Clone)]
pub struct VoiceProfile {
    /// Average sentence length (words)
    pub avg_sentence_length: f64,
    
    /// Lexical diversity (unique words / total words)
    pub lexical_diversity: f64,
    
    /// Common sentence structures
    pub sentence_patterns: Vec<SentencePattern>,
    
    /// Preferred vocabulary
    pub vocabulary_fingerprint: HashMap<String, f64>,
    
    /// Punctuation style
    pub punctuation_profile: PunctuationProfile,
    
    /// Paragraph structure
    pub avg_paragraph_length: f64,
    
    /// Transitional phrases
    pub transitions: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct SentencePattern {
    pub pattern: String,  // e.g., "SUBJ VERB ADV"
    pub frequency: f64,
}

#[derive(Debug, Clone)]
pub struct PunctuationProfile {
    pub comma_density: f64,      // commas per sentence
    pub semicolon_usage: f64,
    pub em_dash_usage: f64,
    pub parenthetical_usage: f64,
}

pub struct VoiceAnalyzer {
    corpus: Vec<String>,  // User's papers
}

impl VoiceAnalyzer {
    pub fn new() -> Self {
        Self {
            corpus: Vec::new(),
        }
    }

    /// Add document to personal corpus
    pub fn add_document(&mut self, text: String) {
        self.corpus.push(text);
    }

    /// Analyze corpus and extract voice profile
    pub fn analyze(&self) -> VoiceProfile {
        let all_text = self.corpus.join("\n\n");
        
        // Extract sentences
        let sentences = self.extract_sentences(&all_text);
        
        // Compute metrics
        let avg_sentence_length = self.compute_avg_sentence_length(&sentences);
        let lexical_diversity = self.compute_lexical_diversity(&all_text);
        let vocabulary_fingerprint = self.build_vocabulary_fingerprint(&all_text);
        let punctuation_profile = self.analyze_punctuation(&sentences);
        let avg_paragraph_length = self.compute_avg_paragraph_length(&all_text);
        let transitions = self.extract_transitions(&sentences);
        
        VoiceProfile {
            avg_sentence_length,
            lexical_diversity,
            sentence_patterns: vec![],  // TODO: Implement pattern extraction
            vocabulary_fingerprint,
            punctuation_profile,
            avg_paragraph_length,
            transitions,
        }
    }

    fn extract_sentences(&self, text: &str) -> Vec<String> {
        // Simple sentence splitter (improve with syntactic parser)
        let re = Regex::new(r"[.!?]+\s+").unwrap();
        re.split(text)
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect()
    }

    fn compute_avg_sentence_length(&self, sentences: &[String]) -> f64 {
        if sentences.is_empty() {
            return 0.0;
        }
        
        let total_words: usize = sentences
            .iter()
            .map(|s| s.unicode_words().count())
            .sum();
        
        total_words as f64 / sentences.len() as f64
    }

    fn compute_lexical_diversity(&self, text: &str) -> f64 {
        let words: Vec<&str> = text.unicode_words().collect();
        let total = words.len();
        
        if total == 0 {
            return 0.0;
        }
        
        let mut unique = std::collections::HashSet::new();
        for word in words {
            unique.insert(word.to_lowercase());
        }
        
        unique.len() as f64 / total as f64
    }

    fn build_vocabulary_fingerprint(&self, text: &str) -> HashMap<String, f64> {
        let mut freq: HashMap<String, usize> = HashMap::new();
        let words: Vec<&str> = text.unicode_words().collect();
        let total = words.len();
        
        for word in words {
            let word_lower = word.to_lowercase();
            *freq.entry(word_lower).or_insert(0) += 1;
        }
        
        // Convert to probabilities
        freq.into_iter()
            .map(|(word, count)| (word, count as f64 / total as f64))
            .collect()
    }

    fn analyze_punctuation(&self, sentences: &[String]) -> PunctuationProfile {
        let total_sentences = sentences.len() as f64;
        
        let comma_count: usize = sentences.iter().map(|s| s.matches(',').count()).sum();
        let semicolon_count: usize = sentences.iter().map(|s| s.matches(';').count()).sum();
        let em_dash_count: usize = sentences.iter().map(|s| s.matches('—').count()).sum();
        let paren_count: usize = sentences.iter().map(|s| s.matches('(').count()).sum();
        
        PunctuationProfile {
            comma_density: comma_count as f64 / total_sentences,
            semicolon_usage: semicolon_count as f64 / total_sentences,
            em_dash_usage: em_dash_count as f64 / total_sentences,
            parenthetical_usage: paren_count as f64 / total_sentences,
        }
    }

    fn compute_avg_paragraph_length(&self, text: &str) -> f64 {
        let paragraphs: Vec<&str> = text.split("\n\n").collect();
        let total_sentences: usize = paragraphs
            .iter()
            .map(|p| self.extract_sentences(p).len())
            .sum();
        
        if paragraphs.is_empty() {
            return 0.0;
        }
        
        total_sentences as f64 / paragraphs.len() as f64
    }

    fn extract_transitions(&self, sentences: &[String]) -> Vec<String> {
        // Common academic transitions
        let transition_words = vec![
            "however", "moreover", "furthermore", "consequently",
            "therefore", "thus", "hence", "nevertheless",
            "in contrast", "on the other hand", "in addition",
            "similarly", "likewise", "for example", "for instance",
        ];
        
        let mut found_transitions = Vec::new();
        
        for sentence in sentences {
            let sentence_lower = sentence.to_lowercase();
            for transition in &transition_words {
                if sentence_lower.contains(transition) {
                    found_transitions.push(transition.to_string());
                }
            }
        }
        
        // Return unique transitions
        let mut unique: Vec<String> = found_transitions.into_iter().collect();
        unique.sort();
        unique.dedup();
        unique
    }

    /// Compare two texts for voice similarity (0.0-1.0)
    pub fn voice_similarity(
        &self,
        profile: &VoiceProfile,
        candidate_text: &str,
    ) -> f64 {
        let candidate_sentences = self.extract_sentences(candidate_text);
        let candidate_length = self.compute_avg_sentence_length(&candidate_sentences);
        let candidate_diversity = self.compute_lexical_diversity(candidate_text);
        
        // Compute similarity scores for different features
        let length_sim = if profile.avg_sentence_length > 0.0 {
            1.0 - ((candidate_length - profile.avg_sentence_length).abs() 
                / profile.avg_sentence_length).min(1.0)
        } else {
            0.0
        };
        
        let diversity_sim = if profile.lexical_diversity > 0.0 {
            1.0 - ((candidate_diversity - profile.lexical_diversity).abs()
                / profile.lexical_diversity).min(1.0)
        } else {
            0.0
        };
        
        // Vocabulary overlap
        let candidate_vocab = self.build_vocabulary_fingerprint(candidate_text);
        let vocab_sim = self.compute_vocab_overlap(&profile.vocabulary_fingerprint, &candidate_vocab);
        
        // Weighted average
        length_sim * 0.2 + diversity_sim * 0.2 + vocab_sim * 0.6
    }

    fn compute_vocab_overlap(
        &self,
        vocab1: &HashMap<String, f64>,
        vocab2: &HashMap<String, f64>,
    ) -> f64 {
        let mut overlap = 0.0;
        let mut total_weight = 0.0;
        
        for (word, freq1) in vocab1 {
            if let Some(freq2) = vocab2.get(word) {
                overlap += freq1.min(*freq2);
            }
            total_weight += freq1;
        }
        
        if total_weight == 0.0 {
            0.0
        } else {
            overlap / total_weight
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_voice_analyzer() {
        let mut analyzer = VoiceAnalyzer::new();
        
        analyzer.add_document(
            "This is a test document. It contains multiple sentences with repeated words. \
             The style should be analyzable. This document has many words. \
             Some words appear multiple times in this text.".to_string()
        );
        
        let profile = analyzer.analyze();
        
        assert!(profile.avg_sentence_length > 0.0);
        assert!(profile.lexical_diversity > 0.0);
        assert!(profile.lexical_diversity <= 1.0);  // Can be 1.0 if all words unique
    }

    #[test]
    fn test_voice_similarity() {
        let mut analyzer = VoiceAnalyzer::new();
        
        analyzer.add_document(
            "The results demonstrate significant improvements in the methodology. \
             Moreover, the approach proves robust and reliable. \
             Thus, we conclude with confidence that the findings are valid. \
             The methodology demonstrates substantial enhancements.".to_string()
        );
        
        let profile = analyzer.analyze();
        
        // Similar text (academic style, similar vocabulary)
        let similar = "The findings show substantial enhancements in the approach. \
                       Furthermore, the methodology remains sound and demonstrates reliability. \
                       Therefore, we conclude that the results are valid and significant.";
        let sim = analyzer.voice_similarity(&profile, similar);
        assert!(sim > 0.3, "Similarity should be > 0.3, got {}", sim);
        
        // Dissimilar text (short, informal)
        let dissimilar = "Cool stuff. Works great. Nice job.";
        let dissim = analyzer.voice_similarity(&profile, dissimilar);
        assert!(dissim < sim, "Dissimilar text should score lower");
    }
}

