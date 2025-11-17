//! Temporal analysis of concept evolution

use chrono::{DateTime, Utc};
use std::collections::HashMap;
use tracing::debug;

pub struct TemporalAnalyzer {
    // Configuration for temporal analysis
    time_window_days: i64,
}

impl TemporalAnalyzer {
    pub fn new(time_window_days: i64) -> Self {
        Self { time_window_days }
    }

    /// Analyze concept growth rate over time
    pub fn analyze_growth_rate(&self, insights: &[super::concepts::ClusteredInsight]) -> f64 {
        if insights.len() < 2 {
            return 0.0;
        }

        // Sort by timestamp
        let mut sorted: Vec<_> = insights.iter().collect();
        sorted.sort_by_key(|i| i.timestamp);

        // Calculate time span (bounded by configured window)
        let first = sorted.first().unwrap().timestamp;
        let last = sorted.last().unwrap().timestamp;
        let elapsed_days = (last - first).num_days().max(1);
        let time_span = elapsed_days.min(self.time_window_days);

        // Growth rate: insights per day
        let growth_rate = insights.len() as f64 / time_span as f64;
        debug!(
            "Growth rate: {:.2} insights/day over {} days",
            growth_rate, time_span
        );

        growth_rate
    }

    /// Detect emerging themes (concepts with accelerating growth)
    pub fn detect_emerging_themes(
        &self,
        concept_clusters: &[super::concepts::ConceptCluster],
    ) -> Vec<String> {
        let mut emerging = Vec::new();

        for cluster in concept_clusters {
            let growth_rate = self.analyze_growth_rate(&cluster.insights);

            // High growth rate indicates emerging theme
            // Emerging theme threshold scales with configured window
            let threshold = 0.5 / (self.time_window_days as f64 / 30.0);
            if growth_rate > threshold {
                emerging.push(cluster.concept_name.clone());
                debug!(
                    "Emerging theme detected: {} (growth: {:.2}/day)",
                    cluster.concept_name, growth_rate
                );
            }
        }

        emerging
    }

    /// Calculate recency score (more recent = higher score)
    pub fn recency_score(&self, timestamp: DateTime<Utc>) -> f64 {
        let now = Utc::now();
        let age_days = (now - timestamp).num_days();

        // Exponential decay: score = e^(-age/30)
        // Recent (0 days) = 1.0, 30 days = 0.37, 60 days = 0.14
        let decay_rate = 30.0;
        (-(age_days as f64) / decay_rate).exp()
    }

    /// Find temporal patterns in insights
    pub fn find_temporal_patterns(
        &self,
        insights: &[super::concepts::ClusteredInsight],
    ) -> TemporalPatterns {
        if insights.is_empty() {
            return TemporalPatterns::default();
        }

        // Group by time windows using configured rolling window
        let mut hourly_distribution: HashMap<u32, usize> = HashMap::new();
        let mut daily_distribution: HashMap<u32, usize> = HashMap::new();

        for insight in insights {
            // Extract hour and day from timestamp
            // Using format string parsing for compatibility
            let timestamp_str = insight.timestamp.format("%H %w").to_string();
            let parts: Vec<&str> = timestamp_str.split_whitespace().collect();
            if parts.len() >= 2 {
                if let (Ok(hour), Ok(day)) = (parts[0].parse::<u32>(), parts[1].parse::<u32>()) {
                    *hourly_distribution.entry(hour).or_insert(0) += 1;
                    *daily_distribution.entry(day).or_insert(0) += 1;
                }
            }
        }

        // Find peak hours/days
        let peak_hour = hourly_distribution
            .iter()
            .max_by_key(|(_, &count)| count)
            .map(|(&hour, _)| hour)
            .unwrap_or(12);

        let peak_day = daily_distribution
            .iter()
            .max_by_key(|(_, &count)| count)
            .map(|(&day, _)| day)
            .unwrap_or(1);

        TemporalPatterns {
            peak_hour,
            peak_day,
            hourly_distribution,
            daily_distribution,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct TemporalPatterns {
    pub peak_hour: u32,
    pub peak_day: u32,
    pub hourly_distribution: HashMap<u32, usize>,
    pub daily_distribution: HashMap<u32, usize>,
}
