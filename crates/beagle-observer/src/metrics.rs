//! Metrics collection and registry with Prometheus integration

use anyhow::Result;
use prometheus::{
    Counter, CounterVec, Gauge, GaugeVec, Histogram, HistogramOpts, HistogramVec, Opts, Registry,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Metric type
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MetricType {
    Counter,
    Gauge,
    Histogram,
    Summary,
}

/// Metric data point
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Metric {
    pub name: String,
    pub value: f64,
    pub metric_type: MetricType,
    pub labels: HashMap<String, String>,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

impl Metric {
    /// Create counter metric
    pub fn counter(name: &str, value: f64) -> Self {
        Self {
            name: name.to_string(),
            value,
            metric_type: MetricType::Counter,
            labels: HashMap::new(),
            timestamp: chrono::Utc::now(),
        }
    }

    /// Create gauge metric
    pub fn gauge(name: &str, value: f64) -> Self {
        Self {
            name: name.to_string(),
            value,
            metric_type: MetricType::Gauge,
            labels: HashMap::new(),
            timestamp: chrono::Utc::now(),
        }
    }

    /// Create histogram metric
    pub fn histogram(name: &str, values: Vec<f64>) -> Self {
        let value = if !values.is_empty() {
            values.iter().sum::<f64>() / values.len() as f64
        } else {
            0.0
        };

        Self {
            name: name.to_string(),
            value,
            metric_type: MetricType::Histogram,
            labels: HashMap::new(),
            timestamp: chrono::Utc::now(),
        }
    }

    /// Add label
    pub fn with_label(mut self, key: &str, value: &str) -> Self {
        self.labels.insert(key.to_string(), value.to_string());
        self
    }
}

/// Metrics collector with Prometheus backend
pub struct MetricsCollector {
    registry: Registry,
    counters: Arc<RwLock<HashMap<String, Counter>>>,
    gauges: Arc<RwLock<HashMap<String, Gauge>>>,
    histograms: Arc<RwLock<HashMap<String, Histogram>>>,
    buffer: Arc<RwLock<Vec<Metric>>>,
    config: MetricsConfig,
}

impl MetricsCollector {
    /// Create new metrics collector with default config
    pub fn new() -> Self {
        Self::with_config(MetricsConfig::default()).unwrap_or_else(|_| {
            // Fallback without process collector if it fails
            Self {
                registry: Registry::new(),
                counters: Arc::new(RwLock::new(HashMap::new())),
                gauges: Arc::new(RwLock::new(HashMap::new())),
                histograms: Arc::new(RwLock::new(HashMap::new())),
                buffer: Arc::new(RwLock::new(Vec::new())),
                config: MetricsConfig::default(),
            }
        })
    }

    /// Create new metrics collector with custom config
    pub fn with_config(config: MetricsConfig) -> Result<Self> {
        let registry = Registry::new();

        // Try to register default metrics (may fail on some platforms)
        if let Ok(process_collector) =
            std::panic::catch_unwind(|| prometheus::process_collector::ProcessCollector::for_self())
        {
            let _ = registry.register(Box::new(process_collector));
        }

        Ok(Self {
            registry,
            counters: Arc::new(RwLock::new(HashMap::new())),
            gauges: Arc::new(RwLock::new(HashMap::new())),
            histograms: Arc::new(RwLock::new(HashMap::new())),
            buffer: Arc::new(RwLock::new(Vec::new())),
            config,
        })
    }

    /// Record a metric by name and value (simple sync interface)
    pub fn record(&self, name: &str, value: f64, _labels: HashMap<String, String>) {
        // Use tokio blocking for sync context
        let metric = Metric::gauge(name, value);
        let buffer = self.buffer.clone();
        tokio::spawn(async move {
            let mut buf = buffer.write().await;
            buf.push(metric);
        });
    }

    /// Record a full metric object (async interface)
    pub async fn record_metric(&self, metric: Metric) -> Result<()> {
        // Add to buffer for historical data
        {
            let mut buffer = self.buffer.write().await;
            buffer.push(metric.clone());

            // Keep buffer size limited
            if buffer.len() > self.config.max_buffer_size {
                let drain_count = buffer.len() - self.config.max_buffer_size;
                buffer.drain(0..drain_count);
            }
        }

        // Update Prometheus metrics
        match metric.metric_type {
            MetricType::Counter => {
                let counter = self.get_or_create_counter(&metric.name).await?;
                counter.inc_by(metric.value);
            }
            MetricType::Gauge => {
                let gauge = self.get_or_create_gauge(&metric.name).await?;
                gauge.set(metric.value);
            }
            MetricType::Histogram => {
                let histogram = self.get_or_create_histogram(&metric.name).await?;
                histogram.observe(metric.value);
            }
            MetricType::Summary => {
                // Summary type handled similarly to histogram
                let histogram = self.get_or_create_histogram(&metric.name).await?;
                histogram.observe(metric.value);
            }
        }

        Ok(())
    }

    /// Get metrics within time window
    pub async fn get_window(&self, window: TimeWindow) -> Result<Vec<Metric>> {
        let buffer = self.buffer.read().await;
        let cutoff = chrono::Utc::now() - window.to_duration();

        Ok(buffer
            .iter()
            .filter(|m| m.timestamp > cutoff)
            .cloned()
            .collect())
    }

    /// Get or create counter
    async fn get_or_create_counter(&self, name: &str) -> Result<Counter> {
        let mut counters = self.counters.write().await;

        if let Some(counter) = counters.get(name) {
            return Ok(counter.clone());
        }

        let opts = Opts::new(name, format!("Counter for {}", name));
        let counter = Counter::with_opts(opts)?;
        self.registry.register(Box::new(counter.clone()))?;
        counters.insert(name.to_string(), counter.clone());

        Ok(counter)
    }

    /// Get or create gauge
    async fn get_or_create_gauge(&self, name: &str) -> Result<Gauge> {
        let mut gauges = self.gauges.write().await;

        if let Some(gauge) = gauges.get(name) {
            return Ok(gauge.clone());
        }

        let opts = Opts::new(name, format!("Gauge for {}", name));
        let gauge = Gauge::with_opts(opts)?;
        self.registry.register(Box::new(gauge.clone()))?;
        gauges.insert(name.to_string(), gauge.clone());

        Ok(gauge)
    }

    /// Get or create histogram
    async fn get_or_create_histogram(&self, name: &str) -> Result<Histogram> {
        let mut histograms = self.histograms.write().await;

        if let Some(histogram) = histograms.get(name) {
            return Ok(histogram.clone());
        }

        let opts = HistogramOpts::new(name, format!("Histogram for {}", name));
        let histogram = Histogram::with_opts(opts)?;
        self.registry.register(Box::new(histogram.clone()))?;
        histograms.insert(name.to_string(), histogram.clone());

        Ok(histogram)
    }

    /// Export metrics in Prometheus format
    pub fn export(&self) -> Result<String> {
        use prometheus::Encoder;
        let encoder = prometheus::TextEncoder::new();
        let metric_families = self.registry.gather();

        let mut buffer = Vec::new();
        encoder.encode(&metric_families, &mut buffer)?;

        Ok(String::from_utf8(buffer)?)
    }

    /// Get metric statistics
    pub async fn get_stats(&self, metric_name: &str) -> Result<MetricStats> {
        let buffer = self.buffer.read().await;
        let values: Vec<f64> = buffer
            .iter()
            .filter(|m| m.name == metric_name)
            .map(|m| m.value)
            .collect();

        if values.is_empty() {
            return Ok(MetricStats::default());
        }

        let count = values.len() as f64;
        let sum: f64 = values.iter().sum();
        let mean = sum / count;

        let mut sorted = values.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());

        let min = *sorted.first().unwrap();
        let max = *sorted.last().unwrap();
        let median = if sorted.len() % 2 == 0 {
            (sorted[sorted.len() / 2 - 1] + sorted[sorted.len() / 2]) / 2.0
        } else {
            sorted[sorted.len() / 2]
        };

        let p95_idx = ((sorted.len() as f64 * 0.95) as usize).min(sorted.len() - 1);
        let p99_idx = ((sorted.len() as f64 * 0.99) as usize).min(sorted.len() - 1);

        let variance = values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / count;
        let std_dev = variance.sqrt();

        Ok(MetricStats {
            count: count as usize,
            sum,
            mean,
            median,
            min,
            max,
            p95: sorted[p95_idx],
            p99: sorted[p99_idx],
            std_dev,
        })
    }
}

/// Metrics registry for managing multiple collectors
pub struct MetricsRegistry {
    collectors: Arc<RwLock<HashMap<String, Arc<MetricsCollector>>>>,
    global: Arc<MetricsCollector>,
}

impl MetricsRegistry {
    /// Create new registry
    pub fn new() -> Result<Self> {
        let global = Arc::new(MetricsCollector::new());

        Ok(Self {
            collectors: Arc::new(RwLock::new(HashMap::new())),
            global,
        })
    }

    /// Register a collector
    pub async fn register(&self, name: &str, collector: Arc<MetricsCollector>) {
        let mut collectors = self.collectors.write().await;
        collectors.insert(name.to_string(), collector);
    }

    /// Get collector by name
    pub async fn get(&self, name: &str) -> Option<Arc<MetricsCollector>> {
        let collectors = self.collectors.read().await;
        collectors.get(name).cloned()
    }

    /// Get global collector
    pub fn global(&self) -> Arc<MetricsCollector> {
        self.global.clone()
    }

    /// Export all metrics
    pub async fn export_all(&self) -> Result<HashMap<String, String>> {
        let mut exports = HashMap::new();

        // Export global metrics
        exports.insert("global".to_string(), self.global.export()?);

        // Export from all registered collectors
        let collectors = self.collectors.read().await;
        for (name, collector) in collectors.iter() {
            exports.insert(name.clone(), collector.export()?);
        }

        Ok(exports)
    }
}

/// Time window for metrics aggregation
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum TimeWindow {
    Seconds(u64),
    Minutes(u64),
    Hours(u64),
    Days(u64),
}

impl TimeWindow {
    /// Convert to duration
    pub fn to_duration(&self) -> chrono::Duration {
        match self {
            Self::Seconds(s) => chrono::Duration::seconds(*s as i64),
            Self::Minutes(m) => chrono::Duration::minutes(*m as i64),
            Self::Hours(h) => chrono::Duration::hours(*h as i64),
            Self::Days(d) => chrono::Duration::days(*d as i64),
        }
    }
}

/// Metric statistics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MetricStats {
    pub count: usize,
    pub sum: f64,
    pub mean: f64,
    pub median: f64,
    pub min: f64,
    pub max: f64,
    pub p95: f64,
    pub p99: f64,
    pub std_dev: f64,
}

