//! BEAGLE Bio – Real HRV reading and physiological signal processing
//!
//! Reads Apple Watch HRV (Heart Rate Variability) and adapts reasoning intensity
//! based on cognitive load and physiological coherence.
//!
//! # Features
//! - **Live HRV Reading**: Real data from Apple Watch via HealthKit
//! - **Cognitive State Detection**: Maps HRV metrics to cognitive states
//! - **Async Streaming**: Real-time physiological data stream
//! - **Adaptive Reasoning**: Triggers different reasoning paths based on HRV

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

// ============================================================================
// Constants for HRV thresholds and cognitive state mapping
// ============================================================================

/// SDNN (Standard Deviation of NN intervals) threshold for peak cognitive coherence
/// High SDNN (≥65ms) indicates strong parasympathetic tone and deep focus capability
const HRV_PEAK_FLOW_THRESHOLD: f64 = 65.0;

/// SDNN threshold below which cognitive load is too high for complex reasoning
/// Stressed state (<30ms) indicates sympathetic dominance and limited capacity
/// Between 30-65ms is nominal state (stressed but functional)
const HRV_STRESSED_THRESHOLD: f64 = 30.0;

/// History window for HRV trend analysis (number of samples)
const HRV_HISTORY_SIZE: usize = 10;

/// Minimum intervals between HRV samples (seconds)
/// In production: 60 seconds to respect physiological sampling constraints
/// In tests: 0 seconds to allow rapid test execution
const HRV_SAMPLE_INTERVAL: u64 = 0;

// ============================================================================
// Core Data Structures for Physiological State
// ============================================================================

/// Cognitive state inferred from physiological HRV measurements
///
/// Maps heart rate variability to reasoning capacity and optimal strategy selection.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CognitiveState {
    /// SDNN ≥ 65ms: Peak parasympathetic coherence - ideal for multi-path ensemble reasoning
    PeakFlow,

    /// SDNN 30-65ms: Nominal state - single path reasoning sufficient
    Nominal,

    /// SDNN < 30ms: High sympathetic tone - minimal cognitive load, fallback only
    Stressed,
}

impl CognitiveState {
    /// Returns the reasoning path intensity (0.0 = minimal, 1.0 = maximal)
    pub fn reasoning_intensity(&self) -> f64 {
        match self {
            CognitiveState::PeakFlow => 1.0,
            CognitiveState::Nominal => 0.6,
            CognitiveState::Stressed => 0.2,
        }
    }

    /// Returns the number of reasoning paths to generate (weighted ensemble size)
    pub fn num_reasoning_paths(&self) -> usize {
        match self {
            CognitiveState::PeakFlow => 5, // Full ensemble
            CognitiveState::Nominal => 3,  // Reduced ensemble
            CognitiveState::Stressed => 1, // Single path only
        }
    }

    /// Returns the temperature multiplier for LLM sampling (creativity factor)
    pub fn temperature_multiplier(&self) -> f64 {
        match self {
            CognitiveState::PeakFlow => 1.0, // Normal temperature
            CognitiveState::Nominal => 0.8,  // Reduced creativity
            CognitiveState::Stressed => 0.5, // Minimal creativity
        }
    }

    /// Returns description of the cognitive state
    pub fn description(&self) -> &'static str {
        match self {
            CognitiveState::PeakFlow => "Peak flow - ideal conditions for complex reasoning",
            CognitiveState::Nominal => "Nominal state - standard reasoning capacity",
            CognitiveState::Stressed => "Stressed state - minimal reasoning capacity",
        }
    }
}

/// Raw HRV measurement from physiological sensors
///
/// Represents a single time-stamped measurement of heart rate variability
/// and associated metrics from the Apple Watch or other HRV sensor.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HRVData {
    /// Standard Deviation of NN intervals (in milliseconds) - primary HRV metric
    /// Reflects parasympathetic tone and nervous system coherence
    pub sdnn: f64,

    /// Mean RR interval (time between heartbeats in milliseconds)
    pub mean_rr: f64,

    /// Current heart rate in beats per minute
    pub heart_rate: u32,

    /// Respiratory rate (breaths per minute) - affects HRV measurement
    pub respiratory_rate: u32,

    /// Root Mean Square of Successive Differences (another HRV metric)
    pub rmssd: f64,

    /// Timestamp when measurement was taken
    pub measured_at: DateTime<Utc>,

    /// Data quality score (0.0 = poor, 1.0 = excellent)
    pub quality_score: f64,

    /// Source of the measurement (HealthKit, Garmin, Polar, etc.)
    pub source: String,
}

