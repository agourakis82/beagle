//! BEAGLE v0.4 Integration Tests
//!
//! Tests all new features with real services:
//! - PubMed search integration
//! - arXiv search integration
//! - Neo4j graph storage
//! - Reflexion loop with quality threshold
//! - Multi-provider LLM router
//!
//! IMPORTANT: These tests require:
//! - Neo4j running at NEO4J_URI
//! - Internet connection for PubMed/arXiv APIs
//! - LLM API keys (ANTHROPIC_API_KEY, GITHUB_TOKEN, etc.)
//!
//! Run with: cargo test --test v04_integration_tests -- --ignored --nocapture

use anyhow::Result;
use std::time::Instant;

// ============================================================================
// Test 1: PubMed Search Integration
// ============================================================================

#[tokio::test]
#[ignore] // Requires network + NCBI API
async fn test_pubmed_search_crispr() -> Result<()> {
    println!("\n=== Test 1: PubMed Search (CRISPR) ===");

    // This test would require importing beagle-search
    // For now, we'll create a placeholder that documents what to test

    println!("TODO: Import PubMedClient and test search");
    println!("Expected behavior:");
    println!("  - Query: 'CRISPR off-target effects'");
    println!("  - Should return 10-20 papers");
    println!("  - Each paper should have: title, abstract, authors, PMID");
    println!("  - Should complete within 5 seconds");

    // let client = beagle_search::PubMedClient::from_env();
    // let query = beagle_search::SearchQuery::new("CRISPR off-target effects")
    //     .with_max_results(10);
    //
    // let start = Instant::now();
    // let result = client.search(&query).await?;
    // let elapsed = start.elapsed();
    //
    // assert!(result.papers.len() >= 5, "Should find at least 5 papers");
    // assert!(result.papers.len() <= 10, "Should respect max_results");
    // assert!(elapsed.as_secs() < 10, "Should complete within 10 seconds");
    //
    // // Verify first paper has required fields
    // let paper = &result.papers[0];
    // assert!(!paper.title.is_empty(), "Paper should have title");
    // assert!(!paper.abstract_text.is_empty(), "Paper should have abstract");
    // assert!(!paper.authors.is_empty(), "Paper should have authors");
    // assert!(paper.id.starts_with("PMID:"), "ID should be PMID");
    //
    // println!("✅ Found {} papers in {:?}", result.papers.len(), elapsed);
    // println!("✅ First paper: {}", paper.title);

    Ok(())
}

#[tokio::test]
#[ignore]
async fn test_pubmed_rate_limiting() -> Result<()> {
    println!("\n=== Test 2: PubMed Rate Limiting ===");

    println!("TODO: Test rate limiter");
    println!("Expected behavior:");
    println!("  - Without API key: max 3 req/s");
    println!("  - With NCBI_API_KEY: max 10 req/s");
    println!("  - Should throttle requests automatically");

    // let client = beagle_search::PubMedClient::from_env();
    //
    // // Fire 5 requests rapidly
    // let start = Instant::now();
    // for i in 0..5 {
    //     let query = beagle_search::SearchQuery::new(&format!("test query {}", i))
    //         .with_max_results(1);
    //     client.search(&query).await?;
    // }
    // let elapsed = start.elapsed();
    //
    // // Should take at least 1.5 seconds (5 requests / 3 req/s)
    // let min_expected = std::time::Duration::from_millis(1500);
    // assert!(elapsed >= min_expected,
    //     "Rate limiter should throttle: took {:?}, expected >= {:?}",
    //     elapsed, min_expected);
    //
    // println!("✅ Rate limiter working: 5 requests took {:?}", elapsed);

    Ok(())
}

// ============================================================================
// Test 3: arXiv Search Integration
// ============================================================================

#[tokio::test]
#[ignore]
async fn test_arxiv_search_quantum() -> Result<()> {
    println!("\n=== Test 3: arXiv Search (Quantum ML) ===");

    println!("TODO: Import ArxivClient and test search");
    println!("Expected behavior:");
    println!("  - Query: 'quantum machine learning'");
    println!("  - Should return papers from cs.AI, quant-ph categories");
    println!("  - Each paper should have: arXiv ID, title, abstract, PDF URL");

    // let client = beagle_search::ArxivClient::new();
    // let query = beagle_search::SearchQuery::new("quantum machine learning")
    //     .with_max_results(10);
    //
    // let start = Instant::now();
    // let result = client.search(&query).await?;
    // let elapsed = start.elapsed();
    //
    // assert!(result.papers.len() >= 5, "Should find at least 5 papers");
    //
    // let paper = &result.papers[0];
    // assert!(paper.id.contains("arXiv"), "ID should be arXiv ID");
    // assert!(paper.pdf_url.is_some(), "Should have PDF URL");
    // assert!(!paper.categories.is_empty(), "Should have categories");
    //
    // println!("✅ Found {} papers in {:?}", result.papers.len(), elapsed);
    // println!("✅ First paper: {} ({})", paper.title, paper.id);

    Ok(())
}

