use serde::{Deserialize, Serialize};

/// Modelos LLM disponíveis para roteamento dinâmico.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ModelChoice {
    ClaudeHaiku45,
    ClaudeSonnet45,
    Gemini15Pro,
    Auto,
}

impl Default for ModelChoice {
    fn default() -> Self {
        Self::Auto
    }
}

impl ModelChoice {
    /// Seleção heurística quando `model = "auto"`.
    pub fn auto_select(message: &str) -> Self {
        let msg_lower = message.to_lowercase();

        if msg_lower.contains("calcul")
            || msg_lower.contains("matemática")
            || msg_lower.contains("derivada")
            || msg_lower.contains("integral")
        {
            return Self::Gemini15Pro;
        }

        if msg_lower.contains("explique detalhadamente")
            || msg_lower.contains("filosofia")
            || message.len() > 500
        {
            return Self::ClaudeSonnet45;
        }

        Self::ClaudeHaiku45
    }
}
