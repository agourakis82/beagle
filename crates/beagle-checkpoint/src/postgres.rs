//! PostgreSQL checkpointer implementation
//!
//! Production-ready checkpointer using PostgreSQL with JSONB storage.

#![cfg(feature = "postgres")]

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{de::DeserializeOwned, Serialize};
use sqlx::postgres::{PgPool, PgPoolOptions};
use sqlx::Row;
use uuid::Uuid;

use crate::checkpoint::{
    Checkpoint, CheckpointFilter, CheckpointTuple, Checkpointer, PendingWrite,
};
use crate::config::CheckpointConfig;
use crate::error::{CheckpointError, CheckpointResult};
use crate::metadata::CheckpointMetadata;

/// PostgreSQL-backed checkpointer for production use
pub struct PostgresCheckpointer {
    pool: PgPool,
}

impl PostgresCheckpointer {
    /// Create a new PostgreSQL checkpointer
    pub async fn new(database_url: &str) -> CheckpointResult<Self> {
        let pool = PgPoolOptions::new()
            .max_connections(10)
            .connect(database_url)
            .await
            .map_err(|e| CheckpointError::Connection(e.to_string()))?;

        Ok(Self { pool })
    }

    /// Create with existing pool
    pub fn with_pool(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Run migrations to create necessary tables
    pub async fn migrate(&self) -> CheckpointResult<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS beagle_checkpoints (
                id UUID PRIMARY KEY,
                thread_id VARCHAR(255) NOT NULL,
                namespace VARCHAR(255),
                source VARCHAR(255) NOT NULL,
                step BIGINT NOT NULL,
                state JSONB NOT NULL,
                metadata JSONB NOT NULL,
                parent_id UUID REFERENCES beagle_checkpoints(id),
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

                CONSTRAINT unique_checkpoint UNIQUE (id)
            );

            CREATE INDEX IF NOT EXISTS idx_checkpoints_thread
                ON beagle_checkpoints(thread_id, created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_checkpoints_namespace
                ON beagle_checkpoints(namespace, thread_id);
            CREATE INDEX IF NOT EXISTS idx_checkpoints_parent
                ON beagle_checkpoints(parent_id);
            CREATE INDEX IF NOT EXISTS idx_checkpoints_source
                ON beagle_checkpoints(source);
            "#,
        )
        .execute(&self.pool)
        .await
        .map_err(|e| CheckpointError::Database(e.to_string()))?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS beagle_pending_writes (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                thread_id VARCHAR(255) NOT NULL,
                namespace VARCHAR(255),
                node VARCHAR(255) NOT NULL,
                data JSONB NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );

            CREATE INDEX IF NOT EXISTS idx_pending_writes_thread
                ON beagle_pending_writes(thread_id, namespace);
            "#,
        )
        .execute(&self.pool)
        .await
        .map_err(|e| CheckpointError::Database(e.to_string()))?;

        Ok(())
    }

    /// Get pool reference
    pub fn pool(&self) -> &PgPool {
        &self.pool
    }
}

