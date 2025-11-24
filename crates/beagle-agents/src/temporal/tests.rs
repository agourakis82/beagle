#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{Duration, Utc};
    use std::sync::Arc;

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
    fn test_temporal_scale_display() {
        assert_eq!(format!("{}", TemporalScale::Microsecond), "Microsecond");
        assert_eq!(format!("{}", TemporalScale::Hour), "Hour");
        assert_eq!(format!("{}", TemporalScale::Year), "Year");
    }

    // ============================================================================
    // TimePoint Tests
    // ============================================================================

    #[test]
    fn test_timepoint_creation() {
        let tp = TimePoint::new(Utc::now(), TemporalScale::Second, "test_event".to_string());

        assert_eq!(tp.scale, TemporalScale::Second);
        assert_eq!(tp.event, "test_event");
    }

    #[test]
    fn test_timepoint_with_metadata() {
        let mut tp = TimePoint::new(Utc::now(), TemporalScale::Hour, "event".to_string());

        tp.add_metadata("key1".to_string(), "value1".to_string());
        tp.add_metadata("key2".to_string(), "value2".to_string());

        assert_eq!(tp.get_metadata("key1"), Some(&"value1".to_string()));
        assert_eq!(tp.get_metadata("key2"), Some(&"value2".to_string()));
        assert_eq!(tp.get_metadata("nonexistent"), None);
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

    #[test]
    fn test_timepoint_parse_temporal_expression_hours_ago() {
        let result = TimePoint::parse_temporal_expression("2 hours ago");
        assert!(result.is_ok());

        let tp = result.unwrap();
        assert_eq!(tp.event, "2 hours ago");
        assert_eq!(tp.scale, TemporalScale::Hour);

        // Check timestamp is approximately 2 hours in the past
        let expected = Utc::now() - Duration::hours(2);
        let diff = (tp.timestamp - expected).num_seconds().abs();
        assert!(diff < 5, "Timestamp should be within 5 seconds of expected");
    }

    #[test]
    fn test_timepoint_parse_temporal_expression_days_ago() {
        let result = TimePoint::parse_temporal_expression("3 days ago");
        assert!(result.is_ok());

        let tp = result.unwrap();
        assert_eq!(tp.scale, TemporalScale::Day);

        let expected = Utc::now() - Duration::days(3);
        let diff = (tp.timestamp - expected).num_seconds().abs();
        assert!(diff < 5);
    }

    #[test]
    fn test_timepoint_parse_temporal_expression_next_week() {
        let result = TimePoint::parse_temporal_expression("next week");
        assert!(result.is_ok());

        let tp = result.unwrap();
        assert_eq!(tp.scale, TemporalScale::Week);

        let expected = Utc::now() + Duration::weeks(1);
        let diff = (tp.timestamp - expected).num_seconds().abs();
        assert!(diff < 5);
    }

    #[test]
    fn test_timepoint_parse_temporal_expression_minutes() {
        let result = TimePoint::parse_temporal_expression("15 minutes ago");
        assert!(result.is_ok());

        let tp = result.unwrap();
        assert_eq!(tp.scale, TemporalScale::Minute);
    }

    #[test]
    fn test_timepoint_parse_temporal_expression_invalid() {
        let result = TimePoint::parse_temporal_expression("invalid expression");
        assert!(result.is_err());
    }

    // ============================================================================
    // TimeRange Tests
    // ============================================================================

    #[test]
    fn test_timerange_creation() {
        let now = Utc::now();
        let start = TimePoint::new(now, TemporalScale::Second, "start".to_string());
        let end = TimePoint::new(
            now + Duration::hours(2),
            TemporalScale::Hour,
            "end".to_string(),
        );

        let range = TimeRange::new(start, end);
        assert_eq!(range.start.event, "start");
        assert_eq!(range.end.event, "end");
    }

    #[test]
    fn test_timerange_overlaps_true() {
        let now = Utc::now();

        let range1 = TimeRange::new(
            TimePoint::new(now, TemporalScale::Hour, "r1_start".to_string()),
            TimePoint::new(
                now + Duration::hours(3),
                TemporalScale::Hour,
                "r1_end".to_string(),
            ),
        );

        let range2 = TimeRange::new(
            TimePoint::new(
                now + Duration::hours(2),
                TemporalScale::Hour,
                "r2_start".to_string(),
            ),
            TimePoint::new(
                now + Duration::hours(5),
                TemporalScale::Hour,
                "r2_end".to_string(),
            ),
        );

        assert!(range1.overlaps(&range2));
        assert!(range2.overlaps(&range1));
    }

    #[test]
    fn test_timerange_overlaps_false() {
        let now = Utc::now();

        let range1 = TimeRange::new(
            TimePoint::new(now, TemporalScale::Hour, "r1_start".to_string()),
            TimePoint::new(
                now + Duration::hours(2),
                TemporalScale::Hour,
                "r1_end".to_string(),
            ),
        );

        let range2 = TimeRange::new(
            TimePoint::new(
                now + Duration::hours(3),
                TemporalScale::Hour,
                "r2_start".to_string(),
            ),
            TimePoint::new(
                now + Duration::hours(5),
                TemporalScale::Hour,
                "r2_end".to_string(),
            ),
        );

        assert!(!range1.overlaps(&range2));
        assert!(!range2.overlaps(&range1));
    }

    #[test]
    fn test_timerange_overlaps_edge_case_exact_boundary() {
        let now = Utc::now();

        let range1 = TimeRange::new(
            TimePoint::new(now, TemporalScale::Hour, "r1_start".to_string()),
            TimePoint::new(
                now + Duration::hours(2),
                TemporalScale::Hour,
                "r1_end".to_string(),
            ),
        );

        let range2 = TimeRange::new(
            TimePoint::new(
                now + Duration::hours(2),
                TemporalScale::Hour,
                "r2_start".to_string(),
            ),
            TimePoint::new(
                now + Duration::hours(4),
                TemporalScale::Hour,
                "r2_end".to_string(),
            ),
        );

        // Ranges touching at exact boundary should not overlap
        assert!(!range1.overlaps(&range2));
    }

    #[test]
    fn test_timerange_normalize_scale_seconds() {
        let now = Utc::now();
        let range = TimeRange::new(
            TimePoint::new(now, TemporalScale::Second, "start".to_string()),
            TimePoint::new(
                now + Duration::seconds(45),
                TemporalScale::Second,
                "end".to_string(),
            ),
        );

        assert_eq!(range.normalize_scale(), TemporalScale::Second);
    }

    #[test]
    fn test_timerange_normalize_scale_days() {
        let now = Utc::now();
        let range = TimeRange::new(
            TimePoint::new(now, TemporalScale::Day, "start".to_string()),
            TimePoint::new(
                now + Duration::days(5),
                TemporalScale::Day,
                "end".to_string(),
            ),
        );

        assert_eq!(range.normalize_scale(), TemporalScale::Day);
    }

    #[test]
    fn test_timerange_normalize_scale_months() {
        let now = Utc::now();
        let range = TimeRange::new(
            TimePoint::new(now, TemporalScale::Month, "start".to_string()),
            TimePoint::new(
                now + Duration::days(90),
                TemporalScale::Month,
                "end".to_string(),
            ),
        );

        assert_eq!(range.normalize_scale(), TemporalScale::Month);
    }

    // ============================================================================
    // CrossScaleCausality Tests
    // ============================================================================

    #[test]
    fn test_cross_scale_causality_creation() {
        let now = Utc::now();
        let cause = TimePoint::new(now, TemporalScale::Second, "fast_event".to_string());
        let effect = TimePoint::new(
            now + Duration::hours(2),
            TemporalScale::Hour,
            "slow_event".to_string(),
        );

        let causality = CrossScaleCausality {
            cause: cause.clone(),
            effect: effect.clone(),
            causal_type: CausalityType::FastToSlow,
            strength: 0.85,
            lag_ms: 7_200_000, // 2 hours
            explanation: "Fast trigger causes delayed slow effect".to_string(),
        };

        assert_eq!(causality.causal_type, CausalityType::FastToSlow);
        assert_eq!(causality.strength, 0.85);
        assert_eq!(causality.lag_ms, 7_200_000);
    }

    #[test]
    fn test_causality_detector_estimate_strength_perfect_lag() {
        let detector = CrossScaleCausalityDetector {
            llm: Arc::new(AnthropicClient::new("test_key".to_string())),
        };

        let now = Utc::now();
        let cause = TimePoint::new(now, TemporalScale::Hour, "cause".to_string());
        let effect = TimePoint::new(
            now + Duration::hours(1),
            TemporalScale::Hour,
            "effect".to_string(),
        );

        let strength = detector.estimate_causal_strength(&cause, &effect, 3_600_000); // 1 hour lag

        // Lag matches scale exactly (1 hour), so strength should be high
        assert!(strength >= 0.8);
    }

    #[test]
    fn test_causality_detector_estimate_strength_poor_lag() {
        let detector = CrossScaleCausalityDetector {
            llm: Arc::new(AnthropicClient::new("test_key".to_string())),
        };

        let now = Utc::now();
        let cause = TimePoint::new(now, TemporalScale::Second, "cause".to_string());
        let effect = TimePoint::new(
            now + Duration::hours(24),
            TemporalScale::Day,
            "effect".to_string(),
        );

        let strength = detector.estimate_causal_strength(&cause, &effect, 86_400_000); // 24 hour lag

        // Lag is much larger than cause scale (second), so strength should be lower
        assert!(strength < 0.8);
    }

    // ============================================================================
    // TemporalPatternMiner Tests
    // ============================================================================

    #[test]
    fn test_pattern_miner_frequent_sequences() {
        let miner = TemporalPatternMiner::new(2, 0.7);

        let now = Utc::now();
        let events = vec![
            TimePoint::new(now, TemporalScale::Second, "A".to_string()),
            TimePoint::new(
                now + Duration::seconds(1),
                TemporalScale::Second,
                "B".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(2),
                TemporalScale::Second,
                "A".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(3),
                TemporalScale::Second,
                "B".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(4),
                TemporalScale::Second,
                "A".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(5),
                TemporalScale::Second,
                "B".to_string(),
            ),
        ];

        let patterns = miner.mine_frequent_sequences(&events);

        // Should find A→B pattern (appears 3 times, meets min_support=2)
        assert!(!patterns.is_empty());

        let ab_pattern = patterns.iter().find(|p| {
            p.pattern_type == TemporalPatternType::FrequentSequence
                && p.description.contains("A → B")
        });

        assert!(ab_pattern.is_some());
        let pattern = ab_pattern.unwrap();
        assert!(pattern.support >= 2);
    }

    #[test]
    fn test_pattern_miner_frequent_sequences_below_threshold() {
        let miner = TemporalPatternMiner::new(5, 0.7); // High min_support

        let now = Utc::now();
        let events = vec![
            TimePoint::new(now, TemporalScale::Second, "A".to_string()),
            TimePoint::new(
                now + Duration::seconds(1),
                TemporalScale::Second,
                "B".to_string(),
            ),
        ];

        let patterns = miner.mine_frequent_sequences(&events);

        // Support is only 1, below min_support=5
        assert!(patterns.is_empty());
    }

    #[test]
    fn test_pattern_miner_detect_anomalies() {
        let miner = TemporalPatternMiner::new(2, 0.7);

        let now = Utc::now();
        let mut events = vec![];

        // Create regular intervals of 10 seconds
        for i in 0..10 {
            events.push(TimePoint::new(
                now + Duration::seconds(i * 10),
                TemporalScale::Second,
                format!("event_{}", i),
            ));
        }

        // Add anomalous event with 100 second gap (10x normal)
        events.push(TimePoint::new(
            now + Duration::seconds(100 + 100),
            TemporalScale::Second,
            "anomaly".to_string(),
        ));

        let patterns = miner.detect_anomalies(&events);

        // Should detect the 100-second gap as anomaly (>3 sigma from mean of 10s)
        assert!(!patterns.is_empty());

        let anomaly = patterns
            .iter()
            .find(|p| p.pattern_type == TemporalPatternType::Anomaly);

        assert!(anomaly.is_some());
    }

    #[test]
    fn test_pattern_miner_detect_anomalies_uniform() {
        let miner = TemporalPatternMiner::new(2, 0.7);

        let now = Utc::now();
        let mut events = vec![];

        // All events at exact 10-second intervals - no anomalies
        for i in 0..10 {
            events.push(TimePoint::new(
                now + Duration::seconds(i * 10),
                TemporalScale::Second,
                format!("event_{}", i),
            ));
        }

        let patterns = miner.detect_anomalies(&events);

        // Should find no anomalies (std_dev will be 0)
        assert!(patterns.is_empty());
    }

    #[test]
    fn test_pattern_miner_predictive_patterns() {
        let miner = TemporalPatternMiner::new(2, 0.7); // min_confidence = 0.7

        let now = Utc::now();
        let events = vec![
            TimePoint::new(now, TemporalScale::Second, "A".to_string()),
            TimePoint::new(
                now + Duration::seconds(1),
                TemporalScale::Second,
                "B".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(2),
                TemporalScale::Second,
                "A".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(3),
                TemporalScale::Second,
                "B".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(4),
                TemporalScale::Second,
                "A".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(5),
                TemporalScale::Second,
                "C".to_string(),
            ), // A→C
        ];

        let patterns = miner.find_predictive_patterns(&events);

        // Should find A→B with high confidence (2/3 = 0.67, below 0.7)
        // Actually A appears 3 times, followed by B twice and C once
        // So P(B|A) = 2/3 ≈ 0.67, which is below min_confidence

        // Let's check if any patterns were found
        let ab_pattern = patterns.iter().find(|p| p.description.contains("A → B"));

        // Should not find it because 0.67 < 0.7
        assert!(ab_pattern.is_none() || patterns.is_empty());
    }

    #[test]
    fn test_pattern_miner_predictive_patterns_high_confidence() {
        let miner = TemporalPatternMiner::new(2, 0.75);

        let now = Utc::now();
        let events = vec![
            TimePoint::new(now, TemporalScale::Second, "A".to_string()),
            TimePoint::new(
                now + Duration::seconds(1),
                TemporalScale::Second,
                "B".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(2),
                TemporalScale::Second,
                "A".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(3),
                TemporalScale::Second,
                "B".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(4),
                TemporalScale::Second,
                "A".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(5),
                TemporalScale::Second,
                "B".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(6),
                TemporalScale::Second,
                "A".to_string(),
            ),
            TimePoint::new(
                now + Duration::seconds(7),
                TemporalScale::Second,
                "B".to_string(),
            ),
        ];

        let patterns = miner.find_predictive_patterns(&events);

        // P(B|A) = 4/4 = 1.0, which is > 0.75
        assert!(!patterns.is_empty());

        let ab_pattern = patterns.iter().find(|p| p.description.contains("A → B"));

        assert!(ab_pattern.is_some());
        let pattern = ab_pattern.unwrap();
        assert!(pattern.confidence >= 0.75);
    }

    // ============================================================================
    // Helper Function Tests
    // ============================================================================

    #[test]
    fn test_extract_number() {
        assert_eq!(extract_number("15 minutes ago"), Some(15));
        assert_eq!(extract_number("2 hours"), Some(2));
        assert_eq!(extract_number("next week"), Some(1));
        assert_eq!(extract_number("no numbers here"), None);
        assert_eq!(extract_number("100 days"), Some(100));
    }

    #[test]
    fn test_calculate_std_dev() {
        let values = vec![2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0];
        let mean = 5.0;

        let std_dev = calculate_std_dev(&values, mean);

        // Expected std dev ≈ 2.0
        assert!((std_dev - 2.0).abs() < 0.1);
    }

    #[test]
    fn test_calculate_std_dev_zero_variance() {
        let values = vec![5.0, 5.0, 5.0, 5.0];
        let mean = 5.0;

        let std_dev = calculate_std_dev(&values, mean);

        assert_eq!(std_dev, 0.0);
    }

    #[test]
    fn test_calculate_std_dev_empty() {
        let values: Vec<f64> = vec![];
        let mean = 0.0;

        let std_dev = calculate_std_dev(&values, mean);

        assert_eq!(std_dev, 0.0);
    }
}
