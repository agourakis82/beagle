//! Citation verification against Semantic Scholar

use super::formatter::Citation;
use crate::error::{HermesError, Result};
use reqwest::Client;
use serde_json::Value;
use tracing::info;

pub struct CitationVerifier {
    client: Client,
    api_key: String,
}

impl CitationVerifier {
    pub fn new() -> Self {
        let api_key = std::env::var("SEMANTIC_SCHOLAR_API_KEY")
            .unwrap_or_else(|_| "flE0Xf1Q8F4k5yoxskzQi1h26DvihxoEaEXY42oE".to_string());
        
        Self {
            client: Client::new(),
            api_key,
        }
    }

    /// Verify citation against Semantic Scholar
    pub async fn verify(&self, citation: &Citation) -> Result<VerificationResult> {
        info!("Verifying citation: {}", citation.title);
        
        // Search by title
        let query = urlencoding::encode(&citation.title);
        let url = format!(
            "https://api.semanticscholar.org/graph/v1/paper/search?query={}&limit=5",
            query
        );
        
        let response = self
            .client
            .get(&url)
            .header("x-api-key", &self.api_key)
            .send()
            .await
            .map_err(|e| HermesError::CitationError(format!("API request failed: {}", e)))?;
        
        if !response.status().is_success() {
            return Ok(VerificationResult {
                verified: false,
                confidence: 0.0,
                matched_paper: None,
                issues: vec!["API request failed".to_string()],
            });
        }
        
        let data: Value = response
            .json()
            .await
            .map_err(|e| HermesError::CitationError(format!("Failed to parse response: {}", e)))?;
        
        let papers = data
            .get("data")
            .and_then(|d| d.as_array())
            .ok_or_else(|| HermesError::CitationError("Invalid API response".to_string()))?;
        
        // Find best match
        let mut best_match: Option<(f64, Value)> = None;
        
        for paper in papers {
            if let Some(title) = paper.get("title").and_then(|t| t.as_str()) {
                let similarity = self.compute_title_similarity(&citation.title, title);
                
                if similarity > 0.8 {
                    if best_match.is_none() || similarity > best_match.as_ref().unwrap().0 {
                        best_match = Some((similarity, paper.clone()));
                    }
                }
            }
        }
        
        if let Some((confidence, matched)) = best_match {
            let mut issues = Vec::new();
            
            // Verify authors
            if let Some(authors) = matched.get("authors").and_then(|a| a.as_array()) {
                let matched_authors: Vec<String> = authors
                    .iter()
                    .filter_map(|a| a.get("name").and_then(|n| n.as_str()))
                    .map(String::from)
                    .collect();
                
                if !self.authors_match(&citation.authors, &matched_authors) {
                    issues.push("Author mismatch".to_string());
                }
            }
            
            // Verify year
            if let Some(year) = matched.get("year").and_then(|y| y.as_i64()) {
                if let Some(citation_year) = citation.year {
                    if year as u32 != citation_year {
                        issues.push(format!("Year mismatch: {} vs {}", citation_year, year));
                    }
                }
            }
            
            Ok(VerificationResult {
                verified: issues.is_empty(),
                confidence,
                matched_paper: Some(matched),
                issues,
            })
        } else {
            Ok(VerificationResult {
                verified: false,
                confidence: 0.0,
                matched_paper: None,
                issues: vec!["No matching paper found".to_string()],
            })
        }
    }

    fn compute_title_similarity(&self, title1: &str, title2: &str) -> f64 {
        // Simple word overlap similarity
        let title1_lower: String = title1.to_lowercase();
        let title2_lower: String = title2.to_lowercase();
        let words1: std::collections::HashSet<&str> = title1_lower
            .split_whitespace()
            .collect();
        let words2: std::collections::HashSet<&str> = title2_lower
            .split_whitespace()
            .collect();
        
        let intersection: usize = words1.intersection(&words2).count();
        let union = words1.union(&words2).count();
        
        if union == 0 {
            return 0.0;
        }
        
        intersection as f64 / union as f64
    }

    fn authors_match(&self, citation_authors: &[String], matched_authors: &[String]) -> bool {
        if citation_authors.is_empty() || matched_authors.is_empty() {
            return false;
        }
        
        // Check if at least 50% of citation authors appear in matched authors
        let citation_lower: Vec<String> = citation_authors
            .iter()
            .map(|a| a.to_lowercase())
            .collect();
        
        let matched_lower: Vec<String> = matched_authors
            .iter()
            .map(|a| a.to_lowercase())
            .collect();
        
        let matches: usize = citation_lower
            .iter()
            .filter(|ca| {
                matched_lower.iter().any(|ma| {
                    ma.contains(ca.as_str()) || ca.contains(ma.as_str()) || 
                    self.name_similarity(ca.as_str(), ma.as_str()) > 0.8
                })
            })
            .count();
        
        matches as f64 / citation_authors.len() as f64 >= 0.5
    }

    fn name_similarity(&self, name1: &str, name2: &str) -> f64 {
        // Simple similarity based on common words
        let words1: std::collections::HashSet<&str> = name1.split_whitespace().collect();
        let words2: std::collections::HashSet<&str> = name2.split_whitespace().collect();
        
        let intersection = words1.intersection(&words2).count();
        let union = words1.union(&words2).count();
        
        if union == 0 {
            return 0.0;
        }
        
        intersection as f64 / union as f64
    }
}

#[derive(Debug, Clone)]
pub struct VerificationResult {
    pub verified: bool,
    pub confidence: f64,
    pub matched_paper: Option<Value>,
    pub issues: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires API key
    async fn test_verification() {
        let verifier = CitationVerifier::new();
        
        let citation = Citation {
            title: "Attention Is All You Need".to_string(),
            authors: vec!["Vaswani".to_string()],
            year: Some(2017),
            doi: None,
            url: None,
            abstract_text: None,
        };
        
        let result = verifier.verify(&citation).await.unwrap();
        
        assert!(result.confidence > 0.0);
        println!("Verification result: {:?}", result);
    }
}
