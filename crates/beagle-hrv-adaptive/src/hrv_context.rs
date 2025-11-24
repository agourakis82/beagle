//! HRV Context: Shared context for all modules integrating HRV-adaptive behavior
//!
//! This module provides a unified interface for any BEAGLE crate to:
//! 1. Query current HRV state
//! 2. Get adaptive parameters based on physiological state
//! 3. Make physiologically-informed decisions
//! 4. Track HRV-correlated metrics

use crate::{EnsembleReasoningEngine, ReasoningPath};
use beagle_bio::HRVMonitor;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::debug;

/// HRV context available to any module in BEAGLE system
#[derive(Clone)]
pub struct HRVContext {
    hrv_monitor: Arc<HRVMonitor>,
    ensemble_engine: Arc<EnsembleReasoningEngine>,
    metrics: Arc<std::sync::Mutex<HRVMetrics>>,
}

/// Aggregated metrics tracking HRV effects across system
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct HRVMetrics {
    pub queries_in_peakflow: u64,
    pub queries_in_nominal: u64,
    pub queries_in_stressed: u64,
    pub average_quality_peakflow: f64,
    pub average_quality_nominal: f64,
    pub average_quality_stressed: f64,
    pub last_updated: Option<DateTime<Utc>>,
}

/// HRV-adaptive configuration for any module
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HRVAdaptiveConfig {
    /// Base temperature for LLM queries
    pub base_temperature: f32,
    /// Base token limit for LLM responses
    pub base_max_tokens: u32,
    /// Base timeout for operations (seconds)
    pub base_timeout_secs: u64,
    /// Enable HRV-aware adaptation
    pub enabled: bool,
}

impl Default for HRVAdaptiveConfig {
    fn default() -> Self {
        Self {
            base_temperature: 0.8,
            base_max_tokens: 8192,
            base_timeout_secs: 120,
            enabled: true,
        }
    }
}

/// Adaptive parameters computed from current HRV state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdaptiveParameters {
    /// LLM temperature (creativity)
    pub temperature: f32,
    /// Maximum tokens for response
    pub max_tokens: u32,
    /// Operation timeout in seconds
    pub timeout_secs: u64,
    /// Number of reasoning paths to generate (0 = single path)
    pub num_paths: usize,
    /// Confidence threshold for accepting results
    pub quality_threshold: f64,
    /// Maximum refinement iterations
    pub max_refinements: u32,
    /// HRV state that generated these parameters
    pub hrv_state: String,
    /// Intensity multiplier (0.2 - 1.0)
    pub intensity: f64,
}

impl HRVContext {
    /// Create new HRV context
    pub fn new(
        hrv_monitor: Arc<HRVMonitor>,
        ensemble_engine: Arc<EnsembleReasoningEngine>,
    ) -> Self {
        Self {
            hrv_monitor,
            ensemble_engine,
            metrics: Arc::new(std::sync::Mutex::new(HRVMetrics::default())),
        }
    }

    /// Create with mock HRV monitor for testing
    pub fn with_mock() -> Self {
        let monitor = Arc::new(HRVMonitor::with_mock());
        let engine = Arc::new(EnsembleReasoningEngine::new(Arc::clone(&monitor)));
        Self::new(monitor, engine)
    }

    /// Get current HRV cognitive state
    pub async fn get_cognitive_state(&self) -> String {
        let state = self.hrv_monitor.current_state().await;
        format!("{:?}", state)
    }

    /// Compute adaptive parameters for current HRV state
    pub async fn get_adaptive_parameters(&self, config: &HRVAdaptiveConfig) -> AdaptiveParameters {
        if !config.enabled {
            return AdaptiveParameters::default();
        }

        let state = self.hrv_monitor.current_state().await;
        let intensity = state.reasoning_intensity();
        let is_ensemble = self.ensemble_engine.should_use_ensemble().await;
        let num_paths = self.ensemble_engine.get_num_paths().await;
        let temp_mult = self.ensemble_engine.get_adaptive_temperature(1.0).await;

        let (quality_threshold, max_refinements) = match intensity {
            i if i > 0.8 => (0.85, 5),    // VeryHigh/High HRV
            i if i > 0.6 => (0.80, 4),    // Nominal HRV
            i if i > 0.3 => (0.70, 3),    // Low HRV
            _ => (0.60, 2),                // VeryLow HRV
        };

        AdaptiveParameters {
            temperature: (config.base_temperature as f64 * temp_mult) as f32,
            max_tokens: (config.base_max_tokens as f64 * (0.5 + 0.5 * intensity)) as u32,
            timeout_secs: config.base_timeout_secs,
            num_paths: if is_ensemble { num_paths } else { 1 },
            quality_threshold,
            max_refinements,
            hrv_state: format!("{:?}", state),
            intensity,
        }
    }

