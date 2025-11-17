//! LoRA fine-tuning pipeline for voice preservation
//! 
//! Uses Python bridge (PyO3) to call HuggingFace transformers for LoRA training
//! This avoids Rust dependency conflicts with candle-transformers

use crate::error::{HermesError, Result};
use pyo3::prelude::*;
use pyo3::types::PyDict;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use tracing::{info, warn};
use thiserror::Error;

/// LoRA adapter configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoRAConfig {
    pub rank: usize,           // LoRA rank (typically 4-16)
    pub alpha: usize,          // LoRA alpha (typically rank * 2)
    pub dropout: f64,          // Dropout rate
    pub target_modules: Vec<String>, // e.g., ["q_proj", "v_proj"]
    pub learning_rate: f64,
    pub batch_size: usize,
    pub num_epochs: usize,
}

impl Default for LoRAConfig {
    fn default() -> Self {
        Self {
            rank: 8,
            alpha: 16,
            dropout: 0.1,
            target_modules: vec!["q_proj".to_string(), "v_proj".to_string()],
            learning_rate: 2e-4,
            batch_size: 4,
            num_epochs: 3,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrainingResult {
    pub adapter_path: String,
    pub loss_history: Vec<f64>,
    pub final_loss: f64,
    pub training_time_seconds: f64,
}

/// Training metrics (alias for TrainingResult for backward compatibility)
pub type TrainingMetrics = TrainingResult;

/// Training dataset from personal corpus
#[derive(Debug, Clone)]
pub struct TrainingDataset {
    pub examples: Vec<TrainingExample>,
}

#[derive(Debug, Clone)]
pub struct TrainingExample {
    pub input: String,
    pub target: String,
    pub metadata: std::collections::HashMap<String, String>,
}

impl TrainingDataset {
    pub fn new() -> Self {
        Self {
            examples: Vec::new(),
        }
    }

    pub fn from_corpus(corpus_dir: &PathBuf) -> std::result::Result<Self, TrainerError> {
        let mut dataset = Self::new();
        
        for entry in std::fs::read_dir(corpus_dir)
            .map_err(|e| TrainerError::CorpusReadError(e.to_string()))?
        {
            let entry = entry.map_err(|e| TrainerError::CorpusReadError(e.to_string()))?;
            let path = entry.path();
            
            if path.extension().and_then(|s| s.to_str()) == Some("txt") {
                let content = std::fs::read_to_string(&path)
                    .map_err(|e| TrainerError::CorpusReadError(e.to_string()))?;
                
                let examples = Self::create_examples_from_text(&content);
                dataset.examples.extend(examples);
            }
        }
        
        info!("Created dataset with {} examples", dataset.examples.len());
        Ok(dataset)
    }

    fn create_examples_from_text(text: &str) -> Vec<TrainingExample> {
        let mut examples = Vec::new();
        let paragraphs: Vec<&str> = text.split("\n\n").collect();
        
        for para in &paragraphs {
            let sentences: Vec<&str> = para.split(". ").collect();
            if sentences.len() >= 2 {
                for i in 0..sentences.len() - 1 {
                    let input = format!("{}.", sentences[i]);
                    let target = format!("{}.", sentences[i + 1]);
                    
                    examples.push(TrainingExample {
                        input,
                        target,
                        metadata: std::collections::HashMap::new(),
                    });
                }
            }
        }
        
        examples
    }

    pub fn add_incremental_examples(&mut self, examples: Vec<TrainingExample>) {
        self.examples.extend(examples);
    }
}

pub struct LoRATrainer {
    config: LoRAConfig,
}

impl LoRATrainer {
    pub fn new(config: LoRAConfig) -> Self {
        Self { config }
    }

    /// Train LoRA adapter on personal corpus
    pub async fn train(
        &self,
        base_model: &str,
        training_data: &[String],
        output_path: &Path,
    ) -> Result<TrainingResult> {
        info!(
            "Starting LoRA training: {} samples, {} epochs",
            training_data.len(),
            self.config.num_epochs
        );

        // Call Python training script via PyO3
        let result = Python::with_gil(|py| -> std::result::Result<TrainingResult, HermesError> {
            // Load Python training module
            let trainer_module = PyModule::from_code(
                py,
                include_str!("../../python/lora_trainer.py"),
                "lora_trainer.py",
                "lora_trainer",
            )
            .map_err(|e| HermesError::PythonError(e))?;

            // Prepare training data as JSON
            let training_json = serde_json::to_string(training_data)
                .map_err(|e| HermesError::ConfigError(format!("Failed to serialize training data: {}", e)))?;

            // Call train_lora function
            let kwargs = PyDict::new(py);
            kwargs.set_item("base_model", base_model)?;
            kwargs.set_item("training_data_json", training_json)?;
            kwargs.set_item("output_path", output_path.to_str().unwrap())?;
            kwargs.set_item("rank", self.config.rank)?;
            kwargs.set_item("alpha", self.config.alpha)?;
            kwargs.set_item("dropout", self.config.dropout)?;
            kwargs.set_item("learning_rate", self.config.learning_rate)?;
            kwargs.set_item("batch_size", self.config.batch_size)?;
            kwargs.set_item("num_epochs", self.config.num_epochs)?;

            let result_dict = trainer_module
                .getattr("train_lora_json")?
                .call((), Some(kwargs))
                .map_err(|e| HermesError::PythonError(e))?;

            // Parse result
            let adapter_path: String = result_dict.get_item("adapter_path")?.extract()?;
            let loss_history: Vec<f64> = result_dict.get_item("loss_history")?.extract()?;
            let final_loss: f64 = result_dict.get_item("final_loss")?.extract()?;
            let training_time: f64 = result_dict.get_item("training_time_seconds")?.extract()?;

            Ok(TrainingResult {
                adapter_path,
                loss_history,
                final_loss,
                training_time_seconds: training_time,
            })
        })?;

        info!(
            "LoRA training complete: adapter saved to {}, final loss: {:.4}",
            result.adapter_path, result.final_loss
        );

        Ok(result)
    }

    /// Validate trained adapter
    pub async fn validate(&self, adapter_path: &Path, test_data: &[String]) -> Result<f64> {
        info!("Validating LoRA adapter: {:?}", adapter_path);

        // Use Python validation script
        Python::with_gil(|py| -> std::result::Result<f64, HermesError> {
            let validator_module = PyModule::from_code(
                py,
                include_str!("../../python/lora_validator.py"),
                "lora_validator.py",
                "lora_validator",
            )
            .map_err(|e| HermesError::PythonError(e))?;

            let test_json = serde_json::to_string(test_data)
                .map_err(|e| HermesError::ConfigError(format!("Failed to serialize test data: {}", e)))?;

            let kwargs = PyDict::new(py);
            kwargs.set_item("adapter_path", adapter_path.to_str().unwrap())?;
            kwargs.set_item("test_data_json", test_json)?;

            let result = validator_module
                .getattr("validate_lora_json")?
                .call((), Some(kwargs))
                .map_err(|e| HermesError::PythonError(e))?;

            let similarity: f64 = result.extract()?;
            Ok(similarity)
        })
    }
}

#[derive(Debug, Error)]
pub enum TrainerError {
    #[error("Corpus read error: {0}")]
    CorpusReadError(String),
    
    #[error("Training error: {0}")]
    TrainingError(String),
    
    #[error("Save error: {0}")]
    SaveError(String),
    
    #[error("Validation error: {0}")]
    ValidationError(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_training_dataset_creation() {
        let text = "This is the first paragraph. It contains multiple sentences.\n\n\
                    This is the second paragraph. It also has multiple sentences.";
        
        let examples = TrainingDataset::create_examples_from_text(text);
        assert!(!examples.is_empty());
    }

    #[tokio::test]
    #[ignore] // Requires Python dependencies and model files
    async fn test_lora_training() {
        let config = LoRAConfig::default();
        let trainer = LoRATrainer::new(config);

        let training_data = vec![
            "This is a sample training text.".to_string(),
            "Another example for fine-tuning.".to_string(),
        ];

        let output_path = std::env::temp_dir().join("test_lora_adapter");
        let result = trainer
            .train("microsoft/DialoGPT-small", &training_data, &output_path)
            .await;

        // This test requires actual model files and Python dependencies
        println!("Training result: {:?}", result);
    }
}

