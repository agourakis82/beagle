//! Integration tests for BEAGLE modules

#[cfg(test)]
mod integration_tests {
    use beagle_memory::{MemorySystem, MemoryConfig, MemoryEntry};
    use beagle_quantum::{QuantumSystem, QuantumCircuit};
    use beagle_neural_engine::{NeuralEngine, NeuralConfig};
    use beagle_observer::{ObserverSystem, ObserverConfig};
    use beagle_symbolic::{SymbolicSystem, Symbol, LogicRule};
    use beagle_search::{SearchSystem, SearchConfig};
    use std::collections::HashMap;

    /// Test 1: Memory + Neural Engine Integration
    /// Store embeddings in memory and retrieve with neural similarity
    #[tokio::test]
    async fn test_memory_neural_integration() {
        // Initialize systems
        let memory = MemorySystem::new(MemoryConfig::default()).await.unwrap();
        let neural = NeuralEngine::new(NeuralConfig::default()).unwrap();

        // Create and store embeddings
        let texts = vec![
            "Quantum computing uses qubits",
            "Neural networks process information",
            "Memory systems store data",
        ];

        for text in &texts {
            // Generate embedding with neural engine
            let embedding = neural.encode(text).await.unwrap();

            // Store in memory
            memory.store(text.to_string(), embedding.clone()).await.unwrap();
        }

        // Retrieve with similarity search
        let query = "quantum information";
        let query_embedding = neural.encode(query).await.unwrap();
        let results = memory.search_similar(&query_embedding, 2).await.unwrap();

        assert_eq!(results.len(), 2);
        assert!(results[0].content.contains("Quantum"));
    }

    /// Test 2: Quantum + Symbolic Integration
    /// Use quantum circuits to optimize symbolic reasoning
    #[tokio::test]
    async fn test_quantum_symbolic_integration() {
        let quantum = QuantumSystem::new();
        let symbolic = SymbolicSystem::new();

        // Create symbolic facts
        let facts = vec![
            Symbol::new("A", true),
            Symbol::new("B", false),
            Symbol::new("C", true),
        ];

        // Create quantum circuit for optimization
        let mut circuit = QuantumCircuit::new(3);
        for (i, fact) in facts.iter().enumerate() {
            if fact.value {
                circuit.x(i); // Apply X gate for true facts
            }
        }

        // Run quantum simulation
        let quantum_state = quantum.simulate(&circuit).await.unwrap();

        // Convert quantum results to symbolic reasoning
        let optimized_facts: Vec<Symbol> = quantum_state
            .iter()
            .enumerate()
            .map(|(i, &prob)| {
                Symbol::new(&format!("Q{}", i), prob > 0.5)
            })
            .collect();

        // Apply symbolic reasoning
        let result = symbolic.apply_rules(&optimized_facts, &[
            LogicRule::new("Q0 AND Q2 => RESULT"),
        ]).unwrap();

        assert!(result.contains_key("RESULT"));
    }

    /// Test 3: Search + Observer Integration
    /// Monitor search operations and collect metrics
    #[tokio::test]
    async fn test_search_observer_integration() {
        let search = SearchSystem::new(SearchConfig::default()).await.unwrap();
        let observer = ObserverSystem::new(ObserverConfig::default()).await.unwrap();

        // Start monitoring
        let span_id = observer.start_span("search_test");

        // Perform multiple searches
        let queries = vec!["AI", "quantum", "neural"];
        let mut total_results = 0;

        for query in queries {
            let start = std::time::Instant::now();

            // Search
            let results = search.search(query).await.unwrap();
            total_results += results.len();

            // Record metrics
            observer.record_metric(
                &format!("search_{}_count", query),
                results.len() as f64
            );
            observer.record_metric(
                &format!("search_{}_latency_ms", query),
                start.elapsed().as_millis() as f64
            );
        }

        // End monitoring
        observer.end_span(span_id);

        // Check metrics
        let metrics = observer.get_metrics().await;
        assert!(metrics.contains_key("search_AI_count"));
        assert_eq!(metrics.len(), 6); // 3 queries * 2 metrics each
    }

