//! # BEAGLE SYNC: Distributed Synchronization System
//!
//! ## SOTA Q1+ Implementation (2024-2025)
//!
//! Based on cutting-edge research:
//! - "Conflict-Free Replicated Data Types" (Shapiro et al., 2011)
//! - "Local-First Software" (Kleppmann et al., 2019)
//! - "Merkle-CRDTs: Merkle-DAGs meet CRDTs" (2024)

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::RwLock;

/// Sync error types
#[derive(Debug, thiserror::Error)]
pub enum SyncError {
    #[error("Merge conflict: {0}")]
    MergeConflict(String),
    #[error("Network error: {0}")]
    Network(String),
    #[error("Storage error: {0}")]
    Storage(String),
    #[error("Invalid operation: {0}")]
    InvalidOp(String),
}

/// Vector clock for causality tracking
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct VectorClock {
    clocks: BTreeMap<String, u64>,
}

impl VectorClock {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn increment(&mut self, node_id: &str) {
        *self.clocks.entry(node_id.to_string()).or_insert(0) += 1;
    }

    pub fn get(&self, node_id: &str) -> u64 {
        self.clocks.get(node_id).copied().unwrap_or(0)
    }

    pub fn merge(&mut self, other: &VectorClock) {
        for (node, &clock) in &other.clocks {
            let entry = self.clocks.entry(node.clone()).or_insert(0);
            *entry = (*entry).max(clock);
        }
    }

    pub fn happens_before(&self, other: &VectorClock) -> bool {
        let mut dominated = false;
        for (node, &clock) in &self.clocks {
            let other_clock = other.get(node);
            if clock > other_clock {
                return false;
            }
            if clock < other_clock {
                dominated = true;
            }
        }
        for (node, &clock) in &other.clocks {
            if self.get(node) < clock {
                dominated = true;
            }
        }
        dominated
    }

    pub fn concurrent(&self, other: &VectorClock) -> bool {
        !self.happens_before(other) && !other.happens_before(self)
    }
}

/// G-Counter (Grow-only Counter) CRDT
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GCounter {
    counts: BTreeMap<String, u64>,
}

impl GCounter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn increment(&mut self, node_id: &str) {
        *self.counts.entry(node_id.to_string()).or_insert(0) += 1;
    }

    pub fn value(&self) -> u64 {
        self.counts.values().sum()
    }

    pub fn merge(&mut self, other: &GCounter) {
        for (node, &count) in &other.counts {
            let entry = self.counts.entry(node.clone()).or_insert(0);
            *entry = (*entry).max(count);
        }
    }
}

/// PN-Counter (Positive-Negative Counter) CRDT
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PNCounter {
    positive: GCounter,
    negative: GCounter,
}

impl PNCounter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn increment(&mut self, node_id: &str) {
        self.positive.increment(node_id);
    }

    pub fn decrement(&mut self, node_id: &str) {
        self.negative.increment(node_id);
    }

    pub fn value(&self) -> i64 {
        self.positive.value() as i64 - self.negative.value() as i64
    }

    pub fn merge(&mut self, other: &PNCounter) {
        self.positive.merge(&other.positive);
        self.negative.merge(&other.negative);
    }
}

/// LWW-Register (Last-Writer-Wins Register) CRDT
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LWWRegister<T> {
    value: T,
    timestamp: u64,
    node_id: String,
}

impl<T: Clone + Default> LWWRegister<T> {
    pub fn new(node_id: &str) -> Self {
        Self {
            value: T::default(),
            timestamp: 0,
            node_id: node_id.to_string(),
        }
    }

    pub fn set(&mut self, value: T, timestamp: u64) {
        if timestamp > self.timestamp {
            self.value = value;
            self.timestamp = timestamp;
        }
    }

    pub fn get(&self) -> &T {
        &self.value
    }

    pub fn merge(&mut self, other: &LWWRegister<T>) {
        if other.timestamp > self.timestamp
            || (other.timestamp == self.timestamp && other.node_id > self.node_id)
        {
            self.value = other.value.clone();
            self.timestamp = other.timestamp;
            self.node_id = other.node_id.clone();
        }
    }
}

impl<T: Clone + Default> Default for LWWRegister<T> {
    fn default() -> Self {
        Self::new("default")
    }
}

/// OR-Set (Observed-Remove Set) CRDT
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ORSet<T: Clone + Eq + std::hash::Hash> {
    elements: HashMap<T, HashSet<String>>, // element -> set of unique tags
    tombstones: HashMap<T, HashSet<String>>, // removed element tags
}

impl<T: Clone + Eq + std::hash::Hash> Default for ORSet<T> {
    fn default() -> Self {
        Self {
            elements: HashMap::new(),
            tombstones: HashMap::new(),
        }
    }
}

impl<T: Clone + Eq + std::hash::Hash> ORSet<T> {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add(&mut self, element: T, tag: String) {
        self.elements.entry(element).or_default().insert(tag);
    }

    pub fn remove(&mut self, element: &T) {
        if let Some(tags) = self.elements.remove(element) {
            self.tombstones
                .entry(element.clone())
                .or_default()
                .extend(tags);
        }
    }

