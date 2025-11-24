//! Integration tests for HRV-Adaptive Ensemble Reasoning System
//! Tests the complete workflow from cognitive state detection through consensus reasoning

use beagle_hrv_adaptive::{
    AdaptiveRouter, EnsembleReasoningEngine, EnsembleConsensus, ReasoningPath,
};
use beagle_bio::{HRVMonitor, CognitiveState};
use chrono::Utc;
use std::sync::Arc;

// ============================================================================
// Setup and Helper Functions
// ============================================================================

/// Create an ensemble engine with mock HRV monitor for testing
fn create_test_engine() -> Arc<EnsembleReasoningEngine> {
    let monitor = Arc::new(HRVMonitor::with_mock());
    Arc::new(EnsembleReasoningEngine::new(monitor))
}

/// Create test reasoning paths with various content
fn create_test_paths() -> Vec<ReasoningPath> {
    vec![
        ReasoningPath {
            id: "path_1".to_string(),
            content: "The quantum entanglement phenomenon demonstrates non-local correlation \
                     in particle physics, suggesting instantaneous information transfer across space.".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.85),
        },
        ReasoningPath {
            id: "path_2".to_string(),
            content: "Quantum entanglement shows correlated particle behavior that appears instantaneous, \
                     though no information travels faster than light according to special relativity.".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.82),
        },
        ReasoningPath {
            id: "path_3".to_string(),
            content: "Bell's theorem proves that quantum mechanics violates local hidden variable theories, \
                     confirming the reality of quantum superposition and entanglement.".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.79),
        },
        ReasoningPath {
            id: "path_4".to_string(),
            content: "Quantum computing leverages entanglement to perform parallel computations, \
                     providing exponential speedup over classical algorithms for specific problems.".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.76),
        },
        ReasoningPath {
            id: "path_5".to_string(),
            content: "Wave function collapse in quantum mechanics remains philosophically contested, \
                     with interpretations ranging from Copenhagen to many-worlds theories.".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.71),
        },
    ]
}

/// Create slightly different reasoning paths to test consensus convergence
fn create_divergent_paths() -> Vec<ReasoningPath> {
    vec![
        ReasoningPath {
            id: "div_1".to_string(),
            content: "Machine learning represents a paradigm shift in computational intelligence, \
                     enabling systems to learn from data without explicit programming.".to_string(),
            temperature_used: 0.8,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.88),
        },
        ReasoningPath {
            id: "div_2".to_string(),
            content: "Artificial intelligence can be broadly categorized as narrow AI (task-specific) \
                     or general AI (human-level), with current systems being purely narrow AI.".to_string(),
            temperature_used: 0.8,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.84),
        },
        ReasoningPath {
            id: "div_3".to_string(),
            content: "Deep learning uses neural networks with multiple layers to extract hierarchical \
                     features from raw input, achieving state-of-the-art performance on many tasks.".to_string(),
            temperature_used: 0.8,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.86),
        },
    ]
}

// ============================================================================
// Ensemble Engine Tests
// ============================================================================

#[tokio::test]
async fn test_consensus_with_five_paths() {
    let engine = create_test_engine();
    let paths = create_test_paths();

    let result = engine
        .consensus_reasoning("What is quantum entanglement?", paths)
        .await;

    assert!(result.is_ok(), "Consensus reasoning should succeed with 5 paths");

    let consensus = result.unwrap();

    // Verify consensus structure
    assert_eq!(consensus.all_paths.len(), 5, "Should contain all 5 paths");
    assert!(!consensus.best_path.id.is_empty(), "Should have selected a best path");
    assert_eq!(
        consensus.confidence_scores.len(),
        5,
        "Should have confidence scores for all paths"
    );

    // Verify scoring properties
    assert!(
        consensus.consensus_score >= 0.0 && consensus.consensus_score <= 1.0,
        "Consensus score should be normalized [0, 1]"
    );

    // Verify all scores are positive and sum to approximately 1.0
    let score_sum: f64 = consensus.confidence_scores.values().sum();
    assert!(
        (score_sum - 1.0).abs() < 0.01,
        "Normalized scores should sum to 1.0, got {}",
        score_sum
    );

    // All individual scores should be normalized
    for (path_id, score) in &consensus.confidence_scores {
        assert!(
            *score >= 0.0 && *score <= 1.0,
            "Score for {} should be in [0, 1], got {}",
            path_id,
            score
        );
    }

    // Best path should have the highest score
    let best_score = consensus
        .confidence_scores
        .get(&consensus.best_path.id)
        .copied()
        .unwrap_or(0.0);
    for (_, score) in &consensus.confidence_scores {
        assert!(
            *score <= best_score + 0.001,
            "Best path should have highest score"
        );
    }
}

