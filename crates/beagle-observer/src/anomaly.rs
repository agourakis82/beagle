//! Anomaly detection with statistical and ML-based methods

use anyhow::Result;
use nalgebra::{DMatrix, DVector};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::metrics::{Metric, TimeWindow};
use crate::severity::SeverityLevel;

/// Anomaly detection result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Anomaly {
    pub metric_name: String,
    pub score: f64,
    pub expected_value: f64,
    pub actual_value: f64,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub detection_method: DetectionMethod,
    pub description: String,
    pub metadata: HashMap<String, String>,
}

impl Anomaly {
    /// Get severity based on score
    pub fn severity(&self) -> SeverityLevel {
        match self.score {
            s if s >= 0.9 => SeverityLevel::Critical,
            s if s >= 0.7 => SeverityLevel::High,
            s if s >= 0.5 => SeverityLevel::Medium,
            s if s >= 0.3 => SeverityLevel::Low,
            _ => SeverityLevel::Info,
        }
    }
}

/// Anomaly score
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct AnomalyScore {
    pub value: f64,
    pub confidence: f64,
}

/// Detection method used
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DetectionMethod {
    ZScore,
    IsolationForest,
    LSTM,
    MovingAverage,
    ExponentialSmoothing,
    SeasonalDecomposition,
}

/// Anomaly detector with multiple algorithms
pub struct AnomalyDetector {
    /// Z-score detector
    zscore_detector: ZScoreDetector,

    /// Isolation forest detector
    isolation_forest: IsolationForest,

    /// Moving average detector
    moving_avg_detector: MovingAverageDetector,

    /// Seasonal detector
    seasonal_detector: SeasonalDetector,

    /// Historical data
    history: Arc<RwLock<HashMap<String, VecDeque<f64>>>>,

    /// Detected anomalies
    anomalies: Arc<RwLock<Vec<Anomaly>>>,

    /// Configuration
    config: AnomalyConfig,
}

impl AnomalyDetector {
    /// Create new anomaly detector
    pub async fn new(config: AnomalyConfig) -> Result<Self> {
        Ok(Self {
            zscore_detector: ZScoreDetector::new(config.zscore_threshold),
            isolation_forest: IsolationForest::new(config.forest_size, config.sample_size)?,
            moving_avg_detector: MovingAverageDetector::new(config.window_size),
            seasonal_detector: SeasonalDetector::new(config.seasonal_period),
            history: Arc::new(RwLock::new(HashMap::new())),
            anomalies: Arc::new(RwLock::new(Vec::new())),
            config,
        })
    }

