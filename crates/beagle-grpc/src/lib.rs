//! Beagle gRPC Services
//!
//! High-performance internal communication via gRPC.

pub mod generated {
    // Generated code from build.rs
    include!("generated/beagle.v1.rs");
}

pub mod agent;
pub mod error;
pub mod memory;
pub mod model;

// Re-exports
pub use agent::{AgentClient, AgentServiceImpl};
pub use error::{GrpcError, Result};
pub use memory::{MemoryClient, MemoryServiceImpl};
pub use model::{ModelClient, ModelServiceImpl};

// Re-export tonic
pub use tonic;
