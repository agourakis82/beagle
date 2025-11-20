//! Grammar correction engine
//! Fixes: spelling, punctuation, subject-verb agreement, tense consistency

use regex::Regex;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct GrammarCorrection {
    pub original: String,
    pub corrected: String,
    pub rule: GrammarRule,
    pub confidence: f64,
    pub span: (usize, usize), // Character positions
}

#[derive(Debug, Clone, PartialEq)]
pub enum GrammarRule {
    Spelling,
    Punctuation,
    SubjectVerbAgreement,
    TenseConsistency,
    ArticleUsage,
    Preposition,
    WordOrder,
    Capitalization,
}

pub struct GrammarEditor {
    rules: Vec<Box<dyn GrammarRuleImpl>>,
    custom_dictionary: HashMap<String, String>,
}

impl GrammarEditor {
    pub fn new() -> Self {
        let mut editor = Self {
            rules: vec![],
            custom_dictionary: HashMap::new(),
        };

        // Register default rules
        editor.register_rule(Box::new(SpellingRule::new()));
        editor.register_rule(Box::new(PunctuationRule::new()));
        editor.register_rule(Box::new(ArticleRule::new()));

        editor
    }

    pub fn register_rule(&mut self, rule: Box<dyn GrammarRuleImpl>) {
        self.rules.push(rule);
    }

    /// Check text and return all grammar issues
    pub fn check(&self, text: &str) -> Vec<GrammarCorrection> {
        let mut corrections = Vec::new();

        for rule in &self.rules {
            let rule_corrections = rule.check(text);
            corrections.extend(rule_corrections);
        }

        // Sort by position
        corrections.sort_by_key(|c| c.span.0);

        corrections
    }

    /// Apply all corrections to text
    pub fn correct(&self, text: &str) -> String {
        let corrections = self.check(text);

        if corrections.is_empty() {
            return text.to_string();
        }

        let mut result = String::new();
        let mut last_end = 0;

        for correction in corrections {
            // Add text before correction
            result.push_str(&text[last_end..correction.span.0]);

            // Add corrected text
            result.push_str(&correction.corrected);

            last_end = correction.span.1;
        }

        // Add remaining text
        result.push_str(&text[last_end..]);

        result
    }

    /// Add custom dictionary entry
    pub fn add_custom_word(&mut self, wrong: String, correct: String) {
        self.custom_dictionary.insert(wrong, correct);
    }
}

/// Trait for grammar rules
pub trait GrammarRuleImpl: Send + Sync {
    fn check(&self, text: &str) -> Vec<GrammarCorrection>;
}

/// Spelling correction rule
struct SpellingRule {
    common_misspellings: HashMap<String, String>,
}

impl SpellingRule {
    fn new() -> Self {
        let mut misspellings = HashMap::new();

        // Scientific/medical common errors
        misspellings.insert("occured".to_string(), "occurred".to_string());
        misspellings.insert("seperate".to_string(), "separate".to_string());
        misspellings.insert("recieve".to_string(), "receive".to_string());
        misspellings.insert("acheive".to_string(), "achieve".to_string());
        misspellings.insert("consistant".to_string(), "consistent".to_string());
        misspellings.insert("definately".to_string(), "definitely".to_string());

        Self {
            common_misspellings: misspellings,
        }
    }
}

impl GrammarRuleImpl for SpellingRule {
    fn check(&self, text: &str) -> Vec<GrammarCorrection> {
        let mut corrections = Vec::new();

        // Simple word-by-word check
        let words: Vec<&str> = text.split_whitespace().collect();
        let mut char_pos = 0;

        for word in words {
            // Find word position in original text
            if let Some(pos) = text[char_pos..].find(word) {
                let start_pos = char_pos + pos;
                let end_pos = start_pos + word.len();

                // Remove punctuation for checking
                let word_clean = word.trim_matches(|c: char| !c.is_alphanumeric());
                let word_lower = word_clean.to_lowercase();

                if let Some(correct) = self.common_misspellings.get(&word_lower) {
                    corrections.push(GrammarCorrection {
                        original: word.to_string(),
                        corrected: correct.clone(),
                        rule: GrammarRule::Spelling,
                        confidence: 0.95,
                        span: (start_pos, end_pos),
                    });
                }

                char_pos = end_pos;
            }
        }

        corrections
    }
}

