//! Temporal Multi-Scale Reasoning
//!
//! Reasoning across 8 time scales (microseconds to years)
//! Enables understanding causality from fast events to slow outcomes

use anyhow::Result;
use beagle_llm::AnthropicClient;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tracing::info;

#[cfg(test)]
mod tests;

// ============================================================================
// Temporal Scales (8 scales: µs → years)
// ============================================================================

/// 8 temporal scales from microseconds to years
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, PartialOrd, Ord)]
pub enum TemporalScale {
    Microsecond, // µs
    Millisecond, // ms
    Second,      // s
    Minute,      // min
    Hour,        // h
    Day,         // d
    Week,        // w
    Month,       // mo
    Year,        // y
}

impl TemporalScale {
    /// Get duration in milliseconds for normalization
    pub fn to_millis(&self) -> i64 {
        match self {
            TemporalScale::Microsecond => 0, // Sub-millisecond
            TemporalScale::Millisecond => 1,
            TemporalScale::Second => 1_000,
            TemporalScale::Minute => 60_000,
            TemporalScale::Hour => 3_600_000,
            TemporalScale::Day => 86_400_000,
            TemporalScale::Week => 604_800_000,
            TemporalScale::Month => 2_592_000_000, // 30 days
            TemporalScale::Year => 31_536_000_000, // 365 days
        }
    }

    /// Detect scale from duration
    pub fn from_duration(duration_ms: i64) -> Self {
        if duration_ms < 1 {
            TemporalScale::Microsecond
        } else if duration_ms < 1_000 {
            TemporalScale::Millisecond
        } else if duration_ms < 60_000 {
            TemporalScale::Second
        } else if duration_ms < 3_600_000 {
            TemporalScale::Minute
        } else if duration_ms < 86_400_000 {
            TemporalScale::Hour
        } else if duration_ms < 604_800_000 {
            TemporalScale::Day
        } else if duration_ms < 2_592_000_000 {
            TemporalScale::Week
        } else if duration_ms < 31_536_000_000 {
            TemporalScale::Month
        } else {
            TemporalScale::Year
        }
    }

    /// Get all scales in order
    pub fn all_scales() -> Vec<TemporalScale> {
        vec![
            TemporalScale::Microsecond,
            TemporalScale::Millisecond,
            TemporalScale::Second,
            TemporalScale::Minute,
            TemporalScale::Hour,
            TemporalScale::Day,
            TemporalScale::Week,
            TemporalScale::Month,
            TemporalScale::Year,
        ]
    }
}

// ============================================================================
// Time Points and Ranges
// ============================================================================

/// A point in time with scale and context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimePoint {
    pub timestamp: DateTime<Utc>,
    pub scale: TemporalScale,
    pub event: String,
    pub metadata: HashMap<String, String>,
}

impl TimePoint {
    pub fn new(timestamp: DateTime<Utc>, scale: TemporalScale, event: String) -> Self {
        Self {
            timestamp,
            scale,
            event,
            metadata: HashMap::new(),
        }
    }

    /// Parse temporal expression like "2 hours ago", "next week"
    pub fn parse_temporal_expression(expr: &str) -> Result<Self> {
        let now = Utc::now();

        // Simple parser - extend as needed
        let (timestamp, scale) = if expr.contains("hour") {
            let hours = extract_number(expr).unwrap_or(1);
            let ts = if expr.contains("ago") {
                now - Duration::hours(hours)
            } else {
                now + Duration::hours(hours)
            };
            (ts, TemporalScale::Hour)
        } else if expr.contains("day") {
            let days = extract_number(expr).unwrap_or(1);
            let ts = if expr.contains("ago") {
                now - Duration::days(days)
            } else {
                now + Duration::days(days)
            };
            (ts, TemporalScale::Day)
        } else if expr.contains("week") {
            let weeks = extract_number(expr).unwrap_or(1);
            let ts = if expr.contains("ago") {
                now - Duration::weeks(weeks)
            } else {
                now + Duration::weeks(weeks)
            };
            (ts, TemporalScale::Week)
        } else if expr.contains("month") {
            let months = extract_number(expr).unwrap_or(1);
            let ts = if expr.contains("ago") {
                now - Duration::days(months * 30)
            } else {
                now + Duration::days(months * 30)
            };
            (ts, TemporalScale::Month)
        } else {
            (now, TemporalScale::Second)
        };

        Ok(TimePoint::new(timestamp, scale, expr.to_string()))
    }

    /// Calculate temporal distance to another point
    pub fn temporal_distance(&self, other: &TimePoint) -> i64 {
        let diff = self.timestamp.signed_duration_since(other.timestamp);
        diff.num_milliseconds()
    }
}

/// A range of time with start and end
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeRange {
    pub start: TimePoint,
    pub end: TimePoint,
}

impl TimeRange {
    pub fn new(start: TimePoint, end: TimePoint) -> Self {
        Self { start, end }
    }

    /// Check if ranges overlap
    pub fn overlaps(&self, other: &TimeRange) -> bool {
        self.start.timestamp <= other.end.timestamp && self.end.timestamp >= other.start.timestamp
    }