#[async_trait]
impl<S> Checkpointer<S> for PostgresCheckpointer
where
    S: Serialize + DeserializeOwned + Clone + Send + Sync + 'static,
{
    async fn put(
        &self,
        config: &CheckpointConfig,
        state: &S,
        metadata: CheckpointMetadata,
    ) -> CheckpointResult<Uuid> {
        let id = Uuid::new_v4();
        let state_json = serde_json::to_value(state)?;
        let metadata_json = serde_json::to_value(&metadata)?;

        sqlx::query(
            r#"
            INSERT INTO beagle_checkpoints
                (id, thread_id, namespace, source, step, state, metadata, parent_id, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            "#,
        )
        .bind(id)
        .bind(&config.thread_id)
        .bind(&config.namespace)
        .bind(&metadata.source)
        .bind(metadata.step as i64)
        .bind(&state_json)
        .bind(&metadata_json)
        .bind(metadata.parent_id)
        .bind(metadata.created_at)
        .execute(&self.pool)
        .await
        .map_err(|e| CheckpointError::Database(e.to_string()))?;

        // Clear pending writes for this thread
        sqlx::query(
            r#"
            DELETE FROM beagle_pending_writes
            WHERE thread_id = $1 AND (namespace = $2 OR (namespace IS NULL AND $2 IS NULL))
            "#,
        )
        .bind(&config.thread_id)
        .bind(&config.namespace)
        .execute(&self.pool)
        .await
        .map_err(|e| CheckpointError::Database(e.to_string()))?;

        tracing::debug!(
            checkpoint_id = %id,
            thread_id = %config.thread_id,
            source = %metadata.source,
            "Checkpoint stored in PostgreSQL"
        );

        Ok(id)
    }

    async fn put_writes(
        &self,
        config: &CheckpointConfig,
        writes: Vec<PendingWrite>,
    ) -> CheckpointResult<()> {
        for write in writes {
            sqlx::query(
                r#"
                INSERT INTO beagle_pending_writes (thread_id, namespace, node, data, created_at)
                VALUES ($1, $2, $3, $4, $5)
                "#,
            )
            .bind(&config.thread_id)
            .bind(&config.namespace)
            .bind(&write.node)
            .bind(&write.data)
            .bind(write.created_at)
            .execute(&self.pool)
            .await
            .map_err(|e| CheckpointError::Database(e.to_string()))?;
        }

        Ok(())
    }

    async fn get_tuple(
        &self,
        config: &CheckpointConfig,
    ) -> CheckpointResult<Option<CheckpointTuple<S>>> {
        // Build query based on whether we're getting specific or latest
        let row = if let Some(checkpoint_id) = config.checkpoint_id {
            sqlx::query(
                r#"
                SELECT id, thread_id, namespace, source, step, state, metadata, parent_id, created_at
                FROM beagle_checkpoints
                WHERE id = $1
                "#,
            )
            .bind(checkpoint_id)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| CheckpointError::Database(e.to_string()))?
        } else {
            sqlx::query(
                r#"
                SELECT id, thread_id, namespace, source, step, state, metadata, parent_id, created_at
                FROM beagle_checkpoints
                WHERE thread_id = $1 AND (namespace = $2 OR (namespace IS NULL AND $2 IS NULL))
                ORDER BY created_at DESC
                LIMIT 1
                "#,
            )
            .bind(&config.thread_id)
            .bind(&config.namespace)
            .fetch_optional(&self.pool)
            .await
            .map_err(|e| CheckpointError::Database(e.to_string()))?
        };

        match row {
            Some(row) => {
                let id: Uuid = row.get("id");
                let thread_id: String = row.get("thread_id");
                let namespace: Option<String> = row.get("namespace");
                let state_json: serde_json::Value = row.get("state");
                let metadata_json: serde_json::Value = row.get("metadata");

                let state: S = serde_json::from_value(state_json)
                    .map_err(|e| CheckpointError::Deserialization(e.to_string()))?;
                let metadata: CheckpointMetadata = serde_json::from_value(metadata_json)
                    .map_err(|e| CheckpointError::Deserialization(e.to_string()))?;

                // Get pending writes
                let pending_rows = sqlx::query(
                    r#"
                    SELECT node, data, created_at
                    FROM beagle_pending_writes
                    WHERE thread_id = $1 AND (namespace = $2 OR (namespace IS NULL AND $2 IS NULL))
                    ORDER BY created_at ASC
                    "#,
                )
                .bind(&config.thread_id)
                .bind(&config.namespace)
                .fetch_all(&self.pool)
                .await
                .map_err(|e| CheckpointError::Database(e.to_string()))?;

                let pending_writes: Vec<PendingWrite> = pending_rows
                    .into_iter()
                    .map(|row| PendingWrite {
                        node: row.get("node"),
                        data: row.get("data"),
                        created_at: row.get("created_at"),
                    })
                    .collect();

                let checkpoint = Checkpoint {
                    id,
                    thread_id,
                    namespace,
                    metadata,
                    state,
                    pending_writes,
                };

                Ok(Some(CheckpointTuple {
                    checkpoint,
                    config: config.clone(),
                    next: Vec::new(),
                    tasks: Vec::new(),
                }))
            }
            None => Ok(None),
        }
    }

    async fn list(
        &self,
        config: &CheckpointConfig,
        filter: Option<CheckpointFilter>,
    ) -> CheckpointResult<Vec<Checkpoint<S>>> {
        let filter = filter.unwrap_or_default();

        // Build dynamic query
        let mut query = String::from(
            r#"
            SELECT id, thread_id, namespace, source, step, state, metadata, parent_id, created_at
            FROM beagle_checkpoints
            WHERE thread_id = $1 AND (namespace = $2 OR (namespace IS NULL AND $2 IS NULL))
            "#,
        );

        let mut param_count = 2;

        if filter.source.is_some() {
            param_count += 1;
            query.push_str(&format!(" AND source = ${}", param_count));
        }

        if filter.step_range.is_some() {
            param_count += 1;
            query.push_str(&format!(" AND step >= ${}", param_count));
            param_count += 1;
            query.push_str(&format!(" AND step <= ${}", param_count));
        }

        if filter.human_edits_only {
            query.push_str(" AND (metadata->>'is_human_edit')::boolean = true");
        }

        query.push_str(" ORDER BY created_at DESC");

        if let Some(limit) = filter.limit {
            query.push_str(&format!(" LIMIT {}", limit));
        }

        if let Some(offset) = filter.offset {
            query.push_str(&format!(" OFFSET {}", offset));
        }

        // Execute query with bindings
        let mut sql_query = sqlx::query(&query)
            .bind(&config.thread_id)
            .bind(&config.namespace);

        if let Some(ref source) = filter.source {
            sql_query = sql_query.bind(source);
        }

        if let Some((min, max)) = filter.step_range {
            sql_query = sql_query.bind(min as i64).bind(max as i64);
        }

        let rows = sql_query
            .fetch_all(&self.pool)
            .await
            .map_err(|e| CheckpointError::Database(e.to_string()))?;

        let mut checkpoints = Vec::new();
        for row in rows {
            let id: Uuid = row.get("id");
            let thread_id: String = row.get("thread_id");
            let namespace: Option<String> = row.get("namespace");
            let state_json: serde_json::Value = row.get("state");
            let metadata_json: serde_json::Value = row.get("metadata");

            let state: S = serde_json::from_value(state_json)
                .map_err(|e| CheckpointError::Deserialization(e.to_string()))?;
            let metadata: CheckpointMetadata = serde_json::from_value(metadata_json)
                .map_err(|e| CheckpointError::Deserialization(e.to_string()))?;

            checkpoints.push(Checkpoint {
                id,
                thread_id,
                namespace,
                metadata,
                state,
                pending_writes: Vec::new(),
            });
        }

        Ok(checkpoints)
    }

    async fn get_history(&self, config: &CheckpointConfig) -> CheckpointResult<Vec<Checkpoint<S>>> {
        let rows = sqlx::query(
            r#"
            SELECT id, thread_id, namespace, source, step, state, metadata, parent_id, created_at
            FROM beagle_checkpoints
            WHERE thread_id = $1 AND (namespace = $2 OR (namespace IS NULL AND $2 IS NULL))
            ORDER BY created_at ASC
            "#,
        )
        .bind(&config.thread_id)
        .bind(&config.namespace)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| CheckpointError::Database(e.to_string()))?;

        let mut checkpoints = Vec::new();
        for row in rows {
            let id: Uuid = row.get("id");
            let thread_id: String = row.get("thread_id");
            let namespace: Option<String> = row.get("namespace");
            let state_json: serde_json::Value = row.get("state");
            let metadata_json: serde_json::Value = row.get("metadata");

            let state: S = serde_json::from_value(state_json)
                .map_err(|e| CheckpointError::Deserialization(e.to_string()))?;
            let metadata: CheckpointMetadata = serde_json::from_value(metadata_json)
                .map_err(|e| CheckpointError::Deserialization(e.to_string()))?;

            checkpoints.push(Checkpoint {
                id,
                thread_id,
                namespace,
                metadata,
                state,
                pending_writes: Vec::new(),
            });
        }

        Ok(checkpoints)
    }

    async fn delete(&self, config: &CheckpointConfig) -> CheckpointResult<()> {
        let checkpoint_id = config
            .checkpoint_id
            .ok_or_else(|| CheckpointError::InvalidConfig("checkpoint_id required".into()))?;

        let result = sqlx::query(
            r#"
            DELETE FROM beagle_checkpoints WHERE id = $1
            "#,
        )
        .bind(checkpoint_id)
        .execute(&self.pool)
        .await
        .map_err(|e| CheckpointError::Database(e.to_string()))?;

        if result.rows_affected() == 0 {
            return Err(CheckpointError::NotFound(checkpoint_id.to_string()));
        }

        Ok(())
    }

    async fn delete_thread(&self, thread_id: &str) -> CheckpointResult<()> {
        // Delete pending writes first
        sqlx::query(
            r#"
            DELETE FROM beagle_pending_writes WHERE thread_id = $1
            "#,
        )
        .bind(thread_id)
        .execute(&self.pool)
        .await
        .map_err(|e| CheckpointError::Database(e.to_string()))?;

        // Delete checkpoints
        sqlx::query(
            r#"
            DELETE FROM beagle_checkpoints WHERE thread_id = $1
            "#,
        )
        .bind(thread_id)
        .execute(&self.pool)
        .await
        .map_err(|e| CheckpointError::Database(e.to_string()))?;

        Ok(())
    }

    async fn count(&self, config: &CheckpointConfig) -> CheckpointResult<usize> {
        let row = sqlx::query(
            r#"
            SELECT COUNT(*) as count
            FROM beagle_checkpoints
            WHERE thread_id = $1 AND (namespace = $2 OR (namespace IS NULL AND $2 IS NULL))
            "#,
        )
        .bind(&config.thread_id)
        .bind(&config.namespace)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| CheckpointError::Database(e.to_string()))?;

        let count: i64 = row.get("count");
        Ok(count as usize)
    }
}

#[cfg(test)]
mod tests {
    // Tests would require a test database
    // Use testcontainers for integration tests
}
