//! HERMES Background Paper Synthesis Engine (BPSE)
//!
//! Autonomous system for continuous thought capture and paper synthesis.
//!
//! # Architecture
//!
//! ```text
//! Voice/Text → Thought Capture → Knowledge Graph → Synthesis → Manuscript
//! ```

pub mod thought_capture;
pub mod knowledge;
pub mod synthesis;
pub mod manuscript;
pub mod error;
pub mod agents;

pub use error::{HermesError, Result};

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

/// HERMES engine configuration
#[derive(Debug, Clone)]
pub struct HermesConfig {
    pub neo4j_uri: String,
    pub neo4j_user: String,
    pub neo4j_password: String,
    pub postgres_uri: String,
    pub redis_uri: String,
    pub whisper_model_path: String,
    pub synthesis_schedule: String, // cron expression
    pub min_insights_for_synthesis: usize, // default: 20
}

impl Default for HermesConfig {
    fn default() -> Self {
        Self {
            neo4j_uri: std::env::var("NEO4J_URI")
                .unwrap_or_else(|_| "neo4j://localhost:7687".to_string()),
            neo4j_user: std::env::var("NEO4J_USER")
                .unwrap_or_else(|_| "neo4j".to_string()),
            neo4j_password: std::env::var("NEO4J_PASSWORD")
                .unwrap_or_else(|_| "password".to_string()),
            postgres_uri: std::env::var("DATABASE_URL")
                .unwrap_or_else(|_| "postgresql://postgres:postgres@localhost:5432/beagle".to_string()),
            redis_uri: std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://localhost:6379".to_string()),
            whisper_model_path: std::env::var("WHISPER_MODEL")
                .unwrap_or_else(|_| "models/whisper-base.en".to_string()),
            synthesis_schedule: "0 0 */6 * * *".to_string(), // every 6 hours
            min_insights_for_synthesis: 20,
        }
    }
}

/// HERMES engine instance
pub struct HermesEngine {
    config: HermesConfig,
    thought_processor: thought_capture::ThoughtProcessor,
    knowledge_graph: knowledge::KnowledgeGraph,
    synthesis_engine: synthesis::SynthesisEngine,
    manuscript_manager: manuscript::ManuscriptManager,
}

impl HermesEngine {
    /// Initialize HERMES engine
    pub async fn new(config: HermesConfig) -> Result<Self> {
        let thought_processor = thought_capture::ThoughtProcessor::new(&config).await?;
        let knowledge_graph = knowledge::KnowledgeGraph::new(
            &config.neo4j_uri,
            &config.neo4j_user,
            &config.neo4j_password,
        ).await?;
        let synthesis_engine = synthesis::SynthesisEngine::new(&config).await?;
        let manuscript_manager = manuscript::ManuscriptManager::new(&config.postgres_uri).await?;

        Ok(Self {
            config,
            thought_processor,
            knowledge_graph,
            synthesis_engine,
            manuscript_manager,
        })
    }

    /// Start background synthesis scheduler
    pub async fn start_scheduler(&self) -> Result<()> {
        use synthesis::SynthesisScheduler;
        let scheduler = SynthesisScheduler::new(
            &self.config,
            self.synthesis_engine.clone(),
            self.knowledge_graph.clone(),
        ).await?;
        scheduler.start().await
    }

    /// Capture a thought (voice or text)
    pub async fn capture_thought(&self, input: ThoughtInput) -> Result<InsightId> {
        // 1. Process thought (transcribe if voice, extract concepts)
        let insight = self.thought_processor.process(input).await?;

        // 2. Store in knowledge graph
        let insight_id = self.knowledge_graph.store_insight(&insight).await?;

        // 3. Check if synthesis should be triggered
        self.synthesis_engine.check_trigger(&insight_id, &self.knowledge_graph).await?;

        Ok(insight_id)
    }

    /// Get manuscript status
    pub async fn get_manuscript_status(&self, paper_id: &str) -> Result<ManuscriptStatus> {
        self.manuscript_manager.get_status(paper_id).await
    }
}

/// Thought input (voice or text)
#[derive(Debug, Clone)]
pub enum ThoughtInput {
    Voice { audio_data: Vec<u8>, sample_rate: u32 },
    Text { content: String, context: ThoughtContext },
}

/// Thought context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ThoughtContext {
    ClinicalObservation,
    LabExperiment,
    LiteratureReview,
    DataAnalysis,
    Hypothesis,
    Discussion,
    Other(String),
}

/// Insight ID (UUID)
pub type InsightId = Uuid;

/// Manuscript status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManuscriptStatus {
    pub paper_id: String,
    pub title: String,
    pub sections: Vec<SectionStatus>,
    pub overall_completion: f64,
    pub last_updated: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SectionStatus {
    pub section_type: SectionType,
    pub completion: f64,
    pub word_count: usize,
    pub has_new_draft: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum SectionType {
    Abstract,
    Introduction,
    Methods,
    Results,
    Discussion,
    Conclusion,
}
