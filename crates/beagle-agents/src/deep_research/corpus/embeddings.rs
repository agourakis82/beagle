//! Embedding engine using sentence-transformers via Python bridge
//!
//! Generates semantic embeddings for text using pre-trained models
//! to enable similarity comparison between hypotheses and literature.

use anyhow::Result;
use std::process::Command;
use tracing::{info, warn};

/// Embedding engine using sentence-transformers via Python bridge
pub struct EmbeddingEngine {
    model_name: String,
}

impl EmbeddingEngine {
    /// Create a new embedding engine with default model
    ///
    /// Default model: `all-MiniLM-L6-v2` (fast, good quality, 384 dimensions)
    pub fn new() -> Self {
        Self {
            model_name: "all-MiniLM-L6-v2".to_string(),
        }
    }

    /// Create embedding engine with custom model
    ///
    /// # Arguments
    /// * `model_name` - HuggingFace model identifier (e.g., "sentence-transformers/all-mpnet-base-v2")
    pub fn with_model(model_name: String) -> Self {
        Self { model_name }
    }

    /// Generate embedding for text via Python sentence-transformers
    ///
    /// # Arguments
    /// * `text` - Text to embed
    ///
    /// # Returns
    /// Vector of f32 values representing the embedding
    ///
    /// # Errors
    /// Returns error if Python execution fails or model is unavailable
    pub async fn embed(&self, text: &str) -> Result<Vec<f32>> {
        // Call Python script to generate embedding
        let python_code = format!(
            r#"
import sys
import json
from sentence_transformers import SentenceTransformer

try:
    model = SentenceTransformer('{}')
    text = sys.stdin.read()
    embedding = model.encode(text, normalize_embeddings=True).tolist()
    print(json.dumps(embedding))
except Exception as e:
    print(json.dumps({{"error": str(e)}}), file=sys.stderr)
    sys.exit(1)
"#,
            self.model_name
        );

        let mut child = Command::new("python3")
            .arg("-c")
            .arg(&python_code)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()?;

        // Write text to stdin
        if let Some(mut stdin) = child.stdin.take() {
            use std::io::Write;
            stdin.write_all(text.as_bytes())?;
            stdin.flush()?;
        }

        let output = child.wait_with_output()?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            warn!("⚠️  Python embedding failed: {}", error);
            return Err(anyhow::anyhow!("Embedding generation failed: {}", error));
        }

        let stdout = String::from_utf8(output.stdout)?;
        let stdout_trimmed = stdout.trim();

        // Check for JSON error in output
        if stdout_trimmed.starts_with('{') {
            if let Ok(error_obj) = serde_json::from_str::<serde_json::Value>(stdout_trimmed) {
                if error_obj.get("error").is_some() {
                    return Err(anyhow::anyhow!(
                        "Python error: {}",
                        error_obj["error"].as_str().unwrap_or("Unknown")
                    ));
                }
            }
        }

        let embedding: Vec<f32> = serde_json::from_str(stdout_trimmed)?;

        info!(
            "✅ Generated embedding (dim={}, model={})",
            embedding.len(),
            self.model_name
        );

        Ok(embedding)
    }

    /// Batch embed multiple texts (more efficient)
    ///
    /// # Arguments
    /// * `texts` - Vector of texts to embed
    ///
    /// # Returns
    /// Vector of embedding vectors
    pub async fn embed_batch(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let python_code = format!(
            r#"
import sys
import json
from sentence_transformers import SentenceTransformer

try:
    model = SentenceTransformer('{}')
    texts = json.load(sys.stdin)
    embeddings = model.encode(texts, normalize_embeddings=True).tolist()
    print(json.dumps(embeddings))
except Exception as e:
    print(json.dumps({{"error": str(e)}}), file=sys.stderr)
    sys.exit(1)
"#,
            self.model_name
        );

        let texts_json = serde_json::to_string(texts)?;

        let mut child = Command::new("python3")
            .arg("-c")
            .arg(&python_code)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()?;

        if let Some(mut stdin) = child.stdin.take() {
            use std::io::Write;
            stdin.write_all(texts_json.as_bytes())?;
            stdin.flush()?;
        }

        let output = child.wait_with_output()?;

        if !output.status.success() {
            let error = String::from_utf8_lossy(&output.stderr);
            warn!("⚠️  Python batch embedding failed: {}", error);
            return Err(anyhow::anyhow!("Batch embedding generation failed: {}", error));
        }

        let stdout = String::from_utf8(output.stdout)?;
        let stdout_trimmed = stdout.trim();

        if stdout_trimmed.starts_with('{') {
            if let Ok(error_obj) = serde_json::from_str::<serde_json::Value>(stdout_trimmed) {
                if error_obj.get("error").is_some() {
                    return Err(anyhow::anyhow!(
                        "Python error: {}",
                        error_obj["error"].as_str().unwrap_or("Unknown")
                    ));
                }
            }
        }

        let embeddings: Vec<Vec<f32>> = serde_json::from_str(stdout_trimmed)?;

        info!(
            "✅ Generated {} embeddings (dim={})",
            embeddings.len(),
            embeddings.first().map(|e| e.len()).unwrap_or(0)
        );

        Ok(embeddings)
    }

    /// Cosine similarity between two embeddings
    ///
    /// # Arguments
    /// * `a` - First embedding vector
    /// * `b` - Second embedding vector
    ///
    /// # Returns
    /// Cosine similarity score (0.0 = orthogonal, 1.0 = identical)
    ///
    /// # Panics
    /// Panics if vectors have different lengths
    pub fn cosine_similarity(a: &[f32], b: &[f32]) -> f64 {
        assert_eq!(a.len(), b.len(), "Embeddings must have same dimension");

        let dot: f32 = a.iter().zip(b).map(|(x, y)| x * y).sum();
        let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
        let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();

        if norm_a == 0.0 || norm_b == 0.0 {
            return 0.0;
        }

        (dot / (norm_a * norm_b)) as f64
    }

    /// Euclidean distance between two embeddings
    ///
    /// # Arguments
    /// * `a` - First embedding vector
    /// * `b` - Second embedding vector
    ///
    /// # Returns
    /// Euclidean distance (lower = more similar)
    pub fn euclidean_distance(a: &[f32], b: &[f32]) -> f64 {
        assert_eq!(a.len(), b.len(), "Embeddings must have same dimension");

        let sum_sq_diff: f32 = a
            .iter()
            .zip(b)
            .map(|(x, y)| (x - y) * (x - y))
            .sum();

        sum_sq_diff.sqrt() as f64
    }
}

impl Default for EmbeddingEngine {
    fn default() -> Self {
        Self::new()
    }
}