    /// Get duration in milliseconds
    pub fn duration_ms(&self) -> i64 {
        self.end.temporal_distance(&self.start).abs()
    }

    /// Normalize scale to canonical representation
    pub fn normalize_scale(&self) -> TemporalScale {
        TemporalScale::from_duration(self.duration_ms())
    }
}

// ============================================================================
// Cross-Scale Causality
// ============================================================================

/// Causal relationship across time scales
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CrossScaleCausality {
    pub from_scale: TemporalScale,
    pub to_scale: TemporalScale,
    pub from_event: String,
    pub to_event: String,
    pub mechanism: String,
    pub strength: f64,
    pub lag_ms: i64,
}

impl CrossScaleCausality {
    /// Detect if this is fast→slow causality
    pub fn is_fast_to_slow(&self) -> bool {
        self.from_scale < self.to_scale
    }

    /// Detect if this is slow→fast causality
    pub fn is_slow_to_fast(&self) -> bool {
        self.from_scale > self.to_scale
    }
}

pub struct CrossScaleCausalityDetector {
    #[allow(dead_code)]
    llm: Arc<AnthropicClient>,
}

impl CrossScaleCausalityDetector {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self { llm }
    }

    /// Detect causality across scales
    pub async fn detect(
        &self,
        events: &[(TimePoint, TimePoint)],
    ) -> Result<Vec<CrossScaleCausality>> {
        info!(
            "🕐 Detecting cross-scale causality for {} event pairs",
            events.len()
        );

        let mut causalities = Vec::new();

        for (cause, effect) in events {
            // Calculate lag
            let lag_ms = effect.temporal_distance(cause);

            if lag_ms <= 0 {
                continue; // Effect must come after cause
            }

            // Detect scale relationship
            let strength = self.estimate_causal_strength(cause, effect, lag_ms);

            if strength > 0.5 {
                causalities.push(CrossScaleCausality {
                    from_scale: cause.scale,
                    to_scale: effect.scale,
                    from_event: cause.event.clone(),
                    to_event: effect.event.clone(),
                    mechanism: "temporal_correlation".to_string(),
                    strength,
                    lag_ms,
                });
            }
        }

        info!("✅ Detected {} cross-scale causalities", causalities.len());
        Ok(causalities)
    }

    /// Estimate causal strength using Granger causality approximation
    fn estimate_causal_strength(&self, _cause: &TimePoint, effect: &TimePoint, lag_ms: i64) -> f64 {
        // Simplified Granger causality:
        // Strength inversely proportional to lag (within reasonable bounds)
        let expected_lag = effect.scale.to_millis();

        if expected_lag == 0 {
            return 0.5; // Default for microsecond scale
        }

        let lag_ratio = (lag_ms as f64) / (expected_lag as f64);

        // Strength is high when lag matches expected scale
        if lag_ratio > 0.5 && lag_ratio < 2.0 {
            0.8
        } else if lag_ratio > 0.1 && lag_ratio < 10.0 {
            0.6
        } else {
            0.3
        }
    }
}