// ============================================================================
// Test 4: Neo4j Graph Storage
// ============================================================================

#[tokio::test]
#[ignore]
async fn test_neo4j_paper_storage() -> Result<()> {
    println!("\n=== Test 4: Neo4j Paper Storage ===");

    println!("TODO: Test Neo4j storage");
    println!("Expected behavior:");
    println!("  - Store paper with authors and categories");
    println!("  - MERGE should avoid duplicates");
    println!("  - Retrieve paper by ID");
    println!("  - Find related papers by co-authorship");

    // // Create mock paper
    // let paper = beagle_search::Paper {
    //     id: "test_pmid_12345".to_string(),
    //     source: "pubmed".to_string(),
    //     title: "Test Paper on CRISPR".to_string(),
    //     authors: vec![
    //         beagle_search::Author {
    //             name: "John Doe".to_string(),
    //             affiliation: Some("MIT".to_string()),
    //         },
    //     ],
    //     abstract_text: "This is a test abstract.".to_string(),
    //     published_date: Some(chrono::Utc::now()),
    //     doi: Some("10.1234/test".to_string()),
    //     categories: vec!["Genetics".to_string()],
    //     url: Some("https://pubmed.ncbi.nlm.nih.gov/12345/".to_string()),
    //     pdf_url: None,
    // };
    //
    // // Store in Neo4j
    // let ctx = beagle_core::BeagleContext::from_env().await?;
    // let (cypher, params) = beagle_search::storage::create_paper_query(&paper);
    // let paper_id = ctx.graph_store_knowledge(vec!["Paper".to_string()], params).await?;
    //
    // println!("✅ Stored paper with ID: {}", paper_id);
    //
    // // Try storing again (should not duplicate)
    // let (cypher2, params2) = beagle_search::storage::create_paper_query(&paper);
    // let paper_id2 = ctx.graph_store_knowledge(vec!["Paper".to_string()], params2).await?;
    //
    // assert_eq!(paper_id, paper_id2, "MERGE should return same ID for duplicate");
    // println!("✅ Duplicate prevention working");
    //
    // // Cleanup
    // ctx.execute_cypher("MATCH (p:Paper {id: $id}) DETACH DELETE p",
    //     serde_json::json!({"id": "test_pmid_12345"})).await?;

    Ok(())
}

#[tokio::test]
#[ignore]
async fn test_neo4j_hybrid_retrieval() -> Result<()> {
    println!("\n=== Test 5: Neo4j Hybrid Retrieval ===");

    println!("TODO: Test hybrid retrieval (vector + graph)");
    println!("Expected behavior:");
    println!("  - Semantic search finds top-k papers");
    println!("  - Graph expansion finds related papers");
    println!("  - Results ranked by relevance");

    // let ctx = beagle_core::BeagleContext::from_env().await?;
    //
    // let query = "CRISPR gene editing";
    // let results = ctx.graph_hybrid_retrieve(query, 5, 2).await?;
    //
    // assert!(results.len() > 0, "Should find related papers");
    // println!("✅ Found {} related papers", results.len());

    Ok(())
}

// ============================================================================
// Test 6: Reflexion Loop
// ============================================================================

#[tokio::test]
#[ignore]
async fn test_reflexion_loop_low_quality() -> Result<()> {
    println!("\n=== Test 6: Reflexion Loop (Triggers Refinement) ===");

    println!("TODO: Test Reflexion loop");
    println!("Expected behavior:");
    println!("  - Initial answer with quality < 0.7");
    println!("  - Should trigger refinement (1-3 iterations)");
    println!("  - Final quality should be >= 0.7");

    // let agent = beagle_agents::ResearcherAgent::new(...).await?;
    //
    // // Query likely to need refinement
    // let query = "Explain the mechanism of CRISPR-Cas9 off-target effects";
    //
    // let start = Instant::now();
    // let result = agent.research(query, None).await?;
    // let elapsed = start.elapsed();
    //
    // assert!(result.refinement_iterations > 0,
    //     "Should have refined at least once for complex query");
    // assert!(result.quality_score >= 0.7,
    //     "Final quality should meet threshold: got {}", result.quality_score);
    // assert!(result.refinement_iterations <= 3,
    //     "Should not exceed max iterations");
    //
    // println!("✅ Reflexion loop completed:");
    // println!("   - Iterations: {}", result.refinement_iterations);
    // println!("   - Quality: {:.2}", result.quality_score);
    // println!("   - Time: {:?}", elapsed);

    Ok(())
}

