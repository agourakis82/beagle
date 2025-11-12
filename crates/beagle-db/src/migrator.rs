use std::{
    collections::{BTreeMap, BTreeSet},
    fmt, fs,
    path::{Path, PathBuf},
};

use chrono::{DateTime, Utc};
use sqlx::{postgres::PgPoolOptions, PgPool, Row};
use thiserror::Error;
use tracing::{info, warn};

const UP_MARKER: &str = "-- migrate:up";
const DOWN_MARKER: &str = "-- migrate:down";

/// Identidade formal da migração, incluindo statements pré-processados.
#[derive(Debug, Clone)]
struct MigrationDefinition {
    version: i32,
    name: String,
    path: PathBuf,
    up_statements: Vec<String>,
    down_statements: Vec<String>,
}

/// Representa o estado de uma migração no banco de dados.
#[derive(Debug, Clone)]
pub struct MigrationStatus {
    pub version: i32,
    pub name: String,
    pub applied: bool,
    pub applied_at: Option<DateTime<Utc>>,
}

impl fmt::Display for MigrationStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.applied {
            write!(
                f,
                "[APPLIED] {:03} {} @ {}",
                self.version,
                self.name,
                self.applied_at
                    .map(|ts| ts.to_rfc3339())
                    .unwrap_or_else(|| "unknown".to_string())
            )
        } else {
            write!(f, "[PENDING] {:03} {}", self.version, self.name)
        }
    }
}

/// Ação solicitada pelo chamador do migrator.
#[derive(Debug, Clone)]
pub enum MigrationAction {
    Up,
    Down { steps: u32 },
    Status,
}

