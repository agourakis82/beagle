use super::monitor::{PerformanceMonitor, QueryPerformance};
use anyhow::Result;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FailurePattern {
    pub pattern_type: String,
    pub description: String,
    pub frequency: usize,
    pub example_queries: Vec<String>,
    pub recommended_fix: String,
    pub severity_score: f64, // 0.0-1.0 based on frequency and impact
    pub first_seen: chrono::DateTime<chrono::Utc>,
    pub last_seen: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PatternCluster {
    pub cluster_id: String,
    pub patterns: Vec<FailurePattern>,
    pub common_theme: String,
    pub aggregate_frequency: usize,
    pub priority: ClusterPriority,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ClusterPriority {
    Critical, // >100 failures, avg severity >0.8
    High,     // >50 failures, avg severity >0.6
    Medium,   // >20 failures, avg severity >0.4
    Low,      // <20 failures or low severity
}

pub struct WeaknessAnalyzer {
    llm: Arc<AnthropicClient>,
    pattern_history: Vec<FailurePattern>,
}

impl WeaknessAnalyzer {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self {
            llm,
            pattern_history: Vec::new(),
        }
    }

    /// Track a new failure pattern or update existing one
    pub fn track_pattern(&mut self, mut pattern: FailurePattern) {
        // Check if similar pattern exists
        if let Some(existing) = self
            .pattern_history
            .iter_mut()
            .find(|p| p.pattern_type == pattern.pattern_type)
        {
            // Update existing pattern
            existing.frequency += pattern.frequency;
            existing.last_seen = pattern.last_seen;
            existing
                .example_queries
                .extend(pattern.example_queries.clone());

            // Keep only last 5 examples
            if existing.example_queries.len() > 5 {
                existing
                    .example_queries
                    .drain(0..existing.example_queries.len() - 5);
            }

            // Update severity based on frequency increase
            existing.severity_score =
                calculate_severity(existing.frequency, &existing.pattern_type);
        } else {
            // Add new pattern
            pattern.severity_score = calculate_severity(pattern.frequency, &pattern.pattern_type);
            self.pattern_history.push(pattern);
        }
    }

    /// Get patterns sorted by severity
    pub fn get_top_patterns(&self, n: usize) -> Vec<&FailurePattern> {
        let mut patterns = self.pattern_history.iter().collect::<Vec<_>>();
        patterns.sort_by(|a, b| {
            b.severity_score
                .partial_cmp(&a.severity_score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        patterns.into_iter().take(n).collect()
    }

    pub async fn analyze_failures(
        &self,
        monitor: &PerformanceMonitor,
    ) -> Result<Vec<FailurePattern>> {
        info!("🔍 Analyzing failure patterns...");

        let failures = monitor.get_failures(50);

        if failures.is_empty() {
            return Ok(vec![]);
        }

        // Group failures by characteristics
        let failure_summary = failures
            .iter()
            .map(|f| {
                format!(
                    "Query: {} | Domain: {} | Error: {} | Quality: {:.2}",
                    &f.query[..50.min(f.query.len())],
                    f.domain,
                    f.error.as_ref().unwrap_or(&"low_quality".to_string()),
                    f.quality_score
                )
            })
            .collect::<Vec<_>>()
            .join("\n");

        let prompt = format!(
            "Analyze these query failures and identify patterns:\n\n{}\n\n\
             Identify 3-5 distinct failure patterns. For each pattern:\n\
             1. Pattern type (e.g., 'Complex causal queries', 'Multi-domain integration')\n\
             2. Description of the pattern\n\
             3. Why the system struggles\n\
             4. Recommended architectural improvement\n\n\
             Format as JSON array:\n\
             [{{\n  \
               \"pattern_type\": \"...\",\n  \
               \"description\": \"...\",\n  \
               \"recommended_fix\": \"...\"\n\
             }}]",
            failure_summary
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet4,
            messages: vec![Message::user(prompt)],
            max_tokens: 2000,
            temperature: 0.3,
            system: Some("You are an AI systems analyst identifying failure patterns.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        // Parse JSON
        let content = response.content.trim();
        let json_content = if content.contains("```json") {
            content
                .lines()
                .skip_while(|l| !l.contains('['))
                .take_while(|l| !l.starts_with("```"))
                .collect::<Vec<_>>()
                .join("\n")
        } else {
            content.to_string()
        };

        #[derive(Deserialize)]
        struct PatternData {
            pattern_type: String,
            description: String,
            recommended_fix: String,
        }

        let patterns: Vec<PatternData> =
            serde_json::from_str(&json_content).unwrap_or_else(|_| vec![]);

        // Extract actual examples and frequencies from failures
        let now = chrono::Utc::now();
        let failure_patterns: Vec<FailurePattern> = patterns
            .into_iter()
            .map(|p| {
                // Count how many failures match this pattern type (simple keyword matching)
                let matching_failures: Vec<&_> = failures
                    .iter()
                    .filter(|f| {
                        f.domain
                            .to_lowercase()
                            .contains(&p.pattern_type.to_lowercase())
                            || f.query
                                .to_lowercase()
                                .contains(&p.pattern_type.to_lowercase())
                            || f.error
                                .as_ref()
                                .map(|e| e.to_lowercase().contains(&p.pattern_type.to_lowercase()))
                                .unwrap_or(false)
                    })
                    .collect();

                let frequency = matching_failures.len().max(1);
                let examples: Vec<String> = matching_failures
                    .iter()
                    .take(3)
                    .map(|f| f.query.clone())
                    .collect();

                FailurePattern {
                    pattern_type: p.pattern_type.clone(),
                    description: p.description,
                    frequency,
                    example_queries: examples,
                    recommended_fix: p.recommended_fix,
                    severity_score: calculate_severity(frequency, &p.pattern_type),
                    first_seen: now,
                    last_seen: now,
                }
            })
            .collect();

        info!("✅ Identified {} failure patterns", failure_patterns.len());

        Ok(failure_patterns)
    }

    /// Cluster similar failure patterns for strategic insights
    pub async fn cluster_patterns(
        &self,
        patterns: &[FailurePattern],
    ) -> Result<Vec<PatternCluster>> {
        if patterns.is_empty() {
            return Ok(vec![]);
        }

        info!("🔗 Clustering {} patterns...", patterns.len());

        // Prepare pattern summary for LLM
        let pattern_summary = patterns
            .iter()
            .map(|p| {
                format!(
                    "{} (freq: {}, severity: {:.2}): {}",
                    p.pattern_type, p.frequency, p.severity_score, p.description
                )
            })
            .collect::<Vec<_>>()
            .join("\n");

        let prompt = format!(
            "Analyze these failure patterns and group them into 3-5 thematic clusters:\n\n{}\n\n\
             For each cluster:\n\
             1. Assign a cluster_id (e.g., 'reasoning_complexity', 'data_integration')\n\
             2. Identify the common theme connecting these patterns\n\
             3. List which pattern_types belong to this cluster\n\n\
             Format as JSON array:\n\
             [{{\n  \
               \"cluster_id\": \"...\",\n  \
               \"common_theme\": \"...\",\n  \
               \"pattern_types\": [\"pattern1\", \"pattern2\"]\n\
             }}]",
            pattern_summary
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet4,
            messages: vec![Message::user(prompt)],
            max_tokens: 2000,
            temperature: 0.4,
            system: Some("You are an AI systems analyst identifying pattern clusters.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        #[derive(Deserialize)]
        struct ClusterData {
            cluster_id: String,
            common_theme: String,
            pattern_types: Vec<String>,
        }

        let content = response.content.trim();
        let json_content = if content.contains("```json") {
            content
                .lines()
                .skip_while(|l| !l.contains('['))
                .take_while(|l| !l.starts_with("```"))
                .collect::<Vec<_>>()
                .join("\n")
        } else {
            content.to_string()
        };

        let cluster_data: Vec<ClusterData> =
            serde_json::from_str(&json_content).unwrap_or_else(|_| vec![]);

        // Build clusters from data
        let mut clusters = Vec::new();
        for cluster in cluster_data {
            let mut cluster_patterns = Vec::new();
            let mut total_freq = 0;

            for pattern in patterns {
                if cluster.pattern_types.contains(&pattern.pattern_type) {
                    cluster_patterns.push(pattern.clone());
                    total_freq += pattern.frequency;
                }
            }

            if !cluster_patterns.is_empty() {
                let avg_severity: f64 = cluster_patterns
                    .iter()
                    .map(|p| p.severity_score)
                    .sum::<f64>()
                    / cluster_patterns.len() as f64;

                let priority = classify_cluster_priority(total_freq, avg_severity);

                clusters.push(PatternCluster {
                    cluster_id: cluster.cluster_id,
                    patterns: cluster_patterns,
                    common_theme: cluster.common_theme,
                    aggregate_frequency: total_freq,
                    priority,
                });
            }
        }

        info!("✅ Created {} pattern clusters", clusters.len());

        Ok(clusters)
    }

    pub async fn identify_missing_capabilities(
        &self,
        patterns: &[FailurePattern],
    ) -> Result<Vec<String>> {
        let patterns_summary = patterns
            .iter()
            .map(|p| format!("{}: {}", p.pattern_type, p.recommended_fix))
            .collect::<Vec<_>>()
            .join("\n");

        let prompt = format!(
            "Based on these failure patterns:\n\n{}\n\n\
             What specialized agent capabilities are missing?\n\
             List 3-5 specific agent types that should be created.\n\
             Format as JSON array of strings: [\"agent_type_1\", \"agent_type_2\", ...]",
            patterns_summary
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet4,
            messages: vec![Message::user(prompt)],
            max_tokens: 500,
            temperature: 0.5,
            system: Some("You are an AI architect designing specialized agents.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        let capabilities: Vec<String> = serde_json::from_str(response.content.trim())
            .unwrap_or_else(|_| vec!["GeneralizedAgent".to_string()]);

        Ok(capabilities)
    }
}

// Helper functions

fn calculate_severity(frequency: usize, pattern_type: &str) -> f64 {
    // Base severity from frequency (logarithmic scale)
    let freq_score = if frequency == 0 {
        0.0
    } else {
        (frequency as f64).ln() / 10.0
    };

    // Critical patterns get severity boost
    let critical_keywords = ["crash", "timeout", "security", "data_loss", "corruption"];
    let is_critical = critical_keywords
        .iter()
        .any(|k| pattern_type.to_lowercase().contains(k));

    let base_severity = freq_score.min(0.7);

    if is_critical {
        (base_severity + 0.3).min(1.0)
    } else {
        base_severity
    }
}

fn classify_cluster_priority(total_freq: usize, avg_severity: f64) -> ClusterPriority {
    if total_freq > 100 && avg_severity > 0.8 {
        ClusterPriority::Critical
    } else if total_freq > 50 && avg_severity > 0.6 {
        ClusterPriority::High
    } else if total_freq > 20 && avg_severity > 0.4 {
        ClusterPriority::Medium
    } else {
        ClusterPriority::Low
    }
}
