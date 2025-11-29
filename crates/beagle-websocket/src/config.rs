// WebSocket configuration with Q1 SOTA standards

use serde::{Deserialize, Serialize};
use std::time::Duration;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebSocketConfig {
    pub connection: ConnectionConfig,
    pub sync: SyncConfig,
    pub security: SecurityConfig,
    pub performance: PerformanceConfig,
    pub observability: ObservabilityConfig,
}

impl Default for WebSocketConfig {
    fn default() -> Self {
        Self {
            connection: ConnectionConfig::default(),
            sync: SyncConfig::default(),
            security: SecurityConfig::default(),
            performance: PerformanceConfig::default(),
            observability: ObservabilityConfig::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionConfig {
    pub max_connections: usize,
    pub max_frame_size: usize,
    pub heartbeat_interval_secs: u64,
    pub idle_timeout_secs: u64,
    pub handshake_timeout_secs: u64,
    pub max_message_size: usize,
    pub compression_threshold: usize,
    pub backpressure_buffer_size: usize,
}

impl Default for ConnectionConfig {
    fn default() -> Self {
        Self {
            max_connections: 10000,
            max_frame_size: 64 * 1024, // 64KB
            heartbeat_interval_secs: 30,
            idle_timeout_secs: 300,
            handshake_timeout_secs: 10,
            max_message_size: 10 * 1024 * 1024, // 10MB
            compression_threshold: 1024,        // Compress messages > 1KB
            backpressure_buffer_size: 1000,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncConfig {
    pub strategy: String, // "optimistic", "pessimistic", "eventual", "causal", "hybrid"
    pub conflict_resolution: String, // "lww", "mvr", "semantic", "custom"
    pub sync_interval_ms: u64,
    pub max_batch_size: usize,
    pub max_pending_events: usize,
    pub ordering_timeout_secs: u64,
    pub enable_crdts: bool,
    pub enable_vector_clocks: bool,
}

impl Default for SyncConfig {
    fn default() -> Self {
        Self {
            strategy: "hybrid".to_string(),
            conflict_resolution: "semantic".to_string(),
            sync_interval_ms: 100,
            max_batch_size: 1000,
            max_pending_events: 10000,
            ordering_timeout_secs: 30,
            enable_crdts: true,
            enable_vector_clocks: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    pub enable_tls: bool,
    pub require_auth: bool,
    pub jwt_secret: Option<String>,
    pub allowed_origins: Vec<String>,
    pub rate_limit_per_second: u32,
    pub max_connections_per_ip: usize,
    pub enable_message_signing: bool,
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self {
            enable_tls: true,
            require_auth: true,
            jwt_secret: None,
            allowed_origins: vec!["*".to_string()],
            rate_limit_per_second: 1000,
            max_connections_per_ip: 100,
            enable_message_signing: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceConfig {
    pub worker_threads: usize,
    pub io_threads: usize,
    pub queue_capacity: usize,
    pub batch_processing: bool,
    pub batch_interval_ms: u64,
    pub batch_size: usize,
    pub enable_compression: bool,
    pub compression_level: u32, // 0-9
}

impl Default for PerformanceConfig {
    fn default() -> Self {
        Self {
            worker_threads: num_cpus::get(),
            io_threads: 2,
            queue_capacity: 100000,
            batch_processing: true,
            batch_interval_ms: 100,
            batch_size: 100,
            enable_compression: true,
            compression_level: 6,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObservabilityConfig {
    pub enable_metrics: bool,
    pub enable_tracing: bool,
    pub enable_logging: bool,
    pub metrics_interval_secs: u64,
    pub trace_sample_rate: f32,
    pub log_level: String,
}

impl Default for ObservabilityConfig {
    fn default() -> Self {
        Self {
            enable_metrics: true,
            enable_tracing: true,
            enable_logging: true,
            metrics_interval_secs: 10,
            trace_sample_rate: 0.1,
            log_level: "info".to_string(),
        }
    }
}
