//! Self Modifier – Auto-modificador de código
//!
//! Modifica código de forma controlada, com validação e salvaguardas.

use std::fs;
use std::path::{Path, PathBuf};
use tracing::{info, warn};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModificationReport {
    pub file_path: PathBuf,
    pub modification_successful: bool,
    pub code_length_before: usize,
    pub code_length_after: usize,
    pub changes_made: Vec<String>,
    pub validation_passed: bool,
}

pub struct SelfModifier;

impl SelfModifier {
    pub fn new() -> Self {
        Self
    }

    /// Valida se o código Rust é sintaticamente válido (básico)
    pub fn validate_rust_code(&self, code: &str) -> bool {
        // Validações básicas
        if code.trim().is_empty() {
            return false;
        }

        // Verifica se tem pelo menos uma estrutura básica Rust
        let has_rust_structure = code.contains("pub") || code.contains("fn") || code.contains("struct");

        // Verifica se não tem padrões perigosos
        let dangerous = code.contains("unsafe {") && code.contains("std::ptr::null_mut()");

        has_rust_structure && !dangerous
    }

    /// Cria backup do arquivo antes de modificar
    pub fn create_backup(&self, file_path: impl AsRef<Path>) -> anyhow::Result<PathBuf> {
        let file_path = file_path.as_ref();
        let backup_path = file_path.with_extension(format!(
            "{}.backup",
            file_path.extension().and_then(|s| s.to_str()).unwrap_or("rs")
        ));

        if file_path.exists() {
            fs::copy(file_path, &backup_path)?;
            info!("Backup criado: {:?}", backup_path);
        }

        Ok(backup_path)
    }

    /// Aplica modificação com validação
    pub fn apply_modification(
        &self,
        file_path: impl AsRef<Path>,
        new_code: &str,
    ) -> anyhow::Result<ModificationReport> {
        let file_path = file_path.as_ref();

        // Valida código
        if !self.validate_rust_code(new_code) {
            anyhow::bail!("Código não passou na validação");
        }

        // Lê código anterior
        let code_before = if file_path.exists() {
            fs::read_to_string(file_path).unwrap_or_default()
        } else {
            String::new()
        };

        // Cria backup
        let _backup = self.create_backup(file_path)?;

        // Escreve novo código
        fs::write(file_path, new_code)?;

        // Identifica mudanças
        let changes = self.identify_changes(&code_before, new_code);

        Ok(ModificationReport {
            file_path: file_path.to_path_buf(),
            modification_successful: true,
            code_length_before: code_before.len(),
            code_length_after: new_code.len(),
            changes_made: changes,
            validation_passed: true,
        })
    }

    fn identify_changes(&self, before: &str, after: &str) -> Vec<String> {
        let mut changes = Vec::new();

        if before.len() != after.len() {
            changes.push(format!(
                "Tamanho: {} → {} caracteres",
                before.len(),
                after.len()
            ));
        }

        let lines_before: Vec<&str> = before.lines().collect();
        let lines_after: Vec<&str> = after.lines().collect();

        if lines_before.len() != lines_after.len() {
            changes.push(format!(
                "Linhas: {} → {}",
                lines_before.len(),
                lines_after.len()
            ));
        }

        // Detecta novas funções
        let functions_before: Vec<&str> = before
            .lines()
            .filter(|l| l.trim().starts_with("pub fn") || l.trim().starts_with("fn"))
            .collect();
        let functions_after: Vec<&str> = after
            .lines()
            .filter(|l| l.trim().starts_with("pub fn") || l.trim().starts_with("fn"))
            .collect();

        if functions_before.len() != functions_after.len() {
            changes.push(format!(
                "Funções: {} → {}",
                functions_before.len(),
                functions_after.len()
            ));
        }

        if changes.is_empty() {
            changes.push("Modificações estruturais detectadas".to_string());
        }

        changes
    }
}

impl Default for SelfModifier {
    fn default() -> Self {
        Self::new()
    }
}




