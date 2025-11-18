//! BEAGLE Configuration - Centralized path management
//!
//! Todos os paths do BEAGLE são gerenciados centralmente aqui.
//! Usa ~/beagle-data/ por padrão, mas pode ser configurado via BEAGLE_DATA_DIR.

use std::path::PathBuf;

/// Obtém o diretório base de dados do BEAGLE
///
/// Ordem de prioridade:
/// 1. Variável de ambiente BEAGLE_DATA_DIR
/// 2. Arquivo .beagle-data-path no repo
/// 3. ~/beagle-data (padrão)
pub fn beagle_data_dir() -> PathBuf {
    // 1. Tenta variável de ambiente
    if let Ok(dir) = std::env::var("BEAGLE_DATA_DIR") {
        return PathBuf::from(dir);
    }

    // 2. Tenta arquivo .beagle-data-path no repo
    let repo_root = find_repo_root();
    if let Some(repo_root) = repo_root {
        let config_file = repo_root.join(".beagle-data-path");
        if let Ok(contents) = std::fs::read_to_string(&config_file) {
            for line in contents.lines() {
                if let Some(value) = line.strip_prefix("BEAGLE_DATA_DIR=") {
                    return PathBuf::from(value.trim());
                }
            }
        }
    }

    // 3. Padrão: ~/beagle-data
    dirs::home_dir()
        .map(|h| h.join("beagle-data"))
        .unwrap_or_else(|| PathBuf::from("beagle-data"))
}

fn find_repo_root() -> Option<PathBuf> {
    let mut current = std::env::current_dir().ok()?;

    loop {
        let git_dir = current.join(".git");
        let cargo_toml = current.join("Cargo.toml");

        if git_dir.exists() || cargo_toml.exists() {
            return Some(current);
        }

        if !current.pop() {
            break;
        }
    }

    None
}

/// Path para modelos LLM
pub fn models_dir() -> PathBuf {
    beagle_data_dir().join("models")
}

/// Path para LoRA adapters
pub fn lora_dir() -> PathBuf {
    beagle_data_dir().join("lora")
}

/// Path para PostgreSQL data
pub fn postgres_dir() -> PathBuf {
    beagle_data_dir().join("postgres")
}

/// Path para Qdrant data
pub fn qdrant_dir() -> PathBuf {
    beagle_data_dir().join("qdrant")
}

/// Path para Redis data
pub fn redis_dir() -> PathBuf {
    beagle_data_dir().join("redis")
}

/// Path para Neo4j data
pub fn neo4j_dir() -> PathBuf {
    beagle_data_dir().join("neo4j")
}

/// Path para logs
pub fn logs_dir() -> PathBuf {
    beagle_data_dir().join("logs")
}

/// Path para drafts de papers
pub fn papers_drafts_dir() -> PathBuf {
    beagle_data_dir().join("papers").join("drafts")
}

/// Path para papers finais
pub fn papers_final_dir() -> PathBuf {
    beagle_data_dir().join("papers").join("final")
}

/// Path para embeddings cache
pub fn embeddings_dir() -> PathBuf {
    beagle_data_dir().join("embeddings")
}

/// Path para datasets
pub fn datasets_dir() -> PathBuf {
    beagle_data_dir().join("datasets")
}

/// Garante que todos os diretórios necessários existem
pub fn ensure_dirs() -> std::io::Result<()> {
    let dirs = vec![
        models_dir(),
        lora_dir(),
        postgres_dir(),
        qdrant_dir(),
        redis_dir(),
        neo4j_dir(),
        logs_dir(),
        papers_drafts_dir(),
        papers_final_dir(),
        embeddings_dir(),
        datasets_dir(),
    ];

    for dir in dirs {
        std::fs::create_dir_all(&dir)?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_beagle_data_dir() {
        let dir = beagle_data_dir();
        assert!(dir.to_string_lossy().contains("beagle-data"));
    }

    #[test]
    fn test_paths_exist() {
        // Só testa que as funções retornam paths válidos
        let _ = models_dir();
        let _ = lora_dir();
        let _ = logs_dir();
    }
}

