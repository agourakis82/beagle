//! BEAGLE LaTeX + Pandoc PDF Generation System
//!
//! Production-grade PDF generation with:
//! - Multiple LaTeX engines (XeLaTeX, LuaLaTeX, pdfLaTeX)
//! - Comprehensive template database
//! - Bibliography and citation support
//! - Custom styling and branding
//! - Multi-pass compilation for references
//!
//! # Architecture
//!
//! ```text
//! Markdown → Pandoc → LaTeX → [XeLaTeX/LuaLaTeX/pdfLaTeX] → PDF
//!                ↓
//!            Templates
//!            ↓
//!         - Nature style
//!         - IEEE style
//!         - arXiv preprint
//!         - BEAGLE custom
//! ```

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use tempfile::TempDir;
use tracing::{debug, error, info, warn};

pub mod templates;
pub mod engines;
pub mod citations;

pub use templates::{Template, TemplateManager};
pub use engines::{LatexEngine, PandocOptions};
pub use citations::{Bibliography, CitationStyle};

/// PDF generation configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PdfConfig {
    /// LaTeX engine to use
    pub engine: LatexEngine,

    /// Template style
    pub template: String,

    /// Citation style (apa, ieee, nature, chicago, vancouver)
    pub citation_style: CitationStyle,

    /// Enable bibliography generation
    pub include_bibliography: bool,

    /// Custom LaTeX preamble
    pub custom_preamble: Option<String>,

    /// PDF metadata
    pub metadata: PdfMetadata,

    /// Number of compilation passes (for references)
    pub compilation_passes: u8,

    /// Enable shell escape (for TikZ, minted, etc.)
    pub shell_escape: bool,

    /// Additional Pandoc options
    pub pandoc_options: Vec<String>,
}

impl Default for PdfConfig {
    fn default() -> Self {
        Self {
            engine: LatexEngine::XeLaTeX,
            template: "beagle-scientific".to_string(),
            citation_style: CitationStyle::Nature,
            include_bibliography: true,
            custom_preamble: None,
            metadata: PdfMetadata::default(),
            compilation_passes: 2,
            shell_escape: false,
            pandoc_options: vec![],
        }
    }
}

/// PDF metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PdfMetadata {
    pub title: String,
    pub authors: Vec<Author>,
    pub abstract_text: Option<String>,
    pub keywords: Vec<String>,
    pub date: Option<chrono::NaiveDate>,
    pub institution: Option<String>,
    pub email: Option<String>,
}

impl Default for PdfMetadata {
    fn default() -> Self {
        Self {
            title: "Untitled".to_string(),
            authors: vec![],
            abstract_text: None,
            keywords: vec![],
            date: None,
            institution: None,
            email: None,
        }
    }
}

/// Author information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Author {
    pub name: String,
    pub affiliation: Option<String>,
    pub email: Option<String>,
    pub orcid: Option<String>,
}

/// PDF generator with template support
pub struct PdfGenerator {
    template_manager: TemplateManager,
    pandoc_path: PathBuf,
    config: PdfConfig,
}

impl PdfGenerator {
    /// Create new PDF generator
    pub fn new(config: PdfConfig) -> Result<Self> {
        // Verify pandoc is available
        let pandoc_path = which::which("pandoc")
            .context("Pandoc not found in PATH. Install with: apt install pandoc")?;

        info!("Found pandoc at: {}", pandoc_path.display());

        // Verify LaTeX engine is available
        let engine_binary = config.engine.binary();
        which::which(engine_binary)
            .with_context(|| format!(
                "LaTeX engine '{}' not found. Install with: apt install texlive-full",
                engine_binary
            ))?;

        let template_manager = TemplateManager::new()?;

        Ok(Self {
            template_manager,
            pandoc_path,
            config,
        })
    }

