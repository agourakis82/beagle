use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;

/// Metadados do profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileMetadata {
    pub domain: String,
    pub name: String,
    pub version: String,
}

/// Configuração do system prompt principal
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemPromptConfig {
    pub role: String,
    pub tone: String,
    pub depth: String,
}

/// Diretrizes editoriais e de segurança
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Guidelines {
    pub always_include: Vec<String>,
    pub avoid: Vec<String>,

    #[serde(default)]
    pub language_style: Option<String>,

    #[serde(default)]
    pub code_style: Option<String>,

    #[serde(default)]
    pub disclaimers: Vec<String>,

    #[serde(default)]
    pub safety_priorities: Vec<String>,
}

/// Profile completo carregado de TOML
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    pub profile: ProfileMetadata,
    pub system_prompt: SystemPromptConfig,
    pub guidelines: Guidelines,

    #[serde(default)]
    pub examples: HashMap<String, String>,

    #[serde(default)]
    pub clinical_approach: Option<Value>,

    #[serde(default)]
    pub psychopharmacology: Option<Value>,

    #[serde(default)]
    pub disclaimers: Option<HashMap<String, String>>,
}

impl Profile {
    /// Carrega profile a partir de string TOML
    pub fn from_toml(toml_str: &str) -> Result<Self, toml::de::Error> {
        toml::from_str(toml_str)
    }

    /// Constrói system prompt completo para LLM
    pub fn build_system_prompt(&self) -> String {
        let mut prompt = String::new();

        // Role
        prompt.push_str(&self.system_prompt.role);
        prompt.push_str("\n\n");

        // Tone e profundidade
        prompt.push_str(&format!(
            "Tone: {}\nDepth: {}\n\n",
            self.system_prompt.tone, self.system_prompt.depth
        ));

        // Diretrizes obrigatórias
        if !self.guidelines.always_include.is_empty() {
            prompt.push_str("Always include:\n");
            for item in &self.guidelines.always_include {
                prompt.push_str(&format!("- {}\n", item));
            }
            prompt.push('\n');
        }

        if !self.guidelines.avoid.is_empty() {
            prompt.push_str("Avoid:\n");
            for item in &self.guidelines.avoid {
                prompt.push_str(&format!("- {}\n", item));
            }
            prompt.push('\n');
        }

        // Estilo de linguagem / código
        if let Some(ref style) = self.guidelines.language_style {
            prompt.push_str(&format!("Language style: {}\n\n", style));
        }

        if let Some(ref style) = self.guidelines.code_style {
            prompt.push_str(&format!("Code style: {}\n\n", style));
        }

        // Prioridades de segurança
        if !self.guidelines.safety_priorities.is_empty() {
            prompt.push_str("Safety priorities:\n");
            for item in &self.guidelines.safety_priorities {
                prompt.push_str(&format!("- {}\n", item));
            }
            prompt.push('\n');
        }

        // Disclaimers das diretrizes
        if !self.guidelines.disclaimers.is_empty() {
            prompt.push_str("Important disclaimers:\n");
            for item in &self.guidelines.disclaimers {
                prompt.push_str(&format!("- {}\n", item));
            }
            prompt.push('\n');
        }

        // Disclaimers adicionais (mapa)
        if let Some(extra) = &self.disclaimers {
            if !extra.is_empty() {
                prompt.push_str("Additional disclaimers:\n");
                for (key, value) in extra {
                    prompt.push_str(&format!("- {}: {}\n", key, value));
                }
            }
        }

        prompt
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_minimal_profile() {
        let toml = r#"
[profile]
domain = "Test"
name = "Test Profile"
version = "1.0"

[system_prompt]
role = "You are a test assistant"
tone = "friendly"
depth = "moderate"

[guidelines]
always_include = ["Be helpful"]
avoid = ["Be rude"]
        "#;

        let profile = Profile::from_toml(toml).unwrap();
        assert_eq!(profile.profile.domain, "Test");

        let system_prompt = profile.build_system_prompt();
        assert!(system_prompt.contains("You are a test assistant"));
        assert!(system_prompt.contains("Be helpful"));
    }
}