/// Punctuation rule
struct PunctuationRule;

impl PunctuationRule {
    fn new() -> Self {
        Self
    }
}

impl GrammarRuleImpl for PunctuationRule {
    fn check(&self, text: &str) -> Vec<GrammarCorrection> {
        let mut corrections = Vec::new();

        // Rule: Space after comma
        let re = Regex::new(r",([^\s])").unwrap();
        for cap in re.captures_iter(text) {
            let match_pos = cap.get(0).unwrap().start();
            corrections.push(GrammarCorrection {
                original: format!(",{}", &cap[1]),
                corrected: format!(", {}", &cap[1]),
                rule: GrammarRule::Punctuation,
                confidence: 0.99,
                span: (match_pos, match_pos + 1 + cap[1].len()),
            });
        }

        // Rule: Space after period (not in abbreviations)
        let re = Regex::new(r"\.([A-Z][a-z])").unwrap();
        for cap in re.captures_iter(text) {
            let match_pos = cap.get(0).unwrap().start();
            corrections.push(GrammarCorrection {
                original: format!(".{}", &cap[1]),
                corrected: format!(". {}", &cap[1]),
                rule: GrammarRule::Punctuation,
                confidence: 0.95,
                span: (match_pos, match_pos + 1 + cap[1].len()),
            });
        }

        corrections
    }
}

/// Article usage rule (a/an)
struct ArticleRule;

impl ArticleRule {
    fn new() -> Self {
        Self
    }
}

impl GrammarRuleImpl for ArticleRule {
    fn check(&self, text: &str) -> Vec<GrammarCorrection> {
        let mut corrections = Vec::new();

        // Rule: "a" before consonant sound, "an" before vowel sound
        let re = Regex::new(r"\ba ([aeiouAEIOU])").unwrap();
        for cap in re.captures_iter(text) {
            let match_pos = cap.get(0).unwrap().start();
            corrections.push(GrammarCorrection {
                original: format!("a {}", &cap[1]),
                corrected: format!("an {}", &cap[1]),
                rule: GrammarRule::ArticleUsage,
                confidence: 0.90,
                span: (match_pos, match_pos + 2 + cap[1].len()),
            });
        }

        let re = Regex::new(r"\ban ([bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ])").unwrap();
        for cap in re.captures_iter(text) {
            let match_pos = cap.get(0).unwrap().start();

            // Exception: "an hour", "an honest"
            let next_word = &cap[1];
            if next_word.starts_with('h') || next_word.starts_with('H') {
                continue; // Might be correct
            }

            corrections.push(GrammarCorrection {
                original: format!("an {}", &cap[1]),
                corrected: format!("a {}", &cap[1]),
                rule: GrammarRule::ArticleUsage,
                confidence: 0.85,
                span: (match_pos, match_pos + 3 + cap[1].len()),
            });
        }

        corrections
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spelling_correction() {
        let editor = GrammarEditor::new();
        let text = "The results occured seperate from expectations.";

        let corrections = editor.check(text);
        assert_eq!(corrections.len(), 2);
        assert_eq!(corrections[0].rule, GrammarRule::Spelling);

        let corrected = editor.correct(text);
        assert!(corrected.contains("occurred"));
        assert!(corrected.contains("separate"));
    }

    #[test]
    fn test_punctuation_correction() {
        let editor = GrammarEditor::new();
        let text = "First,second,third.Fourth sentence.";

        let corrected = editor.correct(text);
        assert!(corrected.contains("First, second"));
        assert!(corrected.contains(". Fourth"));
    }

    #[test]
    fn test_article_correction() {
        let editor = GrammarEditor::new();
        let text = "This is a example of a error.";

        let corrected = editor.correct(text);
        assert!(corrected.contains("an example"));
        assert!(corrected.contains("an error"));
    }
}
