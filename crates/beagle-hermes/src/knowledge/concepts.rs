//! Concept clustering and analysis

use crate::thought_capture::Insight;
use super::temporal_analysis::TemporalAnalyzer;
use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

/// Concept cluster (candidate for synthesis)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConceptCluster {
    pub concept_name: String,
    pub insight_count: usize,
    pub insights: Vec<ClusteredInsight>,
    pub last_synthesis: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClusteredInsight {
    pub id: Uuid,
    pub content: String,
    pub timestamp: DateTime<Utc>,
}

impl ConceptCluster {
    /// Check if cluster is ready for synthesis
    pub fn is_ready_for_synthesis(&self, min_insights: usize, cooldown_hours: i64) -> bool {
        // Condition 1: Enough insights
        if self.insight_count < min_insights {
            return false;
        }

        // Condition 2: Cooldown period passed
        if let Some(last_synthesis) = self.last_synthesis {
            let hours_since = (Utc::now() - last_synthesis).num_hours();
            if hours_since < cooldown_hours {
                return false;
            }
        }

        true
    }
}

/// Analyzer for concept relationships
pub struct ClusterAnalyzer {
    temporal_analyzer: TemporalAnalyzer,
}

impl ClusterAnalyzer {
    pub fn new() -> Self {
        Self {
            temporal_analyzer: TemporalAnalyzer::new(30), // 30-day window
        }
    }

    /// Detect emerging research themes
    pub async fn detect_emerging_themes(&self, clusters: &[ConceptCluster]) -> Vec<String> {
        // Use temporal analyzer to find concepts with accelerating growth
        self.temporal_analyzer.detect_emerging_themes(clusters)
    }

    /// Calculate concept centrality (how connected a concept is)
    pub fn calculate_centrality(&self, cluster: &ConceptCluster) -> f64 {
        // Simple centrality: based on insight count and relationships
        // More insights = higher centrality
        let base_centrality = (cluster.insight_count as f64 / 100.0).min(1.0);
        
        // Boost for recent insights
        if let Some(latest) = cluster.insights.iter().map(|i| i.timestamp).max() {
            let recency = self.temporal_analyzer.recency_score(latest);
            base_centrality * 0.7 + recency * 0.3
        } else {
            base_centrality
        }
    }

    /// Find cross-domain connections between clusters
    pub fn find_cross_domain_connections(
        &self,
        clusters: &[ConceptCluster],
    ) -> Vec<(String, String, f64)> {
        let mut connections = Vec::new();

        // Simple heuristic: clusters with overlapping keywords
        for i in 0..clusters.len() {
            for j in (i + 1)..clusters.len() {
                let cluster1 = &clusters[i];
                let cluster2 = &clusters[j];

                // Extract keywords from concept names and insights
                let keywords1: std::collections::HashSet<&str> = cluster1.concept_name
                    .split_whitespace()
                    .filter(|w| w.len() > 4)
                    .collect();
                let keywords2: std::collections::HashSet<&str> = cluster2.concept_name
                    .split_whitespace()
                    .filter(|w| w.len() > 4)
                    .collect();

                let overlap = keywords1.intersection(&keywords2).count();
                if overlap > 0 {
                    let similarity = overlap as f64 / keywords1.len().max(keywords2.len()) as f64;
                    if similarity > 0.2 {
                        connections.push((
                            cluster1.concept_name.clone(),
                            cluster2.concept_name.clone(),
                            similarity,
                        ));
                    }
                }
            }
        }

        connections
    }
}