/// Metrics configuration
#[derive(Debug, Clone)]
pub struct MetricsConfig {
    pub max_buffer_size: usize,
    pub export_interval: Duration,
    pub retention_period: Duration,
}

impl Default for MetricsConfig {
    fn default() -> Self {
        Self {
            max_buffer_size: 10000,
            export_interval: Duration::from_secs(10),
            retention_period: Duration::from_secs(3600), // 1 hour
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_metrics_collector() {
        let collector = MetricsCollector::new();

        // Record counter
        let counter = Metric::counter("test.counter", 1.0);
        collector.record_metric(counter).await.unwrap();

        // Record gauge
        let gauge = Metric::gauge("test.gauge", 42.0);
        collector.record_metric(gauge).await.unwrap();

        // Record histogram
        let histogram = Metric::histogram("test.histogram", vec![1.0, 2.0, 3.0]);
        collector.record_metric(histogram).await.unwrap();

        // Get metrics window
        let window = TimeWindow::Minutes(5);
        let metrics = collector.get_window(window).await.unwrap();
        assert_eq!(metrics.len(), 3);

        // Export metrics
        let export = collector.export().unwrap();
        assert!(!export.is_empty());
    }

    #[tokio::test]
    async fn test_metric_stats() {
        let collector = MetricsCollector::new();

        // Record multiple values
        for i in 1..=100 {
            let metric = Metric::gauge("test.stat", i as f64);
            collector.record_metric(metric).await.unwrap();
        }

        // Get statistics
        let stats = collector.get_stats("test.stat").await.unwrap();
        assert_eq!(stats.count, 100);
        assert_eq!(stats.mean, 50.5);
        assert_eq!(stats.median, 50.5);
        assert_eq!(stats.min, 1.0);
        assert_eq!(stats.max, 100.0);
    }
}
