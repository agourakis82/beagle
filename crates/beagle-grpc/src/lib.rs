//! Beagle gRPC Services
//!
//! High-performance internal communication via gRPC.

pub mod generated {
    // Generated code from build.rs
    include!("generated/beagle.v1.rs");
}

pub mod agent;
pub mod memory;
pub mod model;
pub mod error;

// Re-exports
pub use agent::{AgentServiceImpl, AgentClient};
pub use memory::{MemoryServiceImpl, MemoryClient};
pub use model::{ModelServiceImpl, ModelClient};
pub use error::{GrpcError, Result};

// Re-export tonic
pub use tonic;


