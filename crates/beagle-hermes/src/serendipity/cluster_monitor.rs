//! Cluster Monitor: Detects insight clusters ready for synthesis

use crate::knowledge::graph_client::KnowledgeGraph;
use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use tokio::time::{interval, Duration};
use tracing::{info, warn};

/// Threshold for triggering synthesis (number of insights in cluster)
const SYNTHESIS_THRESHOLD: usize = 20;

/// Polling interval (5 minutes)
const POLL_INTERVAL_SECS: u64 = 300;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InsightCluster {
    pub cluster_id: String,
    pub topic: String,
    pub insight_count: usize,
    pub novelty_score: f64,
    pub first_insight_time: DateTime<Utc>,
    pub last_insight_time: DateTime<Utc>,
    pub is_synthesized: bool,
    pub priority: f64,
}

impl InsightCluster {
    /// Calculate priority for synthesis queue
    pub fn calculate_priority(&self) -> f64 {
        // Priority = insight_count * novelty_score * recency_factor
        let recency_hours = (Utc::now() - self.last_insight_time).num_hours() as f64;
        let recency_factor = 1.0 / (1.0 + recency_hours / 24.0); // Decay over days

        self.insight_count as f64 * self.novelty_score * recency_factor
    }
}

pub struct ClusterMonitor {
    graph: KnowledgeGraph,
    synthesized_clusters: HashSet<String>,
}

impl ClusterMonitor {
    pub async fn new(neo4j_uri: &str, user: &str, password: &str) -> Result<Self> {
        Ok(Self {
            graph: KnowledgeGraph::new(neo4j_uri, user, password).await?,
            synthesized_clusters: HashSet::new(),
        })
    }

    /// Start background monitoring task
    pub async fn start_monitoring(mut self) -> Result<()> {
        info!(
            "🔍 Starting cluster monitor (polling every {}s)",
            POLL_INTERVAL_SECS
        );

        let mut poll_timer = interval(Duration::from_secs(POLL_INTERVAL_SECS));

        loop {
            poll_timer.tick().await;

            match self.poll_clusters().await {
                Ok(clusters) => {
                    info!(
                        "📊 Found {} clusters, {} ready for synthesis",
                        clusters.len(),
                        clusters
                            .iter()
                            .filter(|c| c.insight_count >= SYNTHESIS_THRESHOLD)
                            .count()
                    );

                    for cluster in clusters {
                        if self.should_synthesize(&cluster) {
                            info!(
                                "✨ Cluster '{}' ready for synthesis ({} insights)",
                                cluster.cluster_id, cluster.insight_count
                            );

                            // TODO: Send to synthesis queue
                            self.mark_synthesized(&cluster.cluster_id);
                        }
                    }
                }
                Err(e) => {
                    warn!("❌ Error polling clusters: {}", e);
                }
            }
        }
    }

    /// Poll Neo4j for insight clusters
    pub async fn poll_clusters(&self) -> Result<Vec<InsightCluster>> {
        info!("🔎 Polling Neo4j for insight clusters...");

        // Cypher query to find clusters of related insights
        let query = r#"
            MATCH (i:Insight)
            WHERE NOT i.synthesized
            WITH i.topic as topic,
                 count(i) as insight_count,
                 avg(i.novelty_score) as avg_novelty,
                 min(i.created_at) as first_time,
                 max(i.created_at) as last_time,
                 collect(i.id) as insight_ids
            WHERE insight_count >= 5
            RETURN topic,
                   insight_count,
                   avg_novelty,
                   first_time,
                   last_time,
                   insight_ids
            ORDER BY insight_count DESC, avg_novelty DESC
            LIMIT 50
        "#;

        let results = self.graph.execute_query(query, &[]).await?;

        let mut clusters = Vec::new();

        for row in results {
            let topic = row.get_string("topic")?;
            let insight_count = row.get_i64("insight_count")? as usize;
            let avg_novelty = row.get_f64("avg_novelty")?;
            let first_time = row.get_datetime("first_time")?;
            let last_time = row.get_datetime("last_time")?;

            let cluster = InsightCluster {
                cluster_id: format!("cluster_{}", topic.replace(' ', "_")),
                topic,
                insight_count,
                novelty_score: avg_novelty,
                first_insight_time: first_time,
                last_insight_time: last_time,
                is_synthesized: false,
                priority: 0.0, // Will be calculated
            };

            let mut cluster_with_priority = cluster;
            cluster_with_priority.priority = cluster_with_priority.calculate_priority();

            clusters.push(cluster_with_priority);
        }

        Ok(clusters)
    }

