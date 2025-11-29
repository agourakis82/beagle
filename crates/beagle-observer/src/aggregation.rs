//! Data aggregation for metrics and events
//!
//! Provides time-windowed aggregation of metrics data with various
//! aggregation types (sum, average, min, max, percentiles).

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::time::{Duration, Instant};

/// Time window for aggregation
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct TimeWindow {
    /// Window duration
    pub duration: Duration,
    /// Slide interval (for sliding windows)
    pub slide: Option<Duration>,
}

impl TimeWindow {
    /// Create a tumbling window (non-overlapping)
    pub fn tumbling(duration: Duration) -> Self {
        Self {
            duration,
            slide: None,
        }
    }

    /// Create a sliding window
    pub fn sliding(duration: Duration, slide: Duration) -> Self {
        Self {
            duration,
            slide: Some(slide),
        }
    }

    /// 1-minute window
    pub fn one_minute() -> Self {
        Self::tumbling(Duration::from_secs(60))
    }

    /// 5-minute window
    pub fn five_minutes() -> Self {
        Self::tumbling(Duration::from_secs(300))
    }

    /// 1-hour window
    pub fn one_hour() -> Self {
        Self::tumbling(Duration::from_secs(3600))
    }
}

impl Default for TimeWindow {
    fn default() -> Self {
        Self::one_minute()
    }
}

/// Aggregation type
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum AggregationType {
    /// Sum of all values
    Sum,
    /// Average (mean) of values
    Average,
    /// Minimum value
    Min,
    /// Maximum value
    Max,
    /// Count of values
    Count,
    /// Percentile (e.g., p50, p95, p99)
    Percentile(u8),
    /// Standard deviation
    StdDev,
    /// Rate (values per second)
    Rate,
}

/// Aggregated result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatedResult {
    /// Aggregation type used
    pub aggregation_type: AggregationType,
    /// Resulting value
    pub value: f64,
    /// Number of samples
    pub sample_count: usize,
    /// Window start time (as duration since start)
    pub window_start: Duration,
    /// Window end time
    pub window_end: Duration,
}

/// Data point with timestamp
#[derive(Debug, Clone)]
struct DataPoint {
    value: f64,
    timestamp: Instant,
}

/// Aggregator for time-series data
pub struct Aggregator {
    /// Data buffers per metric
    buffers: HashMap<String, VecDeque<DataPoint>>,
    /// Time window configuration
    window: TimeWindow,
    /// Maximum buffer size
    max_buffer_size: usize,
    /// Start time for relative timestamps
    start_time: Instant,
}

impl Aggregator {
    /// Create new aggregator with default window
    pub fn new() -> Self {
        Self::with_window(TimeWindow::default())
    }

    /// Create aggregator with specific window
    pub fn with_window(window: TimeWindow) -> Self {
        Self {
            buffers: HashMap::new(),
            window,
            max_buffer_size: 10000,
            start_time: Instant::now(),
        }
    }

    /// Record a value for a metric
    pub fn record(&mut self, metric_name: &str, value: f64) {
        let buffer = self
            .buffers
            .entry(metric_name.to_string())
            .or_insert_with(VecDeque::new);

        buffer.push_back(DataPoint {
            value,
            timestamp: Instant::now(),
        });

        // Trim old data
        self.trim_buffer(metric_name);
    }

    /// Aggregate data for a metric
    pub fn aggregate(
        &self,
        metric_name: &str,
        aggregation_type: AggregationType,
    ) -> Option<AggregatedResult> {
        let buffer = self.buffers.get(metric_name)?;

        if buffer.is_empty() {
            return None;
        }

        let now = Instant::now();
        let window_start = now - self.window.duration;

        // Filter values within window
        let values: Vec<f64> = buffer
            .iter()
            .filter(|dp| dp.timestamp >= window_start)
            .map(|dp| dp.value)
            .collect();

        if values.is_empty() {
            return None;
        }

        let value = self.compute_aggregation(&values, aggregation_type);

        Some(AggregatedResult {
            aggregation_type,
            value,
            sample_count: values.len(),
            window_start: window_start.duration_since(self.start_time),
            window_end: now.duration_since(self.start_time),
        })
    }

