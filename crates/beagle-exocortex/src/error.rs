//! Error types for the Personal Exocortex

use thiserror::Error;

/// Errors that can occur in the exocortex system
#[derive(Error, Debug)]
pub enum ExocortexError {
    #[error("Identity error: {0}")]
    Identity(String),

    #[error("Brain connector error: {0}")]
    Brain(String),

    #[error("Context manager error: {0}")]
    Context(String),

    #[error("Agent mesh error: {0}")]
    Agent(String),

    #[error("Memory bridge error: {0}")]
    Memory(String),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Initialization error: {0}")]
    Init(String),

    #[error("Processing error: {0}")]
    Processing(String),

    #[error("Consciousness substrate unavailable: {0}")]
    ConsciousnessUnavailable(String),

    #[error("Personality system unavailable: {0}")]
    PersonalityUnavailable(String),

    #[error("World model unavailable: {0}")]
    WorldModelUnavailable(String),

    #[error("Observer unavailable: {0}")]
    ObserverUnavailable(String),

    #[error("LLM routing error: {0}")]
    LlmRouting(String),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Internal error: {0}")]
    Internal(#[from] anyhow::Error),
}

impl From<&str> for ExocortexError {
    fn from(s: &str) -> Self {
        ExocortexError::Internal(anyhow::anyhow!("{}", s))
    }
}

impl From<String> for ExocortexError {
    fn from(s: String) -> Self {
        ExocortexError::Internal(anyhow::anyhow!("{}", s))
    }
}

/// Result type alias for exocortex operations
pub type ExocortexResult<T> = Result<T, ExocortexError>;
