use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryPerformance {
    pub query_id: Uuid,
    pub query: String,
    pub domain: String,
    pub latency_ms: u64,
    pub quality_score: f64,
    pub user_satisfaction: Option<f64>,
    pub timestamp: DateTime<Utc>,
    pub success: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceDegradation {
    pub detected: bool,
    pub metric: String,
    pub current_value: f64,
    pub baseline_value: f64,
    pub degradation_percent: f64,
    pub severity: DegradationSeverity,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DegradationSeverity {
    None,
    Minor,    // 5-15% degradation
    Moderate, // 15-30% degradation
    Severe,   // >30% degradation
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceBottleneck {
    pub bottleneck_type: BottleneckType,
    pub affected_domain: Option<String>,
    pub average_latency_ms: u64,
    pub percentile_95_ms: u64,
    pub recommendation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BottleneckType {
    HighLatency,
    LowQuality,
    FrequentFailures,
    UserDissatisfaction,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceTrend {
    pub metric: String,
    pub direction: TrendDirection,
    pub change_percent: f64,
    pub confidence: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TrendDirection {
    Improving,
    Stable,
    Degrading,
}

pub struct PerformanceMonitor {
    history: Vec<QueryPerformance>,
    max_history: usize,
}

impl PerformanceMonitor {
    pub fn new(max_history: usize) -> Self {
        Self {
            history: Vec::new(),
            max_history,
        }
    }

    pub fn record(&mut self, performance: QueryPerformance) {
        self.history.push(performance);

        // Keep only recent history
        if self.history.len() > self.max_history {
            self.history.drain(0..self.history.len() - self.max_history);
        }
    }

    pub fn get_recent(&self, n: usize) -> &[QueryPerformance] {
        let start = self.history.len().saturating_sub(n);
        &self.history[start..]
    }

    pub fn get_failures(&self, n: usize) -> Vec<&QueryPerformance> {
        self.history
            .iter()
            .rev()
            .filter(|p| !p.success || p.quality_score < 0.5)
            .take(n)
            .collect()
    }

    pub fn success_rate(&self, last_n: usize) -> f64 {
        let recent = self.get_recent(last_n);
        if recent.is_empty() {
            return 0.5;
        }

        let successes = recent.iter().filter(|p| p.success).count();
        successes as f64 / recent.len() as f64
    }

    pub fn average_quality(&self, last_n: usize) -> f64 {
        let recent = self.get_recent(last_n);
        if recent.is_empty() {
            return 0.5;
        }

        let sum: f64 = recent.iter().map(|p| p.quality_score).sum();
        sum / recent.len() as f64
    }

    pub fn domain_performance(&self) -> HashMap<String, DomainStats> {
        let mut stats: HashMap<String, DomainStats> = HashMap::new();

        for perf in &self.history {
            let entry = stats
                .entry(perf.domain.clone())
                .or_insert(DomainStats::default());
            entry.total += 1;
            entry.quality_sum += perf.quality_score;
            if perf.success {
                entry.successes += 1;
            }
        }

        stats
    }

    /// Detect performance degradation by comparing recent vs baseline metrics
    pub fn detect_degradation(&self, window_size: usize) -> Vec<PerformanceDegradation> {
        if self.history.len() < window_size * 2 {
            return vec![]; // Not enough data
        }

        let recent = self.get_recent(window_size);
        let baseline_start = self.history.len().saturating_sub(window_size * 2);
        let baseline_end = self.history.len().saturating_sub(window_size);
        let baseline = &self.history[baseline_start..baseline_end];

        let mut degradations = Vec::new();

        // Check success rate degradation
        let recent_success =
            recent.iter().filter(|p| p.success).count() as f64 / recent.len() as f64;
        let baseline_success =
            baseline.iter().filter(|p| p.success).count() as f64 / baseline.len() as f64;

        if baseline_success > 0.0 {
            let degradation_pct = ((baseline_success - recent_success) / baseline_success) * 100.0;
            if degradation_pct > 5.0 {
                degradations.push(PerformanceDegradation {
                    detected: true,
                    metric: "success_rate".to_string(),
                    current_value: recent_success,
                    baseline_value: baseline_success,
                    degradation_percent: degradation_pct,
                    severity: classify_severity(degradation_pct),
                });
            }
        }

        // Check quality degradation
        let recent_quality: f64 =
            recent.iter().map(|p| p.quality_score).sum::<f64>() / recent.len() as f64;
        let baseline_quality: f64 =
            baseline.iter().map(|p| p.quality_score).sum::<f64>() / baseline.len() as f64;

        if baseline_quality > 0.0 {
            let degradation_pct = ((baseline_quality - recent_quality) / baseline_quality) * 100.0;
            if degradation_pct > 5.0 {
                degradations.push(PerformanceDegradation {
                    detected: true,
                    metric: "quality_score".to_string(),
                    current_value: recent_quality,
                    baseline_value: baseline_quality,
                    degradation_percent: degradation_pct,
                    severity: classify_severity(degradation_pct),
                });
            }
        }

        // Check latency degradation
        let recent_latency: f64 =
            recent.iter().map(|p| p.latency_ms as f64).sum::<f64>() / recent.len() as f64;
        let baseline_latency: f64 =
            baseline.iter().map(|p| p.latency_ms as f64).sum::<f64>() / baseline.len() as f64;

        if baseline_latency > 0.0 {
            let degradation_pct = ((recent_latency - baseline_latency) / baseline_latency) * 100.0;
            if degradation_pct > 15.0 {
                // Higher threshold for latency (15% acceptable)
                degradations.push(PerformanceDegradation {
                    detected: true,
                    metric: "latency_ms".to_string(),
                    current_value: recent_latency,
                    baseline_value: baseline_latency,
                    degradation_percent: degradation_pct,
                    severity: classify_severity(degradation_pct),
                });
            }
        }

        degradations
    }

    /// Identify performance bottlenecks
    pub fn identify_bottlenecks(&self, threshold: usize) -> Vec<PerformanceBottleneck> {
        let recent = self.get_recent(100);
        if recent.is_empty() {
            return vec![];
        }

        let mut bottlenecks = Vec::new();

        // Check for high latency (>95th percentile)
        let mut latencies: Vec<u64> = recent.iter().map(|p| p.latency_ms).collect();
        latencies.sort_unstable();
        let p95_idx = (latencies.len() as f64 * 0.95) as usize;
        let p95_latency = latencies.get(p95_idx).copied().unwrap_or(0);
        let avg_latency: u64 = latencies.iter().sum::<u64>() / latencies.len() as u64;

        if p95_latency > 5000 {
            // >5s is bottleneck
            bottlenecks.push(PerformanceBottleneck {
                bottleneck_type: BottleneckType::HighLatency,
                affected_domain: None,
                average_latency_ms: avg_latency,
                percentile_95_ms: p95_latency,
                recommendation: "Consider caching, parallel processing, or model optimization"
                    .to_string(),
            });
        }

        // Check for low quality domains
        let domain_stats = self.domain_performance();
        for (domain, stats) in domain_stats.iter() {
            if stats.total >= threshold && stats.average_quality() < 0.6 {
                bottlenecks.push(PerformanceBottleneck {
                    bottleneck_type: BottleneckType::LowQuality,
                    affected_domain: Some(domain.clone()),
                    average_latency_ms: 0,
                    percentile_95_ms: 0,
                    recommendation: format!("Create specialized agent for {} domain", domain),
                });
            }

            if stats.total >= threshold && stats.success_rate() < 0.7 {
                bottlenecks.push(PerformanceBottleneck {
                    bottleneck_type: BottleneckType::FrequentFailures,
                    affected_domain: Some(domain.clone()),
                    average_latency_ms: 0,
                    percentile_95_ms: 0,
                    recommendation: format!("Investigate error patterns in {} domain", domain),
                });
            }
        }

        // Check user satisfaction (if available)
        let satisfied: Vec<&QueryPerformance> = recent
            .iter()
            .filter(|p| p.user_satisfaction.is_some())
            .collect();

        if satisfied.len() >= threshold {
            let avg_satisfaction: f64 = satisfied
                .iter()
                .filter_map(|p| p.user_satisfaction)
                .sum::<f64>()
                / satisfied.len() as f64;

            if avg_satisfaction < 0.6 {
                bottlenecks.push(PerformanceBottleneck {
                    bottleneck_type: BottleneckType::UserDissatisfaction,
                    affected_domain: None,
                    average_latency_ms: 0,
                    percentile_95_ms: 0,
                    recommendation: "Review user feedback and adjust quality thresholds"
                        .to_string(),
                });
            }
        }

        bottlenecks
    }

    /// Analyze performance trends over time
    pub fn analyze_trends(&self, window_size: usize) -> Vec<PerformanceTrend> {
        if self.history.len() < window_size * 3 {
            return vec![]; // Need at least 3 windows for trend
        }

        let mut trends = Vec::new();

        // Divide history into 3 windows
        let total = self.history.len();
        let old_start = total.saturating_sub(window_size * 3);
        let old_end = total.saturating_sub(window_size * 2);
        let mid_start = old_end;
        let mid_end = total.saturating_sub(window_size);
        let recent_start = mid_end;

        let old_window = &self.history[old_start..old_end];
        let mid_window = &self.history[mid_start..mid_end];
        let recent_window = &self.history[recent_start..];

        // Analyze success rate trend
        let old_success =
            old_window.iter().filter(|p| p.success).count() as f64 / old_window.len() as f64;
        let mid_success =
            mid_window.iter().filter(|p| p.success).count() as f64 / mid_window.len() as f64;
        let recent_success =
            recent_window.iter().filter(|p| p.success).count() as f64 / recent_window.len() as f64;

        trends.push(classify_trend(
            "success_rate",
            old_success,
            mid_success,
            recent_success,
        ));

        // Analyze quality trend
        let old_quality =
            old_window.iter().map(|p| p.quality_score).sum::<f64>() / old_window.len() as f64;
        let mid_quality =
            mid_window.iter().map(|p| p.quality_score).sum::<f64>() / mid_window.len() as f64;
        let recent_quality =
            recent_window.iter().map(|p| p.quality_score).sum::<f64>() / recent_window.len() as f64;

        trends.push(classify_trend(
            "quality_score",
            old_quality,
            mid_quality,
            recent_quality,
        ));

        // Analyze latency trend (inverted - lower is better)
        let old_latency =
            old_window.iter().map(|p| p.latency_ms as f64).sum::<f64>() / old_window.len() as f64;
        let mid_latency =
            mid_window.iter().map(|p| p.latency_ms as f64).sum::<f64>() / mid_window.len() as f64;
        let recent_latency = recent_window
            .iter()
            .map(|p| p.latency_ms as f64)
            .sum::<f64>()
            / recent_window.len() as f64;

        // For latency, improvement = reduction
        trends.push(classify_trend_inverted(
            "latency_ms",
            old_latency,
            mid_latency,
            recent_latency,
        ));

        trends
    }
}

#[derive(Debug, Clone, Default)]
pub struct DomainStats {
    pub total: usize,
    pub successes: usize,
    pub quality_sum: f64,
}

impl DomainStats {
    pub fn success_rate(&self) -> f64 {
        if self.total == 0 {
            return 0.5;
        }
        self.successes as f64 / self.total as f64
    }

    pub fn average_quality(&self) -> f64 {
        if self.total == 0 {
            return 0.5;
        }
        self.quality_sum / self.total as f64
    }
}

// Helper functions for classification

pub(crate) fn classify_severity(degradation_percent: f64) -> DegradationSeverity {
    if degradation_percent < 5.0 {
        DegradationSeverity::None
    } else if degradation_percent < 15.0 {
        DegradationSeverity::Minor
    } else if degradation_percent < 30.0 {
        DegradationSeverity::Moderate
    } else {
        DegradationSeverity::Severe
    }
}

fn classify_trend(metric: &str, old: f64, mid: f64, recent: f64) -> PerformanceTrend {
    // Calculate linear regression slope
    let x_values = vec![0.0, 1.0, 2.0];
    let y_values = vec![old, mid, recent];

    let mean_x = 1.0;
    let mean_y = (old + mid + recent) / 3.0;

    let mut numerator = 0.0;
    let mut denominator = 0.0;

    for i in 0..3 {
        numerator += (x_values[i] - mean_x) * (y_values[i] - mean_y);
        denominator += (x_values[i] - mean_x).powi(2);
    }

    let slope = if denominator != 0.0 {
        numerator / denominator
    } else {
        0.0
    };

    let change_percent = if old != 0.0 {
        ((recent - old) / old) * 100.0
    } else {
        0.0
    };

    // R-squared for confidence
    let mut ss_res = 0.0;
    let mut ss_tot = 0.0;

    for i in 0..3 {
        let y_pred = mean_y + slope * (x_values[i] - mean_x);
        ss_res += (y_values[i] - y_pred).powi(2);
        ss_tot += (y_values[i] - mean_y).powi(2);
    }

    let r_squared = if ss_tot != 0.0 {
        1.0 - (ss_res / ss_tot)
    } else {
        0.0
    };

    let direction = if slope.abs() < 0.01 {
        TrendDirection::Stable
    } else if slope > 0.0 {
        TrendDirection::Improving
    } else {
        TrendDirection::Degrading
    };

    PerformanceTrend {
        metric: metric.to_string(),
        direction,
        change_percent,
        confidence: r_squared,
    }
}

fn classify_trend_inverted(metric: &str, old: f64, mid: f64, recent: f64) -> PerformanceTrend {
    // For latency, lower is better, so invert the trend
    let mut trend = classify_trend(metric, old, mid, recent);

    trend.direction = match trend.direction {
        TrendDirection::Improving => TrendDirection::Degrading,
        TrendDirection::Degrading => TrendDirection::Improving,
        TrendDirection::Stable => TrendDirection::Stable,
    };

    trend.change_percent = -trend.change_percent;

    trend
}
