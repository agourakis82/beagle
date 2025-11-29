//! LaTeX Engine Support
//!
//! Multiple LaTeX engines with different capabilities:
//! - XeLaTeX: Unicode support, modern fonts (recommended)
//! - LuaLaTeX: Lua scripting, advanced typography
//! - pdfLaTeX: Classic, fastest compilation
//! - LaTeXmk: Automatic multi-pass compilation

use serde::{Deserialize, Serialize};

/// LaTeX compilation engine
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum LatexEngine {
    /// XeLaTeX - Unicode and modern font support (recommended)
    XeLaTeX,

    /// LuaLaTeX - Lua scripting and advanced typography
    LuaLaTeX,

    /// pdfLaTeX - Classic LaTeX engine (fastest)
    PdfLaTeX,

    /// LaTeXmk - Automatic multi-pass compilation manager
    LaTeXmk,
}

impl LatexEngine {
    /// Get binary name for this engine
    pub fn binary(&self) -> &str {
        match self {
            Self::XeLaTeX => "xelatex",
            Self::LuaLaTeX => "lualatex",
            Self::PdfLaTeX => "pdflatex",
            Self::LaTeXmk => "latexmk",
        }
    }

    /// Get description of engine capabilities
    pub fn description(&self) -> &str {
        match self {
            Self::XeLaTeX => "Unicode support, system fonts, excellent for international text",
            Self::LuaLaTeX => "Lua scripting, advanced typography, complex layouts",
            Self::PdfLaTeX => "Classic engine, fastest compilation, widest compatibility",
            Self::LaTeXmk => "Automatic compilation manager, handles references and citations",
        }
    }

    /// Check if engine supports Unicode
    pub fn supports_unicode(&self) -> bool {
        matches!(self, Self::XeLaTeX | Self::LuaLaTeX)
    }

    /// Check if engine supports system fonts
    pub fn supports_system_fonts(&self) -> bool {
        matches!(self, Self::XeLaTeX | Self::LuaLaTeX)
    }

    /// Get recommended for use cases
    pub fn recommended_for(&self) -> Vec<&str> {
        match self {
            Self::XeLaTeX => vec![
                "Modern documents",
                "International text",
                "Custom fonts",
                "General use (recommended default)",
            ],
            Self::LuaLaTeX => vec![
                "Complex typography",
                "Advanced layouts",
                "Lua scripting",
                "Large documents",
            ],
            Self::PdfLaTeX => vec![
                "Legacy documents",
                "Fast compilation",
                "Maximum compatibility",
                "Simple documents",
            ],
            Self::LaTeXmk => vec![
                "Multi-pass compilation",
                "Automatic reference handling",
                "Bibliography management",
                "Production builds",
            ],
        }
    }
}

impl std::fmt::Display for LatexEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.binary())
    }
}

impl Default for LatexEngine {
    fn default() -> Self {
        Self::XeLaTeX
    }
}

/// Pandoc-specific options
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PandocOptions {
    /// Enable table of contents
    pub toc: bool,

    /// TOC depth (1-6)
    pub toc_depth: u8,

    /// Enable section numbering
    pub number_sections: bool,

    /// Syntax highlighting style
    pub highlight_style: HighlightStyle,

    /// Enable standalone document
    pub standalone: bool,

    /// Top-level heading level
    pub top_level_division: TopLevelDivision,

    /// Variables to pass to template
    pub variables: Vec<(String, String)>,
}

/// Syntax highlighting styles
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum HighlightStyle {
    Pygments,
    Tango,
    Espresso,
    Zenburn,
    Kate,
    Monochrome,
    Breezedark,
    Haddock,
}

impl Default for HighlightStyle {
    fn default() -> Self {
        Self::Tango
    }
}

impl std::fmt::Display for HighlightStyle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let name = match self {
            Self::Pygments => "pygments",
            Self::Tango => "tango",
            Self::Espresso => "espresso",
            Self::Zenburn => "zenburn",
            Self::Kate => "kate",
            Self::Monochrome => "monochrome",
            Self::Breezedark => "breezedark",
            Self::Haddock => "haddock",
        };
        write!(f, "{}", name)
    }
}

/// Top-level document division
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum TopLevelDivision {
    /// Default (let Pandoc decide)
    Default,

    /// Sections
    Section,

    /// Chapters
    Chapter,

    /// Parts
    Part,
}

impl Default for TopLevelDivision {
    fn default() -> Self {
        Self::Default
    }
}

impl std::fmt::Display for TopLevelDivision {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let name = match self {
            Self::Default => "default",
            Self::Section => "section",
            Self::Chapter => "chapter",
            Self::Part => "part",
        };
        write!(f, "{}", name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_binary_names() {
        assert_eq!(LatexEngine::XeLaTeX.binary(), "xelatex");
        assert_eq!(LatexEngine::LuaLaTeX.binary(), "lualatex");
        assert_eq!(LatexEngine::PdfLaTeX.binary(), "pdflatex");
        assert_eq!(LatexEngine::LaTeXmk.binary(), "latexmk");
    }

    #[test]
    fn test_unicode_support() {
        assert!(LatexEngine::XeLaTeX.supports_unicode());
        assert!(LatexEngine::LuaLaTeX.supports_unicode());
        assert!(!LatexEngine::PdfLaTeX.supports_unicode());
    }

    #[test]
    fn test_default_engine() {
        let engine = LatexEngine::default();
        assert_eq!(engine, LatexEngine::XeLaTeX);
    }

    #[test]
    fn test_highlight_style_display() {
        assert_eq!(HighlightStyle::Tango.to_string(), "tango");
        assert_eq!(HighlightStyle::Pygments.to_string(), "pygments");
    }
}
