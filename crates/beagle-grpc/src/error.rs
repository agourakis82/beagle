use thiserror::Error;
use tonic::Status;

#[derive(Error, Debug)]
pub enum GrpcError {
    #[error("Agent not found: {0}")]
    AgentNotFound(String),

    #[error("Memory not found: {0}")]
    MemoryNotFound(String),

    #[error("Model error: {0}")]
    ModelError(String),

    #[error("Internal error: {0}")]
    InternalError(String),

    #[error("Invalid request: {0}")]
    InvalidRequest(String),
}

impl From<GrpcError> for Status {
    fn from(err: GrpcError) -> Self {
        match err {
            GrpcError::AgentNotFound(msg) | GrpcError::MemoryNotFound(msg) => {
                Status::not_found(msg)
            }
            GrpcError::InvalidRequest(msg) => {
                Status::invalid_argument(msg)
            }
            GrpcError::ModelError(msg) | GrpcError::InternalError(msg) => {
                Status::internal(msg)
            }
        }
    }
}

pub type Result<T> = std::result::Result<T, GrpcError>;