    /// Check if cluster meets synthesis threshold
    fn should_synthesize(&self, cluster: &InsightCluster) -> bool {
        cluster.insight_count >= SYNTHESIS_THRESHOLD
            && !cluster.is_synthesized
            && !self.synthesized_clusters.contains(&cluster.cluster_id)
    }

    /// Mark cluster as synthesized (prevent duplicates)
    fn mark_synthesized(&mut self, cluster_id: &str) {
        self.synthesized_clusters.insert(cluster_id.to_string());

        // Also mark in Neo4j
        let query = format!(
            "MATCH (i:Insight {{topic: '{}'}}) SET i.synthesized = true",
            cluster_id.replace("cluster_", "").replace('_', " ")
        );

        // Fire-and-forget update
        let graph = self.graph.clone();
        tokio::spawn(async move {
            if let Err(e) = graph.execute_query(&query, &[]).await {
                warn!("Failed to mark cluster as synthesized: {}", e);
            }
        });
    }

    /// Detect threshold crossing (for alerts)
    pub fn detect_threshold(&self, cluster: &InsightCluster) -> bool {
        cluster.insight_count >= SYNTHESIS_THRESHOLD
    }

    /// Calculate priority score for synthesis queue
    pub fn priority_scoring(&self, cluster: &InsightCluster) -> f64 {
        // Priority = strength × novelty × recency
        let strength = cluster.insight_count as f64 / SYNTHESIS_THRESHOLD as f64;
        let novelty = cluster.novelty_score;

        let hours_since_last = (Utc::now() - cluster.last_insight_time).num_hours() as f64;
        let recency = 1.0 / (1.0 + hours_since_last / 24.0);

        strength * novelty * recency * 100.0 // Scale to 0-100
    }
}

// Placeholder implementations for missing types
mod graph_extensions {
    use super::*;

    pub struct QueryResult {
        data: serde_json::Value,
    }

    impl QueryResult {
        pub fn get_string(&self, key: &str) -> Result<String> {
            self.data
                .get(key)
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
                .ok_or_else(|| anyhow::anyhow!("Missing or invalid string field: {}", key))
        }

        pub fn get_i64(&self, key: &str) -> Result<i64> {
            self.data
                .get(key)
                .and_then(|v| v.as_i64())
                .ok_or_else(|| anyhow::anyhow!("Missing or invalid i64 field: {}", key))
        }

        pub fn get_f64(&self, key: &str) -> Result<f64> {
            self.data
                .get(key)
                .and_then(|v| v.as_f64())
                .ok_or_else(|| anyhow::anyhow!("Missing or invalid f64 field: {}", key))
        }

        pub fn get_datetime(&self, key: &str) -> Result<DateTime<Utc>> {
            let timestamp_str = self.get_string(key)?;
            chrono::DateTime::parse_from_rfc3339(&timestamp_str)
                .map(|dt| dt.with_timezone(&Utc))
                .map_err(|e| anyhow::anyhow!("Invalid datetime: {}", e))
        }
    }

    // Extend KnowledgeGraph trait
    impl KnowledgeGraph {
        pub async fn execute_query(
            &self,
            _query: &str,
            _params: &[(&str, &str)],
        ) -> Result<Vec<QueryResult>> {
            // Placeholder - actual implementation would use neo4j driver
            Ok(Vec::new())
        }
    }
}
