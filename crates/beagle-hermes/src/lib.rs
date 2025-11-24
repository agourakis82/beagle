//! HERMES Background Paper Synthesis Engine (BPSE)
//!
//! Autonomous system for continuous thought capture and paper synthesis.
//!
//! # Architecture
//!
//! ```text
//! Voice/Text → Thought Capture → Knowledge Graph → Synthesis → Manuscript
//! ```

pub mod adversarial;
pub mod agents;
pub mod citations;
pub mod editor;
pub mod error;
pub mod knowledge;
pub mod manuscript;
pub mod observability;
pub mod optimization;
pub mod scheduler;
pub mod security;
pub mod synthesis;
pub mod thought_capture;
pub mod voice;

pub use error::{HermesError, Result};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// HERMES engine configuration
#[derive(Debug, Clone)]
pub struct HermesConfig {
    pub neo4j_uri: String,
    pub neo4j_user: String,
    pub neo4j_password: String,
    pub postgres_uri: String,
    pub redis_uri: String,
    pub whisper_model_path: String,
    pub synthesis_schedule: String,        // cron expression
    pub min_insights_for_synthesis: usize, // default: 20
}

impl Default for HermesConfig {
    fn default() -> Self {
        Self {
            neo4j_uri: std::env::var("NEO4J_URI")
                .unwrap_or_else(|_| "neo4j://localhost:7687".to_string()),
            neo4j_user: std::env::var("NEO4J_USER").unwrap_or_else(|_| "neo4j".to_string()),
            neo4j_password: std::env::var("NEO4J_PASSWORD")
                .unwrap_or_else(|_| "password".to_string()),
            postgres_uri: std::env::var("DATABASE_URL").unwrap_or_else(|_| {
                "postgresql://postgres:postgres@localhost:5432/beagle".to_string()
            }),
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
    thought_capture_service: thought_capture::ThoughtCaptureService,
    knowledge_graph: knowledge::KnowledgeGraph,
    synthesis_engine: synthesis::SynthesisEngine,
    manuscript_manager: manuscript::ManuscriptManager,
    /// Opcional: BeagleContext para reutilizar LLM/Graph/Vector stores
    beagle_ctx: Option<std::sync::Arc<beagle_core::BeagleContext>>,
}

impl HermesEngine {
    /// Initialize HERMES engine
    pub async fn new(config: HermesConfig) -> Result<Self> {
        let whisper_config = thought_capture::WhisperConfig::default();
        let thought_capture_service = thought_capture::ThoughtCaptureService::new(whisper_config)?;
        let knowledge_graph = knowledge::KnowledgeGraph::new(
            &config.neo4j_uri,
            &config.neo4j_user,
            &config.neo4j_password,
        )
        .await?;
        let synthesis_engine = synthesis::SynthesisEngine::new(&config).await?;
        let manuscript_manager = manuscript::ManuscriptManager::new(&config.postgres_uri).await?;

        Ok(Self {
            config,
            thought_capture_service,
            knowledge_graph,
            synthesis_engine,
            manuscript_manager,
            beagle_ctx: None,
        })
    }

    /// Initialize HERMES engine com BeagleContext (reutiliza LLM/Graph/Vector stores)
    pub async fn with_context(
        config: HermesConfig,
        ctx: std::sync::Arc<beagle_core::BeagleContext>,
    ) -> Result<Self> {
        let whisper_config = thought_capture::WhisperConfig::default();
        let thought_capture_service = thought_capture::ThoughtCaptureService::new(whisper_config)?;

        // Por enquanto, mantém KnowledgeGraph original para compatibilidade
        // O KnowledgeGraphWrapper está disponível para uso futuro quando
        // todos os métodos de KnowledgeGraph forem migrados para usar GraphStore trait
        let knowledge_graph = knowledge::KnowledgeGraph::new(
            &config.neo4j_uri,
            &config.neo4j_user,
            &config.neo4j_password,
        )
        .await?;

        let synthesis_engine = synthesis::SynthesisEngine::new(&config).await?;
        let manuscript_manager = manuscript::ManuscriptManager::new(&config.postgres_uri).await?;

        Ok(Self {
            config,
            thought_capture_service,
            knowledge_graph,
            synthesis_engine,
            manuscript_manager,
            beagle_ctx: Some(ctx),
        })
    }

    /// Start background synthesis scheduler
    pub async fn start_scheduler(&mut self) -> Result<()> {
        use scheduler::SynthesisScheduler;
        use std::sync::Arc;

        let graph_client = Arc::new(self.knowledge_graph.clone());
        let orchestrator = Arc::new(self.synthesis_engine.clone());

        let mut scheduler =
            SynthesisScheduler::new(&self.config, graph_client, orchestrator).await?;
        scheduler.start().await
    }

    /// Capture a thought (voice or text)
    pub async fn capture_thought(&self, input: ThoughtInput) -> Result<InsightId> {
        // 1. Process thought (transcribe if voice, extract concepts)
        let processed_thought = match input {
            ThoughtInput::Voice { audio_data, .. } => {
                self.thought_capture_service
                    .process_voice_bytes(&audio_data)
                    .await?
            }
            ThoughtInput::Text { content, .. } => {
                self.thought_capture_service.process_text_insight(content)?
            }
        };

        let metadata = thought_capture::InsightMetadata {
            confidence: processed_thought.confidence,
            ..Default::default()
        };
        let captured_insight = processed_thought.to_captured_insight(metadata);

        // 2. Store in knowledge graph
        let insight_id = self
            .knowledge_graph
            .store_insight(&captured_insight)
            .await?;

        // 3. Check if synthesis should be triggered
        self.synthesis_engine
            .check_trigger(&insight_id, &self.knowledge_graph)
            .await?;

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
    Voice {
        audio_data: Vec<u8>,
        sample_rate: u32,
    },
    Text {
        content: String,
        context: ThoughtContext,
    },
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
    pub state: Option<String>, // Optional for backward compatibility
    pub state_last_transition: Option<DateTime<Utc>>, // Optional for backward compatibility
    pub sections: Vec<SectionStatus>,
    pub overall_completion: f64,
    pub last_updated: DateTime<Utc>,
    pub completed_sections: Option<usize>, // Optional for backward compatibility
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SectionStatus {
    pub section_type: SectionType,
    pub completion: f64,
    pub word_count: usize,
    pub has_new_draft: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum SectionType {
    Abstract,
    Introduction,
    Methods,
    Results,
    Discussion,
    Conclusion,
}

impl SectionType {
    pub const fn all() -> [SectionType; 6] {
        [
            SectionType::Abstract,
            SectionType::Introduction,
            SectionType::Methods,
            SectionType::Results,
            SectionType::Discussion,
            SectionType::Conclusion,
        ]
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            SectionType::Abstract => "abstract",
            SectionType::Introduction => "introduction",
            SectionType::Methods => "methods",
            SectionType::Results => "results",
            SectionType::Discussion => "discussion",
            SectionType::Conclusion => "conclusion",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "abstract" => Some(SectionType::Abstract),
            "introduction" => Some(SectionType::Introduction),
            "methods" => Some(SectionType::Methods),
            "results" => Some(SectionType::Results),
            "discussion" => Some(SectionType::Discussion),
            "conclusion" => Some(SectionType::Conclusion),
            _ => None,
        }
    }
}
