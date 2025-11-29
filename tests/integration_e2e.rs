//! End-to-end integration tests for all BEAGLE modules

use anyhow::Result;
use std::time::Duration;
use tokio::time::timeout;

#[tokio::test]
async fn test_complete_rag_workflow() -> Result<()> {
    use beagle_memory::{RAGEngine, Document, QueryOptions};

    let mut rag = RAGEngine::new(128, 256, 50);

    // Add multiple documents
    let docs = vec![
        ("doc1", "Rust is a systems programming language focused on safety and performance."),
        ("doc2", "Python is popular for machine learning and data science applications."),
        ("doc3", "JavaScript runs in browsers and Node.js for web development."),
        ("doc4", "Rust provides memory safety without garbage collection."),
        ("doc5", "Machine learning models require large amounts of training data."),
    ];

    for (id, content) in docs {
        rag.add_document(Document {
            id: id.to_string(),
            content: content.to_string(),
            metadata: Default::default(),
            embeddings: None,
        }).await?;
    }

    // Test keyword search
    let results = rag.query("Rust safety", QueryOptions {
        k: 3,
        use_semantic: false,
        use_keyword: true,
        filters: Default::default(),
    }).await?;

    assert!(!results.is_empty());
    assert!(results[0].content.contains("Rust"));

    // Test semantic search
    let semantic_results = rag.query("programming language memory management", QueryOptions {
        k: 2,
        use_semantic: true,
        use_keyword: false,
        filters: Default::default(),
    }).await?;

    assert!(!semantic_results.is_empty());

    Ok(())
}

#[tokio::test]
async fn test_quantum_circuit_execution() -> Result<()> {
    use beagle_quantum::{QuantumSimulator, QuantumGate};

    // Test single qubit gates
    let mut sim = QuantumSimulator::new(1)?;
    sim.apply_gate(0, QuantumGate::X)?; // NOT gate
    let measurement = sim.measure(0)?;
    assert_eq!(measurement, 1); // Should be |1⟩

    // Test superposition
    let mut sim = QuantumSimulator::new(1)?;
    sim.apply_gate(0, QuantumGate::H)?; // Hadamard
    // Measurement should be 0 or 1 with equal probability
    let _ = sim.measure(0)?;

    // Test entanglement (Bell state)
    let mut sim = QuantumSimulator::new(2)?;
    sim.apply_gate(0, QuantumGate::H)?;
    sim.apply_controlled_gate(0, 1, QuantumGate::X)?;

    // Measure both qubits
    let q0 = sim.measure(0)?;
    let q1 = sim.measure(1)?;
    assert_eq!(q0, q1); // Should be correlated

    Ok(())
}

#[tokio::test]
async fn test_neural_transformer_processing() -> Result<()> {
    use beagle_neural_engine::{Transformer, TransformerConfig, TokenizerConfig};

    let config = TransformerConfig {
        vocab_size: 1000,
        hidden_dim: 128,
        num_heads: 4,
        num_layers: 2,
        max_seq_len: 64,
        dropout: 0.1,
    };

    let transformer = Transformer::new(config, TokenizerConfig::default())?;

    // Test tokenization
    let text = "Hello world";
    let tokens = transformer.tokenize(text)?;
    assert!(!tokens.is_empty());

    // Test encoding
    let encoded = transformer.encode(&tokens)?;
    assert_eq!(encoded.len(), tokens.len());

    // Test generation (with small parameters for testing)
    let generated = transformer.generate("Test", 5, 0.9)?;
    assert!(!generated.is_empty());

    Ok(())
}

#[tokio::test]
async fn test_symbolic_reasoning_chain() -> Result<()> {
    use beagle_symbolic::{InferenceEngine, KnowledgeBase, Rule, Fact};

    let mut kb = KnowledgeBase::new();

    // Create a reasoning chain
    kb.add_fact(Fact::new("bird", vec!["tweety".to_string()]));
    kb.add_fact(Fact::new("penguin", vec!["tux".to_string()]));

    // Birds can fly (default rule)
    kb.add_rule(Rule::new(
        vec![Fact::new("bird", vec!["X".to_string()])],
        Fact::new("can_fly", vec!["X".to_string()]),
    ));

    // Penguins are birds
    kb.add_rule(Rule::new(
        vec![Fact::new("penguin", vec!["X".to_string()])],
        Fact::new("bird", vec!["X".to_string()]),
    ));

    // Penguins cannot fly (exception)
    kb.add_rule(Rule::new(
        vec![Fact::new("penguin", vec!["X".to_string()])],
        Fact::new("cannot_fly", vec!["X".to_string()]),
    ));

    let mut engine = InferenceEngine::new(kb);

    // Test normal bird
    assert!(engine.prove(&Fact::new("can_fly", vec!["tweety".to_string()]))?);

    // Test penguin is a bird
    assert!(engine.prove(&Fact::new("bird", vec!["tux".to_string()]))?);

    // Test penguin cannot fly
    assert!(engine.prove(&Fact::new("cannot_fly", vec!["tux".to_string()]))?);

    Ok(())
}

