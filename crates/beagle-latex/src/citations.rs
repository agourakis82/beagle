//! Bibliography and Citation Support
//!
//! Comprehensive citation styles for scientific publishing:
//! - APA, IEEE, Nature, Science, Chicago, Vancouver
//! - BibTeX and BibLaTeX support
//! - CSL (Citation Style Language) integration

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Citation style
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum CitationStyle {
    /// Nature journal style (numbered, compact)
    Nature,

    /// Science journal style (numbered, superscript)
    Science,

    /// IEEE style (numbered, brackets)
    IEEE,

    /// APA 7th edition (author-year)
    APA,

    /// Chicago style (author-year or notes)
    Chicago,

    /// Vancouver style (numbered, medical)
    Vancouver,

    /// Harvard style (author-year)
    Harvard,

    /// MLA 9th edition
    MLA,

    /// ACM style (numbered)
    ACM,

    /// Springer style (numbered)
    Springer,
}

impl CitationStyle {
    /// Get CSL file name for this style
    pub fn csl_file(&self) -> String {
        match self {
            Self::Nature => "nature.csl",
            Self::Science => "science.csl",
            Self::IEEE => "ieee.csl",
            Self::APA => "apa.csl",
            Self::Chicago => "chicago-author-date.csl",
            Self::Vancouver => "vancouver.csl",
            Self::Harvard => "harvard.csl",
            Self::MLA => "modern-language-association.csl",
            Self::ACM => "acm-sig-proceedings.csl",
            Self::Springer => "springer-basic.csl",
        }
        .to_string()
    }

    /// Get description of citation style
    pub fn description(&self) -> &str {
        match self {
            Self::Nature => "Nature journal - Numbered references, compact format",
            Self::Science => "Science journal - Numbered superscript references",
            Self::IEEE => "IEEE - Numbered references in brackets [1]",
            Self::APA => "APA 7th edition - Author-year (Smith, 2023)",
            Self::Chicago => "Chicago - Author-year or footnote style",
            Self::Vancouver => "Vancouver - Numbered, medical/life sciences",
            Self::Harvard => "Harvard - Author-year with emphasis",
            Self::MLA => "MLA 9th - Humanities style",
            Self::ACM => "ACM - Computer science conferences",
            Self::Springer => "Springer - Basic numbered style",
        }
    }

    /// Check if style is numbered
    pub fn is_numbered(&self) -> bool {
        matches!(
            self,
            Self::Nature
                | Self::Science
                | Self::IEEE
                | Self::Vancouver
                | Self::ACM
                | Self::Springer
        )
    }

    /// Check if style is author-year
    pub fn is_author_year(&self) -> bool {
        matches!(self, Self::APA | Self::Chicago | Self::Harvard | Self::MLA)
    }

    /// Get recommended disciplines
    pub fn recommended_for(&self) -> Vec<&str> {
        match self {
            Self::Nature => vec!["Biology", "Chemistry", "Physics", "Multidisciplinary"],
            Self::Science => vec!["Biology", "Medicine", "General science"],
            Self::IEEE => vec!["Engineering", "Computer science", "Technology"],
            Self::APA => vec!["Psychology", "Social sciences", "Education"],
            Self::Chicago => vec!["History", "Humanities", "Social sciences"],
            Self::Vancouver => vec!["Medicine", "Biomedical sciences", "Public health"],
            Self::Harvard => vec!["Business", "Economics", "Social sciences"],
            Self::MLA => vec!["Literature", "Languages", "Humanities"],
            Self::ACM => vec!["Computer science", "Software engineering"],
            Self::Springer => vec!["Engineering", "Computer science", "Mathematics"],
        }
    }
}

impl std::fmt::Display for CitationStyle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let name = match self {
            Self::Nature => "Nature",
            Self::Science => "Science",
            Self::IEEE => "IEEE",
            Self::APA => "APA",
            Self::Chicago => "Chicago",
            Self::Vancouver => "Vancouver",
            Self::Harvard => "Harvard",
            Self::MLA => "MLA",
            Self::ACM => "ACM",
            Self::Springer => "Springer",
        };
        write!(f, "{}", name)
    }
}

impl Default for CitationStyle {
    fn default() -> Self {
        Self::Nature
    }
}

/// Bibliography manager
pub struct Bibliography {
    pub entries: Vec<BibEntry>,
    pub style: CitationStyle,
}

impl Bibliography {
    /// Create new bibliography
    pub fn new(style: CitationStyle) -> Self {
        Self {
            entries: Vec::new(),
            style,
        }
    }

    /// Add entry
    pub fn add_entry(&mut self, entry: BibEntry) {
        self.entries.push(entry);
    }

    /// Generate BibTeX file
    pub fn to_bibtex(&self) -> String {
        let mut bibtex = String::new();

        for entry in &self.entries {
            bibtex.push_str(&entry.to_bibtex());
            bibtex.push_str("\n\n");
        }

        bibtex
    }

    /// Write to file
    pub fn write_to_file(&self, path: &Path) -> Result<()> {
        let bibtex = self.to_bibtex();
        std::fs::write(path, bibtex)
            .with_context(|| format!("Failed to write bibliography to {}", path.display()))
    }

