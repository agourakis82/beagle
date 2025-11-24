use axum::{extract::State, http::StatusCode, Json};
use beagle_agents::metacognitive::{
    BottleneckType, ClusterPriority, DegradationSeverity, FailurePattern, PatternCluster,
    PerformanceBottleneck, PerformanceDegradation, PerformanceMonitor, PerformanceTrend,
    QueryPerformance, TrendDirection, WeaknessAnalyzer,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::AppState;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct AnalyzePerformanceRequest {
    /// Performance history to analyze
    pub history: Vec<QueryPerformanceDto>,
    /// Window size for analysis (default: 50)
    #[serde(default = "default_window_size")]
    pub window_size: usize,
}

fn default_window_size() -> usize {
    50
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct QueryPerformanceDto {
    pub query: String,
    pub domain: String,
    pub latency_ms: u64,
    pub quality_score: f64,
    pub user_satisfaction: Option<f64>,
    pub success: bool,
    pub error: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PerformanceAnalysisResponse {
    pub success_rate: f64,
    pub average_quality: f64,
    pub degradations: Vec<PerformanceDegradationDto>,
    pub bottlenecks: Vec<PerformanceBottleneckDto>,
    pub trends: Vec<PerformanceTrendDto>,
    pub domain_stats: HashMap<String, DomainStatsDto>,
}

#[derive(Debug, Serialize)]
pub struct PerformanceDegradationDto {
    pub detected: bool,
    pub metric: String,
    pub current_value: f64,
    pub baseline_value: f64,
    pub degradation_percent: f64,
    pub severity: String,
}

#[derive(Debug, Serialize)]
pub struct PerformanceBottleneckDto {
    pub bottleneck_type: String,
    pub affected_domain: Option<String>,
    pub average_latency_ms: u64,
    pub percentile_95_ms: u64,
    pub recommendation: String,
}

#[derive(Debug, Serialize)]
pub struct PerformanceTrendDto {
    pub metric: String,
    pub direction: String,
    pub change_percent: f64,
    pub confidence: f64,
}

#[derive(Debug, Serialize)]
pub struct DomainStatsDto {
    pub total: usize,
    pub successes: usize,
    pub success_rate: f64,
    pub average_quality: f64,
}

#[derive(Debug, Deserialize)]
pub struct AnalyzeFailuresRequest {
    /// Recent query performance history (should include failures)
    pub history: Vec<QueryPerformanceDto>,
    /// Whether to cluster patterns
    #[serde(default)]
    pub cluster_patterns: bool,
}

#[derive(Debug, Serialize)]
pub struct FailureAnalysisResponse {
    pub patterns: Vec<FailurePatternDto>,
    pub clusters: Option<Vec<PatternClusterDto>>,
    pub missing_capabilities: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct FailurePatternDto {
    pub pattern_type: String,
    pub description: String,
    pub frequency: usize,
    pub example_queries: Vec<String>,
    pub recommended_fix: String,
    pub severity_score: f64,
}

#[derive(Debug, Serialize)]
pub struct PatternClusterDto {
    pub cluster_id: String,
    pub common_theme: String,
    pub pattern_count: usize,
    pub aggregate_frequency: usize,
    pub priority: String,
}

// ============================================================================
// Endpoint Handlers
// ============================================================================

/// POST /api/v1/dev/metacognitive/analyze-performance
///
/// Analyzes performance metrics to detect degradation, bottlenecks, and trends.
pub async fn analyze_performance(
    Json(req): Json<AnalyzePerformanceRequest>,
) -> Result<Json<PerformanceAnalysisResponse>, StatusCode> {
    let window_size = req.window_size;

    // Convert DTO to domain model
    let mut monitor = PerformanceMonitor::new(1000);

    for perf_dto in &req.history {
        let perf = QueryPerformance {
            query_id: Uuid::new_v4(),
            query: perf_dto.query.clone(),
            domain: perf_dto.domain.clone(),
            latency_ms: perf_dto.latency_ms,
            quality_score: perf_dto.quality_score,
            user_satisfaction: perf_dto.user_satisfaction,
            timestamp: Utc::now(),
            success: perf_dto.success,
            error: perf_dto.error.clone(),
        };
        monitor.record(perf);
    }

    // Analyze
    let success_rate = monitor.success_rate(window_size);
    let average_quality = monitor.average_quality(window_size);
    let degradations = monitor.detect_degradation(window_size);
    let bottlenecks = monitor.identify_bottlenecks(10);
    let trends = monitor.analyze_trends(window_size);
    let domain_stats = monitor.domain_performance();

    // Convert to DTO
    let response = PerformanceAnalysisResponse {
        success_rate,
        average_quality,
        degradations: degradations.into_iter().map(to_degradation_dto).collect(),
        bottlenecks: bottlenecks.into_iter().map(to_bottleneck_dto).collect(),
        trends: trends.into_iter().map(to_trend_dto).collect(),
        domain_stats: domain_stats
            .into_iter()
            .map(|(k, v)| {
                (
                    k,
                    DomainStatsDto {
                        total: v.total,
                        successes: v.successes,
                        success_rate: v.success_rate(),
                        average_quality: v.average_quality(),
                    },
                )
            })
            .collect(),
    };

    Ok(Json(response))
}

/// POST /api/v1/dev/metacognitive/analyze-failures
///
/// Analyzes failure patterns using LLM to identify systemic issues.
pub async fn analyze_failures(
    State(state): State<AppState>,
    Json(req): Json<AnalyzeFailuresRequest>,
) -> Result<Json<FailureAnalysisResponse>, StatusCode> {
    // Convert DTO to domain model
    let mut monitor = PerformanceMonitor::new(1000);

    for perf_dto in &req.history {
        let perf = QueryPerformance {
            query_id: Uuid::new_v4(),
            query: perf_dto.query.clone(),
            domain: perf_dto.domain.clone(),
            latency_ms: perf_dto.latency_ms,
            quality_score: perf_dto.quality_score,
            user_satisfaction: perf_dto.user_satisfaction,
            timestamp: Utc::now(),
            success: perf_dto.success,
            error: perf_dto.error.clone(),
        };
        monitor.record(perf);
    }

    let llm = state
        .anthropic_client()
        .ok_or(StatusCode::SERVICE_UNAVAILABLE)?;
    let analyzer = WeaknessAnalyzer::new(llm);

    // Analyze failures
    let patterns = analyzer.analyze_failures(&monitor).await.map_err(|e| {
        tracing::error!("Failed to analyze failures: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    // Cluster patterns if requested
    let clusters = if req.cluster_patterns {
        match analyzer.cluster_patterns(&patterns).await {
            Ok(c) => Some(c),
            Err(e) => {
                tracing::warn!("Failed to cluster patterns: {}", e);
                None
            }
        }
    } else {
        None
    };

    // Identify missing capabilities
    let missing_capabilities = analyzer
        .identify_missing_capabilities(&patterns)
        .await
        .unwrap_or_else(|e| {
            tracing::warn!("Failed to identify missing capabilities: {}", e);
            vec![]
        });

    let response = FailureAnalysisResponse {
        patterns: patterns.into_iter().map(to_pattern_dto).collect(),
        clusters: clusters.map(|cs| cs.into_iter().map(to_cluster_dto).collect()),
        missing_capabilities,
    };

    Ok(Json(response))
}

// ============================================================================
// Conversion Helpers
// ============================================================================

fn to_degradation_dto(deg: PerformanceDegradation) -> PerformanceDegradationDto {
    PerformanceDegradationDto {
        detected: deg.detected,
        metric: deg.metric,
        current_value: deg.current_value,
        baseline_value: deg.baseline_value,
        degradation_percent: deg.degradation_percent,
        severity: match deg.severity {
            DegradationSeverity::None => "none".to_string(),
            DegradationSeverity::Minor => "minor".to_string(),
            DegradationSeverity::Moderate => "moderate".to_string(),
            DegradationSeverity::Severe => "severe".to_string(),
        },
    }
}

fn to_bottleneck_dto(bottleneck: PerformanceBottleneck) -> PerformanceBottleneckDto {
    PerformanceBottleneckDto {
        bottleneck_type: match bottleneck.bottleneck_type {
            BottleneckType::HighLatency => "high_latency".to_string(),
            BottleneckType::LowQuality => "low_quality".to_string(),
            BottleneckType::FrequentFailures => "frequent_failures".to_string(),
            BottleneckType::UserDissatisfaction => "user_dissatisfaction".to_string(),
        },
        affected_domain: bottleneck.affected_domain,
        average_latency_ms: bottleneck.average_latency_ms,
        percentile_95_ms: bottleneck.percentile_95_ms,
        recommendation: bottleneck.recommendation,
    }
}

fn to_trend_dto(trend: PerformanceTrend) -> PerformanceTrendDto {
    PerformanceTrendDto {
        metric: trend.metric,
        direction: match trend.direction {
            TrendDirection::Improving => "improving".to_string(),
            TrendDirection::Stable => "stable".to_string(),
            TrendDirection::Degrading => "degrading".to_string(),
        },
        change_percent: trend.change_percent,
        confidence: trend.confidence,
    }
}

fn to_pattern_dto(pattern: FailurePattern) -> FailurePatternDto {
    FailurePatternDto {
        pattern_type: pattern.pattern_type,
        description: pattern.description,
        frequency: pattern.frequency,
        example_queries: pattern.example_queries,
        recommended_fix: pattern.recommended_fix,
        severity_score: pattern.severity_score,
    }
}

fn to_cluster_dto(cluster: PatternCluster) -> PatternClusterDto {
    PatternClusterDto {
        cluster_id: cluster.cluster_id,
        common_theme: cluster.common_theme,
        pattern_count: cluster.patterns.len(),
        aggregate_frequency: cluster.aggregate_frequency,
        priority: match cluster.priority {
            ClusterPriority::Critical => "critical".to_string(),
            ClusterPriority::High => "high".to_string(),
            ClusterPriority::Medium => "medium".to_string(),
            ClusterPriority::Low => "low".to_string(),
        },
    }
}
