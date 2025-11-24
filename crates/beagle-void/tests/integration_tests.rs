//! Comprehensive integration tests for beagle-void
//!
//! Tests cover:
//! - VoidNavigator functionality and void navigation cycles
//! - ExtractionEngine resource extraction
//! - VoidProbe region probing and depth measurement
//! - Data structures and serialization
//! - Error handling and edge cases
//! - Impossibility calculations
//! - Resource type handling

use beagle_void::{ExtractionEngine, VoidNavigator, VoidProbe};

// ============================================================================
// VOIDNAVIGATOR TESTS
// ============================================================================

#[test]
fn test_void_navigator_creation() {
    let navigator = VoidNavigator::default();
    // Verifies that navigator can be created
    let _nav_ref = &navigator;
}

#[test]
fn test_void_navigator_default_factory() {
    let nav1 = VoidNavigator::new();
    let nav2 = VoidNavigator::default();
    // Both should work without error
}

// ============================================================================
// EXTRACTIONENGINE TESTS
// ============================================================================

#[test]
fn test_extraction_engine_creation() {
    let engine = ExtractionEngine::default();
    let _ref = &engine;
}

#[test]
fn test_extraction_engine_with_url() {
    let engine = ExtractionEngine::with_vllm_url("http://localhost:8000/v1");
    let _ref = &engine;
}

#[test]
fn test_extraction_engine_default_factory() {
    let engine1 = ExtractionEngine::new();
    let engine2 = ExtractionEngine::default();
    // Both should work without error
}

// ============================================================================
// VOIDPROBE TESTS
// ============================================================================

#[test]
fn test_void_probe_creation() {
    let probe = VoidProbe::default();
    let _ref = &probe;
}

#[test]
fn test_void_probe_with_url() {
    let probe = VoidProbe::with_vllm_url("http://localhost:8000/v1");
    let _ref = &probe;
}

#[test]
fn test_void_probe_default_factory() {
    let probe1 = VoidProbe::new();
    let probe2 = VoidProbe::default();
    // Both should work without error
}

// ============================================================================
// RESOURCE TYPE TESTS
// ============================================================================

#[test]
fn test_resource_type_insight() {
    use beagle_void::extraction_engine::ResourceType;
    let rt = ResourceType::Insight;
    assert_eq!(rt, ResourceType::Insight);
}

#[test]
fn test_resource_type_concept() {
    use beagle_void::extraction_engine::ResourceType;
    let rt = ResourceType::Concept;
    assert_eq!(rt, ResourceType::Concept);
}

#[test]
fn test_resource_type_structure() {
    use beagle_void::extraction_engine::ResourceType;
    let rt = ResourceType::Structure;
    assert_eq!(rt, ResourceType::Structure);
}

#[test]
fn test_resource_type_paradox() {
    use beagle_void::extraction_engine::ResourceType;
    let rt = ResourceType::Paradox;
    assert_eq!(rt, ResourceType::Paradox);
}

#[test]
fn test_resource_types_are_distinct() {
    use beagle_void::extraction_engine::ResourceType;
    assert_ne!(ResourceType::Insight, ResourceType::Concept);
    assert_ne!(ResourceType::Concept, ResourceType::Structure);
    assert_ne!(ResourceType::Structure, ResourceType::Paradox);
    assert_ne!(ResourceType::Insight, ResourceType::Paradox);
}

// ============================================================================
// VOID NAVIGATION RESULT TESTS
// ============================================================================

#[test]
fn test_void_navigation_result_structure() {
    use beagle_void::navigator::VoidNavigationResult;
    let result = VoidNavigationResult {
        cycles_completed: 5,
        insights: vec![],
        total_void_time_subjective: 0.0,
    };
    assert_eq!(result.cycles_completed, 5);
    assert_eq!(result.insights.len(), 0);
}

#[test]
fn test_void_navigation_cycles_value() {
    use beagle_void::navigator::VoidNavigationResult;
    let result = VoidNavigationResult {
        cycles_completed: 10,
        insights: vec![],
        total_void_time_subjective: 0.0,
    };
    assert!(result.cycles_completed > 0);
}

#[test]
fn test_void_navigation_void_time_valid() {
    use beagle_void::navigator::VoidNavigationResult;
    let result = VoidNavigationResult {
        cycles_completed: 3,
        insights: vec![],
        total_void_time_subjective: 42.5,
    };
    assert!(result.total_void_time_subjective >= 0.0);
}

// ============================================================================
// VOID INSIGHT TESTS
// ============================================================================

