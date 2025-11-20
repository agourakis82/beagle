//! BEAGLE arXiv Validator - Valida papers antes de submeter
//! Checa LaTeX, references, figures, word count, categorias

use std::fs;
use std::process::Command;
use regex::Regex;
use tracing::{info, warn};
use anyhow::{Context, Result};

pub struct ArxivValidator;

impl ArxivValidator {
    pub fn new() -> Self {
        Self {}
    }
    
    /// Valida paper completo antes de submeter pro arXiv
    pub fn validate(&self, tex_path: &str) -> Result<Vec<String>> {
        info!("🔍 Validando paper pro arXiv — {}", tex_path);
        
        let mut errors = Vec::new();
        let content = fs::read_to_string(tex_path)
            .context("Falha ao ler arquivo LaTeX")?;
        
        // 1. Checa \documentclass
        if !content.contains(r"\documentclass") {
            errors.push("❌ Falta \\documentclass".to_string());
        }
        
        // 2. Checa abstract
        if !content.contains("\\begin{abstract}") && !content.contains("\\abstract{") {
            errors.push("❌ Falta abstract (\\begin{abstract} ou \\abstract{})".to_string());
        }
        
        // 3. Checa references (bibtex ou \bibitem)
        let has_bibliography = content.contains("\\bibliography") || 
                               content.contains("\\bibliographystyle") ||
                               content.contains("\\bibitem") ||
                               content.contains("\\cite{");
        
        if !has_bibliography {
            errors.push("⚠️  Nenhuma referência encontrada (arXiv prefere papers com referências)".to_string());
        }
        
        // 4. Checa figures (pelo menos 1)
        let has_figures = content.contains("\\includegraphics") ||
                         content.contains("\\begin{figure}") ||
                         content.contains("\\figure");
        
        if !has_figures {
            warn!("⚠️  Nenhuma figura encontrada (arXiv ama figura)");
            // Não é erro fatal, só aviso
        }
        
        // 5. Checa word count aproximado (remove comandos LaTeX)
        let word_count = estimate_word_count(&content);
        if word_count < 2000 {
            errors.push(format!("❌ Paper muito curto ({} palavras) — arXiv prefere >2000", word_count));
        }
        
        // 6. Checa categorias
        let has_categories = content.contains("\\category") || 
                            content.contains("arXiv:") ||
                            content.contains("cs.") ||
                            content.contains("q-bio.") ||
                            content.contains("physics.");
        
        if !has_categories {
            errors.push("⚠️  Adicione categorias (ex: cs.AI q-bio.NC physics.bio-ph)".to_string());
        }
        
        // 7. Checa se tem seções principais
        let has_sections = content.contains("\\section{") || 
                          content.contains("\\subsection{");
        
        if !has_sections {
            errors.push("❌ Paper não tem seções (\\section{})".to_string());
        }
        
        // 8. Compila LaTeX pra ver se quebra (opcional, só se pdflatex estiver disponível)
        if let Ok(output) = Command::new("pdflatex")
            .args(["-interaction=nonstopmode", tex_path])
            .output()
        {
            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                let stdout = String::from_utf8_lossy(&output.stdout);
                
                // Extrai erros principais
                let error_lines: Vec<&str> = stderr
                    .lines()
                    .chain(stdout.lines())
                    .filter(|line| line.contains("Error") || line.contains("Fatal"))
                    .take(5)
                    .collect();
                
                if !error_lines.is_empty() {
                    errors.push(format!("❌ LaTeX falhou: {}", error_lines.join("; ")));
                }
            } else {
                info!("✅ LaTeX compilou com sucesso");
            }
        } else {
            warn!("⚠️  pdflatex não disponível, pulando compilação");
        }
        
        if errors.is_empty() {
            info!("✅ PAPER VALIDADO 100% — PRONTO PRO ARXIV");
            Ok(vec!["VALIDADO".to_string()])
        } else {
            warn!("❌ Paper tem {} problemas pro arXiv", errors.len());
            Ok(errors)
        }
    }
    
    /// Valida markdown antes de converter para LaTeX
    pub fn validate_markdown(&self, markdown_path: &str) -> Result<Vec<String>> {
        info!("🔍 Validando markdown — {}", markdown_path);
        
        let mut errors = Vec::new();
        let content = fs::read_to_string(markdown_path)
            .context("Falha ao ler markdown")?;
        
        // 1. Checa título
        if !content.starts_with("# ") && !content.contains("\n# ") {
            errors.push("❌ Markdown não tem título (# Título)".to_string());
        }
        
        // 2. Checa abstract
        if !content.contains("## Abstract") && !content.contains("**Abstract**") {
            errors.push("❌ Markdown não tem abstract (## Abstract)".to_string());
        }
        
        // 3. Checa word count
        let word_count = content.split_whitespace().count();
        if word_count < 2000 {
            errors.push(format!("❌ Paper muito curto ({} palavras) — arXiv prefere >2000", word_count));
        }
        
        // 4. Checa seções
        let section_count = content.matches("\n## ").count();
        if section_count < 3 {
            errors.push(format!("❌ Paper tem poucas seções ({}) — arXiv prefere pelo menos 3", section_count));
        }
        
        if errors.is_empty() {
            info!("✅ Markdown validado");
            Ok(vec!["VALIDADO".to_string()])
        } else {
            warn!("❌ Markdown tem {} problemas", errors.len());
            Ok(errors)
        }
    }
}

/// Estima word count removendo comandos LaTeX
fn estimate_word_count(content: &str) -> usize {
    // Remove comandos LaTeX
    let re = Regex::new(r"\\[a-zA-Z]+\{[^}]*\}|\\[a-zA-Z]+").unwrap();
    let cleaned = re.replace_all(content, " ");
    
    // Conta palavras
    cleaned.split_whitespace().count()
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_word_count_estimation() {
        let tex = r#"\documentclass{article}
\title{Test Paper}
\begin{document}
This is a test paper with many words.
\end{document}"#;
        
        let count = estimate_word_count(tex);
        assert!(count > 0);
    }
}