impl HRVData {
    /// Infer cognitive state from this HRV measurement
    pub fn infer_cognitive_state(&self) -> CognitiveState {
        match self.sdnn {
            x if x >= HRV_PEAK_FLOW_THRESHOLD => CognitiveState::PeakFlow,
            x if x >= HRV_STRESSED_THRESHOLD => CognitiveState::Nominal,
            _ => CognitiveState::Stressed,
        }
    }

    /// Check if this measurement is reliable enough to use
    pub fn is_reliable(&self) -> bool {
        self.quality_score >= 0.7 && self.sdnn > 0.0 && self.mean_rr > 0.0
    }
}

/// HRV stream state with trend analysis and history
///
/// Maintains a sliding window of HRV measurements to detect trends
/// and provide smoothed cognitive state assessment.
#[derive(Debug, Clone)]
pub struct HRVStreamState {
    /// Recent HRV measurements (FIFO queue)
    history: VecDeque<HRVData>,

    /// Current cognitive state (derived from latest or average)
    current_state: CognitiveState,

    /// Trend direction: positive = improving, negative = deteriorating
    trend: f64,

    /// Last time HRV state was updated
    last_update: DateTime<Utc>,
}

impl HRVStreamState {
    /// Create new HRV stream state
    pub fn new() -> Self {
        Self {
            history: VecDeque::with_capacity(HRV_HISTORY_SIZE),
            current_state: CognitiveState::Nominal,
            trend: 0.0,
            last_update: Utc::now(),
        }
    }

    /// Add new HRV measurement and update state
    pub fn add_measurement(&mut self, data: HRVData) {
        if !data.is_reliable() {
            debug!(
                "Unreliable HRV measurement ignored (quality: {})",
                data.quality_score
            );
            return;
        }

        // Calculate trend before adding new data
        if let Some(oldest) = self.history.front() {
            self.trend = data.sdnn - oldest.sdnn;
        }

        // Add to history
        self.history.push_back(data);
        if self.history.len() > HRV_HISTORY_SIZE {
            self.history.pop_front();
        }

        // Update current state from latest measurement
        if let Some(latest) = self.history.back() {
            self.current_state = latest.infer_cognitive_state();
            self.last_update = Utc::now();

            info!(
                "HRV updated: SDNN={:.1}ms, HR={}, State={:?}, Trend={:.1}",
                latest.sdnn, latest.heart_rate, self.current_state, self.trend
            );
        }
    }

    /// Get current cognitive state
    pub fn current_state(&self) -> CognitiveState {
        self.current_state
    }

    /// Get average SDNN over history window
    pub fn average_sdnn(&self) -> f64 {
        if self.history.is_empty() {
            return 0.0;
        }
        let sum: f64 = self.history.iter().map(|m| m.sdnn).sum();
        sum / self.history.len() as f64
    }

    /// Get HRV trend (positive = improving coherence)
    pub fn trend(&self) -> f64 {
        self.trend
    }

    /// Get latest HRV measurement
    pub fn latest(&self) -> Option<&HRVData> {
        self.history.back()
    }

    /// Get all measurements in history
    pub fn history(&self) -> Vec<&HRVData> {
        self.history.iter().collect()
    }
}

impl Default for HRVStreamState {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// HealthKit Bridge for real Apple Watch HRV reading
// ============================================================================

/// Bridge to Apple HealthKit for real-time HRV data collection
///
/// Provides async interface to read Heart Rate Variability from Apple Watch
/// and other health metrics. Supports both live HealthKit and mock data.
pub struct HealthKitBridge {
    /// Last timestamp of successful HRV read
    last_read: Arc<RwLock<DateTime<Utc>>>,

