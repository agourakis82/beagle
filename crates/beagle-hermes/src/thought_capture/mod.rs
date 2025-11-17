//! Thought capture and processing pipeline

mod processor;
mod whisper;

pub use processor::{ThoughtProcessor, ProcessedThought};
pub use whisper::WhisperTranscriber;

use crate::{ThoughtInput, ThoughtContext, Result};
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use uuid::Uuid;

/// Processed insight from thought capture
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Insight {
    pub id: Uuid,
    pub timestamp: DateTime<Utc>,
    pub content: String,
    pub context: ThoughtContext,
    pub source: InsightSource,
    pub concepts: Vec<String>,
    pub entities: Vec<Entity>,
    pub embeddings: Option<Vec<f32>>, // Optional for semantic search
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum InsightSource {
    VoiceCapture,
    TextInput,
    NotesImport,
    EmailCapture,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Entity {
    pub text: String,
    pub entity_type: EntityType,
    pub confidence: f64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum EntityType {
    Chemical,
    Disease,
    Protein,
    Gene,
    CellType,
    Tissue,
    Method,
    Device,
    Measurement,
    Other,
}

