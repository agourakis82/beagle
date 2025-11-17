//! ARGOS: Validation and quality control agent

use super::athena::Paper;
use super::hermes_agent::Draft;
use crate::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use tracing::{debug, info};

pub struct ArgosAgent {
    citation_validator: CitationValidator,
    quality_scorer: QualityScorer,
}

impl ArgosAgent {
    pub async fn new() -> Result<Self> {
        let citation_validator = CitationValidator::new()?;
        let quality_scorer = QualityScorer::new()?;

        Ok(Self {
            citation_validator,
            quality_scorer,
        })
    }

    /// Validate draft and compute quality scores
    pub async fn validate(&self, draft: &Draft, papers: &[Paper]) -> Result<ValidationResult> {
        info!("ARGOS: Validating draft ({} words)", draft.word_count);

        // 1. Validate citations (parallel)
        let citation_validity = self.citation_validator.validate(&draft.citations, papers)?;

        // 2. Check logical flow (parallel)
        let flow_score = self.quality_scorer.analyze_flow(&draft.content)?;

        // 3. Detect potential issues (parallel)
        let issues = self.detect_issues(draft)?;

        // 4. Compute overall quality
        let quality_score =
            self.compute_quality_score(citation_validity.completeness, flow_score, issues.len());

        info!("ARGOS: Quality score: {:.1}%", quality_score * 100.0);

        Ok(ValidationResult {
            citation_validity,
            flow_score,
            issues,
            quality_score,
            approved: quality_score >= 0.85,
        })
    }

    fn detect_issues(&self, draft: &Draft) -> Result<Vec<Issue>> {
        let mut issues = Vec::new();

        // 1. Check for missing transitions between paragraphs
        let transition_issues = self.check_transitions(&draft.content);
        issues.extend(transition_issues);

        // 2. Check for unsupported claims (statements without citations)
        let claim_issues = self.check_unsupported_claims(&draft.content);
        issues.extend(claim_issues);

        // 3. Check for unclear references (pronouns without clear antecedents)
        let reference_issues = self.check_unclear_references(&draft.content);
        issues.extend(reference_issues);

        // 4. Basic grammatical checks (very simple heuristics)
        let grammar_issues = self.check_basic_grammar(&draft.content);
        issues.extend(grammar_issues);

        if !issues.is_empty() {
            debug!("ARGOS: Detected {} issues", issues.len());
        }

        Ok(issues)
    }

    fn check_transitions(&self, content: &str) -> Vec<Issue> {
        let mut issues = Vec::new();
        let paragraphs: Vec<&str> = content.split("\n\n").collect();

        // Common transition words/phrases
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
        ];

        for i in 1..paragraphs.len() {
            let prev_para = paragraphs[i - 1].to_lowercase();
            let curr_para = paragraphs[i].to_lowercase();

            // Check if current paragraph starts with transition
            let has_transition = transition_words.iter().any(|&word| {
                curr_para.starts_with(word) || curr_para.contains(&format!(", {}", word))
            });

            // Check if paragraphs are related (simple heuristic: shared keywords)
            let prev_words: HashSet<&str> = prev_para.split_whitespace().collect();
            let curr_words: HashSet<&str> = curr_para.split_whitespace().collect();
            let shared_words: Vec<&str> = prev_words.intersection(&curr_words).copied().collect();

            // If no transition and few shared words, might need a transition
            if !has_transition
                && shared_words.len() < 3
                && prev_para.len() > 50
                && curr_para.len() > 50
            {
                issues.push(Issue {
                    issue_type: IssueType::MissingTransition,
                    description: format!(
                        "Paragraph {} may benefit from a transition word or phrase",
                        i + 1
                    ),
                    severity: Severity::Low,
                });
            }
        }