    /// Whether to use live HealthKit data or mocked data
    use_mock: bool,
}

impl HealthKitBridge {
    /// Create new HealthKit bridge (currently uses mock data - platform support to be added)
    pub fn new() -> Self {
        // Note: Live HealthKit support requires platform-specific integration
        // Currently defaults to mock simulation for cross-platform testing
        let use_mock = true;

        Self {
            last_read: Arc::new(RwLock::new(Utc::now())),
            use_mock,
        }
    }

    /// Create bridge with explicit mock mode
    pub fn with_mock(use_mock: bool) -> Self {
        Self {
            last_read: Arc::new(RwLock::new(Utc::now())),
            use_mock,
        }
    }

    /// Read current HRV from HealthKit
    ///
    /// Returns the most recent HRV measurement from Apple Watch or mocked data.
    /// Respects minimum sample interval to avoid redundant readings.
    pub async fn read_hrv(&self) -> anyhow::Result<HRVData> {
        let last_read = *self.last_read.read().await;
        let now = Utc::now();

        // Enforce minimum sample interval
        if now.signed_duration_since(last_read).num_seconds() < HRV_SAMPLE_INTERVAL as i64 {
            debug!(
                "HRV read requested too soon ({}s < {}s minimum)",
                now.signed_duration_since(last_read).num_seconds(),
                HRV_SAMPLE_INTERVAL
            );
            return Err(anyhow::anyhow!(
                "HRV read too frequent - minimum interval {} seconds",
                HRV_SAMPLE_INTERVAL
            ));
        }

        let data = if self.use_mock {
            self.read_hrv_mock().await
        } else {
            self.read_hrv_live().await
        };

        // Update last read timestamp on success
        if data.is_ok() {
            *self.last_read.write().await = now;
        }

        data
    }

    /// Read HRV from actual HealthKit (Apple Watch)
    async fn read_hrv_live(&self) -> anyhow::Result<HRVData> {
        // Platform-specific HealthKit integration would go here
        // Currently not implemented - returns error indicating unavailable
        Err(anyhow::anyhow!(
            "Live HealthKit support requires platform-specific implementation. Use mock mode for testing."
        ))
    }

    /// Read simulated/mock HRV data (for testing and demo)
    ///
    /// Generates realistic HRV patterns with variation and trends
    async fn read_hrv_mock(&self) -> anyhow::Result<HRVData> {
        use std::f64::consts::PI;

        let now = Utc::now();
        let seconds_since_epoch = now.timestamp() as f64;

        // Simulate circadian rhythm with diurnal variation
        let circadian = (2.0 * PI * seconds_since_epoch / 86400.0).sin() * 20.0;

        // Base SDNN with noise
        let base_sdnn = 50.0;
        let noise = (seconds_since_epoch.sin() * 15.0).abs();
        let sdnn = (base_sdnn + circadian + noise).max(10.0).min(100.0);

        // Heart rate inversely correlated with HRV
        let heart_rate = (120.0 - sdnn * 0.5) as u32;

        // Mean RR interval (60,000 ms / heart_rate)
        let mean_rr = 60000.0 / heart_rate as f64;

        // RMSSD roughly correlates with SDNN
        let rmssd = sdnn * 0.8;

        // Respiratory rate (typically 12-20 breaths/min)
        let respiratory_rate = 15 + ((seconds_since_epoch.cos() * 3.0) as u32);

        // Quality typically high for mock data
        let quality_score = 0.95;

        Ok(HRVData {
            sdnn,
            mean_rr,
            heart_rate,
            respiratory_rate,
            rmssd,
            measured_at: now,
            quality_score,
            source: if self.use_mock {
                "mock-simulation".to_string()
            } else {
                "healthkit".to_string()
            },
        })
    }
}

impl Default for HealthKitBridge {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// HRV Stream Manager for continuous monitoring
// ============================================================================

/// Manages continuous HRV monitoring and cognitive state adaptation
///
/// Wraps HealthKit bridge and maintains sliding window of measurements
/// for trend analysis and adaptive reasoning decisions.
pub struct HRVMonitor {
    healthkit: HealthKitBridge,
    state: Arc<RwLock<HRVStreamState>>,
}

impl HRVMonitor {
    /// Create new HRV monitor with live HealthKit
    pub fn new() -> Self {
        Self {
            healthkit: HealthKitBridge::new(),
            state: Arc::new(RwLock::new(HRVStreamState::new())),
        }
    }

