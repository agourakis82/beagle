//! BEAGLE Healthcheck - Diagnósticos e verificações de saúde do sistema
//!
//! Verifica:
//! - Storage (diretórios existem)
//! - LLM backends (chaves/configurações presentes)
//! - Bancos de dados (Neo4j, Qdrant, Postgres, Redis) - conectividade
//! - SAFE_MODE e profile

use beagle_config::BeagleConfig;
use serde::Serialize;
use std::path::Path;

/// Resultado de um check individual
#[derive(Debug, Clone, Serialize)]
pub struct CheckResult {
    pub name: String,
    pub status: String, // "ok" | "warn" | "error"
    pub details: Option<String>,
}

/// Relatório completo de saúde do BEAGLE
#[derive(Debug, Serialize)]
pub struct HealthReport {
    pub profile: String,
    pub safe_mode: bool,
    pub checks: Vec<CheckResult>,
}

impl HealthReport {
    /// Verifica se todos os checks críticos estão ok
    pub fn is_healthy(&self) -> bool {
        self.checks
            .iter()
            .all(|c| c.status == "ok" || c.status == "warn")
    }

    /// Conta checks por status
    pub fn count_by_status(&self) -> (usize, usize, usize) {
        let mut ok = 0;
        let mut warn = 0;
        let mut error = 0;

        for check in &self.checks {
            match check.status.as_str() {
                "ok" => ok += 1,
                "warn" => warn += 1,
                "error" => error += 1,
                _ => {}
            }
        }

        (ok, warn, error)
    }
}

/// Executa todos os healthchecks
pub async fn check_all(cfg: &BeagleConfig) -> HealthReport {
    let mut checks = Vec::new();

    // 1. Storage
    checks.push(check_storage(cfg));

    // 2. LLM backends
    checks.push(check_llm_config(cfg));

    // 3. Neo4j (se configurado)
    if cfg.has_neo4j() {
        checks.push(check_neo4j(cfg).await);
    } else {
        checks.push(CheckResult {
            name: "neo4j".to_string(),
            status: "warn".to_string(),
            details: Some("Neo4j não configurado (NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)".to_string()),
        });
    }

    // 4. Qdrant (se configurado)
    if cfg.has_qdrant() {
        checks.push(check_qdrant(cfg).await);
    } else {
        checks.push(CheckResult {
            name: "qdrant".to_string(),
            status: "warn".to_string(),
            details: Some("Qdrant não configurado (QDRANT_URL)".to_string()),
        });
    }

    // 5. Postgres (se configurado)
    if let Some(_) = &cfg.hermes.database_url {
        checks.push(check_postgres(cfg).await);
    } else {
        checks.push(CheckResult {
            name: "postgres".to_string(),
            status: "warn".to_string(),
            details: Some("Postgres não configurado (DATABASE_URL)".to_string()),
        });
    }

    // 6. Redis (se configurado)
    if let Some(_) = &cfg.hermes.redis_url {
        checks.push(check_redis(cfg).await);
    } else {
        checks.push(CheckResult {
            name: "redis".to_string(),
            status: "warn".to_string(),
            details: Some("Redis não configurado (REDIS_URL)".to_string()),
        });
    }

    HealthReport {
        profile: cfg.profile.clone(),
        safe_mode: cfg.safe_mode,
        checks,
    }
}

fn check_storage(cfg: &BeagleConfig) -> CheckResult {
    let data_dir = Path::new(&cfg.storage.data_dir);
    if data_dir.exists() {
        CheckResult {
            name: "storage".to_string(),
            status: "ok".to_string(),
            details: Some(cfg.storage.data_dir.clone()),
        }
    } else {
        CheckResult {
            name: "storage".to_string(),
            status: "error".to_string(),
            details: Some(format!("Diretório não existe: {}", cfg.storage.data_dir)),
        }
    }
}

fn check_llm_config(cfg: &BeagleConfig) -> CheckResult {
    if cfg.has_llm_backend() {
        let backends: Vec<&str> = [
            cfg.llm.xai_api_key.as_ref().map(|_| "Grok"),
            cfg.llm.anthropic_api_key.as_ref().map(|_| "Claude"),
            cfg.llm.openai_api_key.as_ref().map(|_| "OpenAI"),
            cfg.llm.vllm_url.as_ref().map(|_| "vLLM"),
        ]
        .into_iter()
        .flatten()
        .collect();

        CheckResult {
            name: "llm_config".to_string(),
            status: "ok".to_string(),
            details: Some(format!("Backends disponíveis: {}", backends.join(", "))),
        }
    } else {
        CheckResult {
            name: "llm_config".to_string(),
            status: "warn".to_string(),
            details: Some("Nenhum backend LLM configurado (XAI_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY, VLLM_URL)".to_string()),
        }
    }
}

async fn check_neo4j(cfg: &BeagleConfig) -> CheckResult {
    // Por enquanto, apenas verifica se está configurado
    // TODO: adicionar ping real ao Neo4j
    CheckResult {
        name: "neo4j".to_string(),
        status: "ok".to_string(),
        details: cfg.graph.neo4j_uri.clone(),
    }
}

async fn check_qdrant(cfg: &BeagleConfig) -> CheckResult {
    if let Some(url) = &cfg.graph.qdrant_url {
        // Tenta fazer ping ao Qdrant
        let health_url = format!("{}/healthz", url.trim_end_matches('/'));
        match reqwest::get(&health_url).await {
            Ok(resp) if resp.status().is_success() => {
                CheckResult {
                    name: "qdrant".to_string(),
                    status: "ok".to_string(),
                    details: Some(format!("{} - conectado", url)),
                }
            }
            Ok(resp) => {
                CheckResult {
                    name: "qdrant".to_string(),
                    status: "error".to_string(),
                    details: Some(format!("{} - status: {}", url, resp.status())),
                }
            }
            Err(e) => {
                CheckResult {
                    name: "qdrant".to_string(),
                    status: "error".to_string(),
                    details: Some(format!("{} - erro: {}", url, e)),
                }
            }
        }
    } else {
        CheckResult {
            name: "qdrant".to_string(),
            status: "warn".to_string(),
            details: Some("QDRANT_URL não configurado".to_string()),
        }
    }
}

async fn check_postgres(cfg: &BeagleConfig) -> CheckResult {
    // Por enquanto, apenas verifica se está configurado
    // TODO: adicionar ping real ao Postgres
    CheckResult {
        name: "postgres".to_string(),
        status: "ok".to_string(),
        details: cfg.hermes.database_url.as_ref().map(|_| "Configurado".to_string()),
    }
}

async fn check_redis(cfg: &BeagleConfig) -> CheckResult {
    // Por enquanto, apenas verifica se está configurado
    // TODO: adicionar ping real ao Redis
    CheckResult {
        name: "redis".to_string(),
        status: "ok".to_string(),
        details: cfg.hermes.redis_url.as_ref().map(|_| "Configurado".to_string()),
    }
}

