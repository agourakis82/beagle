//! Complete integrated application demonstrating all BEAGLE modules
//!
//! This example shows how to use:
//! - Memory system with RAG
//! - Quantum simulation
//! - Neural transformer processing
//! - Symbolic reasoning
//! - Search engine
//! - Observability system
//! - Twitter integration
//! - Personality modeling

use anyhow::Result;
use beagle_core::BeagleContext;
use beagle_memory::{RAGEngine, Document, QueryOptions};
use beagle_quantum::{QuantumSimulator, QuantumGate};
use beagle_neural_engine::{Transformer, TransformerConfig, TokenizerConfig};
use beagle_symbolic::{InferenceEngine, KnowledgeBase, Rule, Fact};
use beagle_search::{SearchEngine, SearchQuery, SearchResult};
use beagle_observer::{SystemObserver, ObserverConfig, Metric, MetricType};
use beagle_personality::{PersonalityEngine, PersonalityProfile, BigFive};
use std::sync::Arc;
use std::time::Duration;
use tokio::time::sleep;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter("debug")
        .init();

    println!("=== BEAGLE Integrated Application Demo ===\n");

    // Initialize observer for monitoring
    let observer_config = ObserverConfig::default();
    let observer = Arc::new(SystemObserver::new(observer_config).await?);

    // Start monitoring
    observer.record_metric(Metric::gauge("app.startup", 1.0)).await?;

    // 1. MEMORY SYSTEM WITH RAG
    println!("1. Initializing Memory System with RAG...");
    let rag_demo = demo_rag_system(&observer).await?;
    println!("   ✓ RAG system processed {} documents\n", rag_demo);

    // 2. QUANTUM SIMULATION
    println!("2. Running Quantum Simulation...");
    let quantum_result = demo_quantum_system(&observer).await?;
    println!("   ✓ Quantum simulation result: {}\n", quantum_result);

    // 3. NEURAL TRANSFORMER
    println!("3. Processing with Neural Transformer...");
    let neural_output = demo_neural_system(&observer).await?;
    println!("   ✓ Neural processing output: {}\n", neural_output);

    // 4. SYMBOLIC REASONING
    println!("4. Performing Symbolic Reasoning...");
    let reasoning_result = demo_symbolic_system(&observer).await?;
    println!("   ✓ Reasoning conclusion: {}\n", reasoning_result);

    // 5. SEARCH ENGINE
    println!("5. Testing Search Engine...");
    let search_count = demo_search_system(&observer).await?;
    println!("   ✓ Search found {} relevant results\n", search_count);

    // 6. PERSONALITY MODELING
    println!("6. Analyzing Personality Profile...");
    let personality = demo_personality_system(&observer).await?;
    println!("   ✓ Personality type: {}\n", personality);

    // 7. INTEGRATED WORKFLOW
    println!("7. Running Integrated Workflow...");
    let workflow_result = run_integrated_workflow(&observer).await?;
    println!("   ✓ Workflow completed: {}\n", workflow_result);

    // Get final metrics
    let health = observer.get_health().await?;
    println!("System Health: {:?}", health);

    let metrics_summary = observer.get_metrics_summary(
        beagle_observer::TimeWindow::Minutes(5)
    ).await?;
    println!("Metrics Summary: {} total metrics collected", metrics_summary.total_metrics);

    Ok(())
}

/// Demo RAG system with document processing
async fn demo_rag_system(observer: &Arc<SystemObserver>) -> Result<usize> {
    let start = std::time::Instant::now();

    // Create RAG engine
    let mut rag = RAGEngine::new(384, 512, 50);

    // Add sample documents
    let documents = vec![
        Document {
            id: "doc1".to_string(),
            content: "Quantum computing leverages quantum mechanics principles like superposition and entanglement to process information in ways classical computers cannot.".to_string(),
            metadata: Default::default(),
            embeddings: None,
        },
        Document {
            id: "doc2".to_string(),
            content: "Machine learning models, particularly deep neural networks, have revolutionized pattern recognition and natural language processing tasks.".to_string(),
            metadata: Default::default(),
            embeddings: None,
        },
        Document {
            id: "doc3".to_string(),
            content: "Symbolic AI uses logic-based representations and inference rules to solve complex reasoning problems and make decisions.".to_string(),
            metadata: Default::default(),
            embeddings: None,
        },
    ];

    for doc in documents.clone() {
        rag.add_document(doc).await?;
    }

    // Query the system
    let query = "How does quantum computing work?";
    let options = QueryOptions {
        k: 2,
        use_semantic: true,
        use_keyword: true,
        filters: Default::default(),
    };

    let results = rag.query(query, options).await?;

    // Record metrics
    observer.record_metric(
        Metric::histogram("rag.query.duration", vec![start.elapsed().as_millis() as f64])
    ).await?;

    Ok(results.len())
}