    /// Check metric for anomalies
    pub async fn check(&self, metric: &Metric) -> Result<Option<Anomaly>> {
        // Add to history
        {
            let mut history = self.history.write().await;
            let values = history
                .entry(metric.name.clone())
                .or_insert_with(|| VecDeque::with_capacity(self.config.history_size));

            values.push_back(metric.value);
            if values.len() > self.config.history_size {
                values.pop_front();
            }
        }

        // Get historical values
        let history = self.history.read().await;
        let values = match history.get(&metric.name) {
            Some(v) => v,
            None => return Ok(None), // No history for this metric yet
        };

        if values.len() < self.config.min_samples {
            return Ok(None); // Not enough data
        }

        let values_vec: Vec<f64> = values.iter().copied().collect();

        // Run multiple detection methods
        let mut scores = Vec::new();
        let mut methods = Vec::new();

        // Z-score detection
        if let Some(score) = self.zscore_detector.detect(&values_vec, metric.value) {
            scores.push(score);
            methods.push(DetectionMethod::ZScore);
        }

        // Moving average detection
        if let Some(score) = self.moving_avg_detector.detect(&values_vec, metric.value) {
            scores.push(score);
            methods.push(DetectionMethod::MovingAverage);
        }

        // Seasonal detection if enough data
        if values.len() >= self.config.seasonal_period * 2 {
            if let Some(score) = self.seasonal_detector.detect(&values_vec, metric.value) {
                scores.push(score);
                methods.push(DetectionMethod::SeasonalDecomposition);
            }
        }

        // Isolation forest for multivariate anomalies
        if self.config.enable_isolation_forest && values.len() >= self.config.sample_size {
            if let Ok(Some(score)) = self
                .isolation_forest
                .detect(&values_vec, metric.value)
                .await
            {
                scores.push(score);
                methods.push(DetectionMethod::IsolationForest);
            }
        }

        // Combine scores (ensemble approach)
        if scores.is_empty() {
            return Ok(None);
        }

        let avg_score = scores.iter().sum::<f64>() / scores.len() as f64;

        if avg_score > self.config.anomaly_threshold {
            // Calculate expected value
            let expected = values_vec.iter().sum::<f64>() / values_vec.len() as f64;

            // Find the method with highest score
            let (method_idx, max_score) = scores
                .iter()
                .enumerate()
                .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
                .unwrap();

            let anomaly = Anomaly {
                metric_name: metric.name.clone(),
                score: *max_score,
                expected_value: expected,
                actual_value: metric.value,
                timestamp: metric.timestamp,
                detection_method: methods[method_idx].clone(),
                description: format!(
                    "Anomaly detected: value {} deviates from expected {} (score: {:.2})",
                    metric.value, expected, max_score
                ),
                metadata: metric.labels.clone(),
            };

            // Store anomaly
            let mut anomalies = self.anomalies.write().await;
            anomalies.push(anomaly.clone());

            // Keep limited history
            if anomalies.len() > self.config.max_anomalies {
                let drain_count = anomalies.len() - self.config.max_anomalies;
                anomalies.drain(0..drain_count);
            }

            return Ok(Some(anomaly));
        }

        Ok(None)
    }

    /// Get recent anomalies
    pub async fn get_recent(&self, window: TimeWindow) -> Result<Vec<Anomaly>> {
        let anomalies = self.anomalies.read().await;
        let cutoff = chrono::Utc::now() - window.to_duration();

        Ok(anomalies
            .iter()
            .filter(|a| a.timestamp > cutoff)
            .cloned()
            .collect())
    }

    /// Train models with historical data
    pub async fn train(&self, metrics: &[Metric]) -> Result<()> {
        // Group metrics by name
        let mut grouped: HashMap<String, Vec<f64>> = HashMap::new();
        for metric in metrics {
            grouped
                .entry(metric.name.clone())
                .or_default()
                .push(metric.value);
        }

        // Train isolation forest if enabled
        if self.config.enable_isolation_forest {
            for (_, values) in grouped.iter() {
                if values.len() >= self.config.sample_size {
                    self.isolation_forest.train(values).await?;
                }
            }
        }

        Ok(())
    }
}

/// Z-score based detector
struct ZScoreDetector {
    threshold: f64,
}

impl ZScoreDetector {
    fn new(threshold: f64) -> Self {
        Self { threshold }
    }

    fn detect(&self, values: &[f64], current: f64) -> Option<f64> {
        if values.len() < 2 {
            return None;
        }

        let mean = values.iter().sum::<f64>() / values.len() as f64;
        let variance = values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / values.len() as f64;
        let std_dev = variance.sqrt();

        if std_dev == 0.0 {
            return None;
        }

        let z_score = (current - mean).abs() / std_dev;

        if z_score > self.threshold {
            Some(z_score / (self.threshold * 2.0)) // Normalize to 0-1
        } else {
            None
        }
    }
}

/// Moving average detector
struct MovingAverageDetector {
    window_size: usize,
}

impl MovingAverageDetector {
    fn new(window_size: usize) -> Self {
        Self { window_size }
    }

    fn detect(&self, values: &[f64], current: f64) -> Option<f64> {
        if values.len() < self.window_size {
            return None;
        }

        let start = values.len().saturating_sub(self.window_size);
        let window = &values[start..];
        let moving_avg = window.iter().sum::<f64>() / window.len() as f64;
        let moving_std = (window.iter().map(|v| (v - moving_avg).powi(2)).sum::<f64>()
            / window.len() as f64)
            .sqrt();

        if moving_std == 0.0 {
            return None;
        }

        let deviation = (current - moving_avg).abs() / moving_std;

        if deviation > 3.0 {
            Some((deviation - 3.0) / 3.0) // Normalize
        } else {
            None
        }
    }
}

