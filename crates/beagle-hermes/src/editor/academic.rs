//! Academic terminology and rigor checks

use crate::error::Result;
use regex::Regex;
use std::collections::HashSet;
use tracing::warn;

pub struct AcademicEditor {
    domain_terms: HashSet<String>,
    informal_words: HashSet<String>,
    weak_phrases: HashSet<String>,
}

impl AcademicEditor {
    pub fn new() -> Self {
        let mut domain_terms = HashSet::new();
        domain_terms.insert("pharmacokinetic".to_string());
        domain_terms.insert("pharmacodynamic".to_string());
        domain_terms.insert("biomaterial".to_string());
        domain_terms.insert("scaffold".to_string());
        domain_terms.insert("entropy".to_string());
        domain_terms.insert("neural".to_string());
        domain_terms.insert("synaptic".to_string());
        domain_terms.insert("neurotransmitter".to_string());
        domain_terms.insert("clearance".to_string());
        domain_terms.insert("bioavailability".to_string());

        let mut informal_words = HashSet::new();
        informal_words.insert("gonna".to_string());
        informal_words.insert("wanna".to_string());
        informal_words.insert("gotta".to_string());
        informal_words.insert("yeah".to_string());
        informal_words.insert("cool".to_string());
        informal_words.insert("awesome".to_string());

        let mut weak_phrases = HashSet::new();
        weak_phrases.insert("i think".to_string());
        weak_phrases.insert("i believe".to_string());
        weak_phrases.insert("in my opinion".to_string());
        weak_phrases.insert("it seems".to_string());
        weak_phrases.insert("maybe".to_string());
        weak_phrases.insert("perhaps".to_string());
        weak_phrases.insert("kind of".to_string());
        weak_phrases.insert("sort of".to_string());

        Self {
            domain_terms,
            informal_words,
            weak_phrases,
        }
    }

    /// Check academic rigor
    pub fn check_rigor(&self, text: &str) -> Result<AcademicRigorReport> {
        let mut issues = Vec::new();
        let mut suggestions = Vec::new();

        let text_lower = text.to_lowercase();

        // Check for informal language
        for word in &self.informal_words {
            if text_lower.contains(word) {
                issues.push(format!("Informal language detected: '{}'", word));
                suggestions.push(format!("Replace '{}' with more formal alternative", word));
            }
        }

        // Check for weak phrases
        for phrase in &self.weak_phrases {
            if text_lower.contains(phrase) {
                issues.push(format!("Weak phrase detected: '{}'", phrase));
                suggestions.push(format!("Consider removing or strengthening '{}'", phrase));
            }
        }

        // Check for first person (should be minimal in academic writing)
        let first_person_re = Regex::new(r"\b(i|we|my|our)\b").unwrap();
        let first_person_count = first_person_re.find_iter(&text_lower).count();
        if first_person_count > text.split_whitespace().count() / 50 {
            issues.push(format!(
                "Excessive first-person usage ({} occurrences)",
                first_person_count
            ));
            suggestions.push("Consider using passive voice or third person".to_string());
        }

        // Check for domain-specific terminology usage
        let domain_term_count: usize = self
            .domain_terms
            .iter()
            .map(|term| text_lower.matches(term).count())
            .sum();

        let word_count = text.split_whitespace().count();
        let domain_density = domain_term_count as f64 / word_count as f64;

        if domain_density < 0.01 && word_count > 200 {
            issues.push("Low domain-specific terminology density".to_string());
            suggestions.push("Consider using more domain-specific terms".to_string());
        }

        // Check for hedging (too much or too little)
        let hedging_phrases = vec![
            "may",
            "might",
            "could",
            "possibly",
            "potentially",
            "suggest",
            "indicate",
            "appear",
            "seem",
        ];
        let hedging_count: usize = hedging_phrases
            .iter()
            .map(|phrase| text_lower.matches(phrase).count())
            .sum();

        let hedging_density = hedging_count as f64 / word_count as f64;
        if hedging_density > 0.05 {
            issues.push("Excessive hedging detected".to_string());
            suggestions.push("Consider being more assertive in some claims".to_string());
        } else if hedging_density < 0.01 && word_count > 500 {
            issues.push("Very little hedging - may be too assertive".to_string());
            suggestions
                .push("Consider adding appropriate hedging for uncertain claims".to_string());
        }

        let score = self.compute_rigor_score(&issues, word_count);

        Ok(AcademicRigorReport {
            score,
            issues,
            suggestions,
            domain_term_density: domain_density,
            hedging_density,
        })
    }

    fn compute_rigor_score(&self, issues: &[String], word_count: usize) -> f64 {
        let base_score = 1.0;
        let penalty_per_issue = 0.1;
        let max_penalty = 0.7;

        let penalty = (issues.len() as f64 * penalty_per_issue).min(max_penalty);
        let score = (base_score - penalty).max(0.0);

        // Bonus for longer texts (more comprehensive)
        if word_count > 1000 {
            (score + 0.1).min(1.0)
        } else {
            score
        }
    }
}

#[derive(Debug, Clone)]
pub struct AcademicRigorReport {
    pub score: f64, // 0.0 - 1.0
    pub issues: Vec<String>,
    pub suggestions: Vec<String>,
    pub domain_term_density: f64,
    pub hedging_density: f64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_informal_language_detection() {
        let editor = AcademicEditor::new();
        let text = "This is gonna be awesome!";
        let report = editor.check_rigor(text).unwrap();

        assert!(report.issues.iter().any(|i| i.contains("gonna")));
        assert!(report.score < 1.0);
    }

    #[test]
    fn test_weak_phrases() {
        let editor = AcademicEditor::new();
        let text = "I think maybe this could work, sort of.";
        let report = editor.check_rigor(text).unwrap();

        assert!(report.issues.len() > 0);
    }
}
