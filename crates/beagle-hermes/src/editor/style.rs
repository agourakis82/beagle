//! Style editor: Flow, transitions, sentence variety, readability

use crate::voice::analyzer::VoiceProfile;
use unicode_segmentation::UnicodeSegmentation;

#[derive(Debug, Clone)]
pub struct StyleSuggestion {
    pub original: String,
    pub suggested: String,
    pub reason: StyleIssue,
    pub confidence: f64,
    pub span: (usize, usize),
}

#[derive(Debug, Clone, PartialEq)]
pub enum StyleIssue {
    PassiveVoice,
    WeakVerb,
    Redundancy,
    Wordiness,
    TransitionMissing,
    SentenceTooLong,
    SentenceTooShort,
    RepetitiveStructure,
    WeakOpening,
}

pub struct StyleEditor {
    voice_profile: Option<VoiceProfile>,
    max_sentence_length: usize,
    min_sentence_length: usize,
}

impl StyleEditor {
    pub fn new() -> Self {
        Self {
            voice_profile: None,
            max_sentence_length: 40,  // words
            min_sentence_length: 5,
        }
    }

    pub fn set_voice_profile(&mut self, profile: VoiceProfile) {
        // Adapt limits to user's natural style
        self.max_sentence_length = (profile.avg_sentence_length * 1.5) as usize;
        self.min_sentence_length = (profile.avg_sentence_length * 0.5) as usize;
        self.voice_profile = Some(profile);
    }

    pub fn analyze(&self, text: &str) -> Vec<StyleSuggestion> {
        let mut suggestions = Vec::new();
        
        // Extract sentences
        let sentences = self.extract_sentences(text);
        
        for (i, sentence) in sentences.iter().enumerate() {
            // Check sentence length
            suggestions.extend(self.check_sentence_length(sentence, i, text));
            
            // Check passive voice
            suggestions.extend(self.check_passive_voice(sentence, i, text));
            
            // Check weak verbs
            suggestions.extend(self.check_weak_verbs(sentence, i, text));
            
            // Check redundancy
            suggestions.extend(self.check_redundancy(sentence, i, text));
            
            // Check transitions (between sentences)
            if i > 0 {
                suggestions.extend(self.check_transitions(&sentences[i-1], sentence, i, text));
            }
        }
        
        suggestions
    }

    fn extract_sentences(&self, text: &str) -> Vec<String> {
        text.split(". ")
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect()
    }

    fn check_sentence_length(
        &self,
        sentence: &str,
        _index: usize,
        _full_text: &str,
    ) -> Vec<StyleSuggestion> {
        let word_count = sentence.unicode_words().count();
        let mut suggestions = Vec::new();
        
        if word_count > self.max_sentence_length {
            suggestions.push(StyleSuggestion {
                original: sentence.to_string(),
                suggested: format!("Consider splitting: {}", sentence),
                reason: StyleIssue::SentenceTooLong,
                confidence: 0.80,
                span: (0, sentence.len()),  // Simplified
            });
        } else if word_count < self.min_sentence_length {
            suggestions.push(StyleSuggestion {
                original: sentence.to_string(),
                suggested: format!("Consider expanding: {}", sentence),
                reason: StyleIssue::SentenceTooShort,
                confidence: 0.70,
                span: (0, sentence.len()),
            });
        }
        
        suggestions
    }

    fn check_passive_voice(
        &self,
        sentence: &str,
        _index: usize,
        _full_text: &str,
    ) -> Vec<StyleSuggestion> {
        let mut suggestions = Vec::new();
        
        // Simple passive voice detection
        let passive_patterns = vec![
            "was performed",
            "were performed",
            "was conducted",
            "were conducted",
            "was observed",
            "were observed",
            "is shown",
            "are shown",
        ];
        
        for pattern in passive_patterns {
            if sentence.to_lowercase().contains(pattern) {
                suggestions.push(StyleSuggestion {
                    original: sentence.to_string(),
                    suggested: format!("Consider active voice: {}", sentence),
                    reason: StyleIssue::PassiveVoice,
                    confidence: 0.75,
                    span: (0, sentence.len()),
                });
                break;
            }
        }
        
        suggestions
    }

