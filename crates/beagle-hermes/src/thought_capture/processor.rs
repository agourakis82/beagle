//! Thought Processing Logic

use super::*;
use anyhow::Result;
use chrono::Utc;
use uuid::Uuid;

pub struct ThoughtProcessor {
    concept_extractor: ConceptExtractor,
}

impl ThoughtProcessor {
    pub fn new() -> Result<Self> {
        Ok(Self {
            concept_extractor: ConceptExtractor::new()?,
        })
    }

    /// Process transcribed text into structured thought
    pub fn process_text(
        &self,
        text: String,
        source: InsightSource,
        confidence: f64,
    ) -> Result<ProcessedThought> {
        // Extract concepts
        let concepts = self.concept_extractor.extract(&text)?;

        tracing::info!(
            "Processed thought: {} chars, {} concepts extracted",
            text.len(),
            concepts.len()
        );

        Ok(ProcessedThought {
            text,
            source,
            concepts,
            confidence,
            timestamp: Utc::now(),
        })
    }
}

#[derive(Debug, Clone)]
pub struct ProcessedThought {
    pub text: String,
    pub source: InsightSource,
    pub concepts: Vec<ExtractedConcept>,
    pub confidence: f64,
    pub timestamp: chrono::DateTime<Utc>,
}

impl ProcessedThought {
    /// Convert to CapturedInsight for storage
    pub fn to_captured_insight(self, metadata: InsightMetadata) -> CapturedInsight {
        CapturedInsight {
            id: Uuid::new_v4(),
            text: self.text,
            source: self.source,
            concepts: self.concepts,
            timestamp: self.timestamp,
            metadata,
        }
    }
}