/// Seasonal decomposition detector
struct SeasonalDetector {
    period: usize,
}

impl SeasonalDetector {
    fn new(period: usize) -> Self {
        Self { period }
    }

    fn detect(&self, values: &[f64], current: f64) -> Option<f64> {
        if values.len() < self.period * 2 {
            return None;
        }

        // Simple seasonal decomposition
        let mut seasonal_avgs = vec![0.0; self.period];
        let mut counts = vec![0; self.period];

        for (i, value) in values.iter().enumerate() {
            let season_idx = i % self.period;
            seasonal_avgs[season_idx] += value;
            counts[season_idx] += 1;
        }

        for i in 0..self.period {
            if counts[i] > 0 {
                seasonal_avgs[i] /= counts[i] as f64;
            }
        }

        // Expected value based on season
        let current_season = values.len() % self.period;
        let expected = seasonal_avgs[current_season];

        if expected == 0.0 {
            return None;
        }

        let deviation = (current - expected).abs() / expected;

        if deviation > 0.5 {
            Some(deviation.min(1.0))
        } else {
            None
        }
    }
}

/// Isolation Forest for multivariate anomaly detection
struct IsolationForest {
    trees: Arc<RwLock<Vec<IsolationTree>>>,
    num_trees: usize,
    sample_size: usize,
}

impl IsolationForest {
    fn new(num_trees: usize, sample_size: usize) -> Result<Self> {
        Ok(Self {
            trees: Arc::new(RwLock::new(Vec::new())),
            num_trees,
            sample_size,
        })
    }

    async fn train(&self, data: &[f64]) -> Result<()> {
        let mut trees = Vec::new();

        for _ in 0..self.num_trees {
            let tree = IsolationTree::build(data, self.sample_size)?;
            trees.push(tree);
        }

        *self.trees.write().await = trees;
        Ok(())
    }

    async fn detect(&self, _context: &[f64], value: f64) -> Result<Option<f64>> {
        let trees = self.trees.read().await;

        if trees.is_empty() {
            return Ok(None);
        }

        let path_lengths: Vec<f64> = trees
            .iter()
            .map(|tree| tree.path_length(value) as f64)
            .collect();

        let avg_path_length = path_lengths.iter().sum::<f64>() / path_lengths.len() as f64;
        let expected_path = 2.0 * ((self.sample_size as f64).ln() - 0.5772); // Euler's constant

        let anomaly_score = 2.0_f64.powf(-avg_path_length / expected_path);

        if anomaly_score > 0.5 {
            Ok(Some(anomaly_score))
        } else {
            Ok(None)
        }
    }
}

/// Isolation tree node
#[derive(Debug, Clone)]
struct IsolationTree {
    split_value: Option<f64>,
    left: Option<Box<IsolationTree>>,
    right: Option<Box<IsolationTree>>,
    size: usize,
}

impl IsolationTree {
    fn build(data: &[f64], max_size: usize) -> Result<Self> {
        Self::build_recursive(data, 0, max_size)
    }

    fn build_recursive(data: &[f64], depth: usize, max_depth: usize) -> Result<Self> {
        if data.len() <= 1 || depth >= max_depth {
            return Ok(Self {
                split_value: None,
                left: None,
                right: None,
                size: data.len(),
            });
        }

        let min = data.iter().fold(f64::INFINITY, |a, &b| a.min(b));
        let max = data.iter().fold(f64::NEG_INFINITY, |a, &b| a.max(b));

        if (max - min).abs() < f64::EPSILON {
            return Ok(Self {
                split_value: None,
                left: None,
                right: None,
                size: data.len(),
            });
        }

        let split_value = min + (max - min) * rand::random::<f64>();

        let left_data: Vec<f64> = data.iter().copied().filter(|&x| x < split_value).collect();
        let right_data: Vec<f64> = data.iter().copied().filter(|&x| x >= split_value).collect();

        Ok(Self {
            split_value: Some(split_value),
            left: Some(Box::new(Self::build_recursive(
                &left_data,
                depth + 1,
                max_depth,
            )?)),
            right: Some(Box::new(Self::build_recursive(
                &right_data,
                depth + 1,
                max_depth,
            )?)),
            size: data.len(),
        })
    }

