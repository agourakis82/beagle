//! Signature error types

use thiserror::Error;

/// Errors that can occur during signature operations
#[derive(Debug, Error)]
pub enum SignatureError {
    /// Failed to parse output
    #[error("Parse error: {0}")]
    ParseError(String),

    /// Missing required field
    #[error("Missing required field: {0}")]
    MissingField(String),

    /// Invalid field value
    #[error("Invalid field value for '{field}': {message}")]
    InvalidValue { field: String, message: String },

    /// Serialization error
    #[error("Serialization error: {0}")]
    Serialization(String),

    /// Deserialization error
    #[error("Deserialization error: {0}")]
    Deserialization(String),

    /// LLM error
    #[error("LLM error: {0}")]
    LlmError(String),

    /// Validation error
    #[error("Validation error: {0}")]
    Validation(String),

    /// Optimization error
    #[error("Optimization error: {0}")]
    Optimization(String),

    /// Timeout
    #[error("Operation timed out after {0}ms")]
    Timeout(u64),

    /// Internal error
    #[error("Internal error: {0}")]
    Internal(String),
}

impl SignatureError {
    /// Check if error is retryable
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            SignatureError::LlmError(_) | SignatureError::Timeout(_)
        )
    }

    /// Create a parse error with context
    pub fn parse_with_context(message: impl Into<String>, context: &str) -> Self {
        SignatureError::ParseError(format!(
            "{}: ...{}...",
            message.into(),
            &context[..context.len().min(100)]
        ))
    }
}

impl From<serde_json::Error> for SignatureError {
    fn from(err: serde_json::Error) -> Self {
        SignatureError::Serialization(err.to_string())
    }
}

impl From<regex::Error> for SignatureError {
    fn from(err: regex::Error) -> Self {
        SignatureError::ParseError(err.to_string())
    }
}

/// Result type for signature operations
pub type SignatureResult<T> = Result<T, SignatureError>;
