//! Complete integrated application demonstrating all BEAGLE modules
//!
//! This example shows how to use:
//! - Memory system with RAG
//! - Quantum simulation
//! - Neural transformer processing
//! - Symbolic reasoning
//! - Search engine
//! - Observability system

use anyhow::Result;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::sleep;
use tracing::{debug, info};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt().with_env_filter("debug").init();

    info!("=== BEAGLE Integrated Application Demo ===\n");

    // 1. MEMORY SYSTEM WITH RAG
    info!("1. Initializing Memory System with RAG...");
    demo_rag_system().await?;

    // 2. QUANTUM SIMULATION
    info!("2. Running Quantum Simulation...");
    demo_quantum_system().await?;

    // 3. NEURAL TRANSFORMER
    info!("3. Processing with Neural Transformer...");
    demo_neural_system().await?;

    // 4. SYMBOLIC REASONING
    info!("4. Performing Symbolic Reasoning...");
    demo_symbolic_system().await?;

    // 5. SEARCH ENGINE
    info!("5. Testing Search Engine...");
    demo_search_system().await?;

    // 6. OBSERVER SYSTEM
    info!("6. Testing Observer System...");
    demo_observer_system().await?;

    // 7. INTEGRATED WORKFLOW
    info!("7. Running Integrated Workflow...");
    run_integrated_workflow().await?;

    info!("All systems demonstrated successfully!");
    Ok(())
}

