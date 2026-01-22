use thiserror::Error;

#[derive(Error, Debug)]
pub enum EventError {
    #[error("Pulsar connection error: {0}")]
    ConnectionError(String),

    #[error("Failed to publish event: {0}")]
    PublishError(String),

    #[error("Failed to subscribe to topic: {0}")]
    SubscribeError(String),

    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    #[cfg(not(feature = "pulsar"))]
    #[error("Pulsar integration disabled (enable feature 'pulsar')")]
    PulsarDisabled,

    #[cfg(feature = "pulsar")]
    #[error("Pulsar error: {0}")]
    PulsarError(#[from] pulsar::Error),

    #[error("Unknown event type: {0}")]
    UnknownEventType(String),
}

pub type Result<T> = std::result::Result<T, EventError>;
