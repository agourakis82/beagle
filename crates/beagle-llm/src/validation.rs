//! Validation Types – Tipos compartilhados para validação de conteúdo científico
//!
//! Este módulo contém tipos que são usados por múltiplos crates para evitar dependências circulares.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    pub citation_validity: CitationValidity,
    pub flow_score: f64,
    pub issues: Vec<Issue>,
    pub quality_score: f64,
    pub approved: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CitationValidity {
    pub completeness: f64,
    pub hallucinated: Vec<String>,
    pub missing: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Issue {
    pub issue_type: IssueType,
    pub description: String,
    pub severity: Severity,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum IssueType {
    UnsupportedClaim,
    MissingTransition,
    UnclearReference,
    GrammaticalError,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum Severity {
    Low,
    Medium,
    High,
}