    /// Generate PDF from markdown
    pub async fn generate_pdf(
        &self,
        markdown_path: &Path,
        output_pdf_path: &Path,
        bibliography_path: Option<&Path>,
    ) -> Result<PdfGenerationResult> {
        info!("Generating PDF: {} → {}",
            markdown_path.display(),
            output_pdf_path.display()
        );

        // Create temporary directory for intermediate files
        let temp_dir = TempDir::new()
            .context("Failed to create temporary directory")?;
        let temp_path = temp_dir.path();

        debug!("Using temporary directory: {}", temp_path.display());

        // Load template
        let template = self.template_manager.get_template(&self.config.template)?;

        // Generate LaTeX preamble
        let preamble = self.generate_preamble(&template)?;
        let preamble_path = temp_path.join("preamble.tex");
        std::fs::write(&preamble_path, preamble)?;

        // Prepare Pandoc command
        let mut cmd = Command::new(&self.pandoc_path);

        // Input
        cmd.arg(markdown_path);

        // Output
        cmd.arg("-o").arg(output_pdf_path);

        // LaTeX engine
        cmd.arg(&format!("--pdf-engine={}", self.config.engine.binary()));

        // Template
        if let Some(template_path) = template.get_pandoc_template_path() {
            cmd.arg(&format!("--template={}", template_path.display()));
        }

        // Include preamble
        cmd.arg(&format!("--include-in-header={}", preamble_path.display()));

        // Citation processing
        if self.config.include_bibliography {
            if let Some(bib_path) = bibliography_path {
                cmd.arg(&format!("--bibliography={}", bib_path.display()));
                cmd.arg(&format!("--csl={}", self.config.citation_style.csl_file()));
                cmd.arg("--citeproc");
            }
        }

        // Metadata
        self.add_metadata_args(&mut cmd)?;

        // Additional options
        cmd.arg("--number-sections");
        cmd.arg("--toc");
        cmd.arg("--toc-depth=3");
        cmd.arg("--highlight-style=tango");

        // Shell escape for advanced features
        if self.config.shell_escape {
            cmd.arg("--pdf-engine-opt=-shell-escape");
        }

        // Custom options
        for opt in &self.config.pandoc_options {
            cmd.arg(opt);
        }

        // Set working directory to temp
        cmd.current_dir(temp_path);

        debug!("Pandoc command: {:?}", cmd);

        // Execute Pandoc
        let start_time = std::time::Instant::now();

        let output = cmd.output()
            .context("Failed to execute pandoc")?;

        let elapsed = start_time.elapsed();

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            error!("Pandoc failed: {}", stderr);
            anyhow::bail!("PDF generation failed: {}", stderr);
        }

        // Get PDF file size
        let pdf_size = std::fs::metadata(output_pdf_path)
            .context("Failed to read PDF metadata")?
            .len();

        info!(
            "PDF generated successfully: {} bytes in {:.2}s",
            pdf_size,
            elapsed.as_secs_f64()
        );