/// Erros possíveis durante o pipeline de migração.
#[derive(Debug, Error)]
pub enum MigrationError {
    #[error("erro de I/O ao ler diretório de migrações: {0}")]
    Io(#[from] std::io::Error),

    #[error("falha no banco de dados (sqlx): {0}")]
    Database(#[from] sqlx::Error),

    #[error("arquivo de migração inválido: {0}")]
    InvalidMigrationFilename(String),

    #[error("arquivo de migração sem seção '{0}' em {1}")]
    MissingSection(&'static str, String),

    #[error("migração {0} não possui bloco DOWN para rollback")]
    MissingRollback(i32),

    #[error("migração {0} aplicada não encontrada no disco")]
    MissingMigrationOnDisk(i32),
}

/// Orquestra execução de migrações versionadas com rollback.
#[derive(Debug, Clone)]
pub struct Migrator {
    pool: PgPool,
    migrations_dir: PathBuf,
}

impl Migrator {
    /// Cria migrator usando diretório padrão `migrations` do crate.
    pub fn new(pool: PgPool) -> Self {
        Self::with_directory(pool, default_migrations_dir())
    }

    /// Cria migrator com diretório explícito de migrações.
    pub fn with_directory<P: Into<PathBuf>>(pool: PgPool, directory: P) -> Self {
        Self {
            pool,
            migrations_dir: directory.into(),
        }
    }

    /// Constrói um `Migrator` a partir de uma URL, útil para scripts e testes.
    pub async fn from_url(database_url: &str) -> Result<Self, MigrationError> {
        let pool = PgPoolOptions::new()
            .max_connections(5)
            .connect(database_url)
            .await?;
        Ok(Self::new(pool))
    }

    /// Executa todas as migrações pendentes (modo "up").
    pub async fn run_migrations(&self) -> Result<(), MigrationError> {
        self.ensure_migrations_table().await?;
        let migrations = self.list_migrations()?;
        let applied_versions = self.fetch_applied_versions().await?;

        for migration in migrations {
            if applied_versions.contains(&migration.version) {
                continue;
            }

            info!(
                version = migration.version,
                name = %migration.name,
                path = %migration.path.display(),
                "Aplicando migração"
            );
            self.execute_statements(&migration.up_statements).await?;
            self.mark_applied(&migration).await?;
            info!(version = migration.version, "Migração aplicada com sucesso");
        }

        Ok(())
    }

    /// Reverte a última migração aplicada (modo "down").
    pub async fn rollback_last(&self) -> Result<Option<i32>, MigrationError> {
        self.ensure_migrations_table().await?;
        let latest = self.fetch_latest_applied_version().await?;

        let Some(version) = latest else {
            info!("Nenhuma migração aplicada para rollback");
            return Ok(None);
        };

        let migrations = self.list_migrations()?;
        let Some(migration) = migrations.into_iter().find(|m| m.version == version) else {
            return Err(MigrationError::MissingMigrationOnDisk(version));
        };

        if migration.down_statements.is_empty() {
            return Err(MigrationError::MissingRollback(version));
        }

        info!(
            version = migration.version,
            name = %migration.name,
            "Executando rollback da migração"
        );
        self.execute_statements(&migration.down_statements).await?;
        self.unmark_applied(version).await?;
        info!(version = migration.version, "Rollback concluído");

        Ok(Some(version))
    }

    /// Retorna status ordenado das migrações (aplicadas e pendentes).
    pub async fn status(&self) -> Result<Vec<MigrationStatus>, MigrationError> {
        self.ensure_migrations_table().await?;
        let migrations = self.list_migrations()?;
        let mut applied = self.fetch_applied_entries().await?;

        let mut statuses = Vec::new();
        for migration in migrations {
            if let Some(entry) = applied.remove(&migration.version) {
                statuses.push(MigrationStatus {
                    version: migration.version,
                    name: migration.name,
                    applied: true,
                    applied_at: Some(entry),
                });
            } else {
                statuses.push(MigrationStatus {
                    version: migration.version,
                    name: migration.name,
                    applied: false,
                    applied_at: None,
                });
            }
        }

        // Restante do mapa corresponde a migrações órfãs (presentes na tabela, ausentes no disco).
        for (version, applied_at) in applied {
            statuses.push(MigrationStatus {
                version,
                name: "[órfã - arquivo ausente]".to_string(),
                applied: true,
                applied_at: Some(applied_at),
            });
        }

        statuses.sort_by_key(|status| status.version);
        Ok(statuses)
    }

    /// Garante existência da tabela `schema_migrations`.
    async fn ensure_migrations_table(&self) -> Result<(), MigrationError> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INT PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            "#,
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Carrega a lista de migrações ordenadas por versão.
    fn list_migrations(&self) -> Result<Vec<MigrationDefinition>, MigrationError> {
        let mut migrations = Vec::new();

        for entry in fs::read_dir(&self.migrations_dir)? {
            let entry = entry?;
            let path = entry.path();

            if !path.is_file() || path.extension().and_then(|ext| ext.to_str()) != Some("sql") {
                continue;
            }

            let definition = parse_migration_file(&path)?;
            migrations.push(definition);
        }

        migrations.sort_by_key(|migration| migration.version);
        Ok(migrations)
    }

    async fn execute_statements(&self, statements: &[String]) -> Result<(), MigrationError> {
        for statement in statements {
            let normalized = statement.trim();

            if normalized.is_empty() {
                continue;
            }

            if is_transaction_marker(normalized) {
                warn!("Ignorando marker de transação manual: {}", normalized);
                continue;
            }

            if should_skip_statement(normalized) {
                warn!(
                    "Ignorando statement marcado para execução manual: {}",
                    normalized.lines().next().unwrap_or_default()
                );
                continue;
            }

            info!(
                "Executando statement: {}",
                normalized.lines().next().unwrap_or(normalized)
            );
            sqlx::query(normalized).execute(&self.pool).await?;
        }

        Ok(())
    }

    async fn mark_applied(&self, migration: &MigrationDefinition) -> Result<(), MigrationError> {
        sqlx::query(
            r#"
            INSERT INTO schema_migrations (version, name, applied_at)
            VALUES ($1, $2, NOW())
            ON CONFLICT (version) DO UPDATE
            SET name = EXCLUDED.name,
                applied_at = NOW()
            "#,
        )
        .bind(migration.version)
        .bind(&migration.name)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn unmark_applied(&self, version: i32) -> Result<(), MigrationError> {
        sqlx::query("DELETE FROM schema_migrations WHERE version = $1")
            .bind(version)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn fetch_applied_versions(&self) -> Result<BTreeSet<i32>, MigrationError> {
        let rows = sqlx::query("SELECT version FROM schema_migrations")
            .fetch_all(&self.pool)
            .await?;

        Ok(rows
            .into_iter()
            .map(|row| row.get::<i32, _>("version"))
            .collect())
    }

    async fn fetch_applied_entries(&self) -> Result<BTreeMap<i32, DateTime<Utc>>, MigrationError> {
        let rows = sqlx::query("SELECT version, applied_at FROM schema_migrations")
            .fetch_all(&self.pool)
            .await?;

        let mut map = BTreeMap::new();
        for row in rows {
            let version: i32 = row.get("version");
            let applied_at: DateTime<Utc> = row.get("applied_at");
            map.insert(version, applied_at);
        }
        Ok(map)
    }

    async fn fetch_latest_applied_version(&self) -> Result<Option<i32>, MigrationError> {
        let row =
            sqlx::query("SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1")
                .fetch_optional(&self.pool)
                .await?;

        Ok(row.map(|r| r.get::<i32, _>("version")))
    }
}

fn default_migrations_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("migrations")
}

fn parse_migration_file(path: &Path) -> Result<MigrationDefinition, MigrationError> {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| MigrationError::InvalidMigrationFilename(path.display().to_string()))?;

    let (version, name) = parse_filename(file_name)?;
    let raw = fs::read_to_string(path)?;
    let (up_block, down_block) = split_sections(&raw, file_name)?;

    let up_statements = extract_statements(&up_block);
    let down_statements = extract_statements(&down_block);

    Ok(MigrationDefinition {
        version,
        name,
        path: path.to_path_buf(),
        up_statements,
        down_statements,
    })
}

fn parse_filename(file_name: &str) -> Result<(i32, String), MigrationError> {
    let stem = file_name
        .strip_suffix(".sql")
        .ok_or_else(|| MigrationError::InvalidMigrationFilename(file_name.to_string()))?;

    let mut parts = stem.splitn(2, '_');
    let version_str = parts
        .next()
        .ok_or_else(|| MigrationError::InvalidMigrationFilename(file_name.to_string()))?;

    let version: i32 = version_str
        .parse()
        .map_err(|_| MigrationError::InvalidMigrationFilename(file_name.to_string()))?;

    let name_part = parts
        .next()
        .unwrap_or("migration")
        .replace('_', " ")
        .trim()
        .to_string();

    Ok((version, name_part))
}

fn split_sections(raw: &str, file_name: &str) -> Result<(String, String), MigrationError> {
    let mut current_section = None;
    let mut up_lines = Vec::new();
    let mut down_lines = Vec::new();

    for line in raw.lines() {
        let trimmed = line.trim();

        if trimmed.eq_ignore_ascii_case(UP_MARKER) {
            current_section = Some("up");
            continue;
        } else if trimmed.eq_ignore_ascii_case(DOWN_MARKER) {
            current_section = Some("down");
            continue;
        }

        match current_section {
            Some("up") => up_lines.push(line),
            Some("down") => down_lines.push(line),
            None => {
                // Cabeçalho anterior à primeira seção é associado ao bloco UP.
                up_lines.push(line);
            }
            _ => {}
        }
    }

    if up_lines.is_empty() {
        return Err(MigrationError::MissingSection("UP", file_name.to_string()));
    }

    if down_lines.is_empty() {
        return Err(MigrationError::MissingSection(
            "DOWN",
            file_name.to_string(),
        ));
    }

    Ok((up_lines.join("\n"), down_lines.join("\n")))
}

fn extract_statements(sql: &str) -> Vec<String> {
    let mut statements = Vec::new();
    let mut buffer = String::new();
    let mut in_block_comment = false;

    for line in sql.lines() {
        let trimmed = line.trim();

        if trimmed.starts_with("/*") && !trimmed.ends_with("*/") {
            in_block_comment = true;
            continue;
        }

        if in_block_comment {
            if trimmed.ends_with("*/") {
                in_block_comment = false;
            }
            continue;
        }

        if trimmed.starts_with("/*") || trimmed.ends_with("*/") {
            continue;
        }

        if trimmed.starts_with("--") || trimmed.is_empty() {
            continue;
        }

        buffer.push_str(trimmed);
        buffer.push('\n');

        if trimmed.ends_with(';') {
            statements.push(buffer.trim().to_string());
            buffer.clear();
        }
    }

    if !buffer.trim().is_empty() {
        statements.push(buffer.trim().to_string());
    }

    statements
}

fn is_transaction_marker(statement: &str) -> bool {
    let normalized = statement.trim_end_matches(';').trim();
    normalized.eq_ignore_ascii_case("BEGIN")
        || normalized.eq_ignore_ascii_case("COMMIT")
        || normalized.eq_ignore_ascii_case("ROLLBACK")
}

fn should_skip_statement(statement: &str) -> bool {
    let upper = statement.to_ascii_uppercase();

    if upper.starts_with("EXPLAIN") {
        return true;
    }

    if upper.starts_with("SELECT") && upper.contains("FROM PG_") {
        return true;
    }

    if upper.contains("::VECTOR") && upper.contains("...") {
        return true;
    }

    false
}