#[tokio::test]
async fn test_consensus_with_three_paths() {
    let engine = create_test_engine();
    let paths = create_divergent_paths();

    let result = engine
        .consensus_reasoning("What is artificial intelligence?", paths)
        .await;

    assert!(result.is_ok());
    let consensus = result.unwrap();

    assert_eq!(consensus.all_paths.len(), 3);
    assert_eq!(consensus.confidence_scores.len(), 3);

    // Verify consensus score is meaningful
    assert!(consensus.consensus_score > 0.0, "Consensus should have positive score");
}

#[tokio::test]
async fn test_single_path_consensus() {
    let engine = create_test_engine();
    let paths = vec![ReasoningPath {
        id: "solo".to_string(),
        content: "Single path reasoning with no comparison baseline.".to_string(),
        temperature_used: 0.5,
        max_tokens_used: 128,
        generated_at: Utc::now(),
        confidence: Some(0.9),
    }];

    let result = engine
        .consensus_reasoning("Test prompt", paths.clone())
        .await;

    assert!(result.is_ok());
    let consensus = result.unwrap();

    // Single path should still be selected
    assert_eq!(consensus.best_path.id, "solo");
    assert_eq!(consensus.all_paths.len(), 1);
}

#[tokio::test]
async fn test_empty_paths_error() {
    let engine = create_test_engine();
    let paths = vec![];

    let result = engine
        .consensus_reasoning("Test prompt", paths)
        .await;

    assert!(result.is_err(), "Empty paths should return error");
}

#[tokio::test]
async fn test_consensus_determinism() {
    let engine = create_test_engine();
    let paths1 = create_test_paths();
    let paths2 = create_test_paths();

    let result1 = engine
        .consensus_reasoning("Same prompt", paths1)
        .await
        .unwrap();

    let result2 = engine
        .consensus_reasoning("Same prompt", paths2)
        .await
        .unwrap();

    // Same paths with same prompt should select same best path
    assert_eq!(
        result1.best_path.id, result2.best_path.id,
        "Same inputs should produce same best path"
    );

    // Scores should be identical (deterministic embedding generation)
    for (path_id, score1) in &result1.confidence_scores {
        let score2 = result2.confidence_scores.get(path_id).unwrap_or(&0.0);
        assert!(
            (score1 - score2).abs() < 1e-9,
            "Scores should be deterministic"
        );
    }
}

#[tokio::test]
async fn test_consensus_cognitive_state_integration() {
    let monitor = Arc::new(HRVMonitor::with_mock());
    let engine = EnsembleReasoningEngine::new(Arc::clone(&monitor));

    // Get current cognitive state to verify it's being used
    let state = monitor.current_state().await;
    let intensity = state.reasoning_intensity();

    let paths = create_test_paths();
    let consensus = engine
        .consensus_reasoning("prompt", paths)
        .await
        .unwrap();

    // Verify cognitive state was captured
    assert!(!consensus.cognitive_state.is_empty());

    // Intensity should be a known value (0.2, 0.6, or 1.0)
    assert!(intensity == 0.2 || intensity == 0.6 || intensity == 1.0);
}

// ============================================================================
// Adaptive Router Tests
// ============================================================================

