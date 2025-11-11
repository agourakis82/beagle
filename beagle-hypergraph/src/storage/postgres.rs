//! Implementação base do backend PostgreSQL para o hipergrafo Beagle.

use std::time::Duration;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{postgres::PgPoolOptions, postgres::PgRow, PgPool, Postgres, Row};
use uuid::Uuid;

use crate::{
    error::{HypergraphError, Result},
    models::{ContentType, Hyperedge, Node},
    storage::{HypergraphStorage, NodeFilters},
};

/// Implementação de armazenamento baseada em PostgreSQL utilizando `sqlx`.
#[derive(Clone)]
pub struct PostgresStorage {
    pool: PgPool,
}

impl PostgresStorage {
    /// Cria uma nova instância configurando pool de conexões.
    pub async fn new(database_url: &str) -> Result<Self> {
        let pool = PgPoolOptions::new()
            .max_connections(20)
            .min_connections(5)
            .acquire_timeout(Duration::from_secs(10))
            .connect(database_url)
            .await
            .map_err(|e| HypergraphError::PoolError(e.to_string()))?;

        Ok(Self { pool })
    }

    /// Executa migrações pendentes usando o diretório padrão do projeto.
    pub async fn migrate(&self) -> Result<()> {
        sqlx::migrate!("../beagle-db/migrations")
            .run(&self.pool)
            .await
            .map_err(|e| HypergraphError::InternalError(e.to_string()))?;
        Ok(())
    }

    /// Retorna referência ao pool (uso avançado ou inspeção).
    pub fn pool(&self) -> &PgPool {
        &self.pool
    }
}

fn parse_content_type(value: &str) -> Result<ContentType> {
    match value {
        "Thought" => Ok(ContentType::Thought),
        "Memory" => Ok(ContentType::Memory),
        "Context" => Ok(ContentType::Context),
        "Task" => Ok(ContentType::Task),
        "Note" => Ok(ContentType::Note),
        other => Err(HypergraphError::InternalError(format!(
            "Unknown content type: {other}"
        ))),
    }
}

fn row_to_node(row: &PgRow) -> Result<Node> {
    let id: Uuid = row.try_get("id").map_err(HypergraphError::DatabaseError)?;
    let content: String = row
        .try_get("content")
        .map_err(HypergraphError::DatabaseError)?;
    let content_type_raw: String = row
        .try_get("content_type")
        .map_err(HypergraphError::DatabaseError)?;
    let metadata: serde_json::Value = row
        .try_get("metadata")
        .map_err(HypergraphError::DatabaseError)?;
    let created_at: DateTime<Utc> = row
        .try_get("created_at")
        .map_err(HypergraphError::DatabaseError)?;
    let updated_at: DateTime<Utc> = row
        .try_get("updated_at")
        .map_err(HypergraphError::DatabaseError)?;
    let deleted_at: Option<DateTime<Utc>> = row
        .try_get("deleted_at")
        .map_err(HypergraphError::DatabaseError)?;
    let device_id: String = row
        .try_get("device_id")
        .map_err(HypergraphError::DatabaseError)?;
    let version: i32 = row
        .try_get("version")
        .map_err(HypergraphError::DatabaseError)?;

    let content_type = parse_content_type(&content_type_raw)?;

    Ok(Node {
        id,
        content,
        content_type,
        metadata,
        embedding: None,
        created_at,
        updated_at,
        deleted_at,
        device_id,
        version,
    })
}

