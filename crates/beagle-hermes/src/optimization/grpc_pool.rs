//! gRPC Connection Pool for Multi-Agent Orchestration

use anyhow::Result;
use tonic::transport::{Channel, Endpoint};
use std::sync::Arc;
use deadpool::managed::{Manager, Object, Pool};
use async_trait::async_trait;
use tracing::{info, debug};

pub struct GrpcChannelManager {
    endpoint: Endpoint,
}

impl GrpcChannelManager {
    pub fn new(endpoint: Endpoint) -> Self {
        Self { endpoint }
    }
}

#[async_trait]
impl Manager for GrpcChannelManager {
    type Type = Channel;
    type Error = tonic::transport::Error;

    async fn create(&self) -> Result<Channel, Self::Error> {
        debug!("Creating new gRPC channel");
        self.endpoint.connect().await
    }

    async fn recycle(
        &self,
        _obj: &mut Channel,
        _metrics: &deadpool::managed::Metrics,
    ) -> std::result::Result<(), deadpool::managed::RecycleError<Self::Error>> {
        // Check if channel is still healthy
        // Note: We can't check ready() here as it consumes the channel
        // The pool will handle dead connections automatically
        debug!("Recycling gRPC channel");
        Ok(())
    }
}

pub type GrpcPool = Pool<GrpcChannelManager>;

pub fn create_grpc_pool(endpoint: Endpoint) -> Result<GrpcPool> {
    let manager = GrpcChannelManager::new(endpoint);

    let pool = Pool::builder(manager)
        .max_size(20)
        .build()?;

    info!("✅ gRPC connection pool created (max_size: 20)");

    Ok(pool)
}

/// Get a channel from the pool
pub async fn get_channel(pool: &GrpcPool) -> Result<Object<GrpcChannelManager>> {
    pool.get().await
        .map_err(|e| anyhow::anyhow!("Failed to get channel from pool: {}", e))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires gRPC server
    async fn test_grpc_pool() {
        let endpoint = Endpoint::from_static("http://localhost:50051");
        let pool = create_grpc_pool(endpoint).unwrap();

        // Get channel from pool
        let channel = get_channel(&pool).await.unwrap();
        
        // Channel should be ready
        assert!(channel.ready().await.is_ok());

        println!("✅ gRPC pool test passed");
    }
}