        issues
    }

    fn check_unsupported_claims(&self, content: &str) -> Vec<Issue> {
        let mut issues = Vec::new();
        use regex::Regex;

        // Pattern to find sentences that might be claims
        // Look for sentences with strong verbs but no citations
        let claim_pattern = Regex::new(r"([A-Z][^.!?]*?(?:demonstrates?|shows?|proves?|indicates?|suggests?|reveals?)[^.!?]*?[.!?])")
            .ok();

        if let Some(pattern) = claim_pattern {
            let citation_pattern = Regex::new(r"\[\d+\]").ok();

            for cap in pattern.captures_iter(content) {
                if let Some(sentence) = cap.get(1) {
                    let sentence_text = sentence.as_str();

                    // Check if sentence has a citation
                    let has_citation = citation_pattern
                        .as_ref()
                        .map(|p| p.is_match(sentence_text))
                        .unwrap_or(false);

                    if !has_citation && sentence_text.len() > 20 {
                        issues.push(Issue {
                            issue_type: IssueType::UnsupportedClaim,
                            description: format!(
                                "Potential unsupported claim: \"{}\"",
                                if sentence_text.len() > 100 {
                                    format!("{}...", &sentence_text[..100])
                                } else {
                                    sentence_text.to_string()
                                }
                            ),
                            severity: Severity::Medium,
                        });
                    }
                }
            }
        }

        issues
    }

    fn check_unclear_references(&self, content: &str) -> Vec<Issue> {
        let mut issues = Vec::new();

        // Simple heuristic: check for pronouns that might be unclear
        let unclear_pronouns = ["this", "that", "these", "those", "it", "they"];
        let sentences: Vec<&str> = content.split(&['.', '!', '?'][..]).collect();

        for (i, sentence) in sentences.iter().enumerate() {
            let lower = sentence.to_lowercase();
            for pronoun in &unclear_pronouns {
                if lower.contains(&format!(" {} ", pronoun))
                    || lower.starts_with(&format!("{} ", pronoun))
                {
                    // Check if previous sentence has a clear referent
                    if i > 0 {
                        let prev_sentence = sentences[i - 1].to_lowercase();
                        // Very simple check: if previous sentence doesn't have nouns, might be unclear
                        let has_nouns = prev_sentence
                            .split_whitespace()
                            .any(|w| w.len() > 4 && !unclear_pronouns.contains(&w));

                        if !has_nouns {
                            issues.push(Issue {
                                issue_type: IssueType::UnclearReference,
                                description: format!(
                                    "Possible unclear reference to '{}' in sentence {}",
                                    pronoun,
                                    i + 1
                                ),
                                severity: Severity::Low,
                            });
                        }
                    }
                }
            }
        }

        issues
    }

    fn check_basic_grammar(&self, content: &str) -> Vec<Issue> {
        let mut issues = Vec::new();

        // Very basic checks
        // 1. Check for double spaces
        if content.contains("  ") {
            issues.push(Issue {
                issue_type: IssueType::GrammaticalError,
                description: "Double spaces detected".to_string(),
                severity: Severity::Low,
            });
        }

        // 2. Check for common typos in scientific writing
        let common_typos = [("teh", "the"), ("adn", "and"), ("taht", "that")];

        for (typo, _correct) in &common_typos {
            if content.to_lowercase().contains(typo) {
                issues.push(Issue {
                    issue_type: IssueType::GrammaticalError,
                    description: format!("Possible typo: '{}'", typo),
                    severity: Severity::Low,
                });
            }
        }

        issues
    }

    fn compute_quality_score(&self, citation_comp: f64, flow: f64, num_issues: usize) -> f64 {
        let issue_penalty = (num_issues as f64) * 0.05;
        let base_score = (citation_comp + flow) / 2.0;
        (base_score - issue_penalty).max(0.0).min(1.0)
    }
}

struct CitationValidator {}

impl CitationValidator {
    fn new() -> Result<Self> {
        Ok(Self {})
    }

    fn validate(&self, citations: &[String], papers: &[Paper]) -> Result<CitationValidity> {
        use crate::synthesis::CitationValidator;

        let validator = CitationValidator::new()?;

        // Build citation text for validation
        let citation_text = citations.join(", ");
        let validation = validator.validate_citations(&citation_text, papers.len());

        // Check for specific paper matches (if DOIs or titles are available)
        let mut hallucinated = Vec::new();
        let mut missing = Vec::new();

        // Parse citation numbers
        for citation in citations {
            let numbers = validator.parse_citation_numbers(citation);
            for num in numbers {
                if num == 0 || num > papers.len() {
                    hallucinated.push(format!("[{}]", citation));
                }
            }
        }

        // Check if important claims lack citations
        // This is a simplified check - in production would use NLP
        if citations.is_empty() && !papers.is_empty() {
            missing.push("No citations found for claims".to_string());
        }

        Ok(CitationValidity {
            completeness: validation.completeness,
            hallucinated,
            missing,
        })
    }
}

struct QualityScorer {}