fn row_to_hyperedge(row: &PgRow, node_ids: Vec<Uuid>) -> Result<Hyperedge> {
    let id: Uuid = row.try_get("id").map_err(HypergraphError::DatabaseError)?;
    let label: String = row
        .try_get("label")
        .map_err(HypergraphError::DatabaseError)?;
    let metadata: serde_json::Value = row
        .try_get("metadata")
        .map_err(HypergraphError::DatabaseError)?;
    let created_at: DateTime<Utc> = row
        .try_get("created_at")
        .map_err(HypergraphError::DatabaseError)?;
    let updated_at: DateTime<Utc> = row
        .try_get("updated_at")
        .map_err(HypergraphError::DatabaseError)?;
    let deleted_at: Option<DateTime<Utc>> = row
        .try_get("deleted_at")
        .map_err(HypergraphError::DatabaseError)?;
    let device_id: String = row
        .try_get("device_id")
        .map_err(HypergraphError::DatabaseError)?;
    let version: i32 = row
        .try_get("version")
        .map_err(HypergraphError::DatabaseError)?;
    let is_directed: bool = row
        .try_get("is_directed")
        .map_err(HypergraphError::DatabaseError)?;

    Ok(Hyperedge {
        id,
        label,
        node_ids,
        metadata,
        created_at,
        updated_at,
        deleted_at,
        device_id,
        version,
        is_directed,
    })
}

