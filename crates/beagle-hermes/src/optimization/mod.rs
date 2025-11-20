//! Performance Optimization Module
//!
//! Caching, connection pooling, and query optimization

pub mod cache;
pub mod grpc_pool;

pub use cache::CacheLayer;
pub use grpc_pool::{create_grpc_pool, GrpcPool};