    /// Record query result with quality metric (categorized by state)
    /// State is determined asynchronously for accuracy
    pub async fn record_query_with_state(&self, state_category: &str, quality_score: f64) {
        if let Ok(mut metrics) = self.metrics.lock() {
            match state_category {
                "PeakFlow" => {
                    metrics.queries_in_peakflow += 1;
                    metrics.average_quality_peakflow = (metrics.average_quality_peakflow
                        * (metrics.queries_in_peakflow - 1) as f64
                        + quality_score)
                        / metrics.queries_in_peakflow as f64;
                }
                "Stressed" => {
                    metrics.queries_in_stressed += 1;
                    metrics.average_quality_stressed = (metrics.average_quality_stressed
                        * (metrics.queries_in_stressed - 1) as f64
                        + quality_score)
                        / metrics.queries_in_stressed as f64;
                }
                _ => {
                    metrics.queries_in_nominal += 1;
                    metrics.average_quality_nominal = (metrics.average_quality_nominal
                        * (metrics.queries_in_nominal - 1) as f64
                        + quality_score)
                        / metrics.queries_in_nominal as f64;
                }
            }
            metrics.last_updated = Some(Utc::now());
        }
    }

    /// Get aggregated metrics
    pub fn get_metrics(&self) -> HRVMetrics {
        self.metrics.lock().ok().map(|m| m.clone()).unwrap_or_default()
    }

    /// Run ensemble reasoning if HRV supports it
    pub async fn ensemble_reasoning_if_supported(
        &self,
        prompt: &str,
        paths: Vec<ReasoningPath>,
    ) -> Result<crate::EnsembleConsensus, Box<dyn std::error::Error>> {
        if self.ensemble_engine.should_use_ensemble().await {
            debug!("HRVContext: Using ensemble reasoning (HRV state supports it)");
            self.ensemble_engine
                .consensus_reasoning(prompt, paths)
                .await
                .map_err(|e| Box::new(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    e.to_string(),
                )) as Box<dyn std::error::Error>)
        } else {
            debug!("HRVContext: Skipping ensemble reasoning (low HRV)");
            Err("HRV state does not support ensemble reasoning".into())
        }
    }
}

impl Default for AdaptiveParameters {
    fn default() -> Self {
        Self {
            temperature: 0.8,
            max_tokens: 8192,
            timeout_secs: 120,
            num_paths: 1,
            quality_threshold: 0.7,
            max_refinements: 3,
            hrv_state: "Unknown".to_string(),
            intensity: 0.6,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_hrv_context_creation() {
        let ctx = HRVContext::with_mock();
        let state = ctx.get_cognitive_state().await;
        assert!(!state.is_empty());
    }

    #[tokio::test]
    async fn test_adaptive_parameters() {
        let ctx = HRVContext::with_mock();
        let config = HRVAdaptiveConfig::default();
        let params = ctx.get_adaptive_parameters(&config).await;

        assert!(params.temperature > 0.0);
        assert!(params.max_tokens > 0);
        assert!(params.quality_threshold > 0.0);
    }

    #[tokio::test]
    async fn test_metrics_recording() {
        let ctx = HRVContext::with_mock();
        ctx.record_query_with_state("PeakFlow", 0.85).await;
        ctx.record_query_with_state("Nominal", 0.90).await;
        let metrics = ctx.get_metrics();
        assert_eq!(metrics.queries_in_peakflow, 1);
        assert_eq!(metrics.queries_in_nominal, 1);
    }
}
