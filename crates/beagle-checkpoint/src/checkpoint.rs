//! Core checkpoint types and traits

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use uuid::Uuid;

use crate::config::CheckpointConfig;
use crate::error::CheckpointResult;
use crate::metadata::CheckpointMetadata;

/// A pending write that hasn't been committed yet
///
/// Used for fault tolerance - if a node fails mid-execution,
/// pending writes can be replayed on recovery.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingWrite {
    /// Node/phase that generated this write
    pub node: String,
    /// Data to be written
    pub data: serde_json::Value,
    /// Timestamp
    pub created_at: DateTime<Utc>,
}

impl PendingWrite {
    /// Create a new pending write
    pub fn new(node: impl Into<String>, data: impl Serialize) -> Self {
        Self {
            node: node.into(),
            data: serde_json::to_value(data).unwrap_or(serde_json::Value::Null),
            created_at: Utc::now(),
        }
    }
}

/// A checkpoint snapshot of pipeline state
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(bound(serialize = "S: Serialize", deserialize = "S: DeserializeOwned"))]
pub struct Checkpoint<S> {
    /// Unique checkpoint ID
    pub id: Uuid,

    /// Thread ID this checkpoint belongs to
    pub thread_id: String,

    /// Namespace (for multi-tenant)
    pub namespace: Option<String>,

    /// Checkpoint metadata
    pub metadata: CheckpointMetadata,

    /// The actual state
    pub state: S,

    /// Pending writes (for fault tolerance)
    #[serde(default)]
    pub pending_writes: Vec<PendingWrite>,
}

impl<S: Serialize + DeserializeOwned + Clone> Checkpoint<S> {
    /// Create a new checkpoint
    pub fn new(thread_id: impl Into<String>, state: S, metadata: CheckpointMetadata) -> Self {
        Self {
            id: Uuid::new_v4(),
            thread_id: thread_id.into(),
            namespace: None,
            metadata,
            state,
            pending_writes: Vec::new(),
        }
    }

    /// Create checkpoint with namespace
    pub fn with_namespace(
        thread_id: impl Into<String>,
        namespace: impl Into<String>,
        state: S,
        metadata: CheckpointMetadata,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            thread_id: thread_id.into(),
            namespace: Some(namespace.into()),
            metadata,
            state,
            pending_writes: Vec::new(),
        }
    }

    /// Add a pending write
    pub fn add_pending_write(&mut self, write: PendingWrite) {
        self.pending_writes.push(write);
    }

    /// Clear pending writes (after successful commit)
    pub fn clear_pending_writes(&mut self) {
        self.pending_writes.clear();
    }

    /// Get config for this checkpoint
    pub fn config(&self) -> CheckpointConfig {
        CheckpointConfig {
            thread_id: self.thread_id.clone(),
            checkpoint_id: Some(self.id),
            namespace: self.namespace.clone(),
            checkpoint_ns: None,
        }
    }
}

/// Tuple containing checkpoint and associated data
#[derive(Debug, Clone)]
pub struct CheckpointTuple<S> {
    /// The checkpoint
    pub checkpoint: Checkpoint<S>,

    /// Configuration used to retrieve this checkpoint
    pub config: CheckpointConfig,

    /// Next nodes to execute (if resuming)
    pub next: Vec<String>,

    /// Tasks that were in progress
    pub tasks: Vec<TaskInfo>,
}

/// Information about a task in progress
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskInfo {
    /// Task/node name
    pub name: String,
    /// Task status
    pub status: TaskStatus,
    /// Error message if failed
    pub error: Option<String>,
}

/// Task status
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum TaskStatus {
    Pending,
    Running,
    Completed,
    Failed,
}

/// Filter criteria for listing checkpoints
#[derive(Debug, Clone, Default)]
pub struct CheckpointFilter {
    /// Filter by source node
    pub source: Option<String>,
    /// Filter by step range
    pub step_range: Option<(u64, u64)>,
    /// Filter by time range
    pub time_range: Option<(DateTime<Utc>, DateTime<Utc>)>,
    /// Filter by tags
    pub tags: Vec<String>,
    /// Filter by human edits only
    pub human_edits_only: bool,
    /// Maximum number of results
    pub limit: Option<usize>,
    /// Offset for pagination
    pub offset: Option<usize>,
}

impl CheckpointFilter {
    /// Create empty filter (returns all)
    pub fn all() -> Self {
        Self::default()
    }

    /// Filter by source node
    pub fn by_source(source: impl Into<String>) -> Self {
        Self {
            source: Some(source.into()),
            ..Default::default()
        }
    }

    /// Filter by step range
    pub fn by_step_range(min: u64, max: u64) -> Self {
        Self {
            step_range: Some((min, max)),
            ..Default::default()
        }
    }

    /// Set limit
    pub fn with_limit(mut self, limit: usize) -> Self {
        self.limit = Some(limit);
        self
    }

    /// Set offset
    pub fn with_offset(mut self, offset: usize) -> Self {
        self.offset = Some(offset);
        self
    }