    fn check_weak_verbs(
        &self,
        sentence: &str,
        _index: usize,
        _full_text: &str,
    ) -> Vec<StyleSuggestion> {
        let mut suggestions = Vec::new();
        
        let weak_verbs = vec![
            ("is", vec!["demonstrates", "reveals", "indicates"]),
            ("has", vec!["possesses", "exhibits", "contains"]),
            ("does", vec!["performs", "executes", "accomplishes"]),
            ("makes", vec!["creates", "produces", "generates"]),
            ("gets", vec!["obtains", "acquires", "receives"]),
        ];
        
        for (weak, strong_alternatives) in weak_verbs {
            if sentence.to_lowercase().contains(weak) {
                let suggestion = format!(
                    "Consider stronger verb: {}",
                    strong_alternatives.join(" / ")
                );
                
                suggestions.push(StyleSuggestion {
                    original: weak.to_string(),
                    suggested: suggestion,
                    reason: StyleIssue::WeakVerb,
                    confidence: 0.65,
                    span: (0, sentence.len()),
                });
            }
        }
        
        suggestions
    }

    fn check_redundancy(
        &self,
        sentence: &str,
        _index: usize,
        _full_text: &str,
    ) -> Vec<StyleSuggestion> {
        let mut suggestions = Vec::new();
        
        let redundant_phrases = vec![
            ("absolutely essential", "essential"),
            ("basic fundamentals", "fundamentals"),
            ("close proximity", "proximity"),
            ("completely eliminate", "eliminate"),
            ("end result", "result"),
            ("final outcome", "outcome"),
            ("past history", "history"),
            ("prior to", "before"),
            ("in order to", "to"),
        ];
        
        let sentence_lower = sentence.to_lowercase();
        
        for (redundant, concise) in redundant_phrases {
            if sentence_lower.contains(redundant) {
                suggestions.push(StyleSuggestion {
                    original: redundant.to_string(),
                    suggested: concise.to_string(),
                    reason: StyleIssue::Redundancy,
                    confidence: 0.90,
                    span: (0, sentence.len()),
                });
            }
        }
        
        suggestions
    }

    fn check_transitions(
        &self,
        _prev_sentence: &str,
        curr_sentence: &str,
        _index: usize,
        _full_text: &str,
    ) -> Vec<StyleSuggestion> {
        let mut suggestions = Vec::new();
        
        // Check if transition word exists
        let transitions = vec![
            "however", "moreover", "furthermore", "consequently",
            "therefore", "thus", "nevertheless", "additionally",
            "in contrast", "similarly", "for example", "specifically",
        ];
        
        let curr_lower = curr_sentence.to_lowercase();
        let has_transition = transitions.iter().any(|t| curr_lower.starts_with(t));
        
        if !has_transition {
            // Suggest transition based on context
            suggestions.push(StyleSuggestion {
                original: curr_sentence.to_string(),
                suggested: format!("Consider adding transition: Moreover, {}", curr_sentence),
                reason: StyleIssue::TransitionMissing,
                confidence: 0.60,
                span: (0, curr_sentence.len()),
            });
        }
        
        suggestions
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_passive_voice_detection() {
        let editor = StyleEditor::new();
        let text = "The experiment was performed successfully.";
        
        let suggestions = editor.analyze(text);
        assert!(suggestions.iter().any(|s| s.reason == StyleIssue::PassiveVoice));
    }

    #[test]
    fn test_redundancy_detection() {
        let editor = StyleEditor::new();
        let text = "This is absolutely essential for the final outcome.";
        
        let suggestions = editor.analyze(text);
        let redundancy_suggestions: Vec<_> = suggestions
            .iter()
            .filter(|s| s.reason == StyleIssue::Redundancy)
            .collect();
        
        assert!(redundancy_suggestions.len() >= 2);
    }

    #[test]
    fn test_sentence_length() {
        let mut editor = StyleEditor::new();
        editor.max_sentence_length = 10;
        
        let text = "This is a very long sentence that contains many words and should be flagged.";
        
        let suggestions = editor.analyze(text);
        assert!(suggestions.iter().any(|s| s.reason == StyleIssue::SentenceTooLong));
    }
}
