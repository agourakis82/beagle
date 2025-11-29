use super::*;
use chrono::{Duration, Utc};

// ============================================================================
// TemporalScale Tests
// ============================================================================

#[test]
fn test_temporal_scale_to_millis() {
    assert_eq!(TemporalScale::Microsecond.to_millis(), 0);
    assert_eq!(TemporalScale::Millisecond.to_millis(), 1);
    assert_eq!(TemporalScale::Second.to_millis(), 1_000);
    assert_eq!(TemporalScale::Minute.to_millis(), 60_000);
    assert_eq!(TemporalScale::Hour.to_millis(), 3_600_000);
    assert_eq!(TemporalScale::Day.to_millis(), 86_400_000);
    assert_eq!(TemporalScale::Week.to_millis(), 604_800_000);
    assert_eq!(TemporalScale::Month.to_millis(), 2_592_000_000);
    assert_eq!(TemporalScale::Year.to_millis(), 31_536_000_000);
}

#[test]
fn test_temporal_scale_from_duration() {
    assert_eq!(
        TemporalScale::from_duration(500),
        TemporalScale::Millisecond
    );
    assert_eq!(TemporalScale::from_duration(5_000), TemporalScale::Second);
    assert_eq!(TemporalScale::from_duration(120_000), TemporalScale::Minute);
    assert_eq!(TemporalScale::from_duration(7_200_000), TemporalScale::Hour);
    assert_eq!(
        TemporalScale::from_duration(172_800_000),
        TemporalScale::Day
    );
    assert_eq!(
        TemporalScale::from_duration(1_209_600_000),
        TemporalScale::Week
    );
    assert_eq!(
        TemporalScale::from_duration(5_184_000_000),
        TemporalScale::Month
    );
    assert_eq!(
        TemporalScale::from_duration(63_072_000_000),
        TemporalScale::Year
    );
}

#[test]
fn test_temporal_scale_ordering() {
    assert!(TemporalScale::Microsecond < TemporalScale::Millisecond);
    assert!(TemporalScale::Millisecond < TemporalScale::Second);
    assert!(TemporalScale::Second < TemporalScale::Minute);
    assert!(TemporalScale::Minute < TemporalScale::Hour);
    assert!(TemporalScale::Hour < TemporalScale::Day);
    assert!(TemporalScale::Day < TemporalScale::Week);
    assert!(TemporalScale::Week < TemporalScale::Month);
    assert!(TemporalScale::Month < TemporalScale::Year);
}

// ============================================================================
// TimePoint Tests
// ============================================================================

#[test]
fn test_timepoint_creation() {
    let tp = TimePoint::new(Utc::now(), TemporalScale::Second, "test_event".to_string());
    assert_eq!(tp.scale, TemporalScale::Second);
    assert_eq!(tp.event, "test_event");
    assert!(tp.metadata.is_empty());
}

#[test]
fn test_timepoint_metadata() {
    let mut tp = TimePoint::new(Utc::now(), TemporalScale::Hour, "event".to_string());
    tp.metadata.insert("key1".to_string(), "value1".to_string());
    tp.metadata.insert("key2".to_string(), "value2".to_string());

    assert_eq!(tp.metadata.get("key1"), Some(&"value1".to_string()));
    assert_eq!(tp.metadata.get("key2"), Some(&"value2".to_string()));
    assert_eq!(tp.metadata.get("nonexistent"), None);
}

#[test]
fn test_timepoint_temporal_distance() {
    let now = Utc::now();
    let tp1 = TimePoint::new(now, TemporalScale::Second, "event1".to_string());
    let tp2 = TimePoint::new(
        now + Duration::seconds(30),
        TemporalScale::Second,
        "event2".to_string(),
    );

    let distance = tp1.temporal_distance(&tp2);
    assert_eq!(distance, -30_000); // -30 seconds in milliseconds

    let distance_reverse = tp2.temporal_distance(&tp1);
    assert_eq!(distance_reverse, 30_000);
}

// ============================================================================
// TimeRange Tests
// ============================================================================