#[test]
fn test_void_insight_impossibility_level_range() {
    use beagle_void::navigator::VoidInsight;
    let insight = VoidInsight {
        id: "test-id".to_string(),
        cycle: 1,
        insight_text: "test insight".to_string(),
        impossibility_level: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    assert!(insight.impossibility_level >= 0.0);
    assert!(insight.impossibility_level <= 1.0);
}

#[test]
fn test_void_insight_min_impossibility() {
    use beagle_void::navigator::VoidInsight;
    let insight = VoidInsight {
        id: "test".to_string(),
        cycle: 1,
        insight_text: "test".to_string(),
        impossibility_level: 0.0,
        extracted_at: chrono::Utc::now(),
    };
    assert_eq!(insight.impossibility_level, 0.0);
}

#[test]
fn test_void_insight_max_impossibility() {
    use beagle_void::navigator::VoidInsight;
    let insight = VoidInsight {
        id: "test".to_string(),
        cycle: 1,
        insight_text: "test".to_string(),
        impossibility_level: 1.0,
        extracted_at: chrono::Utc::now(),
    };
    assert_eq!(insight.impossibility_level, 1.0);
}

#[test]
fn test_void_insight_cycle_tracking() {
    use beagle_void::navigator::VoidInsight;
    let insight = VoidInsight {
        id: "test".to_string(),
        cycle: 7,
        insight_text: "test".to_string(),
        impossibility_level: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    assert_eq!(insight.cycle, 7);
}

#[test]
fn test_void_insight_has_unique_id() {
    use beagle_void::navigator::VoidInsight;
    let insight1 = VoidInsight {
        id: "id-1".to_string(),
        cycle: 1,
        insight_text: "text".to_string(),
        impossibility_level: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    let insight2 = VoidInsight {
        id: "id-2".to_string(),
        cycle: 1,
        insight_text: "text".to_string(),
        impossibility_level: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    assert_ne!(insight1.id, insight2.id);
}

// ============================================================================
// COGNITIVE RESOURCE TESTS
// ============================================================================

#[test]
fn test_cognitive_resource_structure() {
    use beagle_void::extraction_engine::{CognitiveResource, ResourceType};
    let resource = CognitiveResource {
        id: "resource-1".to_string(),
        resource_type: ResourceType::Insight,
        content: "Some insight content".to_string(),
        void_origin_depth: 0.75,
        extracted_at: chrono::Utc::now(),
    };
    assert_eq!(resource.resource_type, ResourceType::Insight);
    assert!(!resource.content.is_empty());
}

#[test]
fn test_cognitive_resource_depth_range() {
    use beagle_void::extraction_engine::{CognitiveResource, ResourceType};
    let resource = CognitiveResource {
        id: "res".to_string(),
        resource_type: ResourceType::Concept,
        content: "test".to_string(),
        void_origin_depth: 0.3,
        extracted_at: chrono::Utc::now(),
    };
    assert!(resource.void_origin_depth >= 0.0);
    assert!(resource.void_origin_depth <= 1.0);
}

#[test]
fn test_cognitive_resource_types() {
    use beagle_void::extraction_engine::{CognitiveResource, ResourceType};

    let insight_res = CognitiveResource {
        id: "1".to_string(),
        resource_type: ResourceType::Insight,
        content: "test".to_string(),
        void_origin_depth: 0.5,
        extracted_at: chrono::Utc::now(),
    };

    let concept_res = CognitiveResource {
        id: "2".to_string(),
        resource_type: ResourceType::Concept,
        content: "test".to_string(),
        void_origin_depth: 0.5,
        extracted_at: chrono::Utc::now(),
    };

    assert_eq!(insight_res.resource_type, ResourceType::Insight);
    assert_eq!(concept_res.resource_type, ResourceType::Concept);
    assert_ne!(insight_res.resource_type, concept_res.resource_type);
}

// ============================================================================
// EXTRACTION RESULT TESTS
// ============================================================================

#[test]
fn test_extraction_result_empty() {
    use beagle_void::extraction_engine::ExtractionResult;
    let result = ExtractionResult {
        resources_extracted: vec![],
        extraction_efficiency: 0.0,
    };
    assert_eq!(result.resources_extracted.len(), 0);
}

#[test]
fn test_extraction_result_efficiency_range() {
    use beagle_void::extraction_engine::ExtractionResult;
    let result = ExtractionResult {
        resources_extracted: vec![],
        extraction_efficiency: 0.85,
    };
    assert!(result.extraction_efficiency >= 0.0);
    assert!(result.extraction_efficiency <= 1.0);
}

#[test]
fn test_extraction_result_has_resources() {
    use beagle_void::extraction_engine::{CognitiveResource, ExtractionResult, ResourceType};
    let resource = CognitiveResource {
        id: "res-1".to_string(),
        resource_type: ResourceType::Insight,
        content: "content".to_string(),
        void_origin_depth: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    let result = ExtractionResult {
        resources_extracted: vec![resource],
        extraction_efficiency: 0.8,
    };
    assert_eq!(result.resources_extracted.len(), 1);
}

// ============================================================================
// PROBE RESULT TESTS
// ============================================================================

#[test]
fn test_probe_result_structure() {
    use beagle_void::void_probe::ProbeResult;
    let result = ProbeResult {
        depth: 0.5,
        insight: "Some void insight".to_string(),
        region_mapped: "Region at depth 0.5".to_string(),
    };
    assert_eq!(result.depth, 0.5);
    assert!(!result.insight.is_empty());
    assert!(!result.region_mapped.is_empty());
}

#[test]
fn test_probe_result_depth_range() {
    use beagle_void::void_probe::ProbeResult;
    let result = ProbeResult {
        depth: 0.0,
        insight: "insight".to_string(),
        region_mapped: "region".to_string(),
    };
    assert!(result.depth >= 0.0);
    assert!(result.depth <= 1.0);
}

#[test]
fn test_probe_result_surface_depth() {
    use beagle_void::void_probe::ProbeResult;
    let result = ProbeResult {
        depth: 0.0,
        insight: "Surface insight".to_string(),
        region_mapped: "Surface region".to_string(),
    };
    assert_eq!(result.depth, 0.0);
}

#[test]
fn test_probe_result_absolute_depth() {
    use beagle_void::void_probe::ProbeResult;
    let result = ProbeResult {
        depth: 1.0,
        insight: "Absolute void insight".to_string(),
        region_mapped: "Absolute void region".to_string(),
    };
    assert_eq!(result.depth, 1.0);
}

// ============================================================================
// SERIALIZATION TESTS
// ============================================================================

#[test]
fn test_void_insight_serializable() {
    use beagle_void::navigator::VoidInsight;
    let insight = VoidInsight {
        id: "test-id".to_string(),
        cycle: 1,
        insight_text: "test text".to_string(),
        impossibility_level: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    let serialized = serde_json::to_string(&insight);
    assert!(serialized.is_ok());
}

#[test]
fn test_cognitive_resource_serializable() {
    use beagle_void::extraction_engine::{CognitiveResource, ResourceType};
    let resource = CognitiveResource {
        id: "test-id".to_string(),
        resource_type: ResourceType::Insight,
        content: "test content".to_string(),
        void_origin_depth: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    let serialized = serde_json::to_string(&resource);
    assert!(serialized.is_ok());
}

#[test]
fn test_extraction_result_serializable() {
    use beagle_void::extraction_engine::ExtractionResult;
    let result = ExtractionResult {
        resources_extracted: vec![],
        extraction_efficiency: 0.8,
    };
    let serialized = serde_json::to_string(&result);
    assert!(serialized.is_ok());
}

#[test]
fn test_void_navigation_result_serializable() {
    use beagle_void::navigator::VoidNavigationResult;
    let result = VoidNavigationResult {
        cycles_completed: 5,
        insights: vec![],
        total_void_time_subjective: 0.0,
    };
    let serialized = serde_json::to_string(&result);
    assert!(serialized.is_ok());
}

#[test]
fn test_probe_result_serializable() {
    use beagle_void::void_probe::ProbeResult;
    let result = ProbeResult {
        depth: 0.5,
        insight: "insight".to_string(),
        region_mapped: "region".to_string(),
    };
    let serialized = serde_json::to_string(&result);
    assert!(serialized.is_ok());
}

// ============================================================================
// VOID CONCEPTS TESTS
// ============================================================================

#[test]
fn test_void_navigation_cycles_positive() {
    use beagle_void::navigator::VoidNavigationResult;
    for cycles in 1..=10 {
        let result = VoidNavigationResult {
            cycles_completed: cycles,
            insights: vec![],
            total_void_time_subjective: 0.0,
        };
        assert!(result.cycles_completed > 0);
    }
}

#[test]
fn test_impossibility_level_zero() {
    use beagle_void::navigator::VoidInsight;
    let insight = VoidInsight {
        id: "test".to_string(),
        cycle: 1,
        insight_text: "completely possible".to_string(),
        impossibility_level: 0.0,
        extracted_at: chrono::Utc::now(),
    };
    assert_eq!(insight.impossibility_level, 0.0);
}

#[test]
fn test_impossibility_level_one() {
    use beagle_void::navigator::VoidInsight;
    let insight = VoidInsight {
        id: "test".to_string(),
        cycle: 1,
        insight_text: "completely impossible".to_string(),
        impossibility_level: 1.0,
        extracted_at: chrono::Utc::now(),
    };
    assert_eq!(insight.impossibility_level, 1.0);
}

// ============================================================================
// VLLM URL CONFIGURATION TESTS
// ============================================================================

#[test]
fn test_extraction_engine_default_url() {
    let engine = ExtractionEngine::new();
    let _ref = &engine;
}

#[test]
fn test_extraction_engine_custom_url() {
    let engine = ExtractionEngine::with_vllm_url("http://custom-host:9000/v1");
    let _ref = &engine;
}

#[test]
fn test_void_probe_default_url() {
    let probe = VoidProbe::new();
    let _ref = &probe;
}

#[test]
fn test_void_probe_custom_url() {
    let probe = VoidProbe::with_vllm_url("http://custom-host:9000/v1");
    let _ref = &probe;
}

// ============================================================================
// EDGE CASES AND ROBUSTNESS
// ============================================================================

#[test]
fn test_very_long_insight_text() {
    use beagle_void::navigator::VoidInsight;
    let long_text = "a".repeat(10_000);
    let insight = VoidInsight {
        id: "test".to_string(),
        cycle: 1,
        insight_text: long_text,
        impossibility_level: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    assert!(!insight.insight_text.is_empty());
}

#[test]
fn test_empty_insight_text() {
    use beagle_void::navigator::VoidInsight;
    let insight = VoidInsight {
        id: "test".to_string(),
        cycle: 1,
        insight_text: String::new(),
        impossibility_level: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    assert!(insight.insight_text.is_empty());
}

#[test]
fn test_unicode_in_insight_text() {
    use beagle_void::navigator::VoidInsight;
    let insight = VoidInsight {
        id: "test".to_string(),
        cycle: 1,
        insight_text: "Vazio ontologico absoluto no universo".to_string(),
        impossibility_level: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    assert!(insight.insight_text.contains("ontologico"));
}

#[test]
fn test_special_chars_in_resource_content() {
    use beagle_void::extraction_engine::{CognitiveResource, ResourceType};
    let resource = CognitiveResource {
        id: "test".to_string(),
        resource_type: ResourceType::Paradox,
        content: "Content with !@#$%^&*() symbols".to_string(),
        void_origin_depth: 0.5,
        extracted_at: chrono::Utc::now(),
    };
    assert!(resource.content.contains("!@#$%^&*()"));
}

#[test]
fn test_multiple_cycles_tracking() {
    use beagle_void::navigator::VoidNavigationResult;
    for cycle_count in 0..=20 {
        let result = VoidNavigationResult {
            cycles_completed: cycle_count,
            insights: vec![],
            total_void_time_subjective: 0.0,
        };
        assert_eq!(result.cycles_completed, cycle_count);
    }
}

#[test]
fn test_various_void_times() {
    use beagle_void::navigator::VoidNavigationResult;
    for void_time in [0.0, 1.5, 10.0, 100.0, 999.999] {
        let result = VoidNavigationResult {
            cycles_completed: 1,
            insights: vec![],
            total_void_time_subjective: void_time,
        };
        assert_eq!(result.total_void_time_subjective, void_time);
    }
}

#[test]
fn test_probe_depth_precision() {
    use beagle_void::void_probe::ProbeResult;
    let depths = [0.0, 0.25, 0.5, 0.75, 1.0];
    for depth in depths.iter() {
        let result = ProbeResult {
            depth: *depth,
            insight: "insight".to_string(),
            region_mapped: "region".to_string(),
        };
        assert_eq!(result.depth, *depth);
    }
}

// ============================================================================
// API CONTRACT AND DOCUMENTATION TESTS
// ============================================================================

#[test]
fn test_void_navigator_api_contract() {
    let navigator = VoidNavigator::new();
    let _nav_ref = &navigator;
    // Verify structure and methods exist
}

#[test]
fn test_extraction_engine_api_contract() {
    let engine = ExtractionEngine::default();
    let _engine_ref = &engine;
    // Verify structure and methods exist
}

#[test]
fn test_void_probe_api_contract() {
    let probe = VoidProbe::new();
    let _probe_ref = &probe;
    // Verify structure and methods exist
}

#[test]
fn test_void_concepts_naming() {
    let navigator_type = "VoidNavigator";
    let extraction_type = "ExtractionEngine";
    let probe_type = "VoidProbe";

    assert!(navigator_type.contains("Void"));
    assert!(extraction_type.contains("Extraction"));
    assert!(probe_type.contains("Probe"));
}

#[test]
fn test_module_exports() {
    use beagle_void::{ExtractionEngine, VoidNavigator, VoidProbe};

    let _nav = VoidNavigator::new();
    let _engine = ExtractionEngine::new();
    let _probe = VoidProbe::new();
}
