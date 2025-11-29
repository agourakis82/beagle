//! Extended application state with all integrated modules

use anyhow::Result;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Extended application state including all new modules
pub struct ExtendedAppState {
    // RAG/Memory system
    pub rag_engine: Arc<RwLock<beagle_memory::RAGEngine>>,

    // Search engine
    pub search_engine: Arc<RwLock<beagle_search::SearchEngine>>,

    // Neural transformer
    pub transformer: Arc<beagle_neural_engine::Transformer>,

    // Observer/monitoring
    pub observer: Arc<beagle_observer::SystemObserver>,
}

impl ExtendedAppState {
    /// Create extended state with all modules
    pub async fn new() -> Result<Self> {
        // Initialize RAG engine
        let rag_engine = Arc::new(RwLock::new(beagle_memory::RAGEngine::new(512, 1024, 100)));

        // Initialize search engine
        let search_engine = Arc::new(RwLock::new(beagle_search::SearchEngine::new(1.2, 0.75)));

        // Initialize transformer
        let config = beagle_neural_engine::TransformerConfig {
            vocab_size: 30000,
            hidden_dim: 768,
            num_heads: 12,
            num_layers: 6,
            max_seq_len: 512,
            dropout: 0.1,
        };
        let transformer = Arc::new(beagle_neural_engine::Transformer::new(
            config,
            beagle_neural_engine::TokenizerConfig::default(),
        )?);

        // Initialize observer
        let observer = Arc::new(
            beagle_observer::SystemObserver::new(beagle_observer::ObserverConfig::default())
                .await?,
        );

        Ok(Self {
            rag_engine,
            search_engine,
            transformer,
            observer,
        })
    }
}