impl QualityScorer {
    fn new() -> Result<Self> {
        Ok(Self {})
    }

    fn analyze_flow(&self, content: &str) -> Result<f64> {
        // Analyze logical flow:
        // - Transition words present
        // - Paragraphs connected
        // - Argument progression clear

        let paragraphs: Vec<&str> = content
            .split("\n\n")
            .filter(|p| p.trim().len() > 20) // Filter very short paragraphs
            .collect();

        if paragraphs.len() < 2 {
            return Ok(0.85); // Single paragraph = good flow by default
        }

        let mut flow_score = 0.0;
        let mut checks = 0;

        // 1. Check transition words between paragraphs
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
            "further",
            "meanwhile",
            "subsequently",
            "previously",
            "initially",
        ];

        for i in 1..paragraphs.len() {
            let prev_para = paragraphs[i - 1].to_lowercase();
            let curr_para = paragraphs[i].to_lowercase();

            // Check if current paragraph starts with transition
            let has_transition = transition_words.iter().any(|&word| {
                curr_para.starts_with(word)
                    || curr_para.starts_with(&format!("{}, ", word))
                    || curr_para.contains(&format!(" {} ", word))
            });

            // Check for shared keywords (coherence)
            let prev_words: std::collections::HashSet<&str> = prev_para
                .split_whitespace()
                .filter(|w| w.len() > 4) // Only meaningful words
                .collect();
            let curr_words: std::collections::HashSet<&str> = curr_para
                .split_whitespace()
                .filter(|w| w.len() > 4)
                .collect();

            let shared_keywords = prev_words.intersection(&curr_words).count();
            let coherence_score = if shared_keywords > 0 {
                (shared_keywords as f64 / prev_words.len().max(1) as f64).min(1.0)
            } else {
                0.0
            };

            // Paragraph flow score: transition (0.6) + coherence (0.4)
            let para_score = if has_transition {
                0.6 + coherence_score * 0.4
            } else {
                coherence_score * 0.8 // Lower weight if no transition
            };

            flow_score += para_score;
            checks += 1;
        }

        // 2. Check for logical progression (intro -> body -> conclusion structure)
        let has_intro = content.to_lowercase().contains("introduction")
            || content.to_lowercase().contains("background");
        let has_conclusion = content.to_lowercase().contains("conclusion")
            || content.to_lowercase().contains("summary");

        let structure_score = if has_intro && has_conclusion {
            0.1 // Bonus for clear structure
        } else if has_intro || has_conclusion {
            0.05
        } else {
            0.0
        };

        // 3. Check for argument progression (claims followed by evidence)
        let claim_indicators = ["demonstrates", "shows", "indicates", "suggests", "reveals"];
        let evidence_indicators = [
            "data",
            "results",
            "analysis",
            "study",
            "experiment",
            "finding",
        ];

        let mut claim_evidence_balance = 0.0;
        let claim_count = claim_indicators
            .iter()
            .map(|word| content.to_lowercase().matches(word).count())
            .sum::<usize>();
        let evidence_count = evidence_indicators
            .iter()
            .map(|word| content.to_lowercase().matches(word).count())
            .sum::<usize>();

        if claim_count > 0 && evidence_count > 0 {
            // Good balance: claims should be supported by evidence
            let ratio = evidence_count as f64 / claim_count as f64;
            claim_evidence_balance = (ratio / 2.0).min(0.1); // Max 0.1 bonus
        }

        // Final flow score
        let avg_para_flow = if checks > 0 {
            flow_score / checks as f64
        } else {
            0.85
        };

        let final_score = (avg_para_flow + structure_score + claim_evidence_balance).min(1.0);
        debug!("ARGOS: Flow analysis - para_flow: {:.2}, structure: {:.2}, balance: {:.2}, final: {:.2}",
            avg_para_flow, structure_score, claim_evidence_balance, final_score);

        Ok(final_score)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    pub citation_validity: CitationValidity,
    pub flow_score: f64,
    pub issues: Vec<Issue>,
    pub quality_score: f64,
    pub approved: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CitationValidity {
    pub completeness: f64,
    pub hallucinated: Vec<String>,
    pub missing: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Issue {
    pub issue_type: IssueType,
    pub description: String,
    pub severity: Severity,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum IssueType {
    UnsupportedClaim,
    MissingTransition,
    UnclearReference,
    GrammaticalError,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum Severity {
    Low,
    Medium,
    High,
}
