//! Checkpoint error types

use thiserror::Error;
use uuid::Uuid;

/// Errors that can occur during checkpoint operations
#[derive(Debug, Error)]
pub enum CheckpointError {
    /// Checkpoint not found
    #[error("Checkpoint not found: {0}")]
    NotFound(String),

    /// Thread not found
    #[error("Thread not found: {0}")]
    ThreadNotFound(String),

    /// Serialization error
    #[error("Serialization error: {0}")]
    Serialization(String),

    /// Deserialization error
    #[error("Deserialization error: {0}")]
    Deserialization(String),

    /// Storage error
    #[error("Storage error: {0}")]
    Storage(String),

    /// Database error
    #[error("Database error: {0}")]
    Database(String),

    /// Connection error
    #[error("Connection error: {0}")]
    Connection(String),

    /// Encryption error
    #[error("Encryption error: {0}")]
    Encryption(String),

    /// Invalid configuration
    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    /// Checkpoint already exists
    #[error("Checkpoint already exists: {0}")]
    AlreadyExists(Uuid),

    /// Invalid parent checkpoint
    #[error("Invalid parent checkpoint: {0}")]
    InvalidParent(Uuid),

    /// Concurrent modification
    #[error("Concurrent modification detected on thread: {0}")]
    ConcurrentModification(String),

    /// Timeout
    #[error("Operation timed out after {0}ms")]
    Timeout(u64),

    /// Internal error
    #[error("Internal error: {0}")]
    Internal(String),
}

impl CheckpointError {
    /// Check if error is retryable
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            CheckpointError::Connection(_)
                | CheckpointError::Timeout(_)
                | CheckpointError::ConcurrentModification(_)
        )
    }

    /// Check if error indicates missing data
    pub fn is_not_found(&self) -> bool {
        matches!(
            self,
            CheckpointError::NotFound(_) | CheckpointError::ThreadNotFound(_)
        )
    }
}

impl From<serde_json::Error> for CheckpointError {
    fn from(err: serde_json::Error) -> Self {
        CheckpointError::Serialization(err.to_string())
    }
}

impl From<bincode::Error> for CheckpointError {
    fn from(err: bincode::Error) -> Self {
        CheckpointError::Serialization(err.to_string())
    }
}

#[cfg(feature = "postgres")]
impl From<sqlx::Error> for CheckpointError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::RowNotFound => CheckpointError::NotFound("Row not found".into()),
            sqlx::Error::PoolTimedOut => CheckpointError::Timeout(30000),
            _ => CheckpointError::Database(err.to_string()),
        }
    }
}

#[cfg(feature = "redis")]
impl From<redis::RedisError> for CheckpointError {
    fn from(err: redis::RedisError) -> Self {
        CheckpointError::Storage(err.to_string())
    }
}

/// Result type for checkpoint operations
pub type CheckpointResult<T> = Result<T, CheckpointError>;