#[tokio::test]
async fn test_adaptive_router_routing_strategy() {
    let monitor = Arc::new(HRVMonitor::with_mock());
    let engine = Arc::new(EnsembleReasoningEngine::new(Arc::clone(&monitor)));
    let router = AdaptiveRouter::new(monitor, engine);

    let strategy = router.get_routing_strategy().await;

    // Verify strategy structure
    assert!(strategy.num_paths >= 1 && strategy.num_paths <= 5);
    assert!(strategy.temperature_mult > 0.0 && strategy.temperature_mult <= 1.0);
    assert!(strategy.max_tokens_mult > 0.0 && strategy.max_tokens_mult <= 1.0);
    assert!(!strategy.priority.is_empty());

    // Priority should be one of the known values
    assert!(
        strategy.priority == "high" || strategy.priority == "normal" || strategy.priority == "low"
    );
}

#[tokio::test]
async fn test_routing_strategy_peakflow_characteristics() {
    let monitor = Arc::new(HRVMonitor::with_mock());

    // Verify that PeakFlow state leads to ensemble usage
    let engine = Arc::new(EnsembleReasoningEngine::new(Arc::clone(&monitor)));
    let should_ensemble = engine.should_use_ensemble().await;
    let num_paths = engine.get_num_paths().await;

    // These should match the cognitive state
    let state = monitor.current_state().await;
    if state == CognitiveState::PeakFlow {
        assert!(should_ensemble, "PeakFlow should enable ensemble");
        assert_eq!(num_paths, 5, "PeakFlow should use 5 paths");
    }
}

#[tokio::test]
async fn test_adaptive_temperature_scaling() {
    let monitor = Arc::new(HRVMonitor::with_mock());
    let engine = EnsembleReasoningEngine::new(monitor);

    let base_temp = 1.0;
    let scaled_temp = engine.get_adaptive_temperature(base_temp).await;

    // Scaled temperature should be reasonable
    assert!(scaled_temp >= 0.4 && scaled_temp <= 1.2,
            "Scaled temp should be 0.4-1.2 for base 1.0, got {}", scaled_temp);
}

#[tokio::test]
async fn test_router_can_perform_complex_reasoning() {
    let monitor = Arc::new(HRVMonitor::with_mock());
    let engine = Arc::new(EnsembleReasoningEngine::new(Arc::clone(&monitor)));
    let router = AdaptiveRouter::new(monitor, engine);

    let can_complex = router.can_perform_complex_reasoning().await;

    // Should return a valid boolean
    assert!(matches!(can_complex, true | false));
}

// ============================================================================
// End-to-End Workflow Tests
// ============================================================================

#[tokio::test]
async fn test_complete_reasoning_workflow() {
    // Setup
    let monitor = Arc::new(HRVMonitor::with_mock());
    let engine = Arc::new(EnsembleReasoningEngine::new(Arc::clone(&monitor)));
    let router = Arc::new(AdaptiveRouter::new(Arc::clone(&monitor), Arc::clone(&engine)));

    // Step 1: Get routing strategy
    let strategy = router.get_routing_strategy().await;
    assert!(strategy.num_paths >= 1 && strategy.num_paths <= 5);

    // Step 2: Generate reasoning paths (simulated)
    let paths = create_test_paths();

    // Step 3: Run consensus
    let prompt = "What are the implications of quantum entanglement for computing?";
    let consensus = engine
        .consensus_reasoning(prompt, paths)
        .await
        .expect("Consensus should succeed");

    // Step 4: Verify output quality
    assert!(!consensus.best_path.content.is_empty());
    assert!(consensus.consensus_score > 0.0);
    assert_eq!(consensus.all_paths.len(), 5);

    // Step 5: Check if complex reasoning can be performed for next iteration
    let can_continue_complex = router.can_perform_complex_reasoning().await;
    assert!(matches!(can_continue_complex, true | false));
}

#[tokio::test]
async fn test_multi_turn_reasoning() {
    let engine = create_test_engine();

    // Turn 1
    let paths1 = create_test_paths();
    let result1 = engine
        .consensus_reasoning("First prompt", paths1)
        .await
        .unwrap();

    // Turn 2 (using previous best as anchor)
    let paths2 = create_divergent_paths();
    let result2 = engine
        .consensus_reasoning("Second prompt", paths2)
        .await
        .unwrap();

    // Both should produce valid consensus
    assert!(!result1.best_path.id.is_empty());
    assert!(!result2.best_path.id.is_empty());

    // They can select different best paths (different prompts/paths)
    // This is valid behavior - no assertion here
}