/// Demo RAG system with document processing
async fn demo_rag_system() -> Result<()> {
    use beagle_memory::{Document, QueryOptions, RAGEngine};

    // Create RAG engine
    let mut rag = RAGEngine::new(384, 512, 50);

    // Add sample documents
    let documents = vec![
        Document {
            id: "doc1".to_string(),
            content: "Quantum computing leverages quantum mechanics principles.".to_string(),
            metadata: Default::default(),
            embeddings: None,
        },
        Document {
            id: "doc2".to_string(),
            content: "Machine learning models have revolutionized AI.".to_string(),
            metadata: Default::default(),
            embeddings: None,
        },
    ];

    for doc in documents {
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
    info!("   ✓ RAG system found {} relevant documents", results.len());

    Ok(())
}

/// Demo quantum simulation
async fn demo_quantum_system() -> Result<()> {
    use beagle_quantum::{QuantumGate, QuantumSimulator};

    // Create 2-qubit simulator
    let mut sim = QuantumSimulator::new(2)?;

    // Create Bell state
    sim.apply_gate(0, QuantumGate::H)?;
    sim.apply_controlled_gate(0, 1, QuantumGate::X)?;

    // Measure
    let measurement = sim.measure(0)?;
    info!("   ✓ Quantum Bell state measured: {}", measurement);

    Ok(())
}

/// Demo neural transformer processing
async fn demo_neural_system() -> Result<()> {
    use beagle_neural_engine::{TokenizerConfig, Transformer, TransformerConfig};

    let config = TransformerConfig {
        vocab_size: 10000,
        hidden_dim: 256,
        num_heads: 8,
        num_layers: 2,
        max_seq_len: 128,
        dropout: 0.1,
    };

    let transformer = Transformer::new(config, TokenizerConfig::default())?;

    info!("   ✓ Neural transformer initialized with 2 layers");

    Ok(())
}

/// Demo symbolic reasoning system
async fn demo_symbolic_system() -> Result<()> {
    use beagle_symbolic::{Fact, InferenceEngine, KnowledgeBase, Rule};

    let mut kb = KnowledgeBase::new();

    // Add facts
    kb.add_fact(Fact::new("human", vec!["Socrates".to_string()]));
    kb.add_fact(Fact::new("philosopher", vec!["Socrates".to_string()]));

    // Add rule
    kb.add_rule(Rule::new(
        vec![Fact::new("human", vec!["X".to_string()])],
        Fact::new("mortal", vec!["X".to_string()]),
    ));

    let mut engine = InferenceEngine::new(kb);
    let query = Fact::new("mortal", vec!["Socrates".to_string()]);
    let result = engine.prove(&query)?;

    info!(
        "   ✓ Symbolic reasoning proved: Socrates is mortal = {}",
        result
    );

    Ok(())
}

/// Demo search engine
async fn demo_search_system() -> Result<()> {
    use beagle_search::{Document, SearchEngine, SearchQuery};

    let mut engine = SearchEngine::new(1.2, 0.75);

    // Index documents
    let docs = vec![
        "Neural networks form the backbone of modern AI",
        "Quantum supremacy achieved with qubits",
        "Symbolic reasoning enables logical inference",
    ];

    for (i, content) in docs.iter().enumerate() {
        let mut doc = Document::new(content);
        doc.id = format!("doc{}", i);
        engine.index_document(doc).await?;
    }

    // Search
    let query = SearchQuery::new("AI neural");
    let results = engine.search(&query).await?;

    info!("   ✓ Search engine found {} results", results.len());

    Ok(())
}

/// Demo observer system
async fn demo_observer_system() -> Result<()> {
    use beagle_observer::{Metric, ObserverConfig, SystemObserver};

    let config = ObserverConfig::default();
    let observer = SystemObserver::new(config).await?;

    // Record metrics
    observer
        .record_metric(Metric::gauge("test.metric", 42.0))
        .await?;
    observer
        .record_metric(Metric::counter("test.counter", 1.0))
        .await?;

    // Start a trace
    let span = observer.start_span("test_operation", None).await?;
    sleep(Duration::from_millis(10)).await;
    observer.end_span(span).await?;

    info!("   ✓ Observer recorded metrics and traces");

    Ok(())
}

/// Run integrated workflow combining multiple systems
async fn run_integrated_workflow() -> Result<()> {
    use beagle_memory::{Document, QueryOptions, RAGEngine};
    use beagle_observer::{Metric, ObserverConfig, SystemObserver};
    use beagle_search::{SearchEngine, SearchQuery};
    use beagle_symbolic::{Fact, InferenceEngine, KnowledgeBase, Rule};

    debug!("Starting integrated workflow...");

    // Initialize observer
    let observer = Arc::new(SystemObserver::new(ObserverConfig::default()).await?);

    // Start workflow trace
    let trace = observer.start_span("integrated_workflow", None).await?;

    // Step 1: Search for information
    let search_span = observer
        .start_span("search_phase", Some(trace.clone()))
        .await?;
    let mut search = SearchEngine::new(1.2, 0.75);

    search
        .index_document(beagle_search::Document::new(
            "Quantum error correction using topological codes",
        ))
        .await?;

    let results = search.search(&SearchQuery::new("quantum")).await?;
    observer.end_span(search_span).await?;
    debug!("  Search found {} results", results.len());

    // Step 2: Store in RAG memory
    let memory_span = observer
        .start_span("memory_phase", Some(trace.clone()))
        .await?;
    let mut rag = RAGEngine::new(128, 256, 25);

    for result in &results {
        rag.add_document(Document {
            id: result.id.clone(),
            content: result.content.clone(),
            metadata: Default::default(),
            embeddings: None,
        })
        .await?;
    }
    observer.end_span(memory_span).await?;
    debug!("  Stored {} documents in memory", results.len());

    // Step 3: Apply reasoning
    let reasoning_span = observer
        .start_span("reasoning_phase", Some(trace.clone()))
        .await?;
    let mut kb = KnowledgeBase::new();
    kb.add_fact(Fact::new("quantum_system", vec!["QS1".to_string()]));
    kb.add_rule(Rule::new(
        vec![Fact::new("quantum_system", vec!["X".to_string()])],
        Fact::new("advanced_system", vec!["X".to_string()]),
    ));

    let mut engine = InferenceEngine::new(kb);
    let query = Fact::new("advanced_system", vec!["QS1".to_string()]);
    let proven = engine.prove(&query)?;
    observer.end_span(reasoning_span).await?;
    debug!("  Reasoning result: {}", proven);

    // End workflow trace
    observer.end_span(trace).await?;

    // Record success metric
    observer
        .record_metric(Metric::counter("workflow.completed", 1.0))
        .await?;

    info!("   ✓ Integrated workflow completed successfully");

    Ok(())
}