#[async_trait]
impl HypergraphStorage for PostgresStorage {
    async fn create_node(&self, node: Node) -> Result<Node> {
        node.validate()?;

        let row = sqlx::query::<Postgres>(
            r#"
            INSERT INTO nodes (
                id, content, content_type, metadata,
                created_at, updated_at, device_id, version
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING id, content, content_type, metadata,
                      created_at, updated_at, deleted_at, device_id, version
            "#,
        )
        .bind(node.id)
        .bind(node.content)
        .bind(node.content_type.to_string())
        .bind(node.metadata)
        .bind(node.created_at)
        .bind(node.updated_at)
        .bind(node.device_id)
        .bind(node.version)
        .fetch_one(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        row_to_node(&row)
    }

    async fn get_node(&self, id: Uuid) -> Result<Node> {
        let maybe_row = sqlx::query::<Postgres>(
            r#"
            SELECT id, content, content_type, metadata,
                   created_at, updated_at, deleted_at, device_id, version
            FROM nodes
            WHERE id = $1 AND deleted_at IS NULL
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        let row = maybe_row.ok_or(HypergraphError::NodeNotFound(id))?;
        row_to_node(&row)
    }

    async fn update_node(&self, node: Node) -> Result<Node> {
        node.validate()?;

        let row = sqlx::query::<Postgres>(
            r#"
            UPDATE nodes
            SET
                content = $2,
                content_type = $3,
                metadata = $4,
                updated_at = NOW(),
                version = version + 1
            WHERE id = $1
              AND deleted_at IS NULL
              AND version = $5
            RETURNING id, content, content_type, metadata,
                      created_at, updated_at, deleted_at, device_id, version
            "#,
        )
        .bind(node.id)
        .bind(node.content)
        .bind(node.content_type.to_string())
        .bind(node.metadata)
        .bind(node.version)
        .fetch_optional(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        if let Some(row) = row {
            return row_to_node(&row);
        }

        let exists = sqlx::query::<Postgres>(
            r#"
            SELECT 1 FROM nodes WHERE id = $1 AND deleted_at IS NULL
            "#,
        )
        .bind(node.id)
        .fetch_optional(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        if exists.is_some() {
            Err(HypergraphError::VersionConflict {
                expected: node.version,
                found: node.version + 1,
            })
        } else {
            Err(HypergraphError::NodeNotFound(node.id))
        }
    }

    async fn delete_node(&self, id: Uuid) -> Result<()> {
        let result = sqlx::query::<Postgres>(
            r#"
            UPDATE nodes
            SET deleted_at = NOW()
            WHERE id = $1 AND deleted_at IS NULL
            "#,
        )
        .bind(id)
        .execute(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        if result.rows_affected() == 0 {
            return Err(HypergraphError::NodeNotFound(id));
        }

        Ok(())
    }

    async fn list_nodes(&self, filters: Option<NodeFilters>) -> Result<Vec<Node>> {
        let filters = filters.unwrap_or_default();
        let content_type = filters.content_type.map(|ct| ct.to_string());

        let rows = sqlx::query::<Postgres>(
            r#"
            SELECT id, content, content_type, metadata,
                   created_at, updated_at, deleted_at, device_id, version
            FROM nodes
            WHERE deleted_at IS NULL
              AND ($1::text IS NULL OR content_type = $1)
              AND ($2::text IS NULL OR device_id = $2)
              AND ($3::timestamptz IS NULL OR created_at > $3)
              AND ($4::timestamptz IS NULL OR created_at < $4)
            ORDER BY created_at DESC
            LIMIT 10000
            "#,
        )
        .bind(content_type.as_deref())
        .bind(filters.device_id.as_deref())
        .bind(filters.created_after)
        .bind(filters.created_before)
        .fetch_all(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        rows.into_iter().map(|row| row_to_node(&row)).collect()
    }

    async fn batch_get_nodes(&self, ids: Vec<Uuid>) -> Result<Vec<Node>> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }

        let rows = sqlx::query::<Postgres>(
            r#"
            SELECT id, content, content_type, metadata,
                   created_at, updated_at, deleted_at, device_id, version
            FROM nodes
            WHERE id = ANY($1::uuid[])
              AND deleted_at IS NULL
            "#,
        )
        .bind(&ids)
        .fetch_all(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        rows.into_iter().map(|row| row_to_node(&row)).collect()
    }

    async fn create_hyperedge(&self, edge: Hyperedge) -> Result<Hyperedge> {
        edge.validate()?;

        let row = sqlx::query::<Postgres>(
            r#"
            INSERT INTO hyperedges (
                id, label, metadata, created_at, updated_at,
                device_id, version, is_directed
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING id, label, metadata, created_at,
                      updated_at, deleted_at, device_id, version, is_directed
            "#,
        )
        .bind(edge.id)
        .bind(edge.label.clone())
        .bind(edge.metadata.clone())
        .bind(edge.created_at)
        .bind(edge.updated_at)
        .bind(edge.device_id.clone())
        .bind(edge.version)
        .bind(edge.is_directed)
        .fetch_one(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        for (position, node_id) in edge.node_ids.iter().enumerate() {
            sqlx::query::<Postgres>(
                r#"
                INSERT INTO edge_nodes (hyperedge_id, node_id, position)
                VALUES ($1, $2, $3)
                "#,
            )
            .bind(edge.id)
            .bind(node_id)
            .bind(position as i32)
            .execute(&self.pool)
            .await
            .map_err(HypergraphError::DatabaseError)?;
        }

        let hyperedge = row_to_hyperedge(&row, edge.node_ids.clone())?;
        hyperedge.validate()?;
        Ok(hyperedge)
    }

    async fn get_hyperedge(&self, id: Uuid) -> Result<Hyperedge> {
        let maybe_row = sqlx::query::<Postgres>(
            r#"
            SELECT id, label, metadata, created_at,
                   updated_at, deleted_at, device_id, version, is_directed
            FROM hyperedges
            WHERE id = $1 AND deleted_at IS NULL
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        let row = maybe_row.ok_or(HypergraphError::HyperedgeNotFound(id))?;

        let node_rows = sqlx::query::<Postgres>(
            r#"
            SELECT node_id
            FROM edge_nodes
            WHERE hyperedge_id = $1
            ORDER BY position
            "#,
        )
        .bind(id)
        .fetch_all(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        let mut node_ids = Vec::with_capacity(node_rows.len());
        for row in node_rows {
            let node_id: Uuid = row
                .try_get("node_id")
                .map_err(HypergraphError::DatabaseError)?;
            node_ids.push(node_id);
        }

        row_to_hyperedge(&row, node_ids)
    }

    async fn update_hyperedge(&self, edge: Hyperedge) -> Result<Hyperedge> {
        edge.validate()?;

        let row = sqlx::query::<Postgres>(
            r#"
            UPDATE hyperedges
            SET
                label = $2,
                metadata = $3,
                updated_at = NOW(),
                version = version + 1,
                is_directed = $4
            WHERE id = $1
              AND deleted_at IS NULL
              AND version = $5
            RETURNING id, label, metadata, created_at,
                      updated_at, deleted_at, device_id, version, is_directed
            "#,
        )
        .bind(edge.id)
        .bind(edge.label.clone())
        .bind(edge.metadata.clone())
        .bind(edge.is_directed)
        .bind(edge.version)
        .fetch_optional(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        let row = if let Some(row) = row {
            row
        } else {
            let exists = sqlx::query::<Postgres>(
                r#"
                SELECT 1 FROM hyperedges WHERE id = $1 AND deleted_at IS NULL
                "#,
            )
            .bind(edge.id)
            .fetch_optional(&self.pool)
            .await
            .map_err(HypergraphError::DatabaseError)?;

            return if exists.is_some() {
                Err(HypergraphError::VersionConflict {
                    expected: edge.version,
                    found: edge.version + 1,
                })
            } else {
                Err(HypergraphError::HyperedgeNotFound(edge.id))
            };
        };

        sqlx::query::<Postgres>(r#"DELETE FROM edge_nodes WHERE hyperedge_id = $1"#)
            .bind(edge.id)
            .execute(&self.pool)
            .await
            .map_err(HypergraphError::DatabaseError)?;

        for (position, node_id) in edge.node_ids.iter().enumerate() {
            sqlx::query::<Postgres>(
                r#"
                INSERT INTO edge_nodes (hyperedge_id, node_id, position)
                VALUES ($1, $2, $3)
                "#,
            )
            .bind(edge.id)
            .bind(node_id)
            .bind(position as i32)
            .execute(&self.pool)
            .await
            .map_err(HypergraphError::DatabaseError)?;
        }

        let hyperedge = row_to_hyperedge(&row, edge.node_ids.clone())?;
        hyperedge.validate()?;
        Ok(hyperedge)
    }

    async fn delete_hyperedge(&self, id: Uuid) -> Result<()> {
        let result = sqlx::query::<Postgres>(
            r#"
            UPDATE hyperedges
            SET deleted_at = NOW()
            WHERE id = $1 AND deleted_at IS NULL
            "#,
        )
        .bind(id)
        .execute(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        if result.rows_affected() == 0 {
            return Err(HypergraphError::HyperedgeNotFound(id));
        }

        Ok(())
    }

    async fn list_hyperedges(&self, node_id: Option<Uuid>) -> Result<Vec<Hyperedge>> {
        let rows = if let Some(node_id) = node_id {
            sqlx::query::<Postgres>(
                r#"
                SELECT
                    he.id,
                    he.label,
                    he.metadata,
                    he.created_at,
                    he.updated_at,
                    he.deleted_at,
                    he.device_id,
                    he.version,
                    he.is_directed,
                    array_agg(en.node_id ORDER BY en.position) AS node_ids
                FROM hyperedges he
                JOIN edge_nodes en ON he.id = en.hyperedge_id
                WHERE he.deleted_at IS NULL
                  AND en.node_id = $1
                GROUP BY he.id
                "#,
            )
            .bind(node_id)
            .fetch_all(&self.pool)
            .await
            .map_err(HypergraphError::DatabaseError)?
        } else {
            sqlx::query::<Postgres>(
                r#"
                SELECT
                    he.id,
                    he.label,
                    he.metadata,
                    he.created_at,
                    he.updated_at,
                    he.deleted_at,
                    he.device_id,
                    he.version,
                    he.is_directed,
                    array_agg(en.node_id ORDER BY en.position) AS node_ids
                FROM hyperedges he
                JOIN edge_nodes en ON he.id = en.hyperedge_id
                WHERE he.deleted_at IS NULL
                GROUP BY he.id
                "#,
            )
            .fetch_all(&self.pool)
            .await
            .map_err(HypergraphError::DatabaseError)?
        };

        rows.into_iter()
            .map(|row| {
                let node_ids: Vec<Uuid> = row
                    .try_get("node_ids")
                    .map_err(HypergraphError::DatabaseError)?;
                row_to_hyperedge(&row, node_ids)
            })
            .collect()
    }

    async fn query_neighborhood(&self, start_node: Uuid, depth: i32) -> Result<Vec<(Node, i32)>> {
        let rows = sqlx::query::<Postgres>(
            r#"
            SELECT
                n.id,
                n.content,
                n.content_type,
                n.metadata,
                n.created_at,
                n.updated_at,
                n.deleted_at,
                n.device_id,
                n.version,
                q.distance
            FROM query_neighborhood($1, $2) AS q
            JOIN nodes n ON n.id = q.node_id
            WHERE n.deleted_at IS NULL
            ORDER BY q.distance, n.created_at DESC
            "#,
        )
        .bind(start_node)
        .bind(depth)
        .fetch_all(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        if rows.is_empty() {
            self.get_node(start_node).await?;
        }

        let mut results = Vec::with_capacity(rows.len());
        for row in rows {
            let distance: i32 = row
                .try_get("distance")
                .map_err(HypergraphError::DatabaseError)?;
            let node = row_to_node(&row)?;
            results.push((node, distance));
        }

        Ok(results)
    }

    async fn get_connected_nodes(&self, edge_id: Uuid) -> Result<Vec<Node>> {
        let rows = sqlx::query::<Postgres>(
            r#"
            SELECT
                n.id,
                n.content,
                n.content_type,
                n.metadata,
                n.created_at,
                n.updated_at,
                n.deleted_at,
                n.device_id,
                n.version
            FROM nodes n
            JOIN edge_nodes en ON n.id = en.node_id
            WHERE en.hyperedge_id = $1
              AND n.deleted_at IS NULL
            ORDER BY en.position
            "#,
        )
        .bind(edge_id)
        .fetch_all(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        if rows.is_empty() {
            self.get_hyperedge(edge_id).await?;
            return Ok(Vec::new());
        }

        rows.into_iter().map(|row| row_to_node(&row)).collect()
    }

    async fn get_edges_for_node(&self, node_id: Uuid) -> Result<Vec<Hyperedge>> {
        let rows = sqlx::query::<Postgres>(
            r#"
            SELECT
                he.id,
                he.label,
                he.metadata,
                he.created_at,
                he.updated_at,
                he.deleted_at,
                he.device_id,
                he.version,
                he.is_directed,
                array_agg(en.node_id ORDER BY en.position) AS node_ids
            FROM hyperedges he
            JOIN edge_nodes en ON he.id = en.hyperedge_id
            WHERE en.node_id = $1
              AND he.deleted_at IS NULL
            GROUP BY he.id
            "#,
        )
        .bind(node_id)
        .fetch_all(&self.pool)
        .await
        .map_err(HypergraphError::DatabaseError)?;

        if rows.is_empty() {
            self.get_node(node_id).await?;
            return Ok(Vec::new());
        }

        rows.into_iter()
            .map(|row| {
                let node_ids: Vec<Uuid> = row
                    .try_get("node_ids")
                    .map_err(HypergraphError::DatabaseError)?;
                row_to_hyperedge(&row, node_ids)
            })
            .collect()
    }

    async fn semantic_search(
        &self,
        _query_embedding: Vec<f32>,
        _limit: usize,
        _threshold: f32,
    ) -> Result<Vec<(Node, f32)>> {
        Err(HypergraphError::OperationNotPermitted {
            reason:
                "Semantic search requires pgvector integration, not yet supported in this build"
                    .to_string(),
        })
    }

    async fn health_check(&self) -> Result<()> {
        sqlx::query::<Postgres>("SELECT 1")
            .execute(&self.pool)
            .await
            .map_err(HypergraphError::DatabaseError)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requer PostgreSQL em execução
    async fn test_postgres_storage_new() {
        let database_url = "postgresql://beagle_user:beagle_dev_password_CHANGE_IN_PRODUCTION@localhost:5432/beagle_dev";
        let storage = PostgresStorage::new(database_url).await;
        assert!(storage.is_ok());
    }

    #[tokio::test]
    #[ignore]
    async fn test_health_check() {
        let database_url = "postgresql://beagle_user:beagle_dev_password_CHANGE_IN_PRODUCTION@localhost:5432/beagle_dev";
        let storage = PostgresStorage::new(database_url).await.unwrap();
        let result = storage.health_check().await;
        assert!(result.is_ok());
    }
}
