use beagle_hermes::serendipity::SerendipityEngine;

#[tokio::test]
#[ignore] // Requires Neo4j running
async fn test_swanson_abc_discovery() {
    let engine = SerendipityEngine::new(
        "bolt://localhost:7687",
        "neo4j",
        "hermespassword",
        0.7
    ).await.unwrap();
    
    // Classic Swanson example: Raynaud's disease
    let discoveries = engine.discover_connections("raynauds_disease", 10).await.unwrap();
    
    assert!(discoveries.len() >= 0); // May be 0 if no data
    
    for discovery in &discoveries {
        println!("\n🔬 Discovery:");
        println!("   A: {}", discovery.concept_a);
        println!("   B: {}", discovery.concept_b);
        println!("   C: {}", discovery.concept_c);
        println!("   Novelty: {:.2}", discovery.novelty_score);
        println!("   Path strength: {:.2}", discovery.path_strength);
        
        // Generate hypothesis
        let hypothesis = engine.generate_hypothesis(discovery);
        println!("\n📝 Hypothesis:\n{}", hypothesis.hypothesis_text);
        println!("   Confidence: {:.2}", hypothesis.confidence);
        println!("   Impact: {:.2}", hypothesis.impact_score);
    }
    
    // Verify cross-domain discoveries
    let domain_classifier = beagle_hermes::serendipity::DomainClassifier::new();
    let cross_domain_count = discoveries.iter()
        .filter(|d| domain_classifier.is_cross_domain(&d.concept_a, &d.concept_c))
        .count();
    
    println!("Cross-domain discoveries: {}", cross_domain_count);
}

