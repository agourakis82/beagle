//! Comprehensive integration tests for beagle-void
//!
//! Tests cover:
//! - VoidNavigator functionality and void navigation cycles
//! - ExtractionEngine resource extraction
//! - VoidProbe region probing and depth measurement
//! - Data structures and serialization
//! - Error handling and edge cases
//! - Void state and phase transitions

use beagle_void::{
    ExtractionConfig, ExtractionEngine, ExtractionResult, ExtractionType,
    ProbeConfig, ProbeResult, VoidConfig, VoidInsight, VoidNavigator,
    VoidNavigationResult, VoidPhase, VoidProbe, VoidState,
};

// ============================================================================
// VOIDNAVIGATOR TESTS
// ============================================================================

#[test]
fn test_void_navigator_creation() {
    let config = VoidConfig::default();
    let navigator = VoidNavigator::new(config);
    let _nav_ref = &navigator;
}

#[tokio::test]
async fn test_void_navigator_with_config() {
    let config = VoidConfig {
        max_depth: 5.0,
        dissolution_rate: 0.2,
        reintegration_rate: 0.3,
        coherence_threshold: 0.4,
    };
    let navigator = VoidNavigator::new(config);
    let result = navigator.navigate(3.0).await;
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_void_navigator_navigation_result() {
    let navigator = VoidNavigator::new(VoidConfig::default());
    let result = navigator.navigate(2.0).await.unwrap();
    assert!(result.max_depth_reached > 0.0);
    // Duration can be 0 in very fast execution, so we just check it's >= 0
    assert!(result.duration_ms >= 0);
}

#[tokio::test]
async fn test_void_navigator_state_transition() {
    let navigator = VoidNavigator::new(VoidConfig::default());
    
    // Initial state should be Grounded
    let initial_state = navigator.get_state().await;
    assert_eq!(initial_state.phase, VoidPhase::Grounded);
    assert_eq!(initial_state.depth, 0.0);
    
    // After navigation, should return to Grounded
    let _result = navigator.navigate(1.0).await.unwrap();
    let final_state = navigator.get_state().await;
    assert_eq!(final_state.phase, VoidPhase::Grounded);
    assert_eq!(final_state.depth, 0.0);
}

// ============================================================================
// EXTRACTIONENGINE TESTS
// ============================================================================

#[test]
fn test_extraction_engine_creation() {
    let config = ExtractionConfig::default();
    let engine = ExtractionEngine::new(config);
    let _ref = &engine;
}

#[test]
fn test_extraction_engine_with_config() {
    let config = ExtractionConfig {
        sensitivity: 0.8,
        min_quality: 0.5,
        max_extractions: 50,
    };
    let engine = ExtractionEngine::new(config);
    let _ref = &engine;
}

#[tokio::test]
async fn test_extraction_engine_extract() {
    let engine = ExtractionEngine::new(ExtractionConfig::default());
    let state = VoidState {
        depth: 5.0,
        coherence: 0.8,
        entropy: 0.2,
        phase: VoidPhase::InVoid,
    };
    
    let result = engine.extract(&state, ExtractionType::Vacuum).await;
    assert!(result.is_ok());
    
    let extraction = result.unwrap();
    assert!(extraction.quality_score > 0.0);
}

#[tokio::test]
async fn test_extraction_engine_different_types() {
    let engine = ExtractionEngine::new(ExtractionConfig::default());
    let state = VoidState {
        depth: 3.0,
        coherence: 0.7,
        entropy: 0.3,
        phase: VoidPhase::InVoid,
    };
    
    for extraction_type in [
        ExtractionType::Vacuum,
        ExtractionType::Negative,
        ExtractionType::ZeroPoint,
        ExtractionType::Liminal,
        ExtractionType::Holographic,
    ] {
        let result = engine.extract(&state, extraction_type).await;
        assert!(result.is_ok());
    }
}

// ============================================================================
// VOIDPROBE TESTS
// ============================================================================

#[test]
fn test_void_probe_creation() {
    let config = ProbeConfig::default();
    let probe = VoidProbe::new(config);
    let _ref = &probe;
}

#[test]
fn test_void_probe_with_config() {
    let config = ProbeConfig {
        probe_intensity: 0.7,
        measurement_precision: 0.95,
        intervention_strength: 0.4,
    };
    let probe = VoidProbe::new(config);
    let _ref = &probe;
}

#[tokio::test]
async fn test_void_probe_probe() {
    let probe = VoidProbe::new(ProbeConfig::default());
    let state = VoidState {
        depth: 4.0,
        coherence: 0.6,
        entropy: 0.4,
        phase: VoidPhase::InVoid,
    };
    
    let result = probe.probe(&state).await;
    assert!(result.is_ok());
    
    let probe_result = result.unwrap();
    assert!(probe_result.measurement >= 0.0);
    assert!(probe_result.uncertainty >= 0.0);
}

#[tokio::test]
async fn test_void_probe_state_tracking() {
    let probe = VoidProbe::new(ProbeConfig::default());
    let state = VoidState::default();
    
    // Initial state
    let initial = probe.get_state().await;
    assert!(!initial.active);
    assert_eq!(initial.measurements, 0);
    
    // After probe
    let _result = probe.probe(&state).await.unwrap();
    let after = probe.get_state().await;
    assert!(!after.active); // Should be false after probe completes
    assert_eq!(after.measurements, 1);
    assert!(after.last_result.is_some());
}

// ============================================================================
// VOID STATE TESTS
// ============================================================================

#[test]
fn test_void_state_default() {
    let state = VoidState::default();
    assert_eq!(state.depth, 0.0);
    assert_eq!(state.coherence, 1.0);
    assert_eq!(state.entropy, 0.0);
    assert_eq!(state.phase, VoidPhase::Grounded);
}

#[test]
fn test_void_state_custom() {
    let state = VoidState {
        depth: 5.0,
        coherence: 0.5,
        entropy: 0.5,
        phase: VoidPhase::InVoid,
    };
    assert_eq!(state.depth, 5.0);
    assert_eq!(state.coherence, 0.5);
    assert_eq!(state.entropy, 0.5);
    assert_eq!(state.phase, VoidPhase::InVoid);
}

#[test]
fn test_void_phase_variants() {
    let phases = [
        VoidPhase::Grounded,
        VoidPhase::Dissolving,
        VoidPhase::InVoid,
        VoidPhase::Reintegrating,
        VoidPhase::Transcended,
    ];
    
    // All phases should be distinct
    for (i, phase1) in phases.iter().enumerate() {
        for (j, phase2) in phases.iter().enumerate() {
            if i == j {
                assert_eq!(phase1, phase2);
            } else {
                assert_ne!(phase1, phase2);
            }
        }
    }
}

// ============================================================================
// VOID INSIGHT TESTS
// ============================================================================

#[test]
fn test_void_insight_creation() {
    use beagle_void::InsightType;
    
    let insight = VoidInsight {
        insight_type: InsightType::Pattern,
        content: "Test insight".to_string(),
        confidence: 0.8,
        depth_found: 3.5,
        metadata: std::collections::HashMap::new(),
    };
    
    assert_eq!(insight.insight_type, InsightType::Pattern);
    assert_eq!(insight.content, "Test insight");
    assert_eq!(insight.confidence, 0.8);
    assert_eq!(insight.depth_found, 3.5);
}

#[test]
fn test_insight_type_variants() {
    use beagle_void::InsightType;
    
    let types = [
        InsightType::Pattern,
        InsightType::Anomaly,
        InsightType::Connection,
        InsightType::Emergence,
        InsightType::Vacuum,
        InsightType::Liminal,
    ];
    
    // All types should be distinct
    for (i, t1) in types.iter().enumerate() {
        for (j, t2) in types.iter().enumerate() {
            if i == j {
                assert_eq!(t1, t2);
            } else {
                assert_ne!(t1, t2);
            }
        }
    }
}

// ============================================================================
// EXTRACTION RESULT TESTS
// ============================================================================

#[test]
fn test_extraction_result_empty() {
    let result = ExtractionResult {
        extracted_info: vec![],
        quality_score: 0.0,
        extraction_type: ExtractionType::Vacuum,
    };
    assert!(result.extracted_info.is_empty());
    assert_eq!(result.quality_score, 0.0);
}

#[test]
fn test_extraction_result_with_data() {
    use beagle_void::ExtractedInfo;
    
    let result = ExtractionResult {
        extracted_info: vec![
            ExtractedInfo {
                content: "Info 1".to_string(),
                source_depth: 1.0,
                certainty: 0.9,
            },
            ExtractedInfo {
                content: "Info 2".to_string(),
                source_depth: 2.0,
                certainty: 0.8,
            },
        ],
        quality_score: 0.85,
        extraction_type: ExtractionType::Liminal,
    };
    
    assert_eq!(result.extracted_info.len(), 2);
    assert_eq!(result.quality_score, 0.85);
    assert_eq!(result.extraction_type, ExtractionType::Liminal);
}

// ============================================================================
// PROBE RESULT TESTS
// ============================================================================

#[test]
fn test_probe_result_structure() {
    use beagle_void::CausalEffect;
    
    let result = ProbeResult {
        measurement: 0.75,
        uncertainty: 0.1,
        causal_effect: Some(CausalEffect {
            intervention: "test".to_string(),
            effect_size: 0.5,
            confidence: 0.8,
        }),
    };
    
    assert_eq!(result.measurement, 0.75);
    assert_eq!(result.uncertainty, 0.1);
    assert!(result.causal_effect.is_some());
}

#[test]
fn test_probe_result_without_causal() {
    let result = ProbeResult {
        measurement: 0.5,
        uncertainty: 0.2,
        causal_effect: None,
    };
    
    assert!(result.causal_effect.is_none());
}

// ============================================================================
// CONFIG TESTS
// ============================================================================

#[test]
fn test_void_config_default() {
    let config = VoidConfig::default();
    assert_eq!(config.max_depth, 10.0);
    assert_eq!(config.dissolution_rate, 0.1);
    assert_eq!(config.reintegration_rate, 0.2);
    assert_eq!(config.coherence_threshold, 0.3);
}

#[test]
fn test_extraction_config_default() {
    let config = ExtractionConfig::default();
    assert_eq!(config.sensitivity, 0.5);
    assert_eq!(config.min_quality, 0.3);
    assert_eq!(config.max_extractions, 100);
}

#[test]
fn test_probe_config_default() {
    let config = ProbeConfig::default();
    assert_eq!(config.probe_intensity, 0.5);
    assert_eq!(config.measurement_precision, 0.9);
    assert_eq!(config.intervention_strength, 0.3);
}

// ============================================================================
// SERIALIZATION TESTS
// ============================================================================

#[test]
fn test_void_state_serializable() {
    let state = VoidState::default();
    let serialized = serde_json::to_string(&state);
    assert!(serialized.is_ok());
    
    let deserialized: Result<VoidState, _> = serde_json::from_str(&serialized.unwrap());
    assert!(deserialized.is_ok());
    
    let restored = deserialized.unwrap();
    assert_eq!(restored.depth, state.depth);
    assert_eq!(restored.coherence, state.coherence);
}

#[test]
fn test_void_insight_serializable() {
    use beagle_void::InsightType;
    
    let insight = VoidInsight {
        insight_type: InsightType::Pattern,
        content: "Test".to_string(),
        confidence: 0.8,
        depth_found: 3.0,
        metadata: std::collections::HashMap::new(),
    };
    
    let serialized = serde_json::to_string(&insight);
    assert!(serialized.is_ok());
}

#[test]
fn test_extraction_result_serializable() {
    let result = ExtractionResult {
        extracted_info: vec![],
        quality_score: 0.8,
        extraction_type: ExtractionType::Vacuum,
    };
    
    let serialized = serde_json::to_string(&result);
    assert!(serialized.is_ok());
}

#[test]
fn test_probe_result_serializable() {
    let result = ProbeResult {
        measurement: 0.5,
        uncertainty: 0.1,
        causal_effect: None,
    };
    
    let serialized = serde_json::to_string(&result);
    assert!(serialized.is_ok());
}

#[test]
fn test_void_config_serializable() {
    let config = VoidConfig::default();
    let serialized = serde_json::to_string(&config);
    assert!(serialized.is_ok());
    
    let deserialized: Result<VoidConfig, _> = serde_json::from_str(&serialized.unwrap());
    assert!(deserialized.is_ok());
}

#[test]
fn test_probe_config_serializable() {
    let config = ProbeConfig::default();
    let serialized = serde_json::to_string(&config);
    assert!(serialized.is_ok());
}

#[test]
fn test_extraction_config_serializable() {
    let config = ExtractionConfig::default();
    let serialized = serde_json::to_string(&config);
    assert!(serialized.is_ok());
}

// ============================================================================
// VOID NAVIGATION RESULT TESTS
// ============================================================================

#[test]
fn test_void_navigation_result_structure() {
    let result = VoidNavigationResult {
        insights: vec![],
        final_state: VoidState::default(),
        max_depth_reached: 5.0,
        duration_ms: 100,
    };
    
    assert!(result.insights.is_empty());
    assert_eq!(result.max_depth_reached, 5.0);
    assert_eq!(result.duration_ms, 100);
}

#[test]
fn test_void_navigation_result_with_insights() {
    use beagle_void::InsightType;
    
    let result = VoidNavigationResult {
        insights: vec![
            VoidInsight {
                insight_type: InsightType::Pattern,
                content: "Insight 1".to_string(),
                confidence: 0.9,
                depth_found: 2.0,
                metadata: std::collections::HashMap::new(),
            },
        ],
        final_state: VoidState::default(),
        max_depth_reached: 3.0,
        duration_ms: 50,
    };
    
    assert_eq!(result.insights.len(), 1);
    assert_eq!(result.insights[0].content, "Insight 1");
}

// ============================================================================
// EDGE CASES AND ROBUSTNESS
// ============================================================================

#[test]
fn test_very_long_insight_content() {
    use beagle_void::InsightType;
    
    let long_content = "a".repeat(10_000);
    let insight = VoidInsight {
        insight_type: InsightType::Pattern,
        content: long_content.clone(),
        confidence: 0.5,
        depth_found: 1.0,
        metadata: std::collections::HashMap::new(),
    };
    assert_eq!(insight.content.len(), 10_000);
    assert_eq!(insight.content, long_content);
}

#[test]
fn test_empty_insight_content() {
    use beagle_void::InsightType;
    
    let insight = VoidInsight {
        insight_type: InsightType::Pattern,
        content: String::new(),
        confidence: 0.5,
        depth_found: 1.0,
        metadata: std::collections::HashMap::new(),
    };
    assert!(insight.content.is_empty());
}

#[test]
fn test_unicode_in_insight_content() {
    use beagle_void::InsightType;
    
    let insight = VoidInsight {
        insight_type: InsightType::Pattern,
        content: "Vazio ontologico absoluto no universo 🌌".to_string(),
        confidence: 0.5,
        depth_found: 1.0,
        metadata: std::collections::HashMap::new(),
    };
    assert!(insight.content.contains("ontologico"));
    assert!(insight.content.contains("🌌"));
}

#[test]
fn test_special_chars_in_extraction_content() {
    use beagle_void::ExtractedInfo;
    
    let info = ExtractedInfo {
        content: "Content with !@#$%^&*() symbols".to_string(),
        source_depth: 0.5,
        certainty: 0.8,
    };
    assert!(info.content.contains("!@#$%^&*()"));
}

#[test]
fn test_extreme_depth_values() {
    let depths = [0.0, 0.0001, 1.0, 10.0, 100.0, 1000.0];
    for depth in depths.iter() {
        let state = VoidState {
            depth: *depth,
            coherence: 0.5,
            entropy: 0.5,
            phase: VoidPhase::InVoid,
        };
        assert_eq!(state.depth, *depth);
    }
}

#[test]
fn test_extreme_coherence_values() {
    let coherences = [0.0, 0.0001, 0.5, 0.9999, 1.0];
    for coherence in coherences.iter() {
        let state = VoidState {
            depth: 1.0,
            coherence: *coherence,
            entropy: 0.5,
            phase: VoidPhase::InVoid,
        };
        assert!((state.coherence - *coherence).abs() < f64::EPSILON);
    }
}

#[test]
fn test_extreme_entropy_values() {
    let entropies = [0.0, 0.0001, 0.5, 0.9999, 1.0];
    for entropy in entropies.iter() {
        let state = VoidState {
            depth: 1.0,
            coherence: 0.5,
            entropy: *entropy,
            phase: VoidPhase::InVoid,
        };
        assert!((state.entropy - *entropy).abs() < f64::EPSILON);
    }
}

#[tokio::test]
async fn test_navigation_zero_depth() {
    let navigator = VoidNavigator::new(VoidConfig::default());
    let result = navigator.navigate(0.0).await;
    assert!(result.is_ok());
    
    let nav_result = result.unwrap();
    assert_eq!(nav_result.max_depth_reached, 0.0);
}

#[tokio::test]
async fn test_extraction_zero_depth() {
    let engine = ExtractionEngine::new(ExtractionConfig::default());
    let state = VoidState {
        depth: 0.0,
        coherence: 1.0,
        entropy: 0.0,
        phase: VoidPhase::Grounded,
    };
    
    let result = engine.extract(&state, ExtractionType::Vacuum).await;
    assert!(result.is_ok());
    
    let extraction = result.unwrap();
    assert!(extraction.extracted_info.is_empty()); // No depth = no extractions
}

#[tokio::test]
async fn test_probe_zero_depth() {
    let probe = VoidProbe::new(ProbeConfig::default());
    let state = VoidState {
        depth: 0.0,
        coherence: 1.0,
        entropy: 0.0,
        phase: VoidPhase::Grounded,
    };
    
    let result = probe.probe(&state).await;
    assert!(result.is_ok());
    
    let probe_result = result.unwrap();
    // With zero depth, measurement should be close to 0 (with some noise)
    // base_measurement = depth * coherence = 0 * 1 = 0
    // noise is small, so measurement should be close to 0
    assert!(probe_result.measurement.abs() < 0.5);
}

// ============================================================================
// API CONTRACT TESTS
// ============================================================================

#[test]
fn test_module_exports() {
    // Verify all main types are exported
    let _config = VoidConfig::default();
    let _extract_config = ExtractionConfig::default();
    let _probe_config = ProbeConfig::default();
    let _state = VoidState::default();
    let _phase = VoidPhase::Grounded;
}

#[test]
fn test_void_concepts_naming() {
    let navigator_type = std::any::type_name::<VoidNavigator>();
    let extraction_type = std::any::type_name::<ExtractionEngine>();
    let probe_type = std::any::type_name::<VoidProbe>();

    assert!(navigator_type.contains("VoidNavigator"));
    assert!(extraction_type.contains("ExtractionEngine"));
    assert!(probe_type.contains("VoidProbe"));
}

#[tokio::test]
async fn test_full_void_workflow() {
    // Create components
    let navigator = VoidNavigator::new(VoidConfig::default());
    let extractor = ExtractionEngine::new(ExtractionConfig::default());
    let probe = VoidProbe::new(ProbeConfig::default());
    
    // Navigate into void
    let nav_result = navigator.navigate(3.0).await.unwrap();
    assert!(nav_result.max_depth_reached > 0.0);
    
    // Extract information from final state
    let extraction = extractor.extract(&nav_result.final_state, ExtractionType::Vacuum).await.unwrap();
    assert!(extraction.quality_score >= 0.0);
    
    // Probe the state
    let probe_result = probe.probe(&nav_result.final_state).await.unwrap();
    // Measurement can have noise, just verify it's a valid float
    assert!(!probe_result.measurement.is_nan());
    assert!(!probe_result.measurement.is_infinite());
}

#[tokio::test]
async fn test_multiple_navigations() {
    let navigator = VoidNavigator::new(VoidConfig::default());
    
    for i in 1..=5 {
        let target_depth = i as f64;
        let result = navigator.navigate(target_depth).await.unwrap();
        assert!(result.max_depth_reached >= target_depth - 0.1); // Allow small floating point variance
    }
}

#[tokio::test]
async fn test_multiple_extractions_same_state() {
    let engine = ExtractionEngine::new(ExtractionConfig::default());
    let state = VoidState {
        depth: 5.0,
        coherence: 0.8,
        entropy: 0.2,
        phase: VoidPhase::InVoid,
    };
    
    for _ in 0..10 {
        let result = engine.extract(&state, ExtractionType::Vacuum).await;
        assert!(result.is_ok());
    }
}

#[tokio::test]
async fn test_multiple_probes_same_state() {
    let probe = VoidProbe::new(ProbeConfig::default());
    let state = VoidState {
        depth: 3.0,
        coherence: 0.7,
        entropy: 0.3,
        phase: VoidPhase::InVoid,
    };
    
    for _ in 0..10 {
        let result = probe.probe(&state).await;
        assert!(result.is_ok());
    }
    
    // Check that measurements are tracked
    let probe_state = probe.get_state().await;
    assert_eq!(probe_state.measurements, 10);
}