#[test]
fn test_timerange_creation() {
    let now = Utc::now();
    let start = TimePoint::new(now, TemporalScale::Second, "start".to_string());
    let end = TimePoint::new(
        now + Duration::hours(1),
        TemporalScale::Hour,
        "end".to_string(),
    );

    let range = TimeRange::new(start, end);
    assert_eq!(range.duration_ms(), 3_600_000);
}

#[test]
fn test_timerange_overlaps() {
    let now = Utc::now();

    let range1_start = TimePoint::new(now, TemporalScale::Hour, "start1".to_string());
    let range1_end = TimePoint::new(
        now + Duration::hours(2),
        TemporalScale::Hour,
        "end1".to_string(),
    );
    let range1 = TimeRange::new(range1_start, range1_end);

    let range2_start = TimePoint::new(
        now + Duration::hours(1),
        TemporalScale::Hour,
        "start2".to_string(),
    );
    let range2_end = TimePoint::new(
        now + Duration::hours(3),
        TemporalScale::Hour,
        "end2".to_string(),
    );
    let range2 = TimeRange::new(range2_start, range2_end);

    let range3_start = TimePoint::new(
        now + Duration::hours(5),
        TemporalScale::Hour,
        "start3".to_string(),
    );
    let range3_end = TimePoint::new(
        now + Duration::hours(6),
        TemporalScale::Hour,
        "end3".to_string(),
    );
    let range3 = TimeRange::new(range3_start, range3_end);

    assert!(range1.overlaps(&range2)); // They overlap
    assert!(!range1.overlaps(&range3)); // They don't overlap
}

#[test]
fn test_timerange_normalize_scale() {
    let now = Utc::now();
    let start = TimePoint::new(now, TemporalScale::Second, "start".to_string());
    let end = TimePoint::new(
        now + Duration::hours(2),
        TemporalScale::Hour,
        "end".to_string(),
    );
    let range = TimeRange::new(start, end);

    assert_eq!(range.normalize_scale(), TemporalScale::Hour);
}

// ============================================================================
// CrossScaleCausality Tests
// ============================================================================

#[test]
fn test_cross_scale_causality_fast_to_slow() {
    let causality = CrossScaleCausality {
        from_scale: TemporalScale::Second,
        to_scale: TemporalScale::Hour,
        from_event: "fast_event".to_string(),
        to_event: "slow_event".to_string(),
        mechanism: "cascade effect".to_string(),
        strength: 0.85,
        lag_ms: 7_200_000,
    };

    assert!(causality.is_fast_to_slow());
    assert!(!causality.is_slow_to_fast());
}

#[test]
fn test_cross_scale_causality_slow_to_fast() {
    let causality = CrossScaleCausality {
        from_scale: TemporalScale::Day,
        to_scale: TemporalScale::Second,
        from_event: "slow_event".to_string(),
        to_event: "fast_event".to_string(),
        mechanism: "trigger effect".to_string(),
        strength: 0.75,
        lag_ms: 1_000,
    };

    assert!(!causality.is_fast_to_slow());
    assert!(causality.is_slow_to_fast());
}

// ============================================================================
// TemporalPattern Tests
// ============================================================================

#[test]
fn test_temporal_pattern_creation() {
    let pattern = TemporalPattern {
        pattern_type: PatternType::PeriodicPattern,
        sequence: vec!["event_a".to_string(), "event_b".to_string()],
        support: 10,
        confidence: 0.9,
        time_windows: vec![1000, 2000],
    };

    // Verify fields are set correctly
    assert_eq!(pattern.sequence.len(), 2);
    assert_eq!(pattern.support, 10);
    assert_eq!(pattern.confidence, 0.9);
    assert_eq!(pattern.time_windows.len(), 2);
}

#[test]
fn test_pattern_type_variants() {
    // Just verify all variants can be constructed
    let _frequent = PatternType::FrequentSequence;
    let _periodic = PatternType::PeriodicPattern;
    let _anomaly = PatternType::Anomaly;
    let _predictive = PatternType::Predictive;
}

// ============================================================================
// TemporalPatternMiner Tests
// ============================================================================

#[test]
fn test_pattern_miner_creation() {
    let miner = TemporalPatternMiner::new(5, 0.8);
    // Just verify it creates without panic
    assert!(true);
}
