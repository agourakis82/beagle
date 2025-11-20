//! Thought Capture Pipeline
//!
//! Real-time processing of voice notes and text insights:
//! 1. Voice → Whisper transcription
//! 2. Text → Concept extraction (spaCy)
//! 3. Concepts → Embeddings (sentence-transformers)
//! 4. Store → Neo4j knowledge graph

pub mod concept_extractor;
pub mod processor;
pub mod service;
pub mod whisper_client;

pub use concept_extractor::{ConceptExtractor, ConceptType, ExtractedConcept};
pub use processor::{ProcessedThought, ThoughtProcessor};
pub use service::ThoughtCaptureService;
pub use whisper_client::{WhisperClient, WhisperConfig};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Source of insight
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum InsightSource {
    Voice,        // Voice note (Siri, Watch, iPhone)
    Text,         // Manual text input
    Paper,        // Extracted from paper reading
    Conversation, // Chat with LLM
}

/// Captured thought/insight
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapturedInsight {
    pub id: Uuid,
    pub text: String,
    pub source: InsightSource,
    pub concepts: Vec<ExtractedConcept>,
    pub timestamp: DateTime<Utc>,
    pub metadata: InsightMetadata,
}

/// Metadata for insight
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct InsightMetadata {
    pub location: Option<String>,
    pub context: Option<String>, // What was user doing
    pub confidence: f64,         // Transcription confidence
    pub language: String,
}