#[tokio::test]
#[ignore]
async fn test_reflexion_loop_high_quality() -> Result<()> {
    println!("\n=== Test 7: Reflexion Loop (Skip Refinement) ===");

    println!("TODO: Test fast path");
    println!("Expected behavior:");
    println!("  - Simple query with quality >= 0.7");
    println!("  - Should NOT trigger refinement");
    println!("  - Should be faster than complex query");

    // let agent = beagle_agents::ResearcherAgent::new(...).await?;
    //
    // let query = "What is CRISPR?";
    //
    // let start = Instant::now();
    // let result = agent.research(query, None).await?;
    // let elapsed = start.elapsed();
    //
    // assert_eq!(result.refinement_iterations, 0,
    //     "Simple query should not need refinement");
    // assert!(result.quality_score >= 0.7);
    // assert!(elapsed.as_secs() < 15, "Should be fast without refinement");
    //
    // println!("✅ Fast path working:");
    // println!("   - Quality: {:.2}", result.quality_score);
    // println!("   - Time: {:?}", elapsed);

    Ok(())
}

// ============================================================================
// Test 8: LLM Router
// ============================================================================

#[tokio::test]
#[ignore]
async fn test_router_provider_selection() -> Result<()> {
    println!("\n=== Test 8: LLM Router Provider Selection ===");

    println!("TODO: Test router logic");
    println!("Expected behavior:");
    println!("  - Premium task → Claude Direct (if ANTHROPIC_API_KEY set)");
    println!("  - Premium task → Copilot (if GITHUB_TOKEN set)");
    println!("  - Premium task → Cursor (if CURSOR_API_KEY set)");
    println!("  - Default → Grok 3");

    // use beagle_llm::{TieredRouter, RequestMeta};
    //
    // let router = TieredRouter::new()?;
    //
    // // Test 1: Premium quality task
    // let meta_premium = RequestMeta {
    //     requires_phd_level_reasoning: true,
    //     critical_section: true,
    //     ..Default::default()
    // };
    // let (client, tier) = router.choose(&meta_premium);
    // println!("Premium task → {:?}", tier);
    //
    // // Should use Claude > Copilot > Cursor if available
    // if std::env::var("ANTHROPIC_API_KEY").is_ok() {
    //     assert_eq!(tier, beagle_llm::ProviderTier::ClaudeDirect);
    // } else if std::env::var("GITHUB_TOKEN").is_ok() {
    //     assert_eq!(tier, beagle_llm::ProviderTier::Copilot);
    // } else if std::env::var("CURSOR_API_KEY").is_ok() {
    //     assert_eq!(tier, beagle_llm::ProviderTier::Cursor);
    // }
    //
    // // Test 2: Default task
    // let meta_default = RequestMeta::default();
    // let (_, tier2) = router.choose(&meta_default);
    // assert_eq!(tier2, beagle_llm::ProviderTier::Grok3);
    // println!("Default task → Grok3");
    //
    // println!("✅ Router selection working correctly");

    Ok(())
}

#[tokio::test]
#[ignore]
async fn test_router_copilot_client() -> Result<()> {
    println!("\n=== Test 9: GitHub Copilot Client ===");

    if std::env::var("GITHUB_TOKEN").is_err() {
        println!("⏭️  Skipped: GITHUB_TOKEN not set");
        return Ok(());
    }

    println!("TODO: Test Copilot client");
    println!("Expected behavior:");
    println!("  - Connect to api.githubcopilot.com");
    println!("  - Use Claude 3.5 Sonnet by default");
    println!("  - Return valid completion");

    // use beagle_llm::{CopilotClient, LlmClient, LlmRequest, ChatMessage};
    //
    // let client = CopilotClient::from_env()?;
    //
    // let request = LlmRequest {
    //     model: "claude-3.5-sonnet".to_string(),
    //     messages: vec![ChatMessage::user("What is 2+2? Answer with just the number.")],
    //     temperature: Some(0.0),
    //     max_tokens: Some(10),
    // };
    //
    // let start = Instant::now();
    // let response = client.chat(request).await?;
    // let elapsed = start.elapsed();
    //
    // assert!(response.contains("4"), "Should answer correctly: got {}", response);
    // assert!(elapsed.as_secs() < 5, "Should respond quickly");
    //
    // println!("✅ Copilot client working");
    // println!("   - Response: {}", response.trim());
    // println!("   - Latency: {:?}", elapsed);

    Ok(())
}