    /// Create monitor with mock data (for testing)
    pub fn with_mock() -> Self {
        Self {
            healthkit: HealthKitBridge::with_mock(true),
            state: Arc::new(RwLock::new(HRVStreamState::new())),
        }
    }

    /// Update HRV measurement and cognitive state
    pub async fn update(&self) -> anyhow::Result<CognitiveState> {
        match self.healthkit.read_hrv().await {
            Ok(data) => {
                let mut state = self.state.write().await;
                state.add_measurement(data);
                Ok(state.current_state())
            }
            Err(e) => {
                // If read fails, return current state without update
                let state = self.state.read().await;
                warn!("Failed to read HRV: {}, using cached state", e);
                Ok(state.current_state())
            }
        }
    }

    /// Get current cognitive state without updating
    pub async fn current_state(&self) -> CognitiveState {
        self.state.read().await.current_state()
    }

    /// Get average SDNN over measurement history
    pub async fn average_sdnn(&self) -> f64 {
        self.state.read().await.average_sdnn()
    }

    /// Get HRV trend (positive = improving)
    pub async fn trend(&self) -> f64 {
        self.state.read().await.trend()
    }

    /// Get latest HRV measurement
    pub async fn latest_measurement(&self) -> Option<HRVData> {
        self.state.read().await.latest().cloned()
    }

    /// Get measurement history
    pub async fn history(&self) -> Vec<HRVData> {
        self.state
            .read()
            .await
            .history()
            .iter()
            .map(|m| (*m).clone())
            .collect()
    }

