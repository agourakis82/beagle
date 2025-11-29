
//! Checkpoint configuration

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Configuration for checkpoint operations
///
/// Identifies a specific thread and optionally a specific checkpoint
/// within that thread for retrieval or replay operations.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct CheckpointConfig {
    /// Thread identifier (e.g., run_id, session_id, conversation_id)
    pub thread_id: String,

    /// Specific checkpoint ID for replay/retrieval
    /// If None, operations target the latest checkpoint
    pub checkpoint_id: Option<Uuid>,

    /// Namespace for multi-tenant isolation
    pub namespace: Option<String>,

    /// Checkpoint version for schema compatibility
    pub checkpoint_ns: Option<String>,
}

impl CheckpointConfig {
    /// Create a new config with just a thread ID
    pub fn new(thread_id: impl Into<String>) -> Self {
        Self {
            thread_id: thread_id.into(),
            checkpoint_id: None,
            namespace: None,
            checkpoint_ns: None,
        }
    }

    /// Create config with namespace
    pub fn with_namespace(thread_id: impl Into<String>, namespace: impl Into<String>) -> Self {
        Self {
            thread_id: thread_id.into(),
            checkpoint_id: None,
            namespace: Some(namespace.into()),
            checkpoint_ns: None,
        }
    }

    /// Set specific checkpoint for replay
    pub fn at_checkpoint(mut self, checkpoint_id: Uuid) -> Self {
        self.checkpoint_id = Some(checkpoint_id);
        self
    }

    /// Set namespace
    pub fn in_namespace(mut self, namespace: impl Into<String>) -> Self {
        self.namespace = Some(namespace.into());
        self
    }

    /// Set checkpoint namespace version
    pub fn with_ns_version(mut self, version: impl Into<String>) -> Self {
        self.checkpoint_ns = Some(version.into());
        self
    }

    /// Generate storage key for this config
    pub fn storage_key(&self) -> String {
        let mut key = String::new();

        if let Some(ref ns) = self.namespace {
            key.push_str(ns);
            key.push(':');
        }

        key.push_str(&self.thread_id);

        if let Some(ref cp_id) = self.checkpoint_id {
            key.push(':');
            key.push_str(&cp_id.to_string());
        }

        key
    }

    /// Generate prefix for listing all checkpoints in thread
    pub fn thread_prefix(&self) -> String {
        let mut key = String::new();

        if let Some(ref ns) = self.namespace {
            key.push_str(ns);
            key.push(':');
        }

        key.push_str(&self.thread_id);
        key
    }

    /// Check if this config targets a specific checkpoint
    pub fn is_specific(&self) -> bool {
        self.checkpoint_id.is_some()
    }

    /// Fork config for a new checkpoint
    pub fn fork(&self) -> Self {
        Self {
            thread_id: self.thread_id.clone(),
            checkpoint_id: None, // Clear checkpoint_id for new checkpoint
            namespace: self.namespace.clone(),
            checkpoint_ns: self.checkpoint_ns.clone(),
        }
    }
}

impl Default for CheckpointConfig {
    fn default() -> Self {
        Self {
            thread_id: Uuid::new_v4().to_string(),
            checkpoint_id: None,
            namespace: None,
            checkpoint_ns: None,
        }
    }
}

impl std::fmt::Display for CheckpointConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "CheckpointConfig({})", self.storage_key())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_creation() {
        let config = CheckpointConfig::new("run-123");
        assert_eq!(config.thread_id, "run-123");
        assert!(config.checkpoint_id.is_none());
        assert!(config.namespace.is_none());
    }

    #[test]
    fn test_config_with_namespace() {
        let config = CheckpointConfig::with_namespace("run-123", "tenant-abc");
        assert_eq!(config.thread_id, "run-123");
        assert_eq!(config.namespace, Some("tenant-abc".to_string()));
    }

    #[test]
    fn test_storage_key() {
        let config = CheckpointConfig::new("run-123");
        assert_eq!(config.storage_key(), "run-123");

        let config_ns = CheckpointConfig::with_namespace("run-123", "tenant");
        assert_eq!(config_ns.storage_key(), "tenant:run-123");

        let cp_id = Uuid::new_v4();
        let config_cp = config.at_checkpoint(cp_id);
        assert_eq!(config_cp.storage_key(), format!("run-123:{}", cp_id));
    }

    #[test]
    fn test_fork() {
        let cp_id = Uuid::new_v4();
        let config = CheckpointConfig::new("run-123")
            .at_checkpoint(cp_id)
            .in_namespace("tenant");

        let forked = config.fork();
        assert_eq!(forked.thread_id, "run-123");
        assert!(forked.checkpoint_id.is_none()); // Cleared
        assert_eq!(forked.namespace, Some("tenant".to_string()));
    }
}
