// beagle-websocket: Real-time bidirectional communication with Q1 SOTA standards
//
// References:
// - Fette, I., & Melnikov, A. (2011). The WebSocket Protocol. RFC 6455.
// - Grigorik, I. (2013). High Performance Browser Networking. O'Reilly Media.
// - Kleppmann, M. (2017). Designing Data-Intensive Applications. O'Reilly.
// - Tanenbaum, A. S., & Van Steen, M. (2017). Distributed Systems (3rd ed.).
// - Burns, B., et al. (2016). Borg, Omega, and Kubernetes. ACM Queue.
// - Vaquero, L. M., & Rodero-Merino, L. (2014). Finding your way in the fog:
//   Towards a comprehensive definition of fog computing. ACM SIGCOMM.

pub mod auth;
pub mod compression;
pub mod config;
pub mod connection;
pub mod handler;
pub mod hub;
pub mod message;
pub mod metrics;
pub mod protocol;
pub mod sync;

pub use auth::{AuthProvider, SessionManager, TokenValidator};
pub use compression::{CompressionLevel, CompressionStrategy};
pub use config::{ConnectionConfig, SyncConfig, WebSocketConfig};
pub use connection::{ConnectionManager, ConnectionState, WebSocketConnection};
pub use handler::{EventHandler, MessageHandler, WebSocketHandler};
pub use hub::{ClientRegistry, HubManager, WebSocketHub};
pub use message::{Message, MessageCodec, MessagePayload, MessageType};
pub use metrics::{ConnectionMetrics, MessageMetrics, WebSocketMetrics};
pub use protocol::{HandshakeRequest, HandshakeResponse, Protocol, ProtocolVersion};
pub use sync::{ConflictResolver, EventOrdering, SyncEngine, SyncStrategy};

use thiserror::Error;

#[derive(Error, Debug)]
pub enum WebSocketError {
    #[error("Connection error: {0}")]
    ConnectionError(String),

    #[error("Protocol error: {0}")]
    ProtocolError(String),

    #[error("Authentication failed: {0}")]
    AuthenticationError(String),

    #[error("Sync error: {0}")]
    SyncError(String),

    #[error("Hub error: {0}")]
    HubError(String),

    #[error("Message codec error: {0}")]
    CodecError(String),

    #[error("Rate limit exceeded")]
    RateLimitExceeded,

    #[error("Circuit breaker open")]
    CircuitBreakerOpen,

    #[error("Backpressure limit reached")]
    BackpressureLimit,

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, WebSocketError>;

