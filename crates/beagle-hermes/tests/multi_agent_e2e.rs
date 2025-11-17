//! End-to-end multi-agent synthesis pipeline test
//!
//! Validates complete flow: ATHENA → HERMES → ARGOS → Refinement

use beagle_hermes::{
    agents::{MultiAgentOrchestrator, AthenaAgent, HermesAgent, ArgosAgent},
    knowledge::{ConceptCluster, ClusteredInsight},
    synthesis::VoiceProfile,
    Result,
};
use chrono::Utc;
use std::sync::Arc;
use uuid::Uuid;

/// Test fixture: Mock concept cluster
fn create_test_cluster() -> ConceptCluster {
    use beagle_hermes::knowledge::ClusteredInsight;
    
    ConceptCluster {
        concept_name: "scaffold_entropy_biomaterials".to_string(),
        insights: vec![
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Entropy gradients influence scaffold architecture and cell behavior".to_string(),
                timestamp: Utc::now(),
            },
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Curvature modulates cell adhesion patterns in neural tissue engineering".to_string(),
                timestamp: Utc::now(),
            },
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Mechanical coherence correlates with tissue formation rates".to_string(),
                timestamp: Utc::now(),
            },
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Surface topology affects protein adsorption and cell migration".to_string(),
                timestamp: Utc::now(),
            },
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Pore size distribution impacts cell migration and differentiation".to_string(),
                timestamp: Utc::now(),
            },
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Biomaterial stiffness influences neural stem cell fate decisions".to_string(),
                timestamp: Utc::now(),
            },
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Scaffold degradation rate affects long-term tissue integration".to_string(),
                timestamp: Utc::now(),
            },
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Topographical cues guide axonal growth in 3D scaffolds".to_string(),
                timestamp: Utc::now(),
            },
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Entropy-based design principles enhance scaffold biocompatibility".to_string(),
                timestamp: Utc::now(),
            },
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Mechanical properties modulate neurogenesis in engineered tissues".to_string(),
                timestamp: Utc::now(),
            },
        ],
        insight_count: 10,
        last_synthesis: None,
    }
}

/// Test: Complete multi-agent synthesis flow
#[tokio::test]
#[ignore] // Requires full infrastructure (Neo4j, PostgreSQL, LLM APIs)
async fn test_complete_multi_agent_synthesis() -> Result<()> {
    // Setup logging
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init();
    
    tracing::info!("🧪 Starting E2E Multi-Agent Synthesis Test");
    
    // 1. Initialize orchestrator
    let voice_profile = VoiceProfile::default();
    
    let orchestrator = MultiAgentOrchestrator::new(voice_profile).await?;
    
    // 2. Create test cluster
    let cluster = create_test_cluster();
    
    tracing::info!("📊 Test Cluster:");
    tracing::info!("   Concept: {}", cluster.concept_name);
    tracing::info!("   Insights: {}", cluster.insight_count);
    
    // 3. Execute synthesis (Introduction section)
    tracing::info!("🚀 Starting multi-agent synthesis...");
    
    let start = std::time::Instant::now();
    
    let result = orchestrator
        .synthesize_section(
            &cluster,
            "Introduction".to_string(),
            500,
        )
        .await?;
    
    let duration_ms = start.elapsed().as_millis() as u64;
    
    // 4. Validate results
    tracing::info!("✅ Synthesis Complete!");
    tracing::info!("   Word count: {}", result.word_count);
    tracing::info!("   Quality score: {:.1}%", result.validation.quality_score * 100.0);
    tracing::info!("   Duration: {}ms", duration_ms);
    
    // Assertions
    assert!(
        result.word_count >= 450 && result.word_count <= 550,
        "Word count out of range: {} (expected 450-550)",
        result.word_count
    );
    
    assert!(
        result.validation.quality_score >= 0.85,
        "Quality score too low: {:.2} (expected ≥0.85)",
        result.validation.quality_score
    );
    
    assert!(
        result.validation.approved,
        "Draft not approved by ARGOS validator"
    );
    
    assert!(
        !result.draft.is_empty(),
        "Generated content is empty"
    );
    
    // 5. Validate content structure
    let content = &result.draft;
    
    // Should contain scientific terminology from cluster
    assert!(
        content.to_lowercase().contains("scaffold") || 
        content.to_lowercase().contains("biomaterial") ||
        content.to_lowercase().contains("entropy"),
        "Content missing key terminology from cluster"
    );
    
    // Should have citations in proper format
    let citation_pattern = regex::Regex::new(r"\[\d+\]").unwrap();
    let citation_count = citation_pattern.find_iter(content).count();
    
    assert!(
        citation_count >= 3,
        "Insufficient inline citations: {} (expected ≥3)",
        citation_count
    );
    
    // 6. Performance validation
    assert!(
        duration_ms < 30000, // 30s for E2E test with real APIs
        "Synthesis too slow: {}ms (expected <30s)",
        duration_ms
    );
    
    // 7. Log sample output
    tracing::info!("\n📄 Generated Introduction (first 300 chars):");
    let preview_len = 300.min(content.len());
    tracing::info!("{}", &content[..preview_len]);
    
    println!("\n✅ ALL VALIDATIONS PASSED!");
    println!("   Total duration: {}ms", duration_ms);
    println!("   Agent calls: ATHENA→HERMES→ARGOS");
    println!("   Quality score: {:.1}%", result.validation.quality_score * 100.0);
    
    Ok(())
}