    pub fn contains(&self, element: &T) -> bool {
        self.elements
            .get(element)
            .map(|t| !t.is_empty())
            .unwrap_or(false)
    }

    pub fn elements(&self) -> Vec<&T> {
        self.elements.keys().collect()
    }

    pub fn merge(&mut self, other: &ORSet<T>) {
        // Merge elements
        for (element, tags) in &other.elements {
            let entry = self.elements.entry(element.clone()).or_default();
            for tag in tags {
                if !self
                    .tombstones
                    .get(element)
                    .map(|t| t.contains(tag))
                    .unwrap_or(false)
                {
                    entry.insert(tag.clone());
                }
            }
        }

        // Merge tombstones
        for (element, tags) in &other.tombstones {
            let tombstone_entry = self.tombstones.entry(element.clone()).or_default();
            tombstone_entry.extend(tags.clone());

            // Remove tombstoned tags from elements
            if let Some(element_tags) = self.elements.get_mut(element) {
                for tag in tags {
                    element_tags.remove(tag);
                }
                if element_tags.is_empty() {
                    self.elements.remove(element);
                }
            }
        }
    }
}

/// Sync state for a document
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncState {
    pub doc_id: String,
    pub version: VectorClock,
    pub last_sync: u64,
}

/// Sync message for network communication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SyncMessage {
    StateVector(String, VectorClock),
    Delta(String, Vec<u8>, VectorClock),
    Ack(String, VectorClock),
}

/// Main sync orchestrator
pub struct SyncOrchestrator {
    node_id: String,
    state: Arc<RwLock<HashMap<String, SyncState>>>,
}

impl SyncOrchestrator {
    pub fn new(node_id: &str) -> Self {
        Self {
            node_id: node_id.to_string(),
            state: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn register_document(&self, doc_id: &str) -> Result<()> {
        let mut state = self.state.write().await;
        state.insert(
            doc_id.to_string(),
            SyncState {
                doc_id: doc_id.to_string(),
                version: VectorClock::new(),
                last_sync: 0,
            },
        );
        Ok(())
    }

    pub async fn update_version(&self, doc_id: &str) -> Result<VectorClock> {
        let mut state = self.state.write().await;
        if let Some(sync_state) = state.get_mut(doc_id) {
            sync_state.version.increment(&self.node_id);
            Ok(sync_state.version.clone())
        } else {
            Err(anyhow::anyhow!("Document not found: {}", doc_id))
        }
    }

    pub async fn get_version(&self, doc_id: &str) -> Option<VectorClock> {
        let state = self.state.read().await;
        state.get(doc_id).map(|s| s.version.clone())
    }

    pub async fn merge_version(&self, doc_id: &str, other: &VectorClock) -> Result<()> {
        let mut state = self.state.write().await;
        if let Some(sync_state) = state.get_mut(doc_id) {
            sync_state.version.merge(other);
            Ok(())
        } else {
            Err(anyhow::anyhow!("Document not found: {}", doc_id))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vector_clock() {
        let mut vc1 = VectorClock::new();
        let mut vc2 = VectorClock::new();

        vc1.increment("node1");
        vc1.increment("node1");
        vc2.increment("node2");

        assert!(vc1.concurrent(&vc2));

        vc1.merge(&vc2);
        assert_eq!(vc1.get("node1"), 2);
        assert_eq!(vc1.get("node2"), 1);
    }

    #[test]
    fn test_gcounter() {
        let mut c1 = GCounter::new();
        let mut c2 = GCounter::new();

        c1.increment("node1");
        c1.increment("node1");
        c2.increment("node2");
        c2.increment("node2");
        c2.increment("node2");

        c1.merge(&c2);
        assert_eq!(c1.value(), 5);
    }

    #[test]
    fn test_pncounter() {
        let mut counter = PNCounter::new();

        counter.increment("node1");
        counter.increment("node1");
        counter.decrement("node1");

        assert_eq!(counter.value(), 1);
    }

    #[test]
    fn test_lww_register() {
        let mut r1 = LWWRegister::<String>::new("node1");
        let mut r2 = LWWRegister::<String>::new("node2");

        r1.set("first".to_string(), 1);
        r2.set("second".to_string(), 2);

        r1.merge(&r2);
        assert_eq!(r1.get(), "second");
    }

    #[test]
    fn test_orset() {
        let mut s1 = ORSet::<String>::new();
        let mut s2 = ORSet::<String>::new();

        s1.add("apple".to_string(), "tag1".to_string());
        s2.add("banana".to_string(), "tag2".to_string());

        s1.merge(&s2);
        assert!(s1.contains(&"apple".to_string()));
        assert!(s1.contains(&"banana".to_string()));
    }

    #[tokio::test]
    async fn test_sync_orchestrator() {
        let sync = SyncOrchestrator::new("node1");

        sync.register_document("doc1").await.unwrap();
        let v1 = sync.update_version("doc1").await.unwrap();
        assert_eq!(v1.get("node1"), 1);

        let v2 = sync.update_version("doc1").await.unwrap();
        assert_eq!(v2.get("node1"), 2);
    }
}