// ============================================================================
// Temporal Pattern Mining
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemporalPattern {
    pub pattern_type: PatternType,
    pub sequence: Vec<String>,
    pub support: usize,
    pub confidence: f64,
    pub time_windows: Vec<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PatternType {
    FrequentSequence,
    PeriodicPattern,
    Anomaly,
    Predictive,
}

pub struct TemporalPatternMiner {
    min_support: usize,
    min_confidence: f64,
}

impl TemporalPatternMiner {
    pub fn new(min_support: usize, min_confidence: f64) -> Self {
        Self {
            min_support,
            min_confidence,
        }
    }

    /// Mine frequent sequences
    pub fn mine_frequent_sequences(&self, events: &[TimePoint]) -> Vec<TemporalPattern> {
        info!("⛏️  Mining frequent sequences from {} events", events.len());

        let mut patterns = Vec::new();

        // Simple frequent itemset mining (2-itemsets)
        let mut sequence_counts: HashMap<(String, String), usize> = HashMap::new();

        for i in 0..events.len().saturating_sub(1) {
            for j in (i + 1)..events.len() {
                let key = (events[i].event.clone(), events[j].event.clone());
                *sequence_counts.entry(key).or_insert(0) += 1;
            }
        }

        for ((event1, event2), count) in sequence_counts {
            if count >= self.min_support {
                patterns.push(TemporalPattern {
                    pattern_type: PatternType::FrequentSequence,
                    sequence: vec![event1, event2],
                    support: count,
                    confidence: count as f64 / events.len() as f64,
                    time_windows: vec![],
                });
            }
        }

        info!("✅ Found {} frequent sequences", patterns.len());
        patterns
    }

    /// Detect temporal anomalies
    pub fn detect_anomalies(&self, events: &[TimePoint]) -> Vec<TemporalPattern> {
        info!("🔍 Detecting temporal anomalies");

        let mut anomalies = Vec::new();

        // Simple anomaly detection: events with unusual timing
        if events.len() < 3 {
            return anomalies;
        }

        // Calculate average inter-event time
        let mut intervals = Vec::new();
        for i in 1..events.len() {
            let interval = events[i].temporal_distance(&events[i - 1]).abs();
            intervals.push(interval);
        }

        let avg_interval: f64 = intervals.iter().sum::<i64>() as f64 / intervals.len() as f64;
        let std_dev = calculate_std_dev(&intervals, avg_interval);

        // Flag intervals > 3 std deviations as anomalies
        for (i, &interval) in intervals.iter().enumerate() {
            if (interval as f64 - avg_interval).abs() > 3.0 * std_dev {
                anomalies.push(TemporalPattern {
                    pattern_type: PatternType::Anomaly,
                    sequence: vec![events[i].event.clone(), events[i + 1].event.clone()],
                    support: 1,
                    confidence: 1.0,
                    time_windows: vec![interval],
                });
            }
        }

        info!("✅ Found {} temporal anomalies", anomalies.len());
        anomalies
    }

    /// Find predictive patterns (A → B with high confidence)
    pub fn find_predictive_patterns(&self, events: &[TimePoint]) -> Vec<TemporalPattern> {
        info!("🔮 Finding predictive patterns");

        let mut predictive = Vec::new();

        // Track A → B occurrences
        let mut transitions: HashMap<(String, String), (usize, usize)> = HashMap::new();

        for i in 0..events.len().saturating_sub(1) {
            let key = (events[i].event.clone(), events[i + 1].event.clone());
            let entry = transitions.entry(key).or_insert((0, 0));
            entry.0 += 1; // Total A→B occurrences
        }

        // Calculate confidence: P(B|A)
        let mut event_counts: HashMap<String, usize> = HashMap::new();
        for event in events {
            *event_counts.entry(event.event.clone()).or_insert(0) += 1;
        }

        for ((event_a, event_b), (count_ab, _)) in transitions {
            if let Some(&count_a) = event_counts.get(&event_a) {
                let confidence = count_ab as f64 / count_a as f64;

                if confidence >= self.min_confidence {
                    predictive.push(TemporalPattern {
                        pattern_type: PatternType::Predictive,
                        sequence: vec![event_a, event_b],
                        support: count_ab,
                        confidence,
                        time_windows: vec![],
                    });
                }
            }
        }

        info!("✅ Found {} predictive patterns", predictive.len());
        predictive
    }
}

// ============================================================================
// Temporal Reasoner
// ============================================================================

pub struct TemporalReasoner {
    #[allow(dead_code)]
    llm: Arc<AnthropicClient>,
    causality_detector: CrossScaleCausalityDetector,
    pattern_miner: TemporalPatternMiner,
}

impl TemporalReasoner {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self {
            causality_detector: CrossScaleCausalityDetector::new(llm.clone()),
            pattern_miner: TemporalPatternMiner::new(3, 0.7),
            llm,
        }
    }

    /// Comprehensive temporal analysis
    pub async fn analyze(&self, events: Vec<TimePoint>) -> Result<TemporalAnalysisResult> {
        info!("🕐 Starting temporal analysis of {} events", events.len());

        // 1. Mine patterns
        let frequent_sequences = self.pattern_miner.mine_frequent_sequences(&events);
        let anomalies = self.pattern_miner.detect_anomalies(&events);
        let predictive = self.pattern_miner.find_predictive_patterns(&events);

        // 2. Detect cross-scale causality
        let event_pairs: Vec<(TimePoint, TimePoint)> = events
            .windows(2)
            .map(|w| (w[0].clone(), w[1].clone()))
            .collect();

        let causalities = self.causality_detector.detect(&event_pairs).await?;

        // 3. Identify scale distribution
        let mut scale_counts: HashMap<TemporalScale, usize> = HashMap::new();
        for event in &events {
            *scale_counts.entry(event.scale).or_insert(0) += 1;
        }

        Ok(TemporalAnalysisResult {
            total_events: events.len(),
            time_span: if events.len() >= 2 {
                Some(TimeRange::new(
                    events.first().unwrap().clone(),
                    events.last().unwrap().clone(),
                ))
            } else {
                None
            },
            scale_distribution: scale_counts,
            frequent_sequences,
            anomalies,
            predictive_patterns: predictive,
            cross_scale_causalities: causalities,
        })
    }
}

#[derive(Debug, Serialize)]
pub struct TemporalAnalysisResult {
    pub total_events: usize,
    pub time_span: Option<TimeRange>,
    pub scale_distribution: HashMap<TemporalScale, usize>,
    pub frequent_sequences: Vec<TemporalPattern>,
    pub anomalies: Vec<TemporalPattern>,
    pub predictive_patterns: Vec<TemporalPattern>,
    pub cross_scale_causalities: Vec<CrossScaleCausality>,
}

// ============================================================================
// Helper Functions
// ============================================================================

fn extract_number(s: &str) -> Option<i64> {
    s.split_whitespace()
        .find_map(|word| word.parse::<i64>().ok())
}

fn calculate_std_dev(values: &[i64], mean: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }

    let variance: f64 = values
        .iter()
        .map(|&x| {
            let diff = x as f64 - mean;
            diff * diff
        })
        .sum::<f64>()
        / values.len() as f64;

    variance.sqrt()
}
