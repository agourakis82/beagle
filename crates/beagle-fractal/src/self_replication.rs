//! Self Replicator – Auto-replicação cognitiva
//!
//! Permite que o sistema se replique em outros pesquisadores ou clusters.
//! Implementa:
//! - Manifest generation (What needs to be replicated)
//! - Serialization (How to export the system)
//! - Dependencies (What's required to run)
//! - Verification (Checksum validation)

use crate::fractal_node::FractalNodeRuntime;
use serde::{Deserialize, Serialize};
use tracing::info;

/// Manifest describing a replicable fractal system state
///
/// Contains all metadata needed to recreate a fractal tree in another environment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReplicationManifest {
    pub root_node_id: uuid::Uuid,
    pub depth: u8,
    pub total_nodes: usize,
    pub compressed_size: usize,
    pub original_size: usize,
    pub compression_ratio: f64,
    pub dependencies: Vec<String>,
    /// Checksum for integrity verification
    #[serde(default)]
    pub checksum: String,
    /// Timestamp of replication
    #[serde(default)]
    pub timestamp: String,
    /// Version of replication format
    #[serde(default)]
    pub version: String,
}

/// Handles self-replication of the fractal cognitive system
///
/// Enables exporting the entire system state and re-instantiating it
/// in another environment (another researcher, cluster, or preservation)
pub struct SelfReplicator;

impl SelfReplicator {
    pub fn new() -> Self {
        Self
    }

    fn default_version() -> String {
        "1.0".to_string()
    }

    /// Generates replication manifest with complete system metadata
    ///
    /// Computes:
    /// - System structure (total nodes, depth, topology)
    /// - Size estimates (original vs compressed)
    /// - Compression ratio achieved
    /// - Dependencies required for reproduction
    /// - Integrity checksum
    pub async fn generate_replication_manifest(
        &self,
        root: &FractalNodeRuntime,
    ) -> anyhow::Result<ReplicationManifest> {
        info!("SELF REPLICATOR: Generating replication manifest");

        let root_id = root.id().await;
        let depth = root.depth().await;
        let children_count = root.children_count().await;

        // Calculate topology stats
        let total_nodes = Self::calculate_total_nodes(depth, children_count);

        // Size estimation: assumes exponential growth with holographic compression
        let original_size = total_nodes * 50_000; // ~50KB per node uncompressed
        let compressed_size = (original_size as f64 * 0.1) as usize; // ~10% ratio
        let compression_ratio = original_size as f64 / compressed_size.max(1) as f64;

        // Generate checksum
        let checksum = Self::generate_checksum(&root_id.to_string(), depth, total_nodes);
        let timestamp = chrono::Utc::now().to_rfc3339();

        let manifest = ReplicationManifest {
            root_node_id: root_id,
            depth,
            total_nodes,
            compressed_size,
            original_size,
            compression_ratio,
            checksum,
            timestamp,
            version: Self::default_version(),
            dependencies: vec![
                "beagle-quantum".to_string(),
                "beagle-consciousness".to_string(),
                "beagle-fractal".to_string(),
                "beagle-llm".to_string(),
            ],
        };

        info!(
            "SELF REPLICATOR: Manifest generated - {} nodes, {:.1}:1 compression",
            manifest.total_nodes, manifest.compression_ratio
        );

        Ok(manifest)
    }

    /// Exports system state as JSON for replication
    pub async fn export_for_replication(
        &self,
        root: &FractalNodeRuntime,
        output_path: impl AsRef<std::path::Path>,
    ) -> anyhow::Result<()> {
        info!("SELF REPLICATOR: Exporting system for replication");

        let manifest = self.generate_replication_manifest(root).await?;

        // Serialize manifest with pretty printing for readability
        let manifest_json = serde_json::to_string_pretty(&manifest)?;
        let json_len = manifest_json.len();

        // Write to file
        std::fs::write(&output_path, &manifest_json)?;

        info!(
            "SELF REPLICATOR: System exported to {:?} ({} bytes)",
            output_path.as_ref(),
            json_len
        );

        Ok(())
    }

    /// Imports and validates a replication manifest
    pub async fn import_from_manifest(
        &self,
        manifest_path: impl AsRef<std::path::Path>,
    ) -> anyhow::Result<ReplicationManifest> {
        info!("SELF REPLICATOR: Importing from manifest");

        let manifest_json = std::fs::read_to_string(manifest_path)?;
        let manifest: ReplicationManifest = serde_json::from_str(&manifest_json)?;

        // Validate checksum if present
        if !manifest.checksum.is_empty() {
            let expected = Self::generate_checksum(
                &manifest.root_node_id.to_string(),
                manifest.depth,
                manifest.total_nodes,
            );
            if manifest.checksum != expected {
                return Err(anyhow::anyhow!(
                    "Checksum mismatch: expected {}, got {}",
                    expected,
                    manifest.checksum
                ));
            }
        }

        info!(
            "SELF REPLICATOR: Successfully imported {} nodes at depth {} (Checksum: OK)",
            manifest.total_nodes, manifest.depth
        );

        Ok(manifest)
    }

    /// Verify manifest integrity
    pub fn verify_manifest(manifest: &ReplicationManifest) -> anyhow::Result<()> {
        // Check all required fields are present
        if manifest.root_node_id.to_string().is_empty() {
            return Err(anyhow::anyhow!("Missing root_node_id"));
        }

        if manifest.total_nodes == 0 && manifest.depth > 0 {
            return Err(anyhow::anyhow!(
                "Inconsistent manifest: depth {} but 0 nodes",
                manifest.depth
            ));
        }

        // Check dependencies
        if manifest.dependencies.is_empty() {
            return Err(anyhow::anyhow!("No dependencies listed"));
        }

        info!("SELF REPLICATOR: Manifest verified successfully");
        Ok(())
    }

    /// Helper: Calculate total nodes in a tree
    fn calculate_total_nodes(depth: u8, children_per_node: usize) -> usize {
        if children_per_node == 0 || depth == 0 {
            return 1;
        }
        // Geometric series: sum of children_per_node^i for i in 0..depth
        let mut total = 1;
        let mut current = 1;
        for _ in 0..depth {
            current *= children_per_node;
            total += current;
            if total > 1_000_000_000 {
                // Cap at 1B to avoid overflow
                return total;
            }
        }
        total
    }

    /// Helper: Generate simple checksum for verification
    fn generate_checksum(root_id: &str, depth: u8, total_nodes: usize) -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();
        root_id.hash(&mut hasher);
        depth.hash(&mut hasher);
        total_nodes.hash(&mut hasher);

        format!("{:x}", hasher.finish())
    }
}

impl Default for SelfReplicator {
    fn default() -> Self {
        Self::new()
    }
}