#[tokio::test]
async fn test_search_engine_ranking() -> Result<()> {
    use beagle_search::{SearchEngine, SearchQuery, Document};

    let mut engine = SearchEngine::new(1.2, 0.75);

    // Index documents with different relevance
    let docs = vec![
        ("Rust programming language guide", "rust", 5.0),
        ("Introduction to Rust", "rust", 4.0),
        ("Advanced Rust patterns", "rust", 4.5),
        ("Python vs Rust comparison", "comparison", 3.0),
        ("C++ programming basics", "cpp", 2.0),
    ];

    for (i, (content, tag, _score)) in docs.iter().enumerate() {
        let mut doc = Document::new(content);
        doc.id = format!("doc{}", i);
        doc.add_metadata("tag", tag);
        engine.index_document(doc).await?;
    }

    // Search for Rust
    let results = engine.search(&SearchQuery::new("Rust programming")).await?;

    assert!(!results.is_empty());
    assert!(results[0].score > 0.0);

    // The most relevant document should be ranked first
    assert!(results[0].content.contains("Rust"));

    // Test faceted search
    let facets = engine.get_facets("tag").await?;
    assert!(facets.contains_key("rust"));
    assert_eq!(facets["rust"], 3);

    Ok(())
}

#[tokio::test]
async fn test_observer_metrics_collection() -> Result<()> {
    use beagle_observer::{SystemObserver, ObserverConfig, Metric, TimeWindow};

    let config = ObserverConfig::default();
    let observer = SystemObserver::new(config).await?;

    // Record various metrics
    for i in 0..10 {
        observer.record_metric(Metric::gauge("test.gauge", i as f64)).await?;
        observer.record_metric(Metric::counter("test.counter", 1.0)).await?;

        if i % 2 == 0 {
            observer.record_metric(
                Metric::histogram("test.histogram", vec![i as f64, (i * 2) as f64])
            ).await?;
        }
    }

    // Get metrics summary
    let summary = observer.get_metrics_summary(TimeWindow::Minutes(5)).await?;
    assert!(summary.total_metrics > 0);

    // Test distributed tracing
    let root_span = observer.start_span("root_operation", None).await?;
    let child_span = observer.start_span("child_operation", Some(root_span.clone())).await?;

    tokio::time::sleep(Duration::from_millis(10)).await;

    observer.end_span(child_span).await?;
    observer.end_span(root_span).await?;

    // Get traces
    let traces = observer.get_traces(10).await?;
    assert!(!traces.is_empty());

    Ok(())
}

#[tokio::test]
async fn test_integrated_workflow_stress() -> Result<()> {
    use beagle_memory::RAGEngine;
    use beagle_search::SearchEngine;
    use beagle_observer::{SystemObserver, ObserverConfig};

    // This test simulates a more realistic workload
    let observer = SystemObserver::new(ObserverConfig::default()).await?;
    let mut rag = RAGEngine::new(256, 512, 100);
    let mut search = SearchEngine::new(1.2, 0.75);

    // Start main trace
    let trace = observer.start_span("stress_test", None).await?;

    // Simulate document ingestion
    let ingest_span = observer.start_span("document_ingestion", Some(trace.clone())).await?;

    for i in 0..50 {
        let doc = beagle_memory::Document {
            id: format!("doc_{}", i),
            content: format!("Document {} contains information about topic {}", i, i % 10),
            metadata: Default::default(),
            embeddings: None,
        };

        rag.add_document(doc.clone()).await?;

        // Also index in search
        let search_doc = beagle_search::Document::new(&doc.content);
        search.index_document(search_doc).await?;

        if i % 10 == 0 {
            observer.record_metric(
                beagle_observer::Metric::counter("docs.processed", 10.0)
            ).await?;
        }
    }

    observer.end_span(ingest_span).await?;

    // Simulate queries
    let query_span = observer.start_span("query_processing", Some(trace.clone())).await?;

    for i in 0..10 {
        let query = format!("topic {}", i);

        // RAG query
        let rag_results = rag.query(&query, beagle_memory::QueryOptions {
            k: 5,
            use_semantic: true,
            use_keyword: true,
            filters: Default::default(),
        }).await?;

        // Search query
        let search_results = search.search(
            &beagle_search::SearchQuery::new(&query)
        ).await?;

        assert!(!rag_results.is_empty() || !search_results.is_empty());
    }

    observer.end_span(query_span).await?;
    observer.end_span(trace).await?;

    // Verify metrics were collected
    let summary = observer.get_metrics_summary(
        beagle_observer::TimeWindow::Minutes(1)
    ).await?;

    assert!(summary.total_metrics > 0);

    Ok(())
}