/// Test: Refinement loop when quality insufficient
#[tokio::test]
#[ignore]
async fn test_refinement_loop() -> Result<()> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init();
    
    tracing::info!("🧪 Testing refinement loop");
    
    let voice_profile = VoiceProfile::default();
    let orchestrator = MultiAgentOrchestrator::new(voice_profile).await?;
    
    // Create cluster with edge case (ambiguous topic)
    let mut cluster = create_test_cluster();
    cluster.concept_name = "quantum_biomaterial_interface".to_string();
    cluster.insight_count = 5; // Below threshold but enough for test
    cluster.insights.truncate(5); // Keep only 5 insights
    
    // Execute synthesis
    let result = orchestrator
        .synthesize_section(
            &cluster,
            "Introduction".to_string(),
            500,
        )
        .await?;
    
    // Validate refinement occurred if needed
    // Note: Refinement is handled internally by orchestrator
    assert!(
        result.validation.quality_score >= 0.75, // Lower threshold for edge case
        "Final quality score too low after refinement: {:.2}",
        result.validation.quality_score
    );
    
    assert!(
        !result.draft.is_empty(),
        "Content is empty after refinement"
    );
    
    println!("✅ Refinement test passed");
    println!("   Final quality: {:.1}%", result.validation.quality_score * 100.0);
    
    Ok(())
}

/// Test: ATHENA paper retrieval
#[tokio::test]
#[ignore] // Requires API keys
async fn test_athena_paper_search() -> Result<()> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init();
    
    let athena = AthenaAgent::new().await?;
    
    let cluster = create_test_cluster();
    
    let papers = athena.search_papers(&cluster).await?;
    
    assert!(!papers.is_empty(), "ATHENA returned no papers");
    assert!(papers.len() <= 20, "ATHENA returned too many papers: {}", papers.len());
    
    // Validate paper structure
    for paper in &papers {
        assert!(!paper.title.is_empty(), "Paper has empty title");
        assert!(!paper.abstract_text.is_empty(), "Paper has empty abstract");
        assert!(paper.relevance_score > 0.0, "Paper has zero relevance");
    }
    
    println!("✅ ATHENA retrieved {} relevant papers", papers.len());
    
    Ok(())
}

/// Test: HERMES draft generation
#[tokio::test]
#[ignore] // Requires API keys
async fn test_hermes_generation() -> Result<()> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init();
    
    let hermes = HermesAgent::new(VoiceProfile::default()).await?;
    
    use beagle_hermes::agents::hermes_agent::GenerationContext;
    use beagle_hermes::agents::athena::Paper;
    
    let context = GenerationContext {
        section_type: "Introduction".to_string(),
        target_words: 500,
        papers: vec![
            Paper {
                title: "Biomaterial scaffolds for neural tissue engineering".to_string(),
                abstract_text: "This paper reviews recent advances in scaffold design...".to_string(),
                authors: vec!["Author 1".to_string(), "Author 2".to_string()],
                year: 2024,
                doi: "10.1000/example1".to_string(),
                relevance_score: 0.92,
            },
        ],
        insights: vec![
            "Test insight 1: Entropy affects scaffold properties".to_string(),
            "Test insight 2: Curvature modulates cell behavior".to_string(),
        ],
    };
    
    let draft = hermes.generate_section(context).await?;
    
    assert!(draft.word_count >= 400, "Draft too short: {}", draft.word_count);
    assert!(!draft.content.is_empty(), "Draft content empty");
    
    println!("✅ HERMES generated {} word draft", draft.word_count);
    
    Ok(())
}

/// Test: ARGOS validation
#[tokio::test]
async fn test_argos_validation() -> Result<()> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init();
    
    let argos = ArgosAgent::new().await?;
    
    use beagle_hermes::agents::hermes_agent::Draft;
    use beagle_hermes::agents::athena::Paper;
    
    let draft = Draft {
        content: "This is a test draft with [1] citation [2] and scientific terminology about biomaterials and scaffolds.".to_string(),
        word_count: 15,
        citations: vec!["1".to_string(), "2".to_string()],
    };
    
    let papers = vec![
        Paper {
            title: "Test Paper 1".to_string(),
            abstract_text: "Abstract 1".to_string(),
            authors: vec!["Author 1".to_string()],
            year: 2024,
            doi: "10.1000/test1".to_string(),
            relevance_score: 0.8,
        },
        Paper {
            title: "Test Paper 2".to_string(),
            abstract_text: "Abstract 2".to_string(),
            authors: vec!["Author 2".to_string()],
            year: 2023,
            doi: "10.1000/test2".to_string(),
            relevance_score: 0.75,
        },
    ];
    
    let validation = argos.validate(&draft, &papers).await?;
    
    assert!(
        validation.quality_score >= 0.0 && validation.quality_score <= 1.0,
        "Quality score out of range: {}",
        validation.quality_score
    );
    
    println!("✅ ARGOS validation score: {:.1}%", validation.quality_score * 100.0);
    println!("   Approved: {}", validation.approved);
    println!("   Issues: {}", validation.issues.len());
    
    Ok(())
}

