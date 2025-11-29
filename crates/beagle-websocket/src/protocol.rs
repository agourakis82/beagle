// WebSocket protocol definitions and handshake
//
// References:
// - RFC 6455: The WebSocket Protocol
// - RFC 7692: Compression Extensions for WebSocket

use crate::{Result, WebSocketError};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Protocol {
    WebSocket,
    WebSocketSecure,
    Custom(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ProtocolVersion {
    V1,
    V2,
    Custom(String),
}

impl Default for ProtocolVersion {
    fn default() -> Self {
        Self::V2
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HandshakeRequest {
    pub protocol_version: ProtocolVersion,
    pub client_id: Option<String>,
    pub auth_token: Option<String>,
    pub capabilities: Vec<String>,
    pub compression: bool,
    pub heartbeat_interval: Option<u64>,
    pub metadata: HashMap<String, String>,
}

impl Default for HandshakeRequest {
    fn default() -> Self {
        Self {
            protocol_version: ProtocolVersion::default(),
            client_id: None,
            auth_token: None,
            capabilities: vec![
                "sync".to_string(),
                "crdts".to_string(),
                "compression".to_string(),
            ],
            compression: true,
            heartbeat_interval: Some(30),
            metadata: HashMap::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HandshakeResponse {
    pub success: bool,
    pub client_id: String,
    pub server_version: ProtocolVersion,
    pub supported_capabilities: Vec<String>,
    pub compression_enabled: bool,
    pub heartbeat_interval: u64,
    pub max_message_size: usize,
    pub sync_config: Option<SyncConfig>,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncConfig {
    pub strategy: String,
    pub conflict_resolution: String,
    pub enable_crdts: bool,
    pub enable_vector_clocks: bool,
}

pub struct ProtocolHandler {
    version: ProtocolVersion,
    capabilities: Vec<String>,
}

impl ProtocolHandler {
    pub fn new(version: ProtocolVersion) -> Self {
        Self {
            version,
            capabilities: vec![
                "sync".to_string(),
                "crdts".to_string(),
                "compression".to_string(),
                "batch".to_string(),
                "heartbeat".to_string(),
            ],
        }
    }

    pub fn negotiate_handshake(
        &self,
        request: HandshakeRequest,
    ) -> Result<HandshakeResponse> {
        // Validate protocol version
        if request.protocol_version != self.version {
            return Err(WebSocketError::ProtocolError(
                format!("Unsupported protocol version: {:?}", request.protocol_version)
            ));
        }

        // Check capabilities
        let supported: Vec<String> = request.capabilities
            .into_iter()
            .filter(|cap| self.capabilities.contains(cap))
            .collect();

        Ok(HandshakeResponse {
            success: true,
            client_id: request.client_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
            server_version: self.version.clone(),
            supported_capabilities: supported,
            compression_enabled: request.compression,
            heartbeat_interval: request.heartbeat_interval.unwrap_or(30),
            max_message_size: 10 * 1024 * 1024, // 10MB
            sync_config: Some(SyncConfig {
                strategy: "hybrid".to_string(),
                conflict_resolution: "semantic".to_string(),
                enable_crdts: true,
                enable_vector_clocks: true,
            }),
            metadata: HashMap::new(),
        })
    }
}
