//! Microsoft Word integration for manuscript export

use crate::error::Result;
use std::path::Path;
use tracing::info;

pub struct WordExporter {
    // Future: COM interface or docx library
}

impl WordExporter {
    pub fn new() -> Self {
        Self {}
    }

    /// Export manuscript to Word document
    pub async fn export_manuscript(
        &self,
        manuscript_content: &ManuscriptContent,
        output_path: &Path,
    ) -> Result<()> {
        info!("Exporting manuscript to Word: {:?}", output_path);

        // Use docx-rs or similar library for Word export
        // For now, create a simple text file that can be opened in Word
        let mut content = String::new();

        content.push_str(&format!("{}\n\n", manuscript_content.title));
        content.push_str("ABSTRACT\n\n");
        if let Some(abstract_text) = &manuscript_content.abstract_text {
            content.push_str(abstract_text);
            content.push_str("\n\n");
        }

        for (section_name, section_content) in &manuscript_content.sections {
            content.push_str(&format!("{}\n\n", section_name.to_uppercase()));
            content.push_str(section_content);
            content.push_str("\n\n");
        }

        std::fs::write(output_path, content)?;

        info!("Manuscript exported successfully");
        Ok(())
    }

    /// Import manuscript from Word document
    pub async fn import_manuscript(&self, word_path: &Path) -> Result<ManuscriptContent> {
        info!("Importing manuscript from Word: {:?}", word_path);

        // For now, read as plain text
        // In production, would use docx-rs to parse .docx structure
        let content = std::fs::read_to_string(word_path)?;

        // Simple parsing (would be more sophisticated with actual Word parser)
        let mut sections = std::collections::HashMap::new();
        let mut current_section = String::new();
        let mut current_section_name = "Introduction".to_string();

        for line in content.lines() {
            let line_upper = line.to_uppercase();
            if line_upper == "ABSTRACT" || line_upper == "INTRODUCTION" || line_upper == "METHODS"
                || line_upper == "RESULTS" || line_upper == "DISCUSSION" || line_upper == "CONCLUSION"
            {
                if !current_section.is_empty() {
                    sections.insert(current_section_name.clone(), current_section.clone());
                }
                current_section_name = line.trim().to_string();
                current_section.clear();
            } else {
                current_section.push_str(line);
                current_section.push('\n');
            }
        }

        if !current_section.is_empty() {
            sections.insert(current_section_name, current_section);
        }

        Ok(ManuscriptContent {
            title: "Imported Manuscript".to_string(),
            abstract_text: sections.remove("ABSTRACT"),
            sections,
        })
    }
}

#[derive(Debug, Clone)]
pub struct ManuscriptContent {
    pub title: String,
    pub abstract_text: Option<String>,
    pub sections: std::collections::HashMap<String, String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_export_manuscript() {
        let exporter = WordExporter::new();
        let content = ManuscriptContent {
            title: "Test Paper".to_string(),
            abstract_text: Some("This is a test abstract.".to_string()),
            sections: {
                let mut map = std::collections::HashMap::new();
                map.insert("Introduction".to_string(), "Introduction text here.".to_string());
                map
            },
        };

        let temp_path = std::env::temp_dir().join("test_export.txt");
        exporter.export_manuscript(&content, &temp_path).await.unwrap();

        assert!(temp_path.exists());
        std::fs::remove_file(&temp_path).ok();
    }
}