    /// Filter by tag
    pub fn with_tag(mut self, tag: impl Into<String>) -> Self {
        self.tags.push(tag.into());
        self
    }

    /// Filter human edits only
    pub fn human_edits(mut self) -> Self {
        self.human_edits_only = true;
        self
    }
}

/// Core trait for checkpoint storage backends
///
/// Implementations should be thread-safe and support concurrent access.
#[async_trait]
pub trait Checkpointer<S>: Send + Sync
where
    S: Serialize + DeserializeOwned + Clone + Send + Sync,
{
    /// Store a checkpoint
    ///
    /// Returns the checkpoint ID on success.
    async fn put(
        &self,
        config: &CheckpointConfig,
        state: &S,
        metadata: CheckpointMetadata,
    ) -> CheckpointResult<Uuid>;

    /// Store pending writes for fault tolerance
    ///
    /// Pending writes are associated with the latest checkpoint.
    async fn put_writes(
        &self,
        config: &CheckpointConfig,
        writes: Vec<PendingWrite>,
    ) -> CheckpointResult<()>;

    /// Get checkpoint tuple for given config
    ///
    /// If `config.checkpoint_id` is Some, returns that specific checkpoint.
    /// Otherwise returns the latest checkpoint for the thread.
    async fn get_tuple(
        &self,
        config: &CheckpointConfig,
    ) -> CheckpointResult<Option<CheckpointTuple<S>>>;

    /// List checkpoints for a thread
    ///
    /// Returns checkpoints in reverse chronological order (newest first).
    async fn list(
        &self,
        config: &CheckpointConfig,
        filter: Option<CheckpointFilter>,
    ) -> CheckpointResult<Vec<Checkpoint<S>>>;

    /// Get full state history for time travel
    ///
    /// Returns all checkpoints from oldest to newest.
    async fn get_history(&self, config: &CheckpointConfig) -> CheckpointResult<Vec<Checkpoint<S>>>;

    /// Delete a specific checkpoint
    async fn delete(&self, config: &CheckpointConfig) -> CheckpointResult<()>;

    /// Delete all checkpoints for a thread
    async fn delete_thread(&self, thread_id: &str) -> CheckpointResult<()>;

    /// Get checkpoint count for a thread
    async fn count(&self, config: &CheckpointConfig) -> CheckpointResult<usize>;
}

/// Extension trait for additional checkpoint operations
#[async_trait]
pub trait CheckpointerExt<S>: Checkpointer<S>
where
    S: Serialize + DeserializeOwned + Clone + Send + Sync,
{
    /// Get the latest checkpoint for a thread
    async fn get_latest(&self, thread_id: &str) -> CheckpointResult<Option<Checkpoint<S>>> {
        let config = CheckpointConfig::new(thread_id);
        Ok(self.get_tuple(&config).await?.map(|t| t.checkpoint))
    }

    /// Check if a thread has any checkpoints
    async fn has_checkpoints(&self, thread_id: &str) -> CheckpointResult<bool> {
        let config = CheckpointConfig::new(thread_id);
        Ok(self.count(&config).await? > 0)
    }

    /// Fork from a specific checkpoint
    async fn fork(
        &self,
        source_config: &CheckpointConfig,
        new_thread_id: &str,
    ) -> CheckpointResult<Option<Uuid>> {
        if let Some(tuple) = self.get_tuple(source_config).await? {
            let mut new_metadata =
                CheckpointMetadata::fork_from(&tuple.checkpoint.metadata, "fork");
            new_metadata.parent_id = Some(tuple.checkpoint.id);

            let new_config = CheckpointConfig::new(new_thread_id);
            let id = self
                .put(&new_config, &tuple.checkpoint.state, new_metadata)
                .await?;
            Ok(Some(id))
        } else {
            Ok(None)
        }
    }
}

// Blanket implementation for all Checkpointers
impl<S, T> CheckpointerExt<S> for T
where
    S: Serialize + DeserializeOwned + Clone + Send + Sync,
    T: Checkpointer<S>,
{
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
    struct TestState {
        step: u64,
        data: String,
    }

    #[test]
    fn test_checkpoint_creation() {
        let state = TestState {
            step: 1,
            data: "test".into(),
        };
        let metadata = CheckpointMetadata::new("test_node", 1);
        let checkpoint = Checkpoint::new("thread-1", state.clone(), metadata);

        assert_eq!(checkpoint.thread_id, "thread-1");
        assert_eq!(checkpoint.state, state);
        assert!(checkpoint.pending_writes.is_empty());
    }

    #[test]
    fn test_pending_write() {
        let write = PendingWrite::new("node_a", serde_json::json!({"key": "value"}));
        assert_eq!(write.node, "node_a");
    }

    #[test]
    fn test_filter() {
        let filter = CheckpointFilter::by_source("research")
            .with_limit(10)
            .with_tag("critical");

        assert_eq!(filter.source, Some("research".to_string()));
        assert_eq!(filter.limit, Some(10));
        assert_eq!(filter.tags, vec!["critical"]);
    }
}
