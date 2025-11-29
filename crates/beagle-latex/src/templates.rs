//! LaTeX Template Management System
//!
//! Comprehensive collection of scientific paper templates:
//! - Nature/Science style
//! - IEEE conference/journal
//! - arXiv preprint
//! - Springer LNCS
//! - ACM proceedings
//! - BEAGLE custom themes

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Template manager
pub struct TemplateManager {
    templates: HashMap<String, Template>,
    template_dir: PathBuf,
}

impl TemplateManager {
    /// Create new template manager
    pub fn new() -> Result<Self> {
        let template_dir = Self::get_template_directory()?;

        // Ensure template directory exists
        std::fs::create_dir_all(&template_dir).context("Failed to create template directory")?;

        let mut manager = Self {
            templates: HashMap::new(),
            template_dir,
        };

        // Register built-in templates
        manager.register_builtin_templates()?;

        Ok(manager)
    }

    /// Get template directory path
    fn get_template_directory() -> Result<PathBuf> {
        let data_dir = std::env::var("BEAGLE_DATA_DIR").unwrap_or_else(|_| {
            dirs::home_dir()
                .expect("Could not determine home directory")
                .join("beagle-data")
                .to_string_lossy()
                .to_string()
        });

        Ok(PathBuf::from(data_dir).join("latex-templates"))
    }

    /// Register all built-in templates
    fn register_builtin_templates(&mut self) -> Result<()> {
        // BEAGLE Scientific (default)
        self.register_template(Template {
            name: "beagle-scientific".to_string(),
            description: "BEAGLE default scientific paper template".to_string(),
            style: "scientific".to_string(),
            preamble: include_str!("../templates/beagle-scientific-preamble.tex").to_string(),
            pandoc_template: Some(include_str!("../templates/beagle-scientific.latex").to_string()),
            recommended_for: vec![
                "General scientific papers".to_string(),
                "Research reports".to_string(),
                "Technical documentation".to_string(),
            ],
        })?;

        // Nature Style
        self.register_template(Template {
            name: "nature".to_string(),
            description: "Nature journal style (single-column, compact)".to_string(),
            style: "journal".to_string(),
            preamble: include_str!("../templates/nature-preamble.tex").to_string(),
            pandoc_template: Some(include_str!("../templates/nature.latex").to_string()),
            recommended_for: vec![
                "Nature journal submissions".to_string(),
                "High-impact papers".to_string(),
                "Concise reports".to_string(),
            ],
        })?;

        // IEEE Style
        self.register_template(Template {
            name: "ieee".to_string(),
            description: "IEEE two-column conference/journal style".to_string(),
            style: "conference".to_string(),
            preamble: include_str!("../templates/ieee-preamble.tex").to_string(),
            pandoc_template: Some(include_str!("../templates/ieee.latex").to_string()),
            recommended_for: vec![
                "IEEE conferences".to_string(),
                "Engineering papers".to_string(),
                "Technical articles".to_string(),
            ],
        })?;

        // arXiv Preprint
        self.register_template(Template {
            name: "arxiv".to_string(),
            description: "arXiv preprint style (clean, readable)".to_string(),
            style: "preprint".to_string(),
            preamble: include_str!("../templates/arxiv-preamble.tex").to_string(),
            pandoc_template: Some(include_str!("../templates/arxiv.latex").to_string()),
            recommended_for: vec![
                "arXiv preprints".to_string(),
                "Working papers".to_string(),
                "Draft versions".to_string(),
            ],
        })?;

        // Springer LNCS
        self.register_template(Template {
            name: "springer-lncs".to_string(),
            description: "Springer Lecture Notes in Computer Science".to_string(),
            style: "conference".to_string(),
            preamble: include_str!("../templates/springer-lncs-preamble.tex").to_string(),
            pandoc_template: None, // Uses standard Springer class
            recommended_for: vec![
                "Springer LNCS".to_string(),
                "Computer science conferences".to_string(),
            ],
        })?;

        // ACM
        self.register_template(Template {
            name: "acm".to_string(),
            description: "ACM proceedings style".to_string(),
            style: "conference".to_string(),
            preamble: include_str!("../templates/acm-preamble.tex").to_string(),
            pandoc_template: None,
            recommended_for: vec![
                "ACM conferences".to_string(),
                "Computer science papers".to_string(),
            ],
        })?;

        // Elsevier
        self.register_template(Template {
            name: "elsevier".to_string(),
            description: "Elsevier journal style".to_string(),
            style: "journal".to_string(),
            preamble: include_str!("../templates/elsevier-preamble.tex").to_string(),
            pandoc_template: None,
            recommended_for: vec![
                "Elsevier journals".to_string(),
                "Life sciences papers".to_string(),
            ],
        })?;

        // Minimal/Clean
        self.register_template(Template {
            name: "minimal".to_string(),
            description: "Minimal clean style for readability".to_string(),
            style: "minimal".to_string(),
            preamble: include_str!("../templates/minimal-preamble.tex").to_string(),
            pandoc_template: Some(include_str!("../templates/minimal.latex").to_string()),
            recommended_for: vec![
                "Internal documents".to_string(),
                "Draft versions".to_string(),
                "Quick reports".to_string(),
            ],
        })?;

        Ok(())
    }