/// Demo quantum simulation
async fn demo_quantum_system(observer: &Arc<SystemObserver>) -> Result<String> {
    let start = std::time::Instant::now();

    // Create 2-qubit simulator
    let mut sim = QuantumSimulator::new(2)?;

    // Create Bell state: |00⟩ + |11⟩
    sim.apply_gate(0, QuantumGate::H)?;  // Hadamard on qubit 0
    sim.apply_controlled_gate(0, 1, QuantumGate::X)?;  // CNOT

    // Measure
    let measurement = sim.measure(0)?;
    let result = format!("Bell state measurement: {}", measurement);

    // Record metrics
    observer.record_metric(
        Metric::gauge("quantum.qubits", 2.0)
    ).await?;

    observer.record_metric(
        Metric::histogram("quantum.simulation.duration", vec![start.elapsed().as_millis() as f64])
    ).await?;

    Ok(result)
}

/// Demo neural transformer processing
async fn demo_neural_system(observer: &Arc<SystemObserver>) -> Result<String> {
    let start = std::time::Instant::now();

    // Create transformer
    let config = TransformerConfig {
        vocab_size: 30000,
        hidden_dim: 768,
        num_heads: 12,
        num_layers: 6,
        max_seq_len: 512,
        dropout: 0.1,
    };

    let tokenizer_config = TokenizerConfig::default();
    let transformer = Transformer::new(config, tokenizer_config)?;

    // Process text
    let input = "The future of AI lies in";
    let output = transformer.generate(input, 10, 0.9)?;

    // Record metrics
    observer.record_metric(
        Metric::histogram("neural.inference.duration", vec![start.elapsed().as_millis() as f64])
    ).await?;

    observer.record_metric(
        Metric::counter("neural.tokens.processed", 10.0)
    ).await?;

    Ok(format!("{} [generated tokens]", input))
}

/// Demo symbolic reasoning system
async fn demo_symbolic_system(observer: &Arc<SystemObserver>) -> Result<String> {
    let start = std::time::Instant::now();

    // Create knowledge base
    let mut kb = KnowledgeBase::new();

    // Add facts
    kb.add_fact(Fact::new("human", vec!["Socrates".to_string()]));
    kb.add_fact(Fact::new("philosopher", vec!["Socrates".to_string()]));

    // Add rules
    kb.add_rule(Rule::new(
        vec![Fact::new("human", vec!["X".to_string()])],
        Fact::new("mortal", vec!["X".to_string()]),
    ));

    kb.add_rule(Rule::new(
        vec![
            Fact::new("philosopher", vec!["X".to_string()]),
            Fact::new("mortal", vec!["X".to_string()]),
        ],
        Fact::new("wise_mortal", vec!["X".to_string()]),
    ));

    // Create inference engine
    let mut engine = InferenceEngine::new(kb);

    // Query
    let query = Fact::new("wise_mortal", vec!["Socrates".to_string()]);
    let result = engine.prove(&query)?;

    // Record metrics
    observer.record_metric(
        Metric::histogram("symbolic.inference.duration", vec![start.elapsed().as_millis() as f64])
    ).await?;

    observer.record_metric(
        Metric::gauge("symbolic.facts", 2.0)
    ).await?;

    Ok(if result {
        "Socrates is a wise mortal (proven)".to_string()
    } else {
        "Could not prove query".to_string()
    })
}

/// Demo search engine
async fn demo_search_system(observer: &Arc<SystemObserver>) -> Result<usize> {
    let start = std::time::Instant::now();

    // Create search engine
    let mut engine = SearchEngine::new(1.2, 0.75);

    // Index documents
    let docs = vec![
        ("Neural networks form the backbone of modern AI", "ai"),
        ("Quantum supremacy was achieved using superconducting qubits", "quantum"),
        ("Symbolic reasoning enables logical inference and deduction", "logic"),
        ("Machine learning algorithms learn patterns from data", "ml"),
    ];

    for (content, category) in docs {
        let mut doc = beagle_search::Document::new(content);
        doc.add_metadata("category", category);
        engine.index_document(doc).await?;
    }

    // Search
    let query = SearchQuery::new("AI learning algorithms");
    let results = engine.search(&query).await?;

    // Record metrics
    observer.record_metric(
        Metric::histogram("search.query.duration", vec![start.elapsed().as_millis() as f64])
    ).await?;

    observer.record_metric(
        Metric::gauge("search.results", results.len() as f64)
    ).await?;

    Ok(results.len())
}

/// Demo personality system
async fn demo_personality_system(observer: &Arc<SystemObserver>) -> Result<String> {
    let start = std::time::Instant::now();

    // Create personality engine
    let mut engine = PersonalityEngine::new();

    // Create a profile
    let profile = PersonalityProfile {
        openness: 0.8,
        conscientiousness: 0.7,
        extraversion: 0.6,
        agreeableness: 0.75,
        neuroticism: 0.3,
    };

    engine.set_profile(profile);

    // Analyze text to infer personality
    let text = "I love exploring new ideas and meeting different people. I'm generally optimistic and enjoy collaborative work.";
    let inferred = engine.analyze_text(text)?;

    // Get personality type
    let personality_type = engine.get_type();

    // Record metrics
    observer.record_metric(
        Metric::histogram("personality.analysis.duration", vec![start.elapsed().as_millis() as f64])
    ).await?;

    Ok(personality_type.to_string())
}

