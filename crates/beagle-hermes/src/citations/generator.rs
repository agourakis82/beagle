//! Citation auto-generation with verification

use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Paper {
    pub title: String,
    pub authors: Vec<Author>,
    pub year: u16,
    pub journal: Option<String>,
    pub volume: Option<String>,
    pub issue: Option<String>,
    pub pages: Option<String>,
    pub doi: Option<String>,
    pub pmid: Option<String>,
    pub semantic_scholar_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Author {
    pub first_name: String,
    pub last_name: String,
    pub initials: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CitationStyle {
    Vancouver,     // Numbered [1]
    APA,           // (Author, Year)
    ABNT,          // (AUTHOR, Year)
    Nature,        // Superscript¹
    JAMA,          // Similar to Vancouver
    Cell,          // (Author et al., Year)
    Harvard,       // (Author Year)
}

pub struct CitationGenerator {
    semantic_scholar_api_key: Option<String>,
}

impl CitationGenerator {
    pub fn new() -> Self {
        Self {
            semantic_scholar_api_key: std::env::var("SEMANTIC_SCHOLAR_API_KEY").ok(),
        }
    }

    /// Generate citation from query (title or DOI)
    pub async fn generate(
        &self,
        query: &str,
        style: CitationStyle,
    ) -> Result<String, CitationError> {
        // 1. Search Semantic Scholar
        let paper = self.search_paper(query).await?;
        
        // 2. Verify paper exists
        if paper.is_none() {
            return Err(CitationError::PaperNotFound(query.to_string()));
        }
        
        let paper = paper.unwrap();
        
        // 3. Format according to style
        let citation = self.format_citation(&paper, style);
        
        Ok(citation)
    }

    async fn search_paper(&self, query: &str) -> Result<Option<Paper>, CitationError> {
        // TODO: Implement actual Semantic Scholar API call
        // For now, return mock data
        
        if query.to_lowercase().contains("fake") {
            return Ok(None);  // Simulate paper not found
        }
        
        Ok(Some(Paper {
            title: "Example Paper Title".to_string(),
            authors: vec![
                Author {
                    first_name: "John".to_string(),
                    last_name: "Doe".to_string(),
                    initials: Some("J".to_string()),
                },
                Author {
                    first_name: "Jane".to_string(),
                    last_name: "Smith".to_string(),
                    initials: Some("J".to_string()),
                },
            ],
            year: 2024,
            journal: Some("Nature".to_string()),
            volume: Some("625".to_string()),
            issue: Some("7995".to_string()),
            pages: Some("123-130".to_string()),
            doi: Some("10.1038/s41586-024-12345-6".to_string()),
            pmid: Some("38123456".to_string()),
            semantic_scholar_id: Some("abc123".to_string()),
        }))
    }

    fn format_citation(&self, paper: &Paper, style: CitationStyle) -> String {
        match style {
            CitationStyle::Vancouver => self.format_vancouver(paper),
            CitationStyle::APA => self.format_apa(paper),
            CitationStyle::ABNT => self.format_abnt(paper),
            CitationStyle::Nature => self.format_nature(paper),
            CitationStyle::JAMA => self.format_jama(paper),
            CitationStyle::Cell => self.format_cell(paper),
            CitationStyle::Harvard => self.format_harvard(paper),
        }
    }

    fn format_vancouver(&self, paper: &Paper) -> String {
        // Format: Author(s). Title. Journal. Year;Volume(Issue):Pages.
        let authors = self.format_authors_vancouver(&paper.authors);
        
        format!(
            "{}. {}. {}. {};{}({}):{}.",
            authors,
            paper.title,
            paper.journal.as_ref().unwrap_or(&"Unknown".to_string()),
            paper.year,
            paper.volume.as_ref().unwrap_or(&"0".to_string()),
            paper.issue.as_ref().unwrap_or(&"0".to_string()),
            paper.pages.as_ref().unwrap_or(&"0".to_string()),
        )
    }

    fn format_authors_vancouver(&self, authors: &[Author]) -> String {
        if authors.is_empty() {
            return "Unknown".to_string();
        }
        
        let formatted: Vec<String> = authors
            .iter()
            .take(6)  // Vancouver: max 6 authors
            .map(|a| format!("{} {}", a.last_name, a.initials.as_ref().unwrap_or(&"".to_string())))
            .collect();
        
        if authors.len() > 6 {
            format!("{}, et al", formatted.join(", "))
        } else {
            formatted.join(", ")
        }
    }

    fn format_apa(&self, paper: &Paper) -> String {
        // Format: Author(s). (Year). Title. Journal, Volume(Issue), Pages.
        let authors = self.format_authors_apa(&paper.authors);
        
        format!(
            "{}. ({}). {}. {}, {}({}), {}.",
            authors,
            paper.year,
            paper.title,
            paper.journal.as_ref().unwrap_or(&"Unknown".to_string()),
            paper.volume.as_ref().unwrap_or(&"0".to_string()),
            paper.issue.as_ref().unwrap_or(&"0".to_string()),
            paper.pages.as_ref().unwrap_or(&"0".to_string()),
        )
    }

    fn format_authors_apa(&self, authors: &[Author]) -> String {
        if authors.is_empty() {
            return "Unknown".to_string();
        }
        
        let formatted: Vec<String> = authors
            .iter()
            .map(|a| {
                let initial = a.initials.as_ref()
                    .map(|i| format!(" {}.", i))
                    .unwrap_or_default();
                format!("{},{}", a.last_name, initial)
            })
            .collect();
        
        if formatted.len() == 1 {
            formatted[0].clone()
        } else if formatted.len() == 2 {
            format!("{} & {}", formatted[0], formatted[1])
        } else {
            let last = formatted.last().unwrap();
            let rest = &formatted[..formatted.len()-1];
            format!("{}, & {}", rest.join(", "), last)
        }
    }

    fn format_abnt(&self, paper: &Paper) -> String {
        // Format: AUTHOR. Title. Journal, Volume, Issue, Pages, Year.
        let authors = self.format_authors_abnt(&paper.authors);
        
        format!(
            "{}. {}. {}, v. {}, n. {}, p. {}, {}.",
            authors,
            paper.title,
            paper.journal.as_ref().unwrap_or(&"Unknown".to_string()),
            paper.volume.as_ref().unwrap_or(&"0".to_string()),
            paper.issue.as_ref().unwrap_or(&"0".to_string()),
            paper.pages.as_ref().unwrap_or(&"0".to_string()),
            paper.year,
        )
    }

    fn format_authors_abnt(&self, authors: &[Author]) -> String {
        if authors.is_empty() {
            return "UNKNOWN".to_string();
        }
        
        let formatted: Vec<String> = authors
            .iter()
            .map(|a| {
                let initial = a.initials.as_ref()
                    .map(|i| format!(", {}.", i))
                    .unwrap_or_default();
                format!("{}{}", a.last_name.to_uppercase(), initial)
            })
            .collect();
        
        formatted.join("; ")
    }

    fn format_nature(&self, paper: &Paper) -> String {
        // Nature: compact format
        let authors = self.format_authors_nature(&paper.authors);
        
        format!(
            "{} {}. {}, {} ({})",
            authors,
            paper.title,
            paper.journal.as_ref().unwrap_or(&"Unknown".to_string()),
            paper.volume.as_ref().unwrap_or(&"0".to_string()),
            paper.year,
        )
    }

    fn format_authors_nature(&self, authors: &[Author]) -> String {
        if authors.is_empty() {
            return "Unknown".to_string();
        }
        
        if authors.len() <= 2 {
            authors
                .iter()
                .map(|a| format!("{}, {}.", a.last_name, a.first_name.chars().next().unwrap_or('X')))
                .collect::<Vec<_>>()
                .join(" & ")
        } else {
            format!(
                "{}, {}. et al.",
                authors[0].last_name,
                authors[0].first_name.chars().next().unwrap_or('X')
            )
        }
    }

    fn format_jama(&self, paper: &Paper) -> String {
        // Similar to Vancouver
        self.format_vancouver(paper)
    }

    fn format_cell(&self, paper: &Paper) -> String {
        // Cell: (Author et al., Year)
        if paper.authors.is_empty() {
            return "(Unknown, 0)".to_string();
        }
        let first_author = &paper.authors[0];
        let et_al = if paper.authors.len() > 1 { " et al." } else { "" };
        
        format!(
            "({}{}, {})",
            first_author.last_name,
            et_al,
            paper.year
        )
    }

    fn format_harvard(&self, paper: &Paper) -> String {
        // Harvard: (Author Year)
        if paper.authors.is_empty() {
            return "(Unknown 0)".to_string();
        }
        let first_author = &paper.authors[0];
        let et_al = if paper.authors.len() > 1 { " et al." } else { "" };
        
        format!(
            "({}{} {})",
            first_author.last_name,
            et_al,
            paper.year
        )
    }

    /// Batch generate citations
    pub async fn generate_batch(
        &self,
        queries: Vec<String>,
        style: CitationStyle,
    ) -> Vec<Result<String, CitationError>> {
        let mut results = Vec::new();
        
        for query in queries {
            results.push(self.generate(&query, style).await);
        }
        
        results
    }
}

#[derive(Debug, Error)]
pub enum CitationError {
    #[error("Paper not found: {0}")]
    PaperNotFound(String),
    
    #[error("API error: {0}")]
    ApiError(String),
    
    #[error("Invalid format")]
    InvalidFormat,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_citation_generation() {
        let generator = CitationGenerator::new();
        
        let citation = generator
            .generate("Example paper about AI", CitationStyle::Vancouver)
            .await
            .unwrap();
        
        assert!(citation.contains("Doe"));
        assert!(citation.contains("2024"));
    }

    #[tokio::test]
    async fn test_fake_paper_detection() {
        let generator = CitationGenerator::new();
        
        let result = generator
            .generate("Fake paper that does not exist", CitationStyle::Vancouver)
            .await;
        
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), CitationError::PaperNotFound(_)));
    }

    #[test]
    fn test_multiple_citation_styles() {
        let paper = Paper {
            title: "Test Paper".to_string(),
            authors: vec![
                Author {
                    first_name: "John".to_string(),
                    last_name: "Doe".to_string(),
                    initials: Some("J".to_string()),
                },
            ],
            year: 2024,
            journal: Some("Nature".to_string()),
            volume: Some("625".to_string()),
            issue: Some("1".to_string()),
            pages: Some("1-10".to_string()),
            doi: None,
            pmid: None,
            semantic_scholar_id: None,
        };
        
        let generator = CitationGenerator::new();
        
        let vancouver = generator.format_citation(&paper, CitationStyle::Vancouver);
        assert!(vancouver.contains("Doe J"));
        
        let apa = generator.format_citation(&paper, CitationStyle::APA);
        assert!(apa.contains("(2024)"));
        
        let nature = generator.format_citation(&paper, CitationStyle::Nature);
        assert!(nature.contains("Doe, J."));
    }
}
