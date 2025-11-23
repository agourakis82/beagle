#[cfg(test)]
mod tests {
    use super::super::monitor::*;
    use chrono::Utc;
    use uuid::Uuid;

    fn create_test_performance(
        query: &str,
        domain: &str,
        latency_ms: u64,
        quality: f64,
        success: bool,
    ) -> QueryPerformance {
        QueryPerformance {
            query_id: Uuid::new_v4(),
            query: query.to_string(),
            domain: domain.to_string(),
            latency_ms,
            quality_score: quality,
            user_satisfaction: None,
            timestamp: Utc::now(),
            success,
            error: if success {
                None
            } else {
                Some("error".to_string())
            },
        }
    }

    #[test]
    fn test_performance_monitor_basic() {
        let mut monitor = PerformanceMonitor::new(100);

        monitor.record(create_test_performance("test1", "science", 1000, 0.9, true));
        monitor.record(create_test_performance("test2", "history", 1500, 0.8, true));
        monitor.record(create_test_performance(
            "test3", "science", 2000, 0.7, false,
        ));

        assert_eq!(monitor.get_recent(10).len(), 3);
        assert_eq!(monitor.success_rate(10), 2.0 / 3.0);

        let avg_quality = monitor.average_quality(10);
        assert!((avg_quality - 0.8).abs() < 0.01);
    }

    #[test]
    fn test_domain_performance() {
        let mut monitor = PerformanceMonitor::new(100);

        monitor.record(create_test_performance("q1", "science", 1000, 0.9, true));
        monitor.record(create_test_performance("q2", "science", 1500, 0.8, true));
        monitor.record(create_test_performance("q3", "history", 2000, 0.7, false));

        let domain_stats = monitor.domain_performance();

        let science_stats = domain_stats.get("science").unwrap();
        assert_eq!(science_stats.total, 2);
        assert_eq!(science_stats.successes, 2);
        assert_eq!(science_stats.success_rate(), 1.0);

        let history_stats = domain_stats.get("history").unwrap();
        assert_eq!(history_stats.total, 1);
        assert_eq!(history_stats.success_rate(), 0.0);
    }

    #[test]
    fn test_degradation_detection() {
        let mut monitor = PerformanceMonitor::new(1000);

        // Baseline: 20 queries with 90% success, 0.9 quality
        for i in 0..20 {
            monitor.record(create_test_performance(
                &format!("baseline_{}", i),
                "science",
                1000,
                0.9,
                i < 18, // 90% success
            ));
        }

        // Recent: 20 queries with 60% success, 0.7 quality (degradation)
        for i in 0..20 {
            monitor.record(create_test_performance(
                &format!("recent_{}", i),
                "science",
                1000,
                0.7,
                i < 12, // 60% success
            ));
        }

        let degradations = monitor.detect_degradation(20);

        assert!(!degradations.is_empty());

        // Should detect success rate degradation
        let success_deg = degradations
            .iter()
            .find(|d| d.metric == "success_rate")
            .expect("Should detect success rate degradation");

        assert!(success_deg.detected);
        assert!(success_deg.degradation_percent > 5.0);

        // Should detect quality degradation
        let quality_deg = degradations.iter().find(|d| d.metric == "quality_score");

        assert!(quality_deg.is_some());
    }

    #[test]
    fn test_bottleneck_identification() {
        let mut monitor = PerformanceMonitor::new(1000);

        // Create high latency bottleneck
        for i in 0..100 {
            let latency = if i > 95 { 6000 } else { 2000 }; // >95th percentile is 6s
            monitor.record(create_test_performance(
                &format!("query_{}", i),
                "science",
                latency,
                0.8,
                true,
            ));
        }

        let bottlenecks = monitor.identify_bottlenecks(10);

        assert!(!bottlenecks.is_empty());

        let latency_bottleneck = bottlenecks
            .iter()
            .find(|b| matches!(b.bottleneck_type, BottleneckType::HighLatency));

        assert!(latency_bottleneck.is_some());
    }

