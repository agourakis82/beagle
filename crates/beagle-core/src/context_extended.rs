//! Extended BeagleContext with new module integrations

use std::sync::Arc;
use anyhow::Result;
use beagle_memory::MemorySystem;
use beagle_quantum::QuantumSystem;
use beagle_neural_engine::NeuralEngine;
use beagle_observer::ObserverSystem;
use beagle_symbolic::SymbolicSystem;
use beagle_search::SearchSystem;
use beagle_twitter::TwitterSystem;

/// Extended context with all new modules
pub struct BeagleContextExtended {
    /// Memory system with RAG
    pub memory: Arc<MemorySystem>,

    /// Quantum computing system
    pub quantum: Arc<QuantumSystem>,

    /// Neural engine with transformers
    pub neural: Arc<NeuralEngine>,

    /// System observer for monitoring
    pub observer: Arc<ObserverSystem>,

    /// Symbolic reasoning system
    pub symbolic: Arc<SymbolicSystem>,

    /// Advanced search system
    pub search: Arc<SearchSystem>,

    /// Twitter/X integration
    pub twitter: Option<Arc<TwitterSystem>>,
}

impl BeagleContextExtended {
    /// Create extended context with all modules
    pub async fn new() -> Result<Self> {
        // Initialize memory system
        let memory_config = beagle_memory::MemoryConfig::default();
        let memory = Arc::new(MemorySystem::new(memory_config).await?);

        // Initialize quantum system
        let quantum = Arc::new(QuantumSystem::new());

        // Initialize neural engine
        let neural_config = beagle_neural_engine::NeuralConfig::default();
        let neural = Arc::new(NeuralEngine::new(neural_config)?);

        // Initialize observer
        let observer_config = beagle_observer::ObserverConfig::default();
        let observer = Arc::new(ObserverSystem::new(observer_config).await?);

        // Initialize symbolic system
        let symbolic = Arc::new(SymbolicSystem::new());

        // Initialize search system
        let search_config = beagle_search::SearchConfig::default();
        let search = Arc::new(SearchSystem::new(search_config).await?);

        Ok(Self {
            memory,
            quantum,
            neural,
            observer,
            symbolic,
            search,
            twitter: None, // Requires API credentials
        })
    }

    /// Initialize Twitter integration with credentials
    pub async fn init_twitter(&mut self, api_key: String, api_secret: String) -> Result<()> {
        let twitter_config = beagle_twitter::TwitterConfig {
            api_key: api_key.clone(),
            api_secret: api_secret.clone(),
            access_token: None,
            access_secret: None,
            bearer_token: Some(format!("Bearer {}", api_key)),
        };

        self.twitter = Some(Arc::new(TwitterSystem::new(twitter_config).await?));
        Ok(())
    }

    /// Example: Use memory with quantum optimization
    pub async fn quantum_enhanced_retrieval(&self, query: &str) -> Result<Vec<String>> {
        // Retrieve from memory
        let memories = self.memory.retrieve(query, 10).await?;

        // Use quantum for similarity optimization
        let quantum_result = self.quantum.run_grover_search(
            memories.len(),
            |idx| memories[idx].content.contains(query)
        ).await?;

        // Return optimized results
        Ok(memories.into_iter()
            .enumerate()
            .filter(|(idx, _)| quantum_result.contains(idx))
            .map(|(_, m)| m.content)
            .collect())
    }

    /// Example: Neural-symbolic reasoning
    pub async fn neural_symbolic_reasoning(&self, input: &str) -> Result<String> {
        // Extract features with neural engine
        let embeddings = self.neural.encode(input).await?;

        // Convert to symbolic representation
        let symbols = self.symbolic.extract_symbols(&embeddings)?;

        // Perform reasoning
        let result = self.symbolic.reason(&symbols)?;

        // Generate response
        Ok(self.neural.decode(&result).await?)
    }

    /// Example: Monitored search
    pub async fn monitored_search(&self, query: &str) -> Result<Vec<String>> {
        // Start monitoring
        let span = self.observer.start_span("search_operation");

        // Perform search
        let results = self.search.search(query).await?;

        // Record metrics
        self.observer.record_metric("search_results_count", results.len() as f64);

        // End monitoring
        self.observer.end_span(span);

        Ok(results.into_iter().map(|r| r.title).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_extended_context_creation() {
        let context = BeagleContextExtended::new().await;
        assert!(context.is_ok());
    }
}