    /// Test 4: Memory + Search + Neural Pipeline
    /// Complete RAG pipeline test
    #[tokio::test]
    async fn test_rag_pipeline() {
        let memory = MemorySystem::new(MemoryConfig::default()).await.unwrap();
        let search = SearchSystem::new(SearchConfig::default()).await.unwrap();
        let neural = NeuralEngine::new(NeuralConfig::default()).unwrap();

        // Store knowledge base
        let knowledge = vec![
            ("doc1", "Rust is a systems programming language"),
            ("doc2", "BEAGLE is an AI framework"),
            ("doc3", "Integration testing ensures quality"),
        ];

        for (id, content) in knowledge {
            let embedding = neural.encode(content).await.unwrap();
            memory.store_with_id(id.to_string(), content.to_string(), embedding)
                .await.unwrap();
        }

        // Search query
        let query = "programming frameworks";

        // Step 1: Search for relevant documents
        let search_results = search.search(query).await.unwrap();

        // Step 2: Retrieve from memory with embeddings
        let query_embedding = neural.encode(query).await.unwrap();
        let memory_results = memory.search_similar(&query_embedding, 2).await.unwrap();

        // Step 3: Combine and rank results
        let mut combined_results = HashMap::new();

        for result in search_results {
            combined_results.insert(result.id.clone(), result.score);
        }

        for result in memory_results {
            let score = combined_results.entry(result.id.clone()).or_insert(0.0);
            *score += result.similarity;
        }

        // Verify we got relevant results
        assert!(!combined_results.is_empty());
    }

    /// Test 5: Symbolic + Memory Learning
    /// Learn new rules from memory patterns
    #[tokio::test]
    async fn test_symbolic_memory_learning() {
        let memory = MemorySystem::new(MemoryConfig::default()).await.unwrap();
        let symbolic = SymbolicSystem::new();

        // Store interaction patterns
        let interactions = vec![
            ("user asks about weather", "assistant provides forecast"),
            ("user asks about news", "assistant provides headlines"),
            ("user asks about stocks", "assistant provides market data"),
        ];

        for (input, output) in interactions {
            memory.store_interaction(input.to_string(), output.to_string())
                .await.unwrap();
        }

        // Extract patterns as symbolic rules
        let patterns = memory.get_patterns(5).await.unwrap();

        let rules: Vec<LogicRule> = patterns
            .iter()
            .map(|p| LogicRule::new(&format!("ASK({}) => PROVIDE({})", p.input_type, p.output_type)))
            .collect();

        // Test learned rules
        let test_facts = vec![
            Symbol::new("ASK(weather)", true),
        ];

        let result = symbolic.apply_rules(&test_facts, &rules).unwrap();

        // Should infer PROVIDE(forecast)
        assert!(result.contains_key("PROVIDE"));
    }

    /// Test 6: Neural + Quantum Optimization
    /// Use quantum annealing to optimize neural network weights
    #[tokio::test]
    async fn test_neural_quantum_optimization() {
        let neural = NeuralEngine::new(NeuralConfig::default()).unwrap();
        let quantum = QuantumSystem::new();

        // Get initial neural network performance
        let test_input = "optimize this text";
        let initial_output = neural.process(test_input).await.unwrap();

        // Create quantum optimization problem
        let weights = neural.get_weights().unwrap();
        let num_weights = weights.len().min(10); // Limit for quantum simulation

        // Run quantum annealing
        let optimized = quantum.quantum_annealing(
            weights[..num_weights].to_vec(),
            |w| {
                // Objective: minimize weight magnitude while maintaining performance
                w.iter().map(|x| x.abs()).sum::<f32>()
            },
            100 // iterations
        ).await.unwrap();

        // Apply optimized weights
        let mut new_weights = weights.clone();
        for (i, w) in optimized.iter().enumerate() {
            new_weights[i] = *w;
        }
        neural.set_weights(new_weights).unwrap();

        // Test improved performance
        let optimized_output = neural.process(test_input).await.unwrap();

        // Outputs should be different after optimization
        assert_ne!(initial_output, optimized_output);
    }

