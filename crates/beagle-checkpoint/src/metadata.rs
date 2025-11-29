//! Checkpoint metadata

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Metadata associated with a checkpoint
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckpointMetadata {
    /// Source node/phase that created this checkpoint
    pub source: String,

    /// Step number in execution sequence
    pub step: u64,

    /// Timestamp when checkpoint was created
    pub created_at: DateTime<Utc>,

    /// Parent checkpoint ID (for time travel/forking)
    pub parent_id: Option<Uuid>,

    /// Custom metadata as JSON
    #[serde(default)]
    pub custom: serde_json::Value,

    /// Tags for filtering/searching
    #[serde(default)]
    pub tags: Vec<String>,

    /// Checksum for integrity verification
    pub checksum: Option<String>,

    /// Whether this checkpoint was created by human intervention
    #[serde(default)]
    pub is_human_edit: bool,
}

impl CheckpointMetadata {
    /// Create new metadata for a checkpoint
    pub fn new(source: impl Into<String>, step: u64) -> Self {
        Self {
            source: source.into(),
            step,
            created_at: Utc::now(),
            parent_id: None,
            custom: serde_json::Value::Null,
            tags: Vec::new(),
            checksum: None,
            is_human_edit: false,
        }
    }

    /// Set parent checkpoint ID
    pub fn with_parent(mut self, parent_id: Uuid) -> Self {
        self.parent_id = Some(parent_id);
        self
    }

    /// Add custom metadata
    pub fn with_custom(mut self, custom: serde_json::Value) -> Self {
        self.custom = custom;
        self
    }

    /// Add a tag
    pub fn with_tag(mut self, tag: impl Into<String>) -> Self {
        self.tags.push(tag.into());
        self
    }

    /// Add multiple tags
    pub fn with_tags(mut self, tags: impl IntoIterator<Item = impl Into<String>>) -> Self {
        self.tags.extend(tags.into_iter().map(|t| t.into()));
        self
    }

    /// Mark as human edit
    pub fn as_human_edit(mut self) -> Self {
        self.is_human_edit = true;
        self
    }

    /// Set checksum
    pub fn with_checksum(mut self, checksum: impl Into<String>) -> Self {
        self.checksum = Some(checksum.into());
        self
    }

    /// Compute checksum from state bytes
    pub fn compute_checksum(state_bytes: &[u8]) -> String {
        let hash = blake3::hash(state_bytes);
        hash.to_hex().to_string()
    }

    /// Create metadata for a forked checkpoint
    pub fn fork_from(parent: &Self, source: impl Into<String>) -> Self {
        Self {
            source: source.into(),
            step: parent.step,
            created_at: Utc::now(),
            parent_id: None, // Will be set when saved
            custom: serde_json::Value::Null,
            tags: vec!["forked".to_string()],
            checksum: None,
            is_human_edit: false,
        }
    }
}

impl Default for CheckpointMetadata {
    fn default() -> Self {
        Self::new("unknown", 0)
    }
}

/// Builder for checkpoint metadata
pub struct MetadataBuilder {
    metadata: CheckpointMetadata,
}

impl MetadataBuilder {
    pub fn new(source: impl Into<String>, step: u64) -> Self {
        Self {
            metadata: CheckpointMetadata::new(source, step),
        }
    }

    pub fn parent(mut self, parent_id: Uuid) -> Self {
        self.metadata.parent_id = Some(parent_id);
        self
    }

    pub fn custom(mut self, key: &str, value: impl Serialize) -> Self {
        if self.metadata.custom.is_null() {
            self.metadata.custom = serde_json::json!({});
        }
        if let serde_json::Value::Object(ref mut map) = self.metadata.custom {
            map.insert(
                key.to_string(),
                serde_json::to_value(value).unwrap_or_default(),
            );
        }
        self
    }

    pub fn tag(mut self, tag: impl Into<String>) -> Self {
        self.metadata.tags.push(tag.into());
        self
    }

    pub fn human_edit(mut self) -> Self {
        self.metadata.is_human_edit = true;
        self
    }

    pub fn build(self) -> CheckpointMetadata {
        self.metadata
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_metadata_creation() {
        let meta = CheckpointMetadata::new("research_phase", 1);
        assert_eq!(meta.source, "research_phase");
        assert_eq!(meta.step, 1);
        assert!(meta.parent_id.is_none());
    }

    #[test]
    fn test_metadata_builder() {
        let parent_id = Uuid::new_v4();
        let meta = MetadataBuilder::new("draft_phase", 2)
            .parent(parent_id)
            .custom("model", "grok-4")
            .tag("critical")
            .tag("reviewed")
            .human_edit()
            .build();

        assert_eq!(meta.source, "draft_phase");
        assert_eq!(meta.step, 2);
        assert_eq!(meta.parent_id, Some(parent_id));
        assert!(meta.is_human_edit);
        assert_eq!(meta.tags, vec!["critical", "reviewed"]);
    }

    #[test]
    fn test_checksum() {
        let data = b"test state data";
        let checksum = CheckpointMetadata::compute_checksum(data);
        assert!(!checksum.is_empty());

        // Same data should produce same checksum
        let checksum2 = CheckpointMetadata::compute_checksum(data);
        assert_eq!(checksum, checksum2);

        // Different data should produce different checksum
        let checksum3 = CheckpointMetadata::compute_checksum(b"different data");
        assert_ne!(checksum, checksum3);
    }
}
