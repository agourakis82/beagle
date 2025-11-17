//! Whisper API Client for voice transcription

use anyhow::{Context, Result};
use pyo3::prelude::*;
use pyo3::types::PyDict;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WhisperConfig {
    pub use_api: bool,
    pub model_size: String, // "tiny", "base", "small", "medium", "large"
    pub api_key: Option<String>,
}

impl Default for WhisperConfig {
    fn default() -> Self {
        Self {
            use_api: false,
            model_size: "base".to_string(),
            api_key: std::env::var("OPENAI_API_KEY").ok(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionResult {
    pub text: String,
    pub language: String,
    pub confidence: f64,
}

pub struct WhisperClient {
    config: WhisperConfig,
}

impl WhisperClient {
    pub fn new(config: WhisperConfig) -> Result<Self> {
        // Validate configuration
        if config.use_api && config.api_key.is_none() {
            anyhow::bail!("OPENAI_API_KEY required when use_api=true");
        }

        Ok(Self { config })
    }

    /// Transcribe audio file to text
    pub async fn transcribe(&self, audio_path: &Path) -> Result<TranscriptionResult> {
        if !audio_path.exists() {
            anyhow::bail!("Audio file not found: {:?}", audio_path);
        }

        // Call Python Whisper transcriber via PyO3
        let result = Python::with_gil(|py| -> Result<TranscriptionResult> {
            // Import Python module
            let whisper_module = PyModule::from_code(
                py,
                include_str!("../../python/whisper_transcriber.py"),
                "whisper_transcriber.py",
                "whisper_transcriber",
            )
            .context("Failed to load whisper_transcriber.py")?;

            // Call transcribe_audio_json
            let kwargs = PyDict::new(py);
            kwargs.set_item("audio_path", audio_path.to_str().unwrap())?;
            kwargs.set_item("use_api", self.config.use_api)?;

            let result_dict = whisper_module
                .getattr("transcribe_audio_json")?
                .call((), Some(kwargs))?;

            // Parse result
            let text: String = result_dict.get_item("text")?.extract()?;
            let language: String = result_dict.get_item("language")?.extract()?;
            let confidence: f64 = result_dict.get_item("confidence")?.extract()?;

            Ok(TranscriptionResult {
                text,
                language,
                confidence,
            })
        })?;

        tracing::info!(
            "Transcribed audio: {} chars, language: {}, confidence: {:.2}",
            result.text.len(),
            result.language,
            result.confidence
        );

        Ok(result)
    }

    /// Transcribe from raw audio bytes (for streaming)
    pub async fn transcribe_bytes(&self, audio_data: &[u8]) -> Result<TranscriptionResult> {
        // Write to temp file
        let temp_path = std::env::temp_dir().join(format!("whisper_{}.wav", uuid::Uuid::new_v4()));
        std::fs::write(&temp_path, audio_data)?;

        let result = self.transcribe(&temp_path).await?;

        // Cleanup
        std::fs::remove_file(&temp_path)?;

        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_whisper_transcription() {
        // Create test audio file (you'll need a real audio file for this test)
        let config = WhisperConfig::default();
        let client = WhisperClient::new(config).unwrap();

        // This test requires a real audio file
        // Skip if not available
        let test_audio = Path::new("test_data/test_audio.wav");
        if !test_audio.exists() {
            println!("Skipping test - no test audio file");
            return;
        }

        let result = client.transcribe(test_audio).await.unwrap();

        assert!(!result.text.is_empty());
        assert!(result.confidence > 0.0);
    }
}