    #[test]
    fn test_bottleneck_low_quality_domain() {
        let mut monitor = PerformanceMonitor::new(1000);

        // science domain: good quality
        for i in 0..20 {
            monitor.record(create_test_performance(
                &format!("sci_{}", i),
                "science",
                1000,
                0.9,
                true,
            ));
        }

        // history domain: low quality
        for i in 0..20 {
            monitor.record(create_test_performance(
                &format!("hist_{}", i),
                "history",
                1000,
                0.4, // Low quality
                true,
            ));
        }

        let bottlenecks = monitor.identify_bottlenecks(10);

        let quality_bottleneck = bottlenecks
            .iter()
            .find(|b| matches!(b.bottleneck_type, BottleneckType::LowQuality));

        assert!(quality_bottleneck.is_some());
        assert_eq!(
            quality_bottleneck.unwrap().affected_domain.as_deref(),
            Some("history")
        );
    }

    #[test]
    fn test_trend_analysis_improving() {
        let mut monitor = PerformanceMonitor::new(1000);

        // Old window: 60% success
        for i in 0..30 {
            monitor.record(create_test_performance(
                &format!("old_{}", i),
                "science",
                1000,
                0.6,
                i < 18,
            ));
        }

        // Middle window: 75% success
        for i in 0..30 {
            monitor.record(create_test_performance(
                &format!("mid_{}", i),
                "science",
                1000,
                0.75,
                i < 22,
            ));
        }

        // Recent window: 90% success
        for i in 0..30 {
            monitor.record(create_test_performance(
                &format!("recent_{}", i),
                "science",
                1000,
                0.9,
                i < 27,
            ));
        }

        let trends = monitor.analyze_trends(30);

        assert!(!trends.is_empty());

        let success_trend = trends
            .iter()
            .find(|t| t.metric == "success_rate")
            .expect("Should have success rate trend");

        assert!(matches!(success_trend.direction, TrendDirection::Improving));
        assert!(success_trend.confidence > 0.5);
    }

    #[test]
    fn test_trend_analysis_degrading() {
        let mut monitor = PerformanceMonitor::new(1000);

        // Old: low latency
        for i in 0..30 {
            monitor.record(create_test_performance(
                &format!("old_{}", i),
                "science",
                1000,
                0.8,
                true,
            ));
        }

        // Middle: medium latency
        for i in 0..30 {
            monitor.record(create_test_performance(
                &format!("mid_{}", i),
                "science",
                2000,
                0.8,
                true,
            ));
        }

        // Recent: high latency
        for i in 0..30 {
            monitor.record(create_test_performance(
                &format!("recent_{}", i),
                "science",
                3000,
                0.8,
                true,
            ));
        }

        let trends = monitor.analyze_trends(30);

        let latency_trend = trends
            .iter()
            .find(|t| t.metric == "latency_ms")
            .expect("Should have latency trend");

        // Latency trend is inverted, so increasing latency = Degrading
        assert!(matches!(latency_trend.direction, TrendDirection::Degrading));
    }

    #[test]
    fn test_severity_classification() {
        assert!(matches!(
            super::super::monitor::classify_severity(3.0),
            DegradationSeverity::None
        ));
        assert!(matches!(
            super::super::monitor::classify_severity(8.0),
            DegradationSeverity::Minor
        ));
        assert!(matches!(
            super::super::monitor::classify_severity(20.0),
            DegradationSeverity::Moderate
        ));
        assert!(matches!(
            super::super::monitor::classify_severity(40.0),
            DegradationSeverity::Severe
        ));
    }

    #[test]
    fn test_max_history_limit() {
        let mut monitor = PerformanceMonitor::new(10);

        // Add 20 records (exceeds max_history)
        for i in 0..20 {
            monitor.record(create_test_performance(
                &format!("query_{}", i),
                "science",
                1000,
                0.8,
                true,
            ));
        }

        // Should only keep last 10
        assert_eq!(monitor.get_recent(100).len(), 10);
    }

    #[test]
    fn test_get_failures() {
        let mut monitor = PerformanceMonitor::new(100);

        monitor.record(create_test_performance("q1", "science", 1000, 0.9, true));
        monitor.record(create_test_performance("q2", "science", 1000, 0.3, true)); // Low quality
        monitor.record(create_test_performance("q3", "science", 1000, 0.8, false)); // Failure
        monitor.record(create_test_performance("q4", "science", 1000, 0.9, true));

        let failures = monitor.get_failures(10);

        assert_eq!(failures.len(), 2); // q2 (low quality) and q3 (failure)
    }
}
