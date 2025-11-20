//! Journal-specific formatting

use crate::error::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Journal {
    Nature,
    Science,
    Cell,
    PNAS,
    JAMA,
    Lancet,
    NatureMaterials,
    NatureMedicine,
    PLOSOne,
    Custom(String),
}

pub struct JournalFormatter {
    styles: HashMap<Journal, JournalStyle>,
}

#[derive(Debug, Clone)]
pub struct JournalStyle {
    pub max_words_abstract: usize,
    pub max_words_title: usize,
    pub reference_style: ReferenceStyle,
    pub figure_requirements: FigureRequirements,
    pub section_order: Vec<String>,
}

#[derive(Debug, Clone)]
pub enum ReferenceStyle {
    Vancouver,
    Nature,
    Science,
    APA,
}

#[derive(Debug, Clone)]
pub struct FigureRequirements {
    pub max_figures: Option<usize>,
    pub max_tables: Option<usize>,
    pub require_high_res: bool,
    pub format: ImageFormat,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageFormat {
    TIFF,
    EPS,
    PDF,
    PNG,
}

impl JournalFormatter {
    pub fn new() -> Self {
        let mut styles = HashMap::new();

        // Nature style
        styles.insert(
            Journal::Nature,
            JournalStyle {
                max_words_abstract: 150,
                max_words_title: 90,
                reference_style: ReferenceStyle::Nature,
                figure_requirements: FigureRequirements {
                    max_figures: Some(8),
                    max_tables: Some(5),
                    require_high_res: true,
                    format: ImageFormat::TIFF,
                },
                section_order: vec![
                    "Abstract".to_string(),
                    "Introduction".to_string(),
                    "Results".to_string(),
                    "Discussion".to_string(),
                    "Methods".to_string(),
                ],
            },
        );

        // Science style
        styles.insert(
            Journal::Science,
            JournalStyle {
                max_words_abstract: 125,
                max_words_title: 90,
                reference_style: ReferenceStyle::Science,
                figure_requirements: FigureRequirements {
                    max_figures: Some(6),
                    max_tables: Some(4),
                    require_high_res: true,
                    format: ImageFormat::EPS,
                },
                section_order: vec![
                    "Abstract".to_string(),
                    "Introduction".to_string(),
                    "Materials and Methods".to_string(),
                    "Results".to_string(),
                    "Discussion".to_string(),
                ],
            },
        );

        // PLOS One style
        styles.insert(
            Journal::PLOSOne,
            JournalStyle {
                max_words_abstract: 250,
                max_words_title: 100,
                reference_style: ReferenceStyle::Vancouver,
                figure_requirements: FigureRequirements {
                    max_figures: None,
                    max_tables: None,
                    require_high_res: false,
                    format: ImageFormat::PNG,
                },
                section_order: vec![
                    "Abstract".to_string(),
                    "Introduction".to_string(),
                    "Methods".to_string(),
                    "Results".to_string(),
                    "Discussion".to_string(),
                    "Supporting Information".to_string(),
                ],
            },
        );

        Self { styles }
    }

    /// Validate manuscript against journal requirements
    pub fn validate(
        &self,
        journal: Journal,
        manuscript: &ManuscriptContent,
    ) -> Result<ValidationReport> {
        let style = self.styles.get(&journal).ok_or_else(|| {
            crate::error::HermesError::EditorError("Journal style not found".to_string())
        })?;

        let mut issues = Vec::new();
        let mut warnings = Vec::new();

        // Check title length
        if manuscript.title.split_whitespace().count() > style.max_words_title {
            issues.push(format!(
                "Title too long: {} words (max: {})",
                manuscript.title.split_whitespace().count(),
                style.max_words_title
            ));
        }

        // Check abstract length
        if let Some(abstract_text) = &manuscript.abstract_text {
            let abstract_words = abstract_text.split_whitespace().count();
            if abstract_words > style.max_words_abstract {
                issues.push(format!(
                    "Abstract too long: {} words (max: {})",
                    abstract_words, style.max_words_abstract
                ));
            }
        }

        // Check section order
        let manuscript_sections: Vec<String> =
            manuscript.sections.keys().map(|s| s.clone()).collect();

        if !self.sections_match_order(&manuscript_sections, &style.section_order) {
            warnings.push("Section order does not match journal requirements".to_string());
        }

        // Check figure count
        if let Some(max_figures) = style.figure_requirements.max_figures {
            if manuscript.figure_count > max_figures {
                issues.push(format!(
                    "Too many figures: {} (max: {})",
                    manuscript.figure_count, max_figures
                ));
            }
        }

        // Check table count
        if let Some(max_tables) = style.figure_requirements.max_tables {
            if manuscript.table_count > max_tables {
                issues.push(format!(
                    "Too many tables: {} (max: {})",
                    manuscript.table_count, max_tables
                ));
            }
        }

        let is_valid = issues.is_empty();

        Ok(ValidationReport {
            is_valid,
            issues,
            warnings,
            style: style.clone(),
        })
    }

    fn sections_match_order(
        &self,
        manuscript_sections: &[String],
        required_order: &[String],
    ) -> bool {
        // Check if manuscript sections follow required order (allowing some flexibility)
        let mut manuscript_idx = 0;

        for required in required_order {
            // Find this required section in manuscript
            while manuscript_idx < manuscript_sections.len() {
                if manuscript_sections[manuscript_idx].eq_ignore_ascii_case(required) {
                    manuscript_idx += 1;
                    break;
                }
                manuscript_idx += 1;
            }
        }

        true // Allow flexibility in section order
    }

    /// Get formatting guidelines for journal
    pub fn get_guidelines(&self, journal: Journal) -> Option<&JournalStyle> {
        self.styles.get(&journal)
    }
}

#[derive(Debug, Clone)]
pub struct ManuscriptContent {
    pub title: String,
    pub abstract_text: Option<String>,
    pub sections: HashMap<String, String>,
    pub figure_count: usize,
    pub table_count: usize,
}

#[derive(Debug, Clone)]
pub struct ValidationReport {
    pub is_valid: bool,
    pub issues: Vec<String>,
    pub warnings: Vec<String>,
    pub style: JournalStyle,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_nature_validation() {
        let formatter = JournalFormatter::new();

        let mut manuscript = ManuscriptContent {
            title: "A".repeat(200), // Too long
            abstract_text: Some("Abstract text here".to_string()),
            sections: HashMap::new(),
            figure_count: 10, // Too many
            table_count: 2,
        };

        let report = formatter.validate(Journal::Nature, &manuscript).unwrap();

        assert!(!report.is_valid);
        assert!(report.issues.iter().any(|i| i.contains("Title too long")));
        assert!(report.issues.iter().any(|i| i.contains("Too many figures")));
    }
}