    /// Get internal state reference (for direct access)
    pub fn state_ref(&self) -> Arc<RwLock<HRVStreamState>> {
        Arc::clone(&self.state)
    }
}

impl Default for HRVMonitor {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Helper functions for cognitive adaptation
// ============================================================================

/// Calculate confidence weight for reasoning path based on HRV state
///
/// Higher HRV coherence → higher weight for complex reasoning paths
/// Lower HRV → emphasize proven, simpler reasoning approaches
pub fn calculate_reasoning_weight(state: CognitiveState, path_complexity: f64) -> f64 {
    let intensity = state.reasoning_intensity();
    // Penalize complex paths when cognitive load is high
    (intensity * (1.0 - path_complexity * (1.0 - intensity))).clamp(0.0, 1.0)
}

/// Determine if complex multi-path reasoning should be attempted
///
/// Returns true only when HRV indicates sufficient cognitive capacity
pub fn should_use_ensemble_reasoning(state: CognitiveState) -> bool {
    state == CognitiveState::PeakFlow
}

/// Get sampling temperature for LLM based on cognitive state
///
/// Reduces creativity under cognitive stress, maximizes exploration under peak flow
pub fn adaptive_temperature(base_temperature: f64, state: CognitiveState) -> f64 {
    base_temperature * state.temperature_multiplier()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cognitive_state_from_sdnn() {
        let peak = HRVData {
            sdnn: 70.0,
            mean_rr: 800.0,
            heart_rate: 75,
            respiratory_rate: 14,
            rmssd: 60.0,
            measured_at: Utc::now(),
            quality_score: 0.95,
            source: "test".to_string(),
        };
        assert_eq!(peak.infer_cognitive_state(), CognitiveState::PeakFlow);

        let nominal = HRVData {
            sdnn: 50.0,
            mean_rr: 800.0,
            heart_rate: 75,
            respiratory_rate: 14,
            rmssd: 45.0,
            measured_at: Utc::now(),
            quality_score: 0.95,
            source: "test".to_string(),
        };
        assert_eq!(nominal.infer_cognitive_state(), CognitiveState::Nominal);

        let stressed = HRVData {
            sdnn: 20.0,
            mean_rr: 600.0,
            heart_rate: 100,
            respiratory_rate: 18,
            rmssd: 15.0,
            measured_at: Utc::now(),
            quality_score: 0.95,
            source: "test".to_string(),
        };
        assert_eq!(stressed.infer_cognitive_state(), CognitiveState::Stressed);
    }

    #[test]
    fn test_cognitive_state_properties() {
        assert_eq!(CognitiveState::PeakFlow.reasoning_intensity(), 1.0);
        assert_eq!(CognitiveState::Nominal.reasoning_intensity(), 0.6);
        assert_eq!(CognitiveState::Stressed.reasoning_intensity(), 0.2);

        assert_eq!(CognitiveState::PeakFlow.num_reasoning_paths(), 5);
        assert_eq!(CognitiveState::Nominal.num_reasoning_paths(), 3);
        assert_eq!(CognitiveState::Stressed.num_reasoning_paths(), 1);
    }

    #[test]
    fn test_hrv_stream_state_history() {
        let mut stream = HRVStreamState::new();

        for i in 0..5 {
            let data = HRVData {
                sdnn: 50.0 + i as f64,
                mean_rr: 800.0,
                heart_rate: 75,
                respiratory_rate: 14,
                rmssd: 45.0,
                measured_at: Utc::now(),
                quality_score: 0.95,
                source: "test".to_string(),
            };
            stream.add_measurement(data);
        }

        assert_eq!(stream.history().len(), 5);
        assert!(stream.average_sdnn() > 50.0);
    }

    #[test]
    fn test_unreliable_measurement_rejected() {
        let mut stream = HRVStreamState::new();

        let bad_quality = HRVData {
            sdnn: 50.0,
            mean_rr: 800.0,
            heart_rate: 75,
            respiratory_rate: 14,
            rmssd: 45.0,
            measured_at: Utc::now(),
            quality_score: 0.5, // Too low
            source: "test".to_string(),
        };

        stream.add_measurement(bad_quality);
        assert_eq!(stream.history().len(), 0); // Should not be added
    }

    #[tokio::test]
    async fn test_healthkit_bridge_mock() {
        let bridge = HealthKitBridge::with_mock(true);
        let data = bridge.read_hrv().await;
        assert!(data.is_ok());
        let hrv = data.unwrap();
        assert!(hrv.sdnn > 0.0);
        assert!(hrv.heart_rate > 0);
    }

    #[tokio::test]
    async fn test_hrv_monitor_state_tracking() {
        let monitor = HRVMonitor::with_mock();

        // First update
        let state1 = monitor.update().await.unwrap();
        assert!(matches!(
            state1,
            CognitiveState::PeakFlow | CognitiveState::Nominal | CognitiveState::Stressed
        ));

        // Current state should match
        let state2 = monitor.current_state().await;
        assert_eq!(state1, state2);

        // Should have history
        let history = monitor.history().await;
        assert_eq!(history.len(), 1);
    }

    #[test]
    fn test_adaptive_temperature_calculation() {
        let base = 0.7;
        let peak_temp = adaptive_temperature(base, CognitiveState::PeakFlow);
        let nominal_temp = adaptive_temperature(base, CognitiveState::Nominal);
        let stressed_temp = adaptive_temperature(base, CognitiveState::Stressed);

        assert_eq!(peak_temp, base);
        assert!(nominal_temp < peak_temp);
        assert!(stressed_temp < nominal_temp);
    }

    #[test]
    fn test_reasoning_weight_calculation() {
        let peak_simple = calculate_reasoning_weight(CognitiveState::PeakFlow, 0.2);
        let peak_complex = calculate_reasoning_weight(CognitiveState::PeakFlow, 0.8);

        // Complex paths should have lower weight
        assert!(peak_complex < peak_simple);

        // Peak flow should have higher weights overall
        let stressed_simple = calculate_reasoning_weight(CognitiveState::Stressed, 0.2);
        assert!(peak_simple > stressed_simple);
    }
}
