/// # Merkle-based Synchronization
///
/// Efficient state reconciliation using Merkle trees and clocks
use anyhow::{Context, Result};
use blake3::{Hash, Hasher};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;

/// Merkle tree for efficient sync
pub struct MerkleSync {
    tree: Arc<RwLock<MerkleTree>>,
    branching_factor: usize,
    operation_log: Arc<RwLock<Vec<crate::Operation>>>,
}

impl MerkleSync {
    pub fn new(branching_factor: usize) -> Self {
        Self {
            tree: Arc::new(RwLock::new(MerkleTree::new(branching_factor))),
            branching_factor,
            operation_log: Arc::new(RwLock::new(Vec::new())),
        }
    }

    pub async fn add_operation(&self, op: &crate::Operation) -> Result<()> {
        let mut log = self.operation_log.write();
        log.push(op.clone());

        // Update tree
        let mut tree = self.tree.write();
        tree.insert(&op.id.to_string(), &op.payload);

        Ok(())
    }

    pub async fn get_root(&self) -> Result<Hash> {
        let tree = self.tree.read();
        Ok(tree.root())
    }

    pub async fn generate_proof(&self, root: &Hash) -> Result<MerkleProof> {
        let tree = self.tree.read();
        Ok(tree.generate_proof(root))
    }

    pub async fn find_differences(
        &self,
        remote_proof: &MerkleProof,
    ) -> Result<Vec<crate::Operation>> {
        let tree = self.tree.read();
        let diff_keys = tree.find_differences(remote_proof);

        let log = self.operation_log.read();
        let diffs = log
            .iter()
            .filter(|op| diff_keys.contains(&op.id.to_string()))
            .cloned()
            .collect();

        Ok(diffs)
    }

    pub async fn update_tree(&self) -> Result<()> {
        let mut tree = self.tree.write();
        tree.recalculate();
        Ok(())
    }
}

/// Merkle tree implementation
#[derive(Debug)]
pub struct MerkleTree {
    nodes: BTreeMap<Vec<u8>, MerkleNode>,
    root_hash: Hash,
    branching_factor: usize,
}

#[derive(Debug, Clone)]
struct MerkleNode {
    key: Vec<u8>,
    value: Vec<u8>,
    hash: Hash,
    children: Vec<Vec<u8>>,
}

impl MerkleTree {
    pub fn new(branching_factor: usize) -> Self {
        Self {
            nodes: BTreeMap::new(),
            root_hash: blake3::hash(b"empty"),
            branching_factor,
        }
    }

    pub fn insert(&mut self, key: &str, value: &[u8]) {
        let node = MerkleNode {
            key: key.as_bytes().to_vec(),
            value: value.to_vec(),
            hash: blake3::hash(value),
            children: Vec::new(),
        };

        self.nodes.insert(key.as_bytes().to_vec(), node);
        self.recalculate();
    }

    pub fn root(&self) -> Hash {
        self.root_hash
    }

    pub fn recalculate(&mut self) {
        if self.nodes.is_empty() {
            self.root_hash = blake3::hash(b"empty");
            return;
        }

        let mut hasher = Hasher::new();
        for node in self.nodes.values() {
            hasher.update(node.hash.as_bytes());
        }
        self.root_hash = hasher.finalize();
    }

    pub fn generate_proof(&self, _root: &Hash) -> MerkleProof {
        MerkleProof {
            root: self.root_hash,
            paths: self.nodes.keys().map(|k| k.clone()).collect(),
            hashes: self.nodes.values().map(|n| n.hash).collect(),
        }
    }

    pub fn find_differences(&self, remote_proof: &MerkleProof) -> Vec<String> {
        let local_keys: std::collections::HashSet<_> = self
            .nodes
            .keys()
            .map(|k| String::from_utf8_lossy(k).to_string())
            .collect();

        let remote_keys: std::collections::HashSet<_> = remote_proof
            .paths
            .iter()
            .map(|k| String::from_utf8_lossy(k).to_string())
            .collect();

        local_keys.difference(&remote_keys).cloned().collect()
    }
}

/// Merkle proof for verification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MerkleProof {
    pub root: Hash,
    pub paths: Vec<Vec<u8>>,
    pub hashes: Vec<Hash>,
}

/// Merkle clock for causal consistency
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MerkleClock {
    entries: HashMap<String, MerkleClockEntry>,
    root: Hash,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MerkleClockEntry {
    node_id: String,
    timestamp: u64,
    hash: Hash,
}

impl MerkleClock {
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
            root: blake3::hash(b"genesis"),
        }
    }

    pub fn tick(&mut self, node_id: &str) -> Hash {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;

        let mut hasher = Hasher::new();
        hasher.update(node_id.as_bytes());
        hasher.update(&timestamp.to_le_bytes());
        hasher.update(self.root.as_bytes());

        let hash = hasher.finalize();

        self.entries.insert(
            node_id.to_string(),
            MerkleClockEntry {
                node_id: node_id.to_string(),
                timestamp,
                hash,
            },
        );

        self.update_root();
        hash
    }

    pub fn merge(&mut self, other: &MerkleClock) {
        for (node_id, entry) in &other.entries {
            self.entries
                .entry(node_id.clone())
                .and_modify(|e| {
                    if entry.timestamp > e.timestamp {
                        *e = entry.clone();
                    }
                })
                .or_insert(entry.clone());
        }

        self.update_root();
    }

    fn update_root(&mut self) {
        let mut hasher = Hasher::new();
        for entry in self.entries.values() {
            hasher.update(entry.hash.as_bytes());
        }
        self.root = hasher.finalize();
    }

    pub fn happens_before(&self, other: &MerkleClock) -> bool {
        self.entries.iter().all(|(node_id, entry)| {
            other.entries.get(node_id).map_or(false, |other_entry| {
                entry.timestamp <= other_entry.timestamp
            })
        })
    }
}