        Ok(PdfGenerationResult {
            output_path: output_pdf_path.to_path_buf(),
            file_size_bytes: pdf_size,
            generation_time_secs: elapsed.as_secs_f64(),
            template_used: self.config.template.clone(),
            engine_used: self.config.engine.clone(),
        })
    }

    /// Generate LaTeX preamble with custom styling
    fn generate_preamble(&self, template: &Template) -> Result<String> {
        let mut preamble = String::new();

        // Base packages
        preamble.push_str(r#"
% BEAGLE LaTeX Preamble - Production Grade
\usepackage{graphicx}
\usepackage{longtable}
\usepackage{booktabs}
\usepackage{array}
\usepackage{multirow}
\usepackage{wrapfig}
\usepackage{float}
\usepackage{colortbl}
\usepackage{pdflscape}
\usepackage{tabu}
\usepackage{threeparttable}
\usepackage{threeparttablex}
\usepackage[normalem]{ulem}
\usepackage{makecell}
\usepackage{xcolor}

% Math support
\usepackage{amsmath}
\usepackage{amssymb}
\usepackage{amsthm}
\usepackage{mathtools}

% Code listings
\usepackage{listings}
\usepackage{fancyvrb}

% References and links
\usepackage{hyperref}
\hypersetup{
    colorlinks=true,
    linkcolor=blue,
    filecolor=magenta,
    urlcolor=cyan,
    citecolor=green,
}

% Typography
\usepackage{microtype}
\usepackage{setspace}

% Headers and footers
\usepackage{fancyhdr}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\leftmark}
\fancyhead[R]{\thepage}
\renewcommand{\headrulewidth}{0.4pt}

% Custom colors
\definecolor{beagleblue}{RGB}{0,102,204}
\definecolor{beaglegray}{RGB}{128,128,128}

% Theorem environments
\theoremstyle{definition}
\newtheorem{definition}{Definition}[section]
\newtheorem{theorem}{Theorem}[section]
\newtheorem{lemma}[theorem]{Lemma}
\newtheorem{corollary}[theorem]{Corollary}
\newtheorem{proposition}[theorem]{Proposition}

% Custom commands
\newcommand{\beagle}{\textcolor{beagleblue}{\textbf{BEAGLE}}}
"#);

        // Template-specific additions
        preamble.push_str(&template.get_preamble());

        // Custom user preamble
        if let Some(custom) = &self.config.custom_preamble {
            preamble.push_str("\n% Custom User Preamble\n");
            preamble.push_str(custom);
        }

        Ok(preamble)
    }

    /// Add metadata to Pandoc command
    fn add_metadata_args(&self, cmd: &mut Command) -> Result<()> {
        let meta = &self.config.metadata;

        cmd.arg(&format!("--metadata=title:{}", meta.title));

        // Authors
        for author in &meta.authors {
            cmd.arg(&format!("--metadata=author:{}", author.name));
        }

        // Date
        if let Some(date) = &meta.date {
            cmd.arg(&format!("--metadata=date:{}", date.format("%Y-%m-%d")));
        } else {
            cmd.arg(&format!("--metadata=date:{}", chrono::Local::now().format("%Y-%m-%d")));
        }

        // Keywords
        if !meta.keywords.is_empty() {
            let keywords = meta.keywords.join(", ");
            cmd.arg(&format!("--metadata=keywords:{}", keywords));
        }

        // Abstract
        if let Some(abstract_text) = &meta.abstract_text {
            cmd.arg(&format!("--metadata=abstract:{}", abstract_text));
        }

        Ok(())
    }

    /// Get available templates
    pub fn list_templates(&self) -> Vec<String> {
        self.template_manager.list_templates()
    }

    /// Get template information
    pub fn get_template_info(&self, name: &str) -> Result<TemplateInfo> {
        let template = self.template_manager.get_template(name)?;
        Ok(TemplateInfo {
            name: template.name.clone(),
            description: template.description.clone(),
            style: template.style.clone(),
            recommended_for: template.recommended_for.clone(),
        })
    }
}

/// PDF generation result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PdfGenerationResult {
    pub output_path: PathBuf,
    pub file_size_bytes: u64,
    pub generation_time_secs: f64,
    pub template_used: String,
    pub engine_used: LatexEngine,
}

/// Template information for display
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateInfo {
    pub name: String,
    pub description: String,
    pub style: String,
    pub recommended_for: Vec<String>,
}

/// Error types
#[derive(Debug, thiserror::Error)]
pub enum LatexError {
    #[error("Pandoc not found: {0}")]
    PandocNotFound(String),

    #[error("LaTeX engine not found: {0}")]
    EngineNotFound(String),

    #[error("Template not found: {0}")]
    TemplateNotFound(String),

    #[error("Compilation failed: {0}")]
    CompilationFailed(String),

    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pdf_config_default() {
        let config = PdfConfig::default();
        assert_eq!(config.compilation_passes, 2);
        assert_eq!(config.template, "beagle-scientific");
    }

    #[test]
    fn test_metadata_default() {
        let meta = PdfMetadata::default();
        assert_eq!(meta.title, "Untitled");
        assert!(meta.authors.is_empty());
    }
}
