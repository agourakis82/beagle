//! Thought processor for voice and text inputs

use super::{Insight, InsightSource, Entity, EntityType, WhisperTranscriber};
use crate::{HermesConfig, ThoughtInput, Result, HermesError};
use pyo3::prelude::*;
use pyo3::types::PyModule;
use uuid::Uuid;
use chrono::Utc;
use tracing::{debug, info, warn};

pub struct ThoughtProcessor {
    whisper: Option<WhisperTranscriber>,
    concept_extractor: ConceptExtractor,
}

impl ThoughtProcessor {
    pub async fn new(config: &HermesConfig) -> Result<Self> {
        // Initialize Whisper (optional, only if model path exists)
        let whisper = if std::path::Path::new(&config.whisper_model_path).exists() {
            Some(WhisperTranscriber::new(&config.whisper_model_path)?)
        } else {
            warn!("Whisper model not found at {}, voice transcription disabled", config.whisper_model_path);
            None
        };

        let concept_extractor = ConceptExtractor::new()?;

        Ok(Self {
            whisper,
            concept_extractor,
        })
    }

    pub async fn process(&self, input: ThoughtInput) -> Result<Insight> {
        // 1. Get text content
        let (content, source) = match &input {
            ThoughtInput::Voice { audio_data, sample_rate } => {
                let transcription = self.whisper
                    .as_ref()
                    .ok_or_else(|| HermesError::WhisperError("Whisper not initialized".to_string()))?
                    .transcribe(audio_data, *sample_rate)?;
                (transcription, InsightSource::VoiceCapture)
            },
            ThoughtInput::Text { content, .. } => {
                (content.clone(), InsightSource::TextInput)
            },
        };

        info!("Processing thought: {} chars", content.len());

        // 2. Extract concepts and entities
        let (concepts, entities) = self.concept_extractor.extract(&content).await?;
        debug!("Extracted {} concepts and {} entities", concepts.len(), entities.len());

        // 3. Generate embeddings (optional, for semantic search)
        let embeddings = self.concept_extractor.generate_embeddings(&content).await?;

        // 4. Create insight
        let insight = Insight {
            id: Uuid::new_v4(),
            timestamp: Utc::now(),
            content,
            context: match &input {
                ThoughtInput::Text { context, .. } => context.clone(),
                _ => crate::ThoughtContext::Other("voice_capture".to_string()),
            },
            source,
            concepts,
            entities,
            embeddings: Some(embeddings),
        };

        Ok(insight)
    }
}

pub struct ProcessedThought {
    pub raw_text: String,
    pub concepts: Vec<String>,
    pub entities: Vec<Entity>,
}

/// Concept extractor using MLX + Python
struct ConceptExtractor {
    py_module: Py<PyModule>,
}

impl ConceptExtractor {
    fn new() -> Result<Self> {
        Python::with_gil(|py| {
            // Import Python module for concept extraction
            let sys = py.import("sys")?;
            let path = sys.getattr("path")?;
            path.call_method1("append", ("./python/hermes",))?;

            let module = py.import("concept_extractor")?;

            Ok(Self {
                py_module: module.into(),
            })
        })
    }

    async fn extract(&self, text: &str) -> Result<(Vec<String>, Vec<Entity>)> {
        Python::with_gil(|py| {
            let module = self.py_module.as_ref(py);

            // Call Python function: extract_concepts(text)
            let result = module.getattr("extract_concepts")?
                .call1((text,))?;

            // Parse result: {"concepts": [...], "entities": [...]}
            let concepts: Vec<String> = result.getattr("concepts")?
                .extract()?;

            let entities_raw: Vec<(String, String, f64)> = result.getattr("entities")?
                .extract()?;

            let entities = entities_raw
                .into_iter()
                .map(|(text, ent_type, confidence)| Entity {
                    text,
                    entity_type: parse_entity_type(&ent_type),
                    confidence,
                })
                .collect();

            Ok((concepts, entities))
        })
    }

    async fn generate_embeddings(&self, text: &str) -> Result<Vec<f32>> {
        Python::with_gil(|py| {
            let module = self.py_module.as_ref(py);

            // Call Python function: generate_embeddings(text)
            let result = module.getattr("generate_embeddings")?
                .call1((text,))?;

            let embeddings: Vec<f32> = result.extract()?;

            Ok(embeddings)
        })
    }
}

fn parse_entity_type(s: &str) -> EntityType {
    match s.to_lowercase().as_str() {
        "chemical" => EntityType::Chemical,
        "disease" => EntityType::Disease,
        "protein" => EntityType::Protein,
        "gene" => EntityType::Gene,
        "cell_type" => EntityType::CellType,
        "tissue" => EntityType::Tissue,
        "method" => EntityType::Method,
        "device" => EntityType::Device,
        "measurement" => EntityType::Measurement,
        _ => EntityType::Other,
    }
}

