//! Observer 2.0 - Classificação de severidade

use serde::{Deserialize, Serialize};

/// Nível de severidade de um evento ou contexto
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    Normal = 0,
    Mild = 1,     // desvio ligeiro
    Moderate = 2, // alerta
    Severe = 3,   // evento grave
}

impl Severity {
    pub fn as_str(&self) -> &'static str {
        match self {
            Severity::Normal => "Normal",
            Severity::Mild => "Mild",
            Severity::Moderate => "Moderate",
            Severity::Severe => "Severe",
        }
    }

    /// Retorna a severidade máxima entre duas severidades
    pub fn max(a: Severity, b: Severity) -> Severity {
        if a > b {
            a
        } else {
            b
        }
    }
}

impl Default for Severity {
    fn default() -> Self {
        Severity::Normal
    }
}