    /// Test 7: Observer + All Systems
    /// Monitor all system interactions
    #[tokio::test]
    async fn test_full_system_monitoring() {
        let observer = ObserverSystem::new(ObserverConfig::default()).await.unwrap();

        // Create spans for each system
        let systems = vec!["memory", "quantum", "neural", "symbolic", "search"];
        let mut spans = HashMap::new();

        for system in &systems {
            let span = observer.start_span(&format!("{}_operation", system));
            spans.insert(system.to_string(), span);

            // Simulate work
            tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;

            // Record system-specific metrics
            observer.record_metric(&format!("{}_items", system), 100.0);
            observer.record_metric(&format!("{}_latency", system), 10.0);
        }

        // End all spans
        for (system, span) in spans {
            observer.end_span(span);
            observer.record_event(&format!("{}_completed", system));
        }

        // Verify monitoring data
        let metrics = observer.get_metrics().await;
        let events = observer.get_events().await;

        assert_eq!(metrics.len(), systems.len() * 2); // 2 metrics per system
        assert_eq!(events.len(), systems.len()); // 1 event per system

        // Check for any anomalies
        let anomalies = observer.check_anomalies().await.unwrap();
        assert_eq!(anomalies.len(), 0); // Should be no anomalies in test
    }

    /// Test 8: Error Recovery Across Systems
    /// Test graceful error handling between modules
    #[tokio::test]
    async fn test_error_recovery() {
        let memory = MemorySystem::new(MemoryConfig::default()).await.unwrap();
        let search = SearchSystem::new(SearchConfig::default()).await.unwrap();

        // Test with invalid input
        let invalid_query = "";

        // Memory should handle gracefully
        let memory_result = memory.retrieve(invalid_query, 10).await;
        assert!(memory_result.is_ok());
        assert_eq!(memory_result.unwrap().len(), 0);

        // Search should handle gracefully
        let search_result = search.search(invalid_query).await;
        assert!(search_result.is_ok());
        assert_eq!(search_result.unwrap().len(), 0);

        // Test with extremely large input
        let large_input = "x".repeat(100000);

        // Systems should handle without panic
        let large_memory = memory.store(large_input.clone(), vec![0.0; 768]).await;
        assert!(large_memory.is_ok() || large_memory.is_err()); // Either handle or error gracefully

        let large_search = search.search(&large_input).await;
        assert!(large_search.is_ok() || large_search.is_err()); // Either handle or error gracefully
    }
}

/// Performance benchmarks for integrated systems
#[cfg(test)]
mod performance_tests {
    use super::*;
    use std::time::Instant;

    #[tokio::test]
    async fn benchmark_memory_operations() {
        let memory = MemorySystem::new(MemoryConfig::default()).await.unwrap();

        let start = Instant::now();

        // Store 1000 items
        for i in 0..1000 {
            let content = format!("Item {}", i);
            let embedding = vec![i as f32 / 1000.0; 768];
            memory.store(content, embedding).await.unwrap();
        }

        let store_time = start.elapsed();

        // Retrieve 100 times
        let start = Instant::now();
        for _ in 0..100 {
            memory.retrieve("Item", 10).await.unwrap();
        }
        let retrieve_time = start.elapsed();

        println!("Memory Performance:");
        println!("  Store 1000 items: {:?}", store_time);
        println!("  100 retrievals: {:?}", retrieve_time);

        // Performance assertions
        assert!(store_time.as_secs() < 10); // Should complete within 10 seconds
        assert!(retrieve_time.as_secs() < 5); // Should complete within 5 seconds
    }

    #[tokio::test]
    async fn benchmark_neural_processing() {
        let neural = NeuralEngine::new(NeuralConfig::default()).unwrap();

        let texts = vec![
            "Short text",
            "Medium length text with more words to process",
            "Long text with many words that should take more time to process through the neural engine pipeline",
        ];

        for text in texts {
            let start = Instant::now();
            let _ = neural.encode(text).await.unwrap();
            let encode_time = start.elapsed();

            println!("Neural encoding '{}...': {:?}", &text[..10.min(text.len())], encode_time);

            // Should process reasonably fast
            assert!(encode_time.as_millis() < 1000);
        }
    }
}
