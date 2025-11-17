//! Error types for HERMES BPSE

use pyo3::PyErr;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum HermesError {
    #[error("Database error: {0}")]
    DatabaseError(#[from] sqlx::Error),

    #[error("Neo4j error: {0}")]
    Neo4jError(String),

    #[error("Redis error: {0}")]
    RedisError(#[from] redis::RedisError),

    #[error("Whisper transcription error: {0}")]
    WhisperError(String),

    #[error("Synthesis error: {0}")]
    SynthesisError(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("Python integration error: {0}")]
    PythonError(#[from] PyErr),

    #[error("LLM error: {0}")]
    LLMError(#[from] anyhow::Error),

    #[error("Knowledge graph error: {0}")]
    KnowledgeGraphError(String),

    #[error("Manuscript error: {0}")]
    ManuscriptError(String),

    #[error("Citation error: {0}")]
    CitationError(String),

    #[error("Editor error: {0}")]
    EditorError(String),

    #[error("Integration error: {0}")]
    IntegrationError(String),
}

pub type Result<T> = std::result::Result<T, HermesError>;
