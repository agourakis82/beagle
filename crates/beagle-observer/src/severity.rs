//! Observer 2.0 - Classificação de severidade

use serde::{Deserialize, Serialize};

/// Nível de severidade de um evento ou contexto
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    /// Informational - no action required
    Info = 0,
    /// Normal operation
    Normal = 1,
    /// Low severity - minor issue
    Low = 2,
    /// Mild deviation
    Mild = 3,
    /// Medium severity
    Medium = 4,
    /// Moderate - alert level
    Moderate = 5,
    /// High severity - needs attention
    High = 6,
    /// Warning - potential issue
    Warning = 7,
    /// Severe - serious event
    Severe = 8,
    /// Critical - immediate action required
    Critical = 9,
}

impl Severity {
    pub fn as_str(&self) -> &'static str {
        match self {
            Severity::Info => "Info",
            Severity::Normal => "Normal",
            Severity::Low => "Low",
            Severity::Mild => "Mild",
            Severity::Medium => "Medium",
            Severity::Moderate => "Moderate",
            Severity::High => "High",
            Severity::Warning => "Warning",
            Severity::Severe => "Severe",
            Severity::Critical => "Critical",
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

    /// Convert from numeric level (0-9)
    pub fn from_level(level: u8) -> Self {
        match level {
            0 => Severity::Info,
            1 => Severity::Normal,
            2 => Severity::Low,
            3 => Severity::Mild,
            4 => Severity::Medium,
            5 => Severity::Moderate,
            6 => Severity::High,
            7 => Severity::Warning,
            8 => Severity::Severe,
            _ => Severity::Critical,
        }
    }

    /// Convert to numeric level
    pub fn to_level(&self) -> u8 {
        *self as u8
    }
}

impl Default for Severity {
    fn default() -> Self {
        Severity::Normal
    }
}

/// Alias for Severity for compatibility
pub type SeverityLevel = Severity;