#[tokio::test]
#[ignore]
async fn test_router_claude_direct_client() -> Result<()> {
    println!("\n=== Test 10: Claude Direct Client ===");

    if std::env::var("ANTHROPIC_API_KEY").is_err() {
        println!("⏭️  Skipped: ANTHROPIC_API_KEY not set");
        return Ok(());
    }

    println!("TODO: Test Claude Direct client");
    println!("Expected behavior:");
    println!("  - Connect to api.anthropic.com");
    println!("  - Use Claude Sonnet 4.5 by default");
    println!("  - Return valid completion");

    // use beagle_llm::{ClaudeClient, LlmClient, LlmRequest, ChatMessage};
    //
    // let client = ClaudeClient::from_env()?;
    //
    // let request = LlmRequest {
    //     model: "claude-sonnet-4.5".to_string(),
    //     messages: vec![ChatMessage::user("What is 2+2? Answer with just the number.")],
    //     temperature: Some(0.0),
    //     max_tokens: Some(10),
    // };
    //
    // let start = Instant::now();
    // let response = client.chat(request).await?;
    // let elapsed = start.elapsed();
    //
    // assert!(response.contains("4"), "Should answer correctly: got {}", response);
    //
    // println!("✅ Claude Direct client working");
    // println!("   - Response: {}", response.trim());
    // println!("   - Latency: {:?}", elapsed);

    Ok(())
}

// ============================================================================
// Test 11: End-to-End Integration
// ============================================================================

#[tokio::test]
#[ignore]
async fn test_e2e_research_query() -> Result<()> {
    println!("\n=== Test 11: End-to-End Research Query ===");

    println!("TODO: Full E2E test");
    println!("Steps:");
    println!("  1. Search PubMed for 'CAR-T cell therapy'");
    println!("  2. Store papers in Neo4j");
    println!("  3. Generate answer with paper citations");
    println!("  4. Run Reflexion loop");
    println!("  5. Return high-quality answer");

    // let agent = beagle_agents::ResearcherAgent::new(...).await?;
    //
    // let query = "What are the latest advances in CAR-T cell therapy for solid tumors?";
    //
    // let start = Instant::now();
    // let result = agent.research(query, None).await?;
    // let elapsed = start.elapsed();
    //
    // // Verify result
    // assert!(!result.content.is_empty(), "Should have answer");
    // assert!(result.quality_score >= 0.7, "Should meet quality threshold");
    // assert!(!result.papers_cited.is_empty(), "Should cite papers");
    //
    // // Verify latency
    // assert!(elapsed.as_secs() < 60, "Should complete within 60 seconds");
    //
    // println!("✅ E2E test passed:");
    // println!("   - Answer length: {} chars", result.content.len());
    // println!("   - Papers cited: {}", result.papers_cited.len());
    // println!("   - Quality: {:.2}", result.quality_score);
    // println!("   - Refinements: {}", result.refinement_iterations);
    // println!("   - Total time: {:?}", elapsed);
    //
    // // Print first 200 chars of answer
    // println!("\nAnswer preview:");
    // println!("{}", result.content.chars().take(200).collect::<String>());

    Ok(())
}

// ============================================================================
// Helper: Environment Check
// ============================================================================

#[test]
fn test_environment_setup() {
    println!("\n=== Environment Check ===");

    let mut missing = vec![];

    // Check Neo4j
    if std::env::var("NEO4J_URI").is_err() {
        missing.push("NEO4J_URI");
    } else {
        println!("✅ NEO4J_URI: {}", std::env::var("NEO4J_URI").unwrap());
    }

    // Check LLM providers (optional)
    if let Ok(key) = std::env::var("ANTHROPIC_API_KEY") {
        println!("✅ ANTHROPIC_API_KEY: sk-ant-...{}", &key[key.len()-4..]);
    } else {
        println!("⚠️  ANTHROPIC_API_KEY not set (Claude Direct unavailable)");
    }

    if let Ok(key) = std::env::var("GITHUB_TOKEN") {
        println!("✅ GITHUB_TOKEN: ghp_...{}", &key[key.len()-4..]);
    } else {
        println!("⚠️  GITHUB_TOKEN not set (Copilot unavailable)");
    }

    if let Ok(key) = std::env::var("CURSOR_API_KEY") {
        println!("✅ CURSOR_API_KEY: ...{}", &key[key.len()-4..]);
    } else {
        println!("⚠️  CURSOR_API_KEY not set (Cursor unavailable)");
    }

    // Check NCBI API key (optional)
    if let Ok(_) = std::env::var("NCBI_API_KEY") {
        println!("✅ NCBI_API_KEY set (10 req/s)");
    } else {
        println!("⚠️  NCBI_API_KEY not set (3 req/s limit)");
    }

    if !missing.is_empty() {
        panic!("❌ Missing required environment variables: {:?}", missing);
    }

    println!("\n✅ Environment setup complete!");
}