    fn path_length(&self, value: f64) -> usize {
        self.path_length_recursive(value, 0)
    }

    fn path_length_recursive(&self, value: f64, current_depth: usize) -> usize {
        match self.split_value {
            None => current_depth + self.adjustment_factor(),
            Some(split) => {
                if value < split {
                    if let Some(ref left) = self.left {
                        left.path_length_recursive(value, current_depth + 1)
                    } else {
                        current_depth + 1
                    }
                } else {
                    if let Some(ref right) = self.right {
                        right.path_length_recursive(value, current_depth + 1)
                    } else {
                        current_depth + 1
                    }
                }
            }
        }
    }

    fn adjustment_factor(&self) -> usize {
        if self.size <= 1 {
            0
        } else {
            ((self.size as f64).ln() / std::f64::consts::LN_2).ceil() as usize
        }
    }
}

/// Anomaly detection configuration
#[derive(Debug, Clone)]
pub struct AnomalyConfig {
    pub zscore_threshold: f64,
    pub anomaly_threshold: f64,
    pub window_size: usize,
    pub seasonal_period: usize,
    pub history_size: usize,
    pub min_samples: usize,
    pub max_anomalies: usize,
    pub enable_isolation_forest: bool,
    pub forest_size: usize,
    pub sample_size: usize,
}

impl Default for AnomalyConfig {
    fn default() -> Self {
        Self {
            zscore_threshold: 3.0,
            anomaly_threshold: 0.5,
            window_size: 20,
            seasonal_period: 24, // Hourly seasonality
            history_size: 1000,
            min_samples: 10,
            max_anomalies: 100,
            enable_isolation_forest: false, // Disabled by default for performance
            forest_size: 100,
            sample_size: 256,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_anomaly_detector() {
        let config = AnomalyConfig::default();
        let detector = AnomalyDetector::new(config).await.unwrap();

        // Generate normal data
        let mut metrics = Vec::new();
        for i in 0..100 {
            let value = 50.0 + (i as f64 * 0.1).sin() * 10.0; // Sinusoidal pattern
            metrics.push(Metric::gauge("test.metric", value));
        }

        // Add to detector
        for metric in &metrics {
            let _ = detector.check(metric).await;
        }

        // Test anomaly
        let anomaly_metric = Metric::gauge("test.metric", 200.0); // Way out of range
        let result = detector.check(&anomaly_metric).await.unwrap();

        assert!(result.is_some());
        if let Some(anomaly) = result {
            assert!(anomaly.score > 0.5);
            assert_eq!(anomaly.actual_value, 200.0);
        }
    }

    #[test]
    fn test_zscore_detector() {
        let detector = ZScoreDetector::new(3.0);
        let values = vec![10.0, 12.0, 11.0, 10.5, 11.5, 10.0, 11.0];

        // Normal value
        assert!(detector.detect(&values, 11.0).is_none());

        // Anomalous value
        assert!(detector.detect(&values, 50.0).is_some());
    }

    #[test]
    fn test_seasonal_detector() {
        let detector = SeasonalDetector::new(4);

        // Create seasonal pattern
        let mut values = Vec::new();
        for i in 0..20 {
            values.push(match i % 4 {
                0 => 10.0,
                1 => 20.0,
                2 => 15.0,
                3 => 5.0,
                _ => 0.0,
            });
        }

        // Test expected seasonal value
        assert!(detector.detect(&values, 10.0).is_none());

        // Test anomalous value
        assert!(detector.detect(&values, 100.0).is_some());
    }
}
