//! Thought Capture Service - Main orchestrator

use super::*;
use anyhow::{Context, Result};
use std::path::Path;

pub struct ThoughtCaptureService {
    whisper_client: WhisperClient,
    processor: ThoughtProcessor,
}

impl ThoughtCaptureService {
    pub fn new(whisper_config: WhisperConfig) -> Result<Self> {
        Ok(Self {
            whisper_client: WhisperClient::new(whisper_config)?,
            processor: ThoughtProcessor::new()?,
        })
    }

    /// Process voice note from file
    pub async fn process_voice_note(&self, audio_path: &Path) -> Result<ProcessedThought> {
        // 1. Transcribe audio
        let transcription = self
            .whisper_client
            .transcribe(audio_path)
            .await
            .context("Whisper transcription failed")?;

        // 2. Process text
        let thought = self.processor.process_text(
            transcription.text,
            InsightSource::Voice,
            transcription.confidence,
        )?;

        Ok(thought)
    }

    /// Process voice note from raw audio bytes
    pub async fn process_voice_bytes(&self, audio_data: &[u8]) -> Result<ProcessedThought> {
        // 1. Transcribe audio
        let transcription = self
            .whisper_client
            .transcribe_bytes(audio_data)
            .await
            .context("Whisper transcription failed")?;

        // 2. Process text
        let thought = self.processor.process_text(
            transcription.text,
            InsightSource::Voice,
            transcription.confidence,
        )?;

        Ok(thought)
    }

    /// Process text insight directly
    pub fn process_text_insight(&self, text: String) -> Result<ProcessedThought> {
        self.processor.process_text(
            text,
            InsightSource::Text,
            1.0, // Text has 100% confidence
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_text_insight_processing() {
        let service = ThoughtCaptureService::new(WhisperConfig::default()).unwrap();

        let text = "Discovered that KEC entropy correlates with collagen scaffold degradation rate in neural tissue engineering. This could explain the observed behavioral changes in rat models.";

        let thought = service.process_text_insight(text.to_string()).unwrap();

        assert_eq!(thought.source, InsightSource::Text);
        assert!(!thought.concepts.is_empty());
        assert_eq!(thought.confidence, 1.0);

        println!("\nExtracted {} concepts:", thought.concepts.len());
        for concept in &thought.concepts {
            println!(
                "  • {} ({:?}, {:.2})",
                concept.text, concept.concept_type, concept.confidence
            );
        }
    }
}