    /// Register a template
    pub fn register_template(&mut self, template: Template) -> Result<()> {
        // Write template files to disk
        let template_path = self.template_dir.join(&template.name);
        std::fs::create_dir_all(&template_path)?;

        // Write preamble
        let preamble_path = template_path.join("preamble.tex");
        std::fs::write(&preamble_path, &template.preamble)?;

        // Write Pandoc template if provided
        if let Some(pandoc_template) = &template.pandoc_template {
            let template_file_path = template_path.join("template.latex");
            std::fs::write(&template_file_path, pandoc_template)?;
        }

        // Store in memory
        self.templates.insert(template.name.clone(), template);

        Ok(())
    }

    /// Get template by name
    pub fn get_template(&self, name: &str) -> Result<&Template> {
        self.templates
            .get(name)
            .ok_or_else(|| anyhow::anyhow!("Template not found: {}", name))
    }

    /// List all available templates
    pub fn list_templates(&self) -> Vec<String> {
        self.templates.keys().cloned().collect()
    }

    /// Get template path on disk
    pub fn get_template_path(&self, name: &str) -> PathBuf {
        self.template_dir.join(name)
    }
}

/// LaTeX template
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Template {
    pub name: String,
    pub description: String,
    pub style: String,
    pub preamble: String,
    pub pandoc_template: Option<String>,
    pub recommended_for: Vec<String>,
}

impl Template {
    /// Get preamble content
    pub fn get_preamble(&self) -> String {
        self.preamble.clone()
    }

    /// Get Pandoc template path if available
    pub fn get_pandoc_template_path(&self) -> Option<PathBuf> {
        if self.pandoc_template.is_some() {
            let template_dir = TemplateManager::get_template_directory().ok()?;
            Some(template_dir.join(&self.name).join("template.latex"))
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_template_manager_creation() {
        let manager = TemplateManager::new().unwrap();
        assert!(!manager.templates.is_empty());
    }

    #[test]
    fn test_builtin_templates() {
        let manager = TemplateManager::new().unwrap();

        // Check key templates exist
        assert!(manager.get_template("beagle-scientific").is_ok());
        assert!(manager.get_template("nature").is_ok());
        assert!(manager.get_template("ieee").is_ok());
        assert!(manager.get_template("arxiv").is_ok());
    }

    #[test]
    fn test_list_templates() {
        let manager = TemplateManager::new().unwrap();
        let templates = manager.list_templates();

        assert!(templates.contains(&"beagle-scientific".to_string()));
        assert!(templates.contains(&"nature".to_string()));
        assert!(templates.len() >= 8); // At least 8 built-in templates
    }
}
