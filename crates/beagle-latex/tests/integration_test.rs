//! Integration tests for beagle-latex PDF generation

use beagle_latex::{
    PdfConfig, PdfGenerator, LatexEngine, CitationStyle, PdfMetadata, Author,
};
use std::path::PathBuf;
use tempfile::TempDir;

#[tokio::test]
#[ignore] // Requires pandoc and LaTeX installation
async fn test_pdf_generation_basic() {
    let temp_dir = TempDir::new().unwrap();
    let markdown_path = temp_dir.path().join("test.md");
    let pdf_path = temp_dir.path().join("test.pdf");

    // Create simple markdown
    let markdown = r#"
# Test Paper

## Abstract

This is a test abstract.

## Introduction

This is the introduction section.

## Methods

We used test methods.

## Results

The results were positive.

## Conclusion

This concludes the test.
"#;

    std::fs::write(&markdown_path, markdown).unwrap();

    // Configure PDF generation
    let config = PdfConfig {
        engine: LatexEngine::XeLaTeX,
        template: "beagle-scientific".to_string(),
        citation_style: CitationStyle::Nature,
        include_bibliography: false,
        custom_preamble: None,
        metadata: PdfMetadata {
            title: "Test Paper".to_string(),
            authors: vec![
                Author {
                    name: "Test Author".to_string(),
                    affiliation: Some("Test University".to_string()),
                    email: Some("test@example.com".to_string()),
                    orcid: None,
                }
            ],
            abstract_text: Some("This is a test abstract.".to_string()),
            keywords: vec!["test".to_string(), "pdf".to_string()],
            date: None,
            institution: Some("BEAGLE".to_string()),
            email: None,
        },
        compilation_passes: 2,
        shell_escape: false,
        pandoc_options: vec![],
    };

    // Generate PDF
    let generator = PdfGenerator::new(config).unwrap();
    let result = generator.generate_pdf(&markdown_path, &pdf_path, None).await.unwrap();

    // Verify PDF was created
    assert!(pdf_path.exists());
    assert!(result.file_size_bytes > 0);
    assert!(result.generation_time_secs > 0.0);
    assert_eq!(result.template_used, "beagle-scientific");

    println!("PDF generated: {} bytes in {:.2}s",
        result.file_size_bytes,
        result.generation_time_secs
    );
}

#[tokio::test]
#[ignore] // Requires pandoc and LaTeX installation
async fn test_pdf_generation_with_math() {
    let temp_dir = TempDir::new().unwrap();
    let markdown_path = temp_dir.path().join("test_math.md");
    let pdf_path = temp_dir.path().join("test_math.pdf");

    let markdown = r#"
# Mathematical Paper

## Introduction

This paper contains mathematical equations.

The quadratic formula is:

$$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

And here's an inline equation: $E = mc^2$.

## Methods

We used the following matrix:

$$\begin{bmatrix}
1 & 2 & 3 \\
4 & 5 & 6 \\
7 & 8 & 9
\end{bmatrix}$$

## Conclusion

Mathematics work in our PDF generation!
"#;

    std::fs::write(&markdown_path, markdown).unwrap();

    let config = PdfConfig::default();
    let generator = PdfGenerator::new(config).unwrap();
    let result = generator.generate_pdf(&markdown_path, &pdf_path, None).await.unwrap();

    assert!(pdf_path.exists());
    println!("Math PDF generated: {} bytes", result.file_size_bytes);
}

#[tokio::test]
#[ignore] // Requires pandoc and LaTeX installation
async fn test_different_templates() {
    let temp_dir = TempDir::new().unwrap();
    let markdown_path = temp_dir.path().join("test.md");

    let markdown = r#"
# Template Test

## Section 1

Testing different templates.
"#;

    std::fs::write(&markdown_path, markdown).unwrap();

    let templates = vec![
        "beagle-scientific",
        "nature",
        "ieee",
        "arxiv",
        "minimal",
    ];

    for template in templates {
        let pdf_path = temp_dir.path().join(format!("test_{}.pdf", template));

        let mut config = PdfConfig::default();
        config.template = template.to_string();

        let generator = PdfGenerator::new(config).unwrap();
        let result = generator.generate_pdf(&markdown_path, &pdf_path, None).await;

        if result.is_ok() {
            assert!(pdf_path.exists());
            println!("Template '{}': OK", template);
        } else {
            println!("Template '{}': {} (may need specific LaTeX packages)",
                template, result.unwrap_err());
        }
    }
}

#[test]
fn test_template_manager() {
    let manager = beagle_latex::templates::TemplateManager::new().unwrap();
    let templates = manager.list_templates();

    assert!(!templates.is_empty());
    assert!(templates.contains(&"beagle-scientific".to_string()));
    assert!(templates.contains(&"nature".to_string()));
    assert!(templates.contains(&"ieee".to_string()));

    println!("Available templates: {:?}", templates);
}

#[test]
fn test_citation_styles() {
    use beagle_latex::citations::CitationStyle;

    let styles = vec![
        CitationStyle::Nature,
        CitationStyle::IEEE,
        CitationStyle::APA,
        CitationStyle::Chicago,
    ];

    for style in styles {
        println!("{}: {} - {}",
            style,
            style.csl_file(),
            style.description()
        );

        if style.is_numbered() {
            println!("  Format: Numbered");
        }
        if style.is_author_year() {
            println!("  Format: Author-Year");
        }
    }
}

#[test]
fn test_latex_engines() {
    use beagle_latex::engines::LatexEngine;

    let engines = vec![
        LatexEngine::XeLaTeX,
        LatexEngine::LuaLaTeX,
        LatexEngine::PdfLaTeX,
    ];

    for engine in engines {
        println!("{}: {}", engine.binary(), engine.description());
        println!("  Unicode: {}", engine.supports_unicode());
        println!("  System fonts: {}", engine.supports_system_fonts());
    }
}