#[tokio::test]
async fn test_error_handling_and_recovery() -> Result<()> {
    use beagle_quantum::QuantumSimulator;
    use beagle_symbolic::{InferenceEngine, KnowledgeBase, Fact};

    // Test quantum simulator with invalid operations
    let sim = QuantumSimulator::new(2)?;
    // Trying to apply gate to non-existent qubit should fail gracefully
    assert!(matches!(sim.apply_gate(5, beagle_quantum::QuantumGate::H), Err(_)));

    // Test inference engine with empty knowledge base
    let kb = KnowledgeBase::new();
    let mut engine = InferenceEngine::new(kb);
    let query = Fact::new("unknown", vec!["X".to_string()]);

    // Should return false, not panic
    assert!(!engine.prove(&query)?);

    Ok(())
}

#[tokio::test]
async fn test_concurrent_operations() -> Result<()> {
    use beagle_memory::RAGEngine;
    use beagle_search::SearchEngine;
    use std::sync::Arc;
    use tokio::sync::RwLock;

    let rag = Arc::new(RwLock::new(RAGEngine::new(128, 256, 50)));
    let search = Arc::new(RwLock::new(SearchEngine::new(1.2, 0.75)));

    // Spawn multiple concurrent tasks
    let mut handles = vec![];

    for i in 0..10 {
        let rag_clone = rag.clone();
        let search_clone = search.clone();

        let handle = tokio::spawn(async move {
            // Add document to RAG
            let doc = beagle_memory::Document {
                id: format!("concurrent_{}", i),
                content: format!("Concurrent document {}", i),
                metadata: Default::default(),
                embeddings: None,
            };

            rag_clone.write().await.add_document(doc).await.unwrap();

            // Add to search
            let search_doc = beagle_search::Document::new(&format!("Concurrent search {}", i));
            search_clone.write().await.index_document(search_doc).await.unwrap();
        });

        handles.push(handle);
    }

    // Wait for all tasks
    for handle in handles {
        handle.await?;
    }

    // Verify all documents were added
    let rag_lock = rag.read().await;
    let results = rag_lock.query("Concurrent", beagle_memory::QueryOptions {
        k: 20,
        use_semantic: false,
        use_keyword: true,
        filters: Default::default(),
    }).await?;

    assert_eq!(results.len(), 10);

    Ok(())
}

#[tokio::test]
async fn test_performance_benchmarks() -> Result<()> {
    use std::time::Instant;
    use beagle_memory::RAGEngine;
    use beagle_search::SearchEngine;

    let mut rag = RAGEngine::new(128, 256, 100);
    let mut search = SearchEngine::new(1.2, 0.75);

    // Benchmark document ingestion
    let start = Instant::now();
    for i in 0..100 {
        let doc = beagle_memory::Document {
            id: format!("perf_{}", i),
            content: format!("Performance test document {}", i),
            metadata: Default::default(),
            embeddings: None,
        };
        rag.add_document(doc).await?;
    }
    let ingest_time = start.elapsed();

    // Should complete in reasonable time (< 5 seconds for 100 docs)
    assert!(ingest_time < Duration::from_secs(5));

    // Benchmark search
    let start = Instant::now();
    for _ in 0..50 {
        let _ = search.search(&beagle_search::SearchQuery::new("test")).await?;
    }
    let search_time = start.elapsed();

    // Should complete quickly (< 2 seconds for 50 searches)
    assert!(search_time < Duration::from_secs(2));

    println!("Performance: Ingestion={:?}, Search={:?}", ingest_time, search_time);

    Ok(())
}

/// Test that all modules can be initialized and work together
#[tokio::test]
async fn test_all_modules_integration() -> Result<()> {
    // Ensure all modules can be initialized
    let _ = beagle_memory::RAGEngine::new(128, 256, 50);
    let _ = beagle_quantum::QuantumSimulator::new(2)?;
    let _ = beagle_neural_engine::Transformer::new(
        beagle_neural_engine::TransformerConfig {
            vocab_size: 1000,
            hidden_dim: 128,
            num_heads: 4,
            num_layers: 2,
            max_seq_len: 64,
            dropout: 0.1,
        },
        beagle_neural_engine::TokenizerConfig::default(),
    )?;
    let _ = beagle_symbolic::InferenceEngine::new(beagle_symbolic::KnowledgeBase::new());
    let _ = beagle_search::SearchEngine::new(1.2, 0.75);
    let _ = beagle_observer::SystemObserver::new(
        beagle_observer::ObserverConfig::default()
    ).await?;

    // All modules initialized successfully
    Ok(())
}
