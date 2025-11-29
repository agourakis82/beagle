//! BEAGLE Checkpoint - LangGraph-inspired State Persistence
//!
//! This crate provides checkpointing and state persistence for BEAGLE pipelines,
//! enabling fault tolerance, time travel, and human-in-the-loop workflows.
//!
//! # Key Concepts
//!
//! - **Checkpointer**: Trait for storing and retrieving pipeline state
//! - **Thread**: A sequence of checkpoints identified by `thread_id`
//! - **Checkpoint**: A snapshot of pipeline state at a specific step
//! - **Pending Writes**: Uncommitted changes for fault tolerance
//!
//! # Example
//!
//! ```rust,ignore
//! use beagle_checkpoint::{Checkpointer, InMemoryCheckpointer, CheckpointConfig};
//!
//! #[derive(Serialize, Deserialize, Clone)]
//! struct MyState {
//!     step: u64,
//!     data: String,
//! }
//!
//! #[tokio::main]
//! async fn main() {
//!     let checkpointer = InMemoryCheckpointer::<MyState>::new();
//!     let config = CheckpointConfig::new("thread-1");
//!
//!     // Save checkpoint
//!     let state = MyState { step: 1, data: "hello".into() };
//!     let id = checkpointer.put(&config, &state, "node_a".into()).await.unwrap();
//!
//!     // Retrieve checkpoint
//!     let checkpoint = checkpointer.get_tuple(&config).await.unwrap();
//! }
//! ```
//!
//! # Features
//!
//! - `memory` (default): In-memory checkpointer for testing
//! - `postgres`: PostgreSQL-backed checkpointer for production
//! - `redis`: Redis-backed checkpointer for distributed deployments
//! - `encrypted`: Encryption support for sensitive state

pub mod checkpoint;
pub mod config;
pub mod error;
pub mod metadata;

#[cfg(feature = "memory")]
pub mod memory;

#[cfg(feature = "postgres")]
pub mod postgres;

#[cfg(feature = "redis")]
pub mod redis_backend;

#[cfg(feature = "encrypted")]
pub mod encrypted;

// Re-exports
pub use checkpoint::{
    Checkpoint, CheckpointFilter, CheckpointTuple, Checkpointer, CheckpointerExt, PendingWrite,
    TaskInfo, TaskStatus,
};
pub use config::CheckpointConfig;
pub use error::{CheckpointError, CheckpointResult};
pub use metadata::CheckpointMetadata;

#[cfg(feature = "memory")]
pub use memory::InMemoryCheckpointer;

#[cfg(feature = "postgres")]
pub use postgres::PostgresCheckpointer;

/// Prelude for convenient imports
pub mod prelude {
    pub use crate::checkpoint::{Checkpoint, CheckpointTuple, Checkpointer, PendingWrite};
    pub use crate::config::CheckpointConfig;
    pub use crate::error::CheckpointError;
    pub use crate::metadata::CheckpointMetadata;

    #[cfg(feature = "memory")]
    pub use crate::memory::InMemoryCheckpointer;

    #[cfg(feature = "postgres")]
    pub use crate::postgres::PostgresCheckpointer;
}
