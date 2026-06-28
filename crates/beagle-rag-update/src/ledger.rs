use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Row};
use tracing::{debug, info};

#[derive(Debug, Clone)]
pub enum LedgerStatus {
    Indexed,
    SkippedUnchanged,
    Deleted,
    Error,
}

impl LedgerStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            LedgerStatus::Indexed => "indexed",
            LedgerStatus::SkippedUnchanged => "skipped_unchanged",
            LedgerStatus::Deleted => "deleted",
            LedgerStatus::Error => "error",
        }
    }
}

#[derive(Debug, Clone)]
pub struct LedgerRecord {
    pub collection: String,
    pub doc_id: String,
    pub doc_type: String,
    pub source_type: String,
    pub source: Option<String>,
    pub source_path: Option<String>,
    pub source_url: Option<String>,
    pub title: Option<String>,
    pub content_hash: String,
    pub tags: Vec<String>,
    pub license: Option<String>,
    pub status: LedgerStatus,
    pub error: Option<String>,
    pub fetched_at: Option<DateTime<Utc>>,
    pub indexed_at: Option<DateTime<Utc>>,
    pub meta: serde_json::Value,
}

#[derive(Debug, Clone)]
pub struct IngestionLedger {
    pool: PgPool,
}

impl IngestionLedger {
    pub async fn connect(database_url: &str) -> Result<Self> {
        let pool = PgPoolOptions::new()
            .max_connections(5)
            .connect(database_url)
            .await
            .context("failed to connect ingestion ledger database")?;
        Ok(Self { pool })
    }

    pub async fn ensure_schema(&self) -> Result<()> {
        // Minimal schema for a document-level ingestion ledger.
        sqlx::query(
            r#"
CREATE TABLE IF NOT EXISTS darwin_ingestion_ledger (
  id BIGSERIAL PRIMARY KEY,
  collection TEXT NOT NULL,
  doc_id TEXT NOT NULL,
  doc_type TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source TEXT,
  source_path TEXT,
  source_url TEXT,
  title TEXT,
  content_hash TEXT NOT NULL,
  tags JSONB NOT NULL DEFAULT '[]'::jsonb,
  license TEXT,
  status TEXT NOT NULL,
  error TEXT,
  fetched_at TIMESTAMPTZ,
  indexed_at TIMESTAMPTZ,
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
"#,
        )
        .execute(&self.pool)
        .await
        .context("failed to create darwin_ingestion_ledger table")?;

        sqlx::query(
            r#"
CREATE UNIQUE INDEX IF NOT EXISTS darwin_ingestion_ledger_unique
  ON darwin_ingestion_ledger (collection, doc_id);
"#,
        )
        .execute(&self.pool)
        .await
        .context("failed to create darwin_ingestion_ledger unique index")?;

        Ok(())
    }

    pub async fn get_content_hash(&self, collection: &str, doc_id: &str) -> Result<Option<String>> {
        let row = sqlx::query(
            r#"
SELECT content_hash
FROM darwin_ingestion_ledger
WHERE collection = $1 AND doc_id = $2
LIMIT 1
"#,
        )
        .bind(collection)
        .bind(doc_id)
        .fetch_optional(&self.pool)
        .await
        .context("failed to query ingestion ledger")?;

        Ok(row.and_then(|r| r.try_get::<String, _>("content_hash").ok()))
    }

    pub async fn upsert(&self, record: LedgerRecord) -> Result<()> {
        let tags = sqlx::types::Json(record.tags);
        let meta = sqlx::types::Json(record.meta);

        debug!(
            collection = %record.collection,
            doc_id = %record.doc_id,
            status = %record.status.as_str(),
            "ledger upsert"
        );

        sqlx::query(
            r#"
INSERT INTO darwin_ingestion_ledger (
  collection, doc_id, doc_type, source_type, source, source_path, source_url,
  title, content_hash, tags, license, status, error, fetched_at, indexed_at, meta, updated_at
)
VALUES (
  $1, $2, $3, $4, $5, $6, $7,
  $8, $9, $10, $11, $12, $13, $14, $15, $16, NOW()
)
ON CONFLICT (collection, doc_id)
DO UPDATE SET
  doc_type = EXCLUDED.doc_type,
  source_type = EXCLUDED.source_type,
  source = EXCLUDED.source,
  source_path = EXCLUDED.source_path,
  source_url = EXCLUDED.source_url,
  title = EXCLUDED.title,
  content_hash = EXCLUDED.content_hash,
  tags = EXCLUDED.tags,
  license = EXCLUDED.license,
  status = EXCLUDED.status,
  error = EXCLUDED.error,
  fetched_at = EXCLUDED.fetched_at,
  indexed_at = COALESCE(EXCLUDED.indexed_at, darwin_ingestion_ledger.indexed_at),
  meta = EXCLUDED.meta,
  updated_at = NOW()
"#,
        )
        .bind(&record.collection)
        .bind(&record.doc_id)
        .bind(&record.doc_type)
        .bind(&record.source_type)
        .bind(&record.source)
        .bind(&record.source_path)
        .bind(&record.source_url)
        .bind(&record.title)
        .bind(&record.content_hash)
        .bind(tags)
        .bind(&record.license)
        .bind(record.status.as_str())
        .bind(&record.error)
        .bind(record.fetched_at)
        .bind(record.indexed_at)
        .bind(meta)
        .execute(&self.pool)
        .await
        .context("failed to upsert ingestion ledger record")?;

        info!(
            collection = %record.collection,
            doc_id = %record.doc_id,
            status = %record.status.as_str(),
            "ledger updated"
        );

        Ok(())
    }
}
