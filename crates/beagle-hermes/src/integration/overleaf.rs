//! Overleaf integration for LaTeX manuscript sync

use crate::error::Result;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

pub struct OverleafClient {
    client: Client,
    api_key: Option<String>,
    base_url: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OverleafProject {
    pub id: String,
    pub name: String,
    pub last_updated: String,
}

impl OverleafClient {
    pub fn new(api_key: Option<String>) -> Self {
        Self {
            client: Client::new(),
            api_key,
            base_url: "https://www.overleaf.com/api/v1".to_string(),
        }
    }

    /// List user's Overleaf projects
    pub async fn list_projects(&self) -> Result<Vec<OverleafProject>> {
        info!("Fetching Overleaf projects");

        if self.api_key.is_none() {
            warn!("No Overleaf API key configured, returning empty list");
            return Ok(Vec::new());
        }

        // Overleaf API requires authentication
        // For now, return empty list (would need OAuth or API key)
        Ok(Vec::new())
    }

    /// Sync manuscript to Overleaf project
    pub async fn sync_manuscript(
        &self,
        project_id: &str,
        manuscript_content: &ManuscriptContent,
    ) -> Result<()> {
        info!("Syncing manuscript to Overleaf project: {}", project_id);

        // Convert manuscript to LaTeX
        let latex_content = self.convert_to_latex(manuscript_content);

        // Upload to Overleaf (would use Overleaf API)
        // For now, just log
        info!("LaTeX content generated: {} chars", latex_content.len());

        Ok(())
    }

    /// Convert manuscript to LaTeX format
    fn convert_to_latex(&self, content: &ManuscriptContent) -> String {
        let mut latex = String::new();

        latex.push_str("\\documentclass{article}\n");
        latex.push_str("\\usepackage[utf8]{inputenc}\n");
        latex.push_str("\\usepackage{amsmath}\n");
        latex.push_str("\\usepackage{graphicx}\n");
        latex.push_str("\\begin{document}\n\n");

        latex.push_str(&format!("\\title{{{}}}\n", escape_latex(&content.title)));
        latex.push_str("\\author{Author}\n");
        latex.push_str("\\maketitle\n\n");

        if let Some(abstract_text) = &content.abstract_text {
            latex.push_str("\\begin{abstract}\n");
            latex.push_str(&escape_latex(abstract_text));
            latex.push_str("\n\\end{abstract}\n\n");
        }

        for (section_name, section_content) in &content.sections {
            latex.push_str(&format!("\\section{{{}}}\n\n", escape_latex(section_name)));
            latex.push_str(&escape_latex(section_content));
            latex.push_str("\n\n");
        }

        latex.push_str("\\end{document}\n");

        latex
    }
}

fn escape_latex(text: &str) -> String {
    text.replace('\\', "\\textbackslash{}")
        .replace('&', "\\&")
        .replace('%', "\\%")
        .replace('$', "\\$")
        .replace('#', "\\#")
        .replace('^', "\\textasciicircum{}")
        .replace('_', "\\_")
        .replace('{', "\\{")
        .replace('}', "\\}")
        .replace('~', "\\textasciitilde{}")
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

    #[test]
    fn test_latex_conversion() {
        let client = OverleafClient::new(None);
        let content = ManuscriptContent {
            title: "Test Paper".to_string(),
            abstract_text: Some("Test abstract with special chars: $ & %".to_string()),
            sections: {
                let mut map = std::collections::HashMap::new();
                map.insert("Introduction".to_string(), "Introduction text.".to_string());
                map
            },
        };

        let latex = client.convert_to_latex(&content);
        assert!(latex.contains("\\documentclass"));
        assert!(latex.contains("Test Paper"));
    }
}