    /// Parse from BibTeX file
    pub fn from_file(path: &Path, style: CitationStyle) -> Result<Self> {
        let content = std::fs::read_to_string(path)
            .with_context(|| format!("Failed to read bibliography from {}", path.display()))?;

        Self::from_bibtex(&content, style)
    }

    /// Parse from BibTeX string
    pub fn from_bibtex(bibtex: &str, style: CitationStyle) -> Result<Self> {
        // Simplified parser - in production, use a proper BibTeX parser
        let mut bib = Self::new(style);

        // Split by @article, @book, etc.
        for entry_text in bibtex.split('@').skip(1) {
            if let Some(entry) = BibEntry::parse(entry_text) {
                bib.add_entry(entry);
            }
        }

        Ok(bib)
    }
}

/// Bibliography entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BibEntry {
    pub entry_type: EntryType,
    pub cite_key: String,
    pub fields: std::collections::HashMap<String, String>,
}

impl BibEntry {
    /// Create new entry
    pub fn new(entry_type: EntryType, cite_key: String) -> Self {
        Self {
            entry_type,
            cite_key,
            fields: std::collections::HashMap::new(),
        }
    }

    /// Add field
    pub fn add_field(&mut self, key: String, value: String) {
        self.fields.insert(key, value);
    }

    /// Convert to BibTeX format
    pub fn to_bibtex(&self) -> String {
        let mut bibtex = format!("@{}{{{},\n", self.entry_type, self.cite_key);

        for (key, value) in &self.fields {
            bibtex.push_str(&format!("  {} = {{{}}},\n", key, value));
        }

        bibtex.push_str("}");
        bibtex
    }

    /// Parse from BibTeX text (simplified)
    pub fn parse(text: &str) -> Option<Self> {
        // This is a simplified parser
        // In production, use a proper BibTeX parsing library

        let lines: Vec<&str> = text.lines().collect();
        if lines.is_empty() {
            return None;
        }

        // Parse entry type and cite key from first line
        let first_line = lines[0].trim();
        let parts: Vec<&str> = first_line.split('{').collect();
        if parts.len() < 2 {
            return None;
        }

        let entry_type = EntryType::from_str(parts[0].trim())?;
        let cite_key = parts[1].trim_end_matches(',').trim().to_string();

        let mut entry = Self::new(entry_type, cite_key);

        // Parse fields
        for line in lines.iter().skip(1) {
            if let Some((key, value)) = Self::parse_field(line) {
                entry.add_field(key, value);
            }
        }

        Some(entry)
    }

    fn parse_field(line: &str) -> Option<(String, String)> {
        let line = line.trim();
        if line.is_empty() || line == "}" {
            return None;
        }

        let parts: Vec<&str> = line.split('=').collect();
        if parts.len() != 2 {
            return None;
        }

        let key = parts[0].trim().to_string();
        let value = parts[1]
            .trim()
            .trim_start_matches('{')
            .trim_end_matches('}')
            .trim_end_matches(',')
            .to_string();

        Some((key, value))
    }
}

/// BibTeX entry types
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum EntryType {
    Article,
    Book,
    InProceedings,
    InCollection,
    PhdThesis,
    MastersThesis,
    TechReport,
    Misc,
    Unpublished,
}

impl EntryType {
    fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "article" => Some(Self::Article),
            "book" => Some(Self::Book),
            "inproceedings" | "conference" => Some(Self::InProceedings),
            "incollection" => Some(Self::InCollection),
            "phdthesis" => Some(Self::PhdThesis),
            "mastersthesis" => Some(Self::MastersThesis),
            "techreport" => Some(Self::TechReport),
            "misc" => Some(Self::Misc),
            "unpublished" => Some(Self::Unpublished),
            _ => None,
        }
    }
}

impl std::fmt::Display for EntryType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let name = match self {
            Self::Article => "article",
            Self::Book => "book",
            Self::InProceedings => "inproceedings",
            Self::InCollection => "incollection",
            Self::PhdThesis => "phdthesis",
            Self::MastersThesis => "mastersthesis",
            Self::TechReport => "techreport",
            Self::Misc => "misc",
            Self::Unpublished => "unpublished",
        };
        write!(f, "{}", name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_citation_style_numbered() {
        assert!(CitationStyle::Nature.is_numbered());
        assert!(CitationStyle::IEEE.is_numbered());
        assert!(!CitationStyle::APA.is_author_year());
    }

    #[test]
    fn test_citation_style_author_year() {
        assert!(CitationStyle::APA.is_author_year());
        assert!(CitationStyle::Harvard.is_author_year());
        assert!(!CitationStyle::Nature.is_author_year());
    }

    #[test]
    fn test_bib_entry_creation() {
        let mut entry = BibEntry::new(EntryType::Article, "smith2023".to_string());
        entry.add_field("author".to_string(), "John Smith".to_string());
        entry.add_field("title".to_string(), "A Great Paper".to_string());
        entry.add_field("year".to_string(), "2023".to_string());

        let bibtex = entry.to_bibtex();
        assert!(bibtex.contains("@article{smith2023"));
        assert!(bibtex.contains("author = {John Smith}"));
    }

    #[test]
    fn test_default_citation_style() {
        let style = CitationStyle::default();
        assert_eq!(style, CitationStyle::Nature);
    }
}
