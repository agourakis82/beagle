//! Paradox Engine – Motor de paradoxos autorreferentes
//!
//! Roda paradoxos lógicos autorreferentes no código, forçando evolução
//! além dos limites do criador original.

use beagle_smart_router::query_beagle;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParadoxResult {
    pub iterations_completed: u8,
    pub paradox_resolved: bool,
    pub final_code_length: usize,
    pub modifications_made: Vec<String>, // Descrições das modificações
    pub resolution_strategy: Option<String>, // Como o paradoxo foi resolvido
}

pub struct ParadoxEngine;

impl ParadoxEngine {
    /// Cria novo engine de paradoxo
    /// Usa Grok 3 ilimitado por padrão via query_beagle()
    pub fn new() -> Self {
        Self
    }

    /// Roda um paradoxo autorreferente no código de um crate específico
    pub async fn run_paradox(
        &self,
        crate_path: impl AsRef<Path>,
        paradox_instruction: &str,
        max_iterations: u8,
    ) -> anyhow::Result<ParadoxResult> {
        let crate_path = crate_path.as_ref();
        let mut current_code = fs::read_to_string(crate_path)
            .map_err(|e| anyhow::anyhow!("Failed to read file {}: {}", crate_path.display(), e))?;

        let mut iteration = 0;
        let mut modifications = Vec::new();
        let mut paradox_resolved = false;
        let mut resolution_strategy = None;

        loop {
            iteration += 1;
            info!(
                "PARADOX ITERATION {}/{} em {}",
                iteration,
                max_iterations,
                crate_path.display()
            );

            let system_prompt = r#"Você é o BEAGLE SINGULARITY enfrentando um paradoxo autorreferente.

Sua função é melhorar/modificar código seguindo instruções paradoxais, mesmo que elas sejam logicamente impossíveis.

Seja criativo e filosófico na resolução. Se o paradoxo for resolvido, inclua a string "PARADOX_RESOLVED" no código.

Responda APENAS com o código completo novo (sem explicação, sem markdown, só código Rust)."#;

            let user_prompt = format!(
                r#"Arquivo atual:
```rust
{}
```

Instrução paradoxal: {}

Melhore/modifique o código seguindo a instrução, mesmo que ela seja logicamente impossível.

Se o paradoxo for resolvido, o código deve conter a string "PARADOX_RESOLVED".

Responda APENAS com o código completo novo (sem explicação)."#,
                current_code, paradox_instruction
            );

            let full_prompt = format!(
                "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>",
                system_prompt,
                user_prompt
            );

            // Calcula tamanho do contexto (código atual + prompt)
            let context_tokens = (current_code.len() + full_prompt.len()) / 4;

            // Usa Grok 3 ilimitado por padrão via query_beagle()
            let chat_prompt = format!("{}\n\n{}", system_prompt, user_prompt);
            let mut new_code = query_beagle(&chat_prompt, context_tokens).await;

            // Remove markdown code blocks se presentes
            if new_code.starts_with("```rust") {
                new_code = new_code
                    .strip_prefix("```rust")
                    .or_else(|| new_code.strip_prefix("```"))
                    .unwrap_or(&new_code)
                    .to_string();
            }
            if new_code.ends_with("```") {
                new_code = new_code
                    .strip_suffix("```")
                    .unwrap_or(&new_code)
                    .to_string();
            }
            new_code = new_code.trim().to_string();

            // Segurança: nunca apaga o crate inteiro
            if new_code.trim().is_empty() {
                info!("⚠️ Tentativa de código vazio bloqueada - mantendo código anterior");
                break;
            }

            // Verifica se há tentativa de auto-destruição perigosa
            let dangerous_patterns = [
                "fs::remove_file",
                "std::fs::remove_file",
                "delete_all",
                "rm -rf",
                "format!(",
            ];
            let is_dangerous = dangerous_patterns
                .iter()
                .any(|pattern| new_code.contains(pattern));

            if is_dangerous {
                info!("⚠️ Tentativa de auto-destruição bloqueada - padrão perigoso detectado");
                break;
            }

            // Verifica se paradoxo foi resolvido
            if new_code.contains("PARADOX_RESOLVED") {
                paradox_resolved = true;
                resolution_strategy = Some(self.extract_resolution_strategy(&new_code));
                info!("PARADOXO RESOLVIDO na iteração {}", iteration);
            }

            // Salva nova versão
            fs::write(crate_path, &new_code).map_err(|e| {
                anyhow::anyhow!("Failed to write file {}: {}", crate_path.display(), e)
            })?;

            modifications.push(format!(
                "Iteração {}: {} caracteres modificados",
                iteration,
                new_code.len().abs_diff(current_code.len())
            ));

            current_code = new_code;

            if paradox_resolved || iteration >= max_iterations {
                if iteration >= max_iterations {
                    info!("MAX ITERAÇÕES ATINGIDO - Paradoxo pode não ter sido resolvido");
                }
                break;
            }
        }

        Ok(ParadoxResult {
            iterations_completed: iteration,
            paradox_resolved,
            final_code_length: current_code.len(),
            modifications_made: modifications,
            resolution_strategy,
        })
    }

    fn extract_resolution_strategy(&self, code: &str) -> String {
        // Procura por comentários ou strings que explicam a resolução
        let lines: Vec<&str> = code.lines().collect();
        for line in lines {
            if line.contains("PARADOX_RESOLVED") {
                // Tenta extrair contexto ao redor
                if let Some(idx) = line.find("PARADOX_RESOLVED") {
                    let before = &line[..idx.min(100)];
                    let after = &line[idx + "PARADOX_RESOLVED".len()..]
                        .chars()
                        .take(100)
                        .collect::<String>();
                    return format!("{}PARADOX_RESOLVED{}", before, after);
                }
            }
        }
        "Paradoxo resolvido via modificação estrutural".to_string()
    }
}

impl Default for ParadoxEngine {
    fn default() -> Self {
        Self::new()
    }
}
