// WebSocket message types and codecs
//
// References:
// - Google Protocol Buffers documentation
// - MessagePack specification
// - CBOR RFC 7049

use crate::{Result, WebSocketError};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use bytes::{Bytes, BytesMut};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: Uuid,
    pub message_type: MessageType,
    pub payload: Vec<u8>,
    pub timestamp: u64,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessageType {
    Text,
    Binary,
    Ping,
    Pong,
    Close,
    Subscribe,
    Unsubscribe,
    Sync,
    Ack,
    Error,
    Custom(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessagePayload {
    Text(String),
    Json(serde_json::Value),
    Binary(Vec<u8>),
    MessagePack(Vec<u8>),
    Protobuf(Vec<u8>),
}

pub trait MessageCodec: Send + Sync {
    fn encode(&self, message: &Message) -> Result<Bytes>;
    fn decode(&self, data: &[u8]) -> Result<Message>;
}

pub struct JsonCodec;

impl MessageCodec for JsonCodec {
    fn encode(&self, message: &Message) -> Result<Bytes> {
        serde_json::to_vec(message)
            .map(|v| Bytes::from(v))
            .map_err(|e| WebSocketError::CodecError(e.to_string()))
    }

    fn decode(&self, data: &[u8]) -> Result<Message> {
        serde_json::from_slice(data)
            .map_err(|e| WebSocketError::CodecError(e.to_string()))
    }
}

pub struct MessagePackCodec;

impl MessageCodec for MessagePackCodec {
    fn encode(&self, message: &Message) -> Result<Bytes> {
        rmp_serde::to_vec(message)
            .map(|v| Bytes::from(v))
            .map_err(|e| WebSocketError::CodecError(e.to_string()))
    }

    fn decode(&self, data: &[u8]) -> Result<Message> {
        rmp_serde::from_slice(data)
            .map_err(|e| WebSocketError::CodecError(e.to_string()))
    }
}

pub struct BincodeCodec;

impl MessageCodec for BincodeCodec {
    fn encode(&self, message: &Message) -> Result<Bytes> {
        bincode::serialize(message)
            .map(|v| Bytes::from(v))
            .map_err(|e| WebSocketError::CodecError(e.to_string()))
    }

    fn decode(&self, data: &[u8]) -> Result<Message> {
        bincode::deserialize(data)
            .map_err(|e| WebSocketError::CodecError(e.to_string()))
    }
}