    /// Compute aggregation for given values
    fn compute_aggregation(&self, values: &[f64], agg_type: AggregationType) -> f64 {
        match agg_type {
            AggregationType::Sum => values.iter().sum(),
            AggregationType::Average => {
                if values.is_empty() {
                    0.0
                } else {
                    values.iter().sum::<f64>() / values.len() as f64
                }
            }
            AggregationType::Min => values.iter().cloned().fold(f64::INFINITY, f64::min),
            AggregationType::Max => values.iter().cloned().fold(f64::NEG_INFINITY, f64::max),
            AggregationType::Count => values.len() as f64,
            AggregationType::Percentile(p) => self.compute_percentile(values, p),
            AggregationType::StdDev => self.compute_std_dev(values),
            AggregationType::Rate => {
                let duration_secs = self.window.duration.as_secs_f64();
                if duration_secs > 0.0 {
                    values.iter().sum::<f64>() / duration_secs
                } else {
                    0.0
                }
            }
        }
    }

    /// Compute percentile
    fn compute_percentile(&self, values: &[f64], percentile: u8) -> f64 {
        if values.is_empty() {
            return 0.0;
        }

        let mut sorted = values.to_vec();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let idx = (percentile as f64 / 100.0 * (sorted.len() - 1) as f64).round() as usize;
        sorted[idx.min(sorted.len() - 1)]
    }

    /// Compute standard deviation
    fn compute_std_dev(&self, values: &[f64]) -> f64 {
        if values.len() < 2 {
            return 0.0;
        }

        let mean = values.iter().sum::<f64>() / values.len() as f64;
        let variance =
            values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / (values.len() - 1) as f64;

        variance.sqrt()
    }

    /// Trim old data from buffer
    fn trim_buffer(&mut self, metric_name: &str) {
        if let Some(buffer) = self.buffers.get_mut(metric_name) {
            // Remove data older than 2x window duration
            let cutoff = Instant::now() - (self.window.duration * 2);
            while let Some(front) = buffer.front() {
                if front.timestamp < cutoff {
                    buffer.pop_front();
                } else {
                    break;
                }
            }

            // Also enforce max buffer size
            while buffer.len() > self.max_buffer_size {
                buffer.pop_front();
            }
        }
    }

    /// Clear all data
    pub fn clear(&mut self) {
        self.buffers.clear();
    }

    /// Get all metric names
    pub fn metric_names(&self) -> Vec<String> {
        self.buffers.keys().cloned().collect()
    }
}

impl Default for Aggregator {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_aggregation_sum() {
        let mut agg = Aggregator::new();

        agg.record("test", 10.0);
        agg.record("test", 20.0);
        agg.record("test", 30.0);

        let result = agg.aggregate("test", AggregationType::Sum).unwrap();
        assert_eq!(result.value, 60.0);
        assert_eq!(result.sample_count, 3);
    }

    #[test]
    fn test_aggregation_average() {
        let mut agg = Aggregator::new();

        agg.record("test", 10.0);
        agg.record("test", 20.0);
        agg.record("test", 30.0);

        let result = agg.aggregate("test", AggregationType::Average).unwrap();
        assert_eq!(result.value, 20.0);
    }

    #[test]
    fn test_aggregation_min_max() {
        let mut agg = Aggregator::new();

        agg.record("test", 10.0);
        agg.record("test", 5.0);
        agg.record("test", 30.0);

        let min = agg.aggregate("test", AggregationType::Min).unwrap();
        let max = agg.aggregate("test", AggregationType::Max).unwrap();

        assert_eq!(min.value, 5.0);
        assert_eq!(max.value, 30.0);
    }

    #[test]
    fn test_percentile() {
        let mut agg = Aggregator::new();

        for i in 1..=100 {
            agg.record("test", i as f64);
        }

        let p50 = agg
            .aggregate("test", AggregationType::Percentile(50))
            .unwrap();
        let p99 = agg
            .aggregate("test", AggregationType::Percentile(99))
            .unwrap();

        assert!((p50.value - 50.0).abs() < 2.0);
        assert!((p99.value - 99.0).abs() < 2.0);
    }
}