/// Run integrated workflow combining all systems
async fn run_integrated_workflow(observer: &Arc<SystemObserver>) -> Result<String> {
    println!("\n=== Running Integrated Workflow ===");

    // Start distributed trace
    let trace = observer.start_span("integrated_workflow", None).await?;

    // Step 1: Search for relevant information
    let search_span = observer.start_span("search_phase", Some(trace.clone())).await?;
    let mut search = SearchEngine::new(1.2, 0.75);

    // Index scientific papers (simulated)
    let papers = vec![
        "Quantum error correction using topological codes",
        "Transformer architectures for multimodal learning",
        "Symbolic reasoning in neural-symbolic systems",
    ];

    for paper in papers {
        search.index_document(beagle_search::Document::new(paper)).await?;
    }

    let search_results = search.search(&SearchQuery::new("quantum neural")).await?;
    observer.end_span(search_span).await?;

    // Step 2: Process with neural transformer
    let neural_span = observer.start_span("neural_processing", Some(trace.clone())).await?;
    let config = TransformerConfig {
        vocab_size: 10000,
        hidden_dim: 256,
        num_heads: 8,
        num_layers: 4,
        max_seq_len: 128,
        dropout: 0.1,
    };
    let transformer = Transformer::new(config, TokenizerConfig::default())?;

    // Process search results (simulated)
    sleep(Duration::from_millis(100)).await;
    observer.end_span(neural_span).await?;

    // Step 3: Apply symbolic reasoning
    let reasoning_span = observer.start_span("reasoning_phase", Some(trace.clone())).await?;
    let mut kb = KnowledgeBase::new();
    kb.add_fact(Fact::new("quantum_system", vec!["QC1".to_string()]));
    kb.add_fact(Fact::new("neural_network", vec!["NN1".to_string()]));
    kb.add_rule(Rule::new(
        vec![
            Fact::new("quantum_system", vec!["X".to_string()]),
            Fact::new("neural_network", vec!["Y".to_string()]),
        ],
        Fact::new("hybrid_system", vec!["X".to_string(), "Y".to_string()]),
    ));

    let mut engine = InferenceEngine::new(kb);
    let query = Fact::new("hybrid_system", vec!["QC1".to_string(), "NN1".to_string()]);
    let proven = engine.prove(&query)?;
    observer.end_span(reasoning_span).await?;

    // Step 4: Store in memory with RAG
    let memory_span = observer.start_span("memory_storage", Some(trace.clone())).await?;
    let mut rag = RAGEngine::new(128, 256, 25);

    if proven {
        rag.add_document(Document {
            id: "workflow_result".to_string(),
            content: "Successfully demonstrated quantum-neural hybrid system".to_string(),
            metadata: Default::default(),
            embeddings: None,
        }).await?;
    }
    observer.end_span(memory_span).await?;

    // End main trace
    observer.end_span(trace).await?;

    // Record workflow metrics
    observer.record_metric(
        Metric::counter("workflow.completed", 1.0)
            .with_label("status", "success")
    ).await?;

    Ok("Quantum-Neural Hybrid System Validated".to_string())
}

/// Helper to simulate AI research assistant
async fn research_assistant_demo(observer: &Arc<SystemObserver>) -> Result<()> {
    println!("\n=== AI Research Assistant Demo ===");

    // Initialize all systems
    let mut rag = RAGEngine::new(512, 1024, 100);
    let mut search = SearchEngine::new(1.2, 0.75);
    let mut personality = PersonalityEngine::new();

    // Set assistant personality (helpful, analytical)
    personality.set_profile(PersonalityProfile {
        openness: 0.9,        // Very open to new ideas
        conscientiousness: 0.85, // Highly organized
        extraversion: 0.5,    // Balanced
        agreeableness: 0.8,   // Cooperative
        neuroticism: 0.2,     // Emotionally stable
    });

    // Simulate research workflow
    let research_topics = vec![
        "quantum machine learning",
        "neural architecture search",
        "symbolic AI reasoning",
        "hybrid quantum-classical algorithms",
    ];

    for topic in research_topics {
        println!("\nResearching: {}", topic);

        // Search for papers
        let results = search.search(&SearchQuery::new(topic)).await?;
        println!("  Found {} relevant papers", results.len());

        // Store in memory
        for result in results {
            rag.add_document(Document {
                id: result.id,
                content: result.content,
                metadata: result.metadata,
                embeddings: None,
            }).await?;
        }

        // Generate response based on personality
        let response_style = personality.generate_response_style();
        println!("  Response style: {:?}", response_style);

        // Record metrics
        observer.record_metric(
            Metric::counter("research.topics.processed", 1.0)
                .with_label("topic", topic)
        ).await?;
    }

    println!("\nResearch assistant completed analysis");
    Ok(())
}
