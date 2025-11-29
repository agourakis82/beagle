//! In-memory checkpointer implementation
//!
//! Useful for testing and development. Not suitable for production
//! as data is lost on restart.

use async_trait::async_trait;
use serde::{de::DeserializeOwned, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::checkpoint::{
    Checkpoint, CheckpointFilter, CheckpointTuple, Checkpointer, PendingWrite,
};
use crate::config::CheckpointConfig;
use crate::error::{CheckpointError, CheckpointResult};
use crate::metadata::CheckpointMetadata;

/// Thread storage containing all checkpoints for a thread
#[derive(Debug, Clone)]
struct ThreadStorage<S>
where
    S: Serialize + DeserializeOwned + Clone,
{
    /// Checkpoints indexed by ID
    checkpoints: HashMap<Uuid, Checkpoint<S>>,
    /// Checkpoint IDs in chronological order
    order: Vec<Uuid>,
    /// Pending writes for the latest checkpoint
    pending_writes: Vec<PendingWrite>,
}

impl<S> Default for ThreadStorage<S>
where
    S: Serialize + DeserializeOwned + Clone,
{
    fn default() -> Self {
        Self {
            checkpoints: HashMap::new(),
            order: Vec::new(),
            pending_writes: Vec::new(),
        }
    }
}

/// In-memory checkpointer for testing and development
pub struct InMemoryCheckpointer<S>
where
    S: Serialize + DeserializeOwned + Clone + Send + Sync,
{
    /// Storage keyed by thread_id (with optional namespace prefix)
    storage: Arc<RwLock<HashMap<String, ThreadStorage<S>>>>,
}

impl<S> InMemoryCheckpointer<S>
where
    S: Serialize + DeserializeOwned + Clone + Send + Sync,
{
    /// Create a new in-memory checkpointer
    pub fn new() -> Self {
        Self {
            storage: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Get storage key for a config
    fn storage_key(config: &CheckpointConfig) -> String {
        config.thread_prefix()
    }

    /// Clear all data
    pub async fn clear(&self) {
        let mut storage = self.storage.write().await;
        storage.clear();
    }

    /// Get thread count
    pub async fn thread_count(&self) -> usize {
        let storage = self.storage.read().await;
        storage.len()
    }

    /// List all thread IDs
    pub async fn list_threads(&self) -> Vec<String> {
        let storage = self.storage.read().await;
        storage.keys().cloned().collect()
    }
}

impl<S> Default for InMemoryCheckpointer<S>
where
    S: Serialize + DeserializeOwned + Clone + Send + Sync,
{
    fn default() -> Self {
        Self::new()
    }
}

impl<S> Clone for InMemoryCheckpointer<S>
where
    S: Serialize + DeserializeOwned + Clone + Send + Sync,
{
    fn clone(&self) -> Self {
        Self {
            storage: Arc::clone(&self.storage),
        }
    }
}

#[async_trait]
impl<S> Checkpointer<S> for InMemoryCheckpointer<S>
where
    S: Serialize + DeserializeOwned + Clone + Send + Sync + 'static,
{
    async fn put(
        &self,
        config: &CheckpointConfig,
        state: &S,
        metadata: CheckpointMetadata,
    ) -> CheckpointResult<Uuid> {
        let key = Self::storage_key(config);
        let mut storage = self.storage.write().await;

        let thread_storage = storage.entry(key).or_default();

        // Create checkpoint
        let checkpoint = if let Some(ref ns) = config.namespace {
            Checkpoint::with_namespace(&config.thread_id, ns, state.clone(), metadata)
        } else {
            Checkpoint::new(&config.thread_id, state.clone(), metadata)
        };

        let id = checkpoint.id;

        // Store checkpoint
        thread_storage.checkpoints.insert(id, checkpoint);
        thread_storage.order.push(id);

        // Clear pending writes (they're now committed)
        thread_storage.pending_writes.clear();

        tracing::debug!(
            checkpoint_id = %id,
            thread_id = %config.thread_id,
            "Checkpoint stored"
        );

        Ok(id)
    }

    async fn put_writes(
        &self,
        config: &CheckpointConfig,
        writes: Vec<PendingWrite>,
    ) -> CheckpointResult<()> {
        let key = Self::storage_key(config);
        let mut storage = self.storage.write().await;

        let thread_storage = storage
            .get_mut(&key)
            .ok_or_else(|| CheckpointError::ThreadNotFound(config.thread_id.clone()))?;

        thread_storage.pending_writes.extend(writes);

        Ok(())
    }

    async fn get_tuple(
        &self,
        config: &CheckpointConfig,
    ) -> CheckpointResult<Option<CheckpointTuple<S>>> {
        let key = Self::storage_key(config);
        let storage = self.storage.read().await;

        let thread_storage = match storage.get(&key) {
            Some(ts) => ts,
            None => return Ok(None),
        };

        // Get specific checkpoint or latest
        let checkpoint = if let Some(checkpoint_id) = config.checkpoint_id {
            thread_storage.checkpoints.get(&checkpoint_id).cloned()
        } else {
            // Get latest
            thread_storage
                .order
                .last()
                .and_then(|id| thread_storage.checkpoints.get(id))
                .cloned()
        };

        match checkpoint {
            Some(mut cp) => {
                // Attach pending writes to the checkpoint
                cp.pending_writes = thread_storage.pending_writes.clone();

                Ok(Some(CheckpointTuple {
                    checkpoint: cp,
                    config: config.clone(),
                    next: Vec::new(), // Would be populated by pipeline
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
        let key = Self::storage_key(config);
        let storage = self.storage.read().await;

        let thread_storage = match storage.get(&key) {
            Some(ts) => ts,
            None => return Ok(Vec::new()),
        };

        let filter = filter.unwrap_or_default();

        // Get checkpoints in reverse order (newest first)
        let mut checkpoints: Vec<Checkpoint<S>> = thread_storage
            .order
            .iter()
            .rev()
            .filter_map(|id| thread_storage.checkpoints.get(id))
            .cloned()
            .collect();

        // Apply filters
        checkpoints.retain(|cp| {
            // Source filter
            if let Some(ref source) = filter.source {
                if &cp.metadata.source != source {
                    return false;
                }
            }

            // Step range filter
            if let Some((min, max)) = filter.step_range {
                if cp.metadata.step < min || cp.metadata.step > max {
                    return false;
                }
            }

            // Time range filter
            if let Some((start, end)) = filter.time_range {
                if cp.metadata.created_at < start || cp.metadata.created_at > end {
                    return false;
                }
            }

            // Tags filter
            if !filter.tags.is_empty() {
                if !filter.tags.iter().all(|t| cp.metadata.tags.contains(t)) {
                    return false;
                }
            }

            // Human edits filter
            if filter.human_edits_only && !cp.metadata.is_human_edit {
                return false;
            }

            true
        });

        // Apply offset and limit
        let offset = filter.offset.unwrap_or(0);
        let limit = filter.limit.unwrap_or(usize::MAX);

        let result: Vec<Checkpoint<S>> = checkpoints.into_iter().skip(offset).take(limit).collect();

        Ok(result)
    }

    async fn get_history(&self, config: &CheckpointConfig) -> CheckpointResult<Vec<Checkpoint<S>>> {
        let key = Self::storage_key(config);
        let storage = self.storage.read().await;

        let thread_storage = match storage.get(&key) {
            Some(ts) => ts,
            None => return Ok(Vec::new()),
        };

        // Get checkpoints in chronological order (oldest first)
        let checkpoints: Vec<Checkpoint<S>> = thread_storage
            .order
            .iter()
            .filter_map(|id| thread_storage.checkpoints.get(id))
            .cloned()
            .collect();

        Ok(checkpoints)
    }

    async fn delete(&self, config: &CheckpointConfig) -> CheckpointResult<()> {
        let checkpoint_id = config.checkpoint_id.ok_or_else(|| {
            CheckpointError::InvalidConfig("checkpoint_id required for delete".into())
        })?;

        let key = Self::storage_key(config);
        let mut storage = self.storage.write().await;

        let thread_storage = storage
            .get_mut(&key)
            .ok_or_else(|| CheckpointError::ThreadNotFound(config.thread_id.clone()))?;

        if thread_storage.checkpoints.remove(&checkpoint_id).is_none() {
            return Err(CheckpointError::NotFound(checkpoint_id.to_string()));
        }

        thread_storage.order.retain(|id| *id != checkpoint_id);

        Ok(())
    }

    async fn delete_thread(&self, thread_id: &str) -> CheckpointResult<()> {
        let config = CheckpointConfig::new(thread_id);
        let key = Self::storage_key(&config);
        let mut storage = self.storage.write().await;

        storage.remove(&key);

        Ok(())
    }

    async fn count(&self, config: &CheckpointConfig) -> CheckpointResult<usize> {
        let key = Self::storage_key(config);
        let storage = self.storage.read().await;

        Ok(storage
            .get(&key)
            .map(|ts| ts.checkpoints.len())
            .unwrap_or(0))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
    struct TestState {
        step: u64,
        data: String,
    }

    #[tokio::test]
    async fn test_put_and_get() {
        let checkpointer = InMemoryCheckpointer::<TestState>::new();
        let config = CheckpointConfig::new("test-thread");

        let state = TestState {
            step: 1,
            data: "hello".into(),
        };
        let metadata = CheckpointMetadata::new("node_a", 1);

        let id = checkpointer.put(&config, &state, metadata).await.unwrap();

        let tuple = checkpointer.get_tuple(&config).await.unwrap().unwrap();
        assert_eq!(tuple.checkpoint.id, id);
        assert_eq!(tuple.checkpoint.state, state);
    }

    #[tokio::test]
    async fn test_multiple_checkpoints() {
        let checkpointer = InMemoryCheckpointer::<TestState>::new();
        let config = CheckpointConfig::new("test-thread");

        // Create multiple checkpoints
        for i in 1..=3 {
            let state = TestState {
                step: i,
                data: format!("step {}", i),
            };
            let metadata = CheckpointMetadata::new(format!("node_{}", i), i);
            checkpointer.put(&config, &state, metadata).await.unwrap();
        }

        // Count should be 3
        assert_eq!(checkpointer.count(&config).await.unwrap(), 3);

        // Latest should be step 3
        let tuple = checkpointer.get_tuple(&config).await.unwrap().unwrap();
        assert_eq!(tuple.checkpoint.state.step, 3);

        // List should return newest first
        let list = checkpointer.list(&config, None).await.unwrap();
        assert_eq!(list.len(), 3);
        assert_eq!(list[0].state.step, 3);
        assert_eq!(list[2].state.step, 1);

        // History should return oldest first
        let history = checkpointer.get_history(&config).await.unwrap();
        assert_eq!(history.len(), 3);
        assert_eq!(history[0].state.step, 1);
        assert_eq!(history[2].state.step, 3);
    }

    #[tokio::test]
    async fn test_get_specific_checkpoint() {
        let checkpointer = InMemoryCheckpointer::<TestState>::new();
        let config = CheckpointConfig::new("test-thread");

        let state1 = TestState {
            step: 1,
            data: "first".into(),
        };
        let id1 = checkpointer
            .put(&config, &state1, CheckpointMetadata::new("node_a", 1))
            .await
            .unwrap();

        let state2 = TestState {
            step: 2,
            data: "second".into(),
        };
        checkpointer
            .put(&config, &state2, CheckpointMetadata::new("node_b", 2))
            .await
            .unwrap();

        // Get specific checkpoint
        let specific_config = config.clone().at_checkpoint(id1);
        let tuple = checkpointer
            .get_tuple(&specific_config)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(tuple.checkpoint.state.step, 1);
        assert_eq!(tuple.checkpoint.state.data, "first");
    }

    #[tokio::test]
    async fn test_pending_writes() {
        let checkpointer = InMemoryCheckpointer::<TestState>::new();
        let config = CheckpointConfig::new("test-thread");

        let state = TestState {
            step: 1,
            data: "hello".into(),
        };
        checkpointer
            .put(&config, &state, CheckpointMetadata::new("node_a", 1))
            .await
            .unwrap();

        // Add pending writes
        let writes = vec![
            PendingWrite::new("node_b", serde_json::json!({"key": "value1"})),
            PendingWrite::new("node_c", serde_json::json!({"key": "value2"})),
        ];
        checkpointer.put_writes(&config, writes).await.unwrap();

        // Get tuple should include pending writes
        let tuple = checkpointer.get_tuple(&config).await.unwrap().unwrap();
        assert_eq!(tuple.checkpoint.pending_writes.len(), 2);

        // New checkpoint should clear pending writes
        let state2 = TestState {
            step: 2,
            data: "world".into(),
        };
        checkpointer
            .put(&config, &state2, CheckpointMetadata::new("node_b", 2))
            .await
            .unwrap();

        let tuple2 = checkpointer.get_tuple(&config).await.unwrap().unwrap();
        assert!(tuple2.checkpoint.pending_writes.is_empty());
    }

    #[tokio::test]
    async fn test_filter() {
        let checkpointer = InMemoryCheckpointer::<TestState>::new();
        let config = CheckpointConfig::new("test-thread");

        // Create checkpoints with different sources
        for i in 1..=5 {
            let state = TestState {
                step: i,
                data: format!("step {}", i),
            };
            let source = if i % 2 == 0 { "even" } else { "odd" };
            let metadata = CheckpointMetadata::new(source, i);
            checkpointer.put(&config, &state, metadata).await.unwrap();
        }

        // Filter by source
        let filter = CheckpointFilter::by_source("even");
        let list = checkpointer.list(&config, Some(filter)).await.unwrap();
        assert_eq!(list.len(), 2);
        assert!(list.iter().all(|cp| cp.metadata.source == "even"));

        // Filter with limit
        let filter = CheckpointFilter::all().with_limit(2);
        let list = checkpointer.list(&config, Some(filter)).await.unwrap();
        assert_eq!(list.len(), 2);
    }

    #[tokio::test]
    async fn test_delete() {
        let checkpointer = InMemoryCheckpointer::<TestState>::new();
        let config = CheckpointConfig::new("test-thread");

        let state = TestState {
            step: 1,
            data: "hello".into(),
        };
        let id = checkpointer
            .put(&config, &state, CheckpointMetadata::new("node_a", 1))
            .await
            .unwrap();

        // Delete checkpoint
        let delete_config = config.clone().at_checkpoint(id);
        checkpointer.delete(&delete_config).await.unwrap();

        assert_eq!(checkpointer.count(&config).await.unwrap(), 0);
    }

    #[tokio::test]
    async fn test_delete_thread() {
        let checkpointer = InMemoryCheckpointer::<TestState>::new();

        // Create checkpoints in multiple threads
        for thread in ["thread-1", "thread-2"] {
            let config = CheckpointConfig::new(thread);
            let state = TestState {
                step: 1,
                data: thread.into(),
            };
            checkpointer
                .put(&config, &state, CheckpointMetadata::new("node_a", 1))
                .await
                .unwrap();
        }

        assert_eq!(checkpointer.thread_count().await, 2);

        // Delete one thread
        checkpointer.delete_thread("thread-1").await.unwrap();

        assert_eq!(checkpointer.thread_count().await, 1);
        assert!(checkpointer
            .list_threads()
            .await
            .contains(&"thread-2".to_string()));
    }

    #[tokio::test]
    async fn test_namespace() {
        let checkpointer = InMemoryCheckpointer::<TestState>::new();

        // Same thread_id but different namespaces
        let config1 = CheckpointConfig::with_namespace("thread-1", "tenant-a");
        let config2 = CheckpointConfig::with_namespace("thread-1", "tenant-b");

        let state1 = TestState {
            step: 1,
            data: "tenant-a".into(),
        };
        let state2 = TestState {
            step: 1,
            data: "tenant-b".into(),
        };

        checkpointer
            .put(&config1, &state1, CheckpointMetadata::new("node", 1))
            .await
            .unwrap();
        checkpointer
            .put(&config2, &state2, CheckpointMetadata::new("node", 1))
            .await
            .unwrap();

        // Should be isolated
        let tuple1 = checkpointer.get_tuple(&config1).await.unwrap().unwrap();
        let tuple2 = checkpointer.get_tuple(&config2).await.unwrap().unwrap();

        assert_eq!(tuple1.checkpoint.state.data, "tenant-a");
        assert_eq!(tuple2.checkpoint.state.data, "tenant-b");
    }
}
