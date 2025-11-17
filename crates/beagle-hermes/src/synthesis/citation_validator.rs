//! Citation validation and verification

use crate::{HermesError, Result};
use regex::Regex;
use std::collections::HashSet;
use tracing::warn;

pub struct CitationValidator {
    citation_pattern: Regex,
}

impl CitationValidator {
    pub fn new() -> Result<Self> {
        // Pattern to match citations like [1], [2-5], [1,3,5]
        let citation_pattern = Regex::new(r"\[(\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*)\]")
            .map_err(|e| HermesError::SynthesisError(format!("Invalid citation regex: {}", e)))?;

        Ok(Self { citation_pattern })
    }

    /// Extract all citations from text
    pub fn extract_citations(&self, text: &str) -> Vec<String> {
        self.citation_pattern
            .captures_iter(text)
            .filter_map(|cap| cap.get(1))
            .map(|m| m.as_str().to_string())
            .collect()
    }

    /// Validate citations against known papers
    pub fn validate_citations(
        &self,
        text: &str,
        known_paper_count: usize,
    ) -> CitationValidationResult {
        let citations = self.extract_citations(text);
        let mut valid_citations = HashSet::new();
        let mut invalid_citations = Vec::new();
        let mut out_of_range = Vec::new();

        for citation in &citations {
            // Parse citation numbers
            let numbers = self.parse_citation_numbers(citation);

            for num in numbers {
                if num == 0 {
                    invalid_citations.push(format!("[{}]", citation));
                } else if num > known_paper_count {
                    out_of_range.push(format!("[{}]", citation));
                } else {
                    valid_citations.insert(num);
                }
            }
        }

        let total_cited = valid_citations.len();
        let completeness = if citations.is_empty() {
            1.0
        } else {
            total_cited as f64 / citations.len() as f64
        };

        CitationValidationResult {
            total_citations: citations.len(),
            valid_citations: total_cited,
            invalid_citations,
            out_of_range,
            completeness,
        }
    }

    pub fn parse_citation_numbers(&self, citation: &str) -> Vec<usize> {
        let mut numbers = Vec::new();

        // Handle ranges like "1-5" and lists like "1,3,5"
        for part in citation.split(',') {
            if part.contains('-') {
                // Range: "1-5"
                let parts: Vec<&str> = part.split('-').collect();
                if parts.len() == 2 {
                    if let (Ok(start), Ok(end)) = (
                        parts[0].trim().parse::<usize>(),
                        parts[1].trim().parse::<usize>(),
                    ) {
                        for i in start..=end {
                            numbers.push(i);
                        }
                    }
                }
            } else {
                // Single number
                if let Ok(num) = part.trim().parse::<usize>() {
                    numbers.push(num);
                }
            }
        }

        numbers
    }

    /// Check for potential hallucinated citations (citations that don't match any known papers)
    pub fn detect_hallucinations(&self, text: &str, known_paper_count: usize) -> Vec<String> {
        let validation = self.validate_citations(text, known_paper_count);

        let mut hallucinations = validation.invalid_citations;
        hallucinations.extend(validation.out_of_range);

        if !hallucinations.is_empty() {
            warn!(
                "Detected {} potential hallucinated citations",
                hallucinations.len()
            );
        }

        hallucinations
    }
}

#[derive(Debug, Clone)]
pub struct CitationValidationResult {
    pub total_citations: usize,
    pub valid_citations: usize,
    pub invalid_citations: Vec<String>,
    pub out_of_range: Vec<String>,
    pub completeness: f64,
}

impl CitationValidationResult {
    pub fn is_valid(&self) -> bool {
        self.completeness >= 0.9
            && self.invalid_citations.is_empty()
            && self.out_of_range.is_empty()
    }
}