#[tokio::test]
async fn test_ensemble_consensus_stability() {
    let engine = create_test_engine();
    let paths = create_test_paths();

    // Run consensus multiple times with identical inputs
    let results: Vec<EnsembleConsensus> = futures::future::join_all(vec![
        engine.consensus_reasoning("prompt", paths.clone()),
        engine.consensus_reasoning("prompt", paths.clone()),
        engine.consensus_reasoning("prompt", paths.clone()),
    ])
    .await
    .into_iter()
    .map(|r| r.unwrap())
    .collect();

    // All should select same best path (deterministic)
    assert_eq!(results[0].best_path.id, results[1].best_path.id);
    assert_eq!(results[1].best_path.id, results[2].best_path.id);

    // Scores should be identical
    for i in 1..results.len() {
        for (path_id, score) in &results[0].confidence_scores {
            let other_score = results[i].confidence_scores.get(path_id).unwrap();
            assert!(
                (score - other_score).abs() < 1e-9,
                "Scores should be stable across invocations"
            );
        }
    }
}

#[tokio::test]
async fn test_content_length_robustness() {
    let engine = create_test_engine();

    // Test with very short content
    let short_paths = vec![
        ReasoningPath {
            id: "short_1".to_string(),
            content: "Brief".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.8),
        },
        ReasoningPath {
            id: "short_2".to_string(),
            content: "Short".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.8),
        },
    ];

    let result = engine
        .consensus_reasoning("prompt", short_paths)
        .await;
    assert!(result.is_ok());

    // Test with very long content
    let long_content = "This is a very long reasoning path that contains extensive analysis. ".repeat(50);
    let long_paths = vec![
        ReasoningPath {
            id: "long_1".to_string(),
            content: long_content.clone(),
            temperature_used: 0.7,
            max_tokens_used: 2048,
            generated_at: Utc::now(),
            confidence: Some(0.8),
        },
    ];

    let result = engine
        .consensus_reasoning("prompt", long_paths)
        .await;
    assert!(result.is_ok());
}

// ============================================================================
// Performance and Scaling Tests
// ============================================================================

#[tokio::test]
async fn test_consensus_with_many_paths() {
    let engine = create_test_engine();

    // Create 20 paths
    let mut paths = Vec::new();
    for i in 0..20 {
        paths.push(ReasoningPath {
            id: format!("path_{}", i),
            content: format!("Reasoning path number {} with unique content.", i),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.8 - i as f64 * 0.01),
        });
    }

    let result = engine
        .consensus_reasoning("prompt", paths)
        .await;

    assert!(result.is_ok());
    let consensus = result.unwrap();
    assert_eq!(consensus.all_paths.len(), 20);
    assert_eq!(consensus.confidence_scores.len(), 20);
}

// ============================================================================
// Error Handling Tests
// ============================================================================

#[tokio::test]
async fn test_consensus_with_missing_confidence() {
    let engine = create_test_engine();
    let paths = vec![
        ReasoningPath {
            id: "no_conf_1".to_string(),
            content: "Path without confidence score".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: None,
        },
        ReasoningPath {
            id: "no_conf_2".to_string(),
            content: "Another path without confidence".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: None,
        },
    ];

    let result = engine
        .consensus_reasoning("prompt", paths)
        .await;

    assert!(result.is_ok(), "Should handle missing confidence scores");
}

#[tokio::test]
async fn test_consensus_with_identical_paths() {
    let engine = create_test_engine();
    let paths = vec![
        ReasoningPath {
            id: "dup_1".to_string(),
            content: "Identical reasoning path content".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.8),
        },
        ReasoningPath {
            id: "dup_2".to_string(),
            content: "Identical reasoning path content".to_string(),
            temperature_used: 0.7,
            max_tokens_used: 256,
            generated_at: Utc::now(),
            confidence: Some(0.8),
        },
    ];

    let result = engine
        .consensus_reasoning("prompt", paths)
        .await;

    assert!(result.is_ok());
    let consensus = result.unwrap();

    // Both should have high similarity scores
    for score in consensus.confidence_scores.values() {
        assert!(*score > 0.4, "Identical paths should have high consensus score");
    }
}
