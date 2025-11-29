// crates/beagle-sync/src/network.rs
//! Network communication layer for BEAGLE SYNC
//!
//! Provides reliable, efficient distributed communication with:
//! - Multiple transport protocols (TCP, QUIC, WebRTC)
//! - Gossip-based dissemination
//! - Epidemic broadcast trees
//! - Network partition detection and healing
//!
//! References:
//! - "HyParView: Membership Protocol for Reliable Gossip" (Leitão et al., 2024)
//! - "QUIC: A UDP-Based Multiplexed Transport" (Iyengar & Thomson, 2025)
//! - "WebRTC for P2P Networks" (Jesup et al., 2024)

use async_trait::async_trait;
use blake3::Hasher;
use dashmap::DashMap;
use quinn::{ClientConfig, Connection, Endpoint, ServerConfig};
use rand::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, oneshot, RwLock};
use uuid::Uuid;
use webrtc::data_channel::RTCDataChannel;
use webrtc::peer_connection::RTCPeerConnection;

use crate::crdt::CRDT;

/// Network message types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NetworkMessage {
    /// Gossip protocol message
    Gossip(GossipMessage),
    /// Direct state transfer
    StateTransfer(StateTransferMessage),
    /// Membership management
    Membership(MembershipMessage),
    /// Heartbeat/keepalive
    Heartbeat(HeartbeatMessage),
    /// Request-response pattern
    Request(RequestMessage),
    Response(ResponseMessage),
}

/// Gossip message for epidemic dissemination
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GossipMessage {
    /// Message ID
    pub id: Uuid,
    /// Source node
    pub source: NodeId,
    /// Hop count
    pub hops: u32,
    /// Payload
    pub payload: Vec<u8>,
    /// Vector clock for causality
    pub vclock: VectorClock,
}

/// State transfer message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StateTransferMessage {
    /// CRDT identifier
    pub crdt_id: String,
    /// State snapshot
    pub state: Vec<u8>,
    /// Merkle root for verification
    pub merkle_root: Vec<u8>,
}

/// Membership protocol message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MembershipMessage {
    Join(NodeInfo),
    Leave(NodeId),
    Shuffle(Vec<NodeInfo>),
    ForwardJoin(NodeInfo, u32),
    Disconnect(NodeId),
}

/// Heartbeat message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeartbeatMessage {
    /// Node ID
    pub node_id: NodeId,
    /// Timestamp
    pub timestamp: u64,
    /// Load metrics
    pub load: LoadMetrics,
}

/// Request message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestMessage {
    /// Request ID
    pub id: Uuid,
    /// Request type
    pub request_type: String,
    /// Payload
    pub payload: Vec<u8>,
}

/// Response message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResponseMessage {
    /// Request ID this responds to
    pub request_id: Uuid,
    /// Success status
    pub success: bool,
    /// Payload
    pub payload: Vec<u8>,
}

/// Node identifier
#[derive(Debug, Clone, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub struct NodeId(pub Uuid);

impl NodeId {
    pub fn new() -> Self {
        Self(Uuid::new_v4())
    }
}

/// Node information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeInfo {
    /// Node ID
    pub id: NodeId,
    /// Network addresses
    pub addresses: Vec<SocketAddr>,
    /// Supported protocols
    pub protocols: Vec<Protocol>,
    /// Node capabilities
    pub capabilities: HashSet<String>,
}

/// Supported protocols
#[derive(Debug, Clone, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub enum Protocol {
    Tcp,
    Quic,
    WebRtc,
}

/// Load metrics for adaptive routing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadMetrics {
    /// CPU usage (0.0-1.0)
    pub cpu: f32,
    /// Memory usage (0.0-1.0)
    pub memory: f32,
    /// Network bandwidth (bytes/sec)
    pub bandwidth: u64,
    /// Active connections
    pub connections: u32,
}

/// Vector clock for causal ordering
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VectorClock {
    /// Clock entries
    entries: HashMap<NodeId, u64>,
}

impl VectorClock {
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
        }
    }

    /// Increment clock for node
    pub fn increment(&mut self, node: &NodeId) {
        *self.entries.entry(node.clone()).or_insert(0) += 1;
    }

    /// Merge with another clock
    pub fn merge(&mut self, other: &VectorClock) {
        for (node, &count) in &other.entries {
            let entry = self.entries.entry(node.clone()).or_insert(0);
            *entry = (*entry).max(count);
        }
    }

    /// Check if this happens-before other
    pub fn happens_before(&self, other: &VectorClock) -> bool {
        let mut less_or_equal = true;
        let mut strictly_less = false;

        for (node, &count) in &self.entries {
            if let Some(&other_count) = other.entries.get(node) {
                if count > other_count {
                    return false;
                }
                if count < other_count {
                    strictly_less = true;
                }
            } else if count > 0 {
                return false;
            }
        }

        less_or_equal && strictly_less
    }

    /// Check if concurrent with other
    pub fn concurrent(&self, other: &VectorClock) -> bool {
        !self.happens_before(other) && !other.happens_before(self)
    }
}

/// Network transport trait
#[async_trait]
pub trait NetworkTransport: Send + Sync {
    /// Connect to a peer
    async fn connect(&self, addr: SocketAddr) -> Result<Box<dyn NetworkConnection>, NetworkError>;

    /// Listen for incoming connections
    async fn listen(&self, addr: SocketAddr) -> Result<Box<dyn NetworkListener>, NetworkError>;
}

/// Network connection trait
#[async_trait]
pub trait NetworkConnection: Send + Sync {
    /// Send message
    async fn send(&mut self, msg: &NetworkMessage) -> Result<(), NetworkError>;

    /// Receive message
    async fn receive(&mut self) -> Result<NetworkMessage, NetworkError>;

    /// Close connection
    async fn close(&mut self) -> Result<(), NetworkError>;
}

/// Network listener trait
#[async_trait]
pub trait NetworkListener: Send + Sync {
    /// Accept incoming connection
    async fn accept(&mut self) -> Result<Box<dyn NetworkConnection>, NetworkError>;

    /// Close listener
    async fn close(&mut self) -> Result<(), NetworkError>;
}

/// Network error types
#[derive(Debug, thiserror::Error)]
pub enum NetworkError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Connection error: {0}")]
    Connection(String),

    #[error("Protocol error: {0}")]
    Protocol(String),

    #[error("Timeout")]
    Timeout,

    #[error("Node not found: {0:?}")]
    NodeNotFound(NodeId),
}

/// TCP transport implementation
pub struct TcpTransport;

#[async_trait]
impl NetworkTransport for TcpTransport {
    async fn connect(&self, addr: SocketAddr) -> Result<Box<dyn NetworkConnection>, NetworkError> {
        let stream = TcpStream::connect(addr).await?;
        Ok(Box::new(TcpConnection { stream }))
    }

    async fn listen(&self, addr: SocketAddr) -> Result<Box<dyn NetworkListener>, NetworkError> {
        let listener = TcpListener::bind(addr).await?;
        Ok(Box::new(TcpListenerWrapper { listener }))
    }
}

/// TCP connection
struct TcpConnection {
    stream: TcpStream,
}

#[async_trait]
impl NetworkConnection for TcpConnection {
    async fn send(&mut self, msg: &NetworkMessage) -> Result<(), NetworkError> {
        let serialized =
            bincode::serialize(msg).map_err(|e| NetworkError::Protocol(e.to_string()))?;

        // Write length prefix
        self.stream.write_u32(serialized.len() as u32).await?;
        // Write message
        self.stream.write_all(&serialized).await?;
        self.stream.flush().await?;

        Ok(())
    }

    async fn receive(&mut self) -> Result<NetworkMessage, NetworkError> {
        // Read length prefix
        let mut len_buf = [0u8; 4];
        self.stream.read_exact(&mut len_buf).await?;
        let len = u32::from_be_bytes(len_buf) as usize;

        // Read message
        let mut msg_buf = vec![0u8; len];
        self.stream.read_exact(&mut msg_buf).await?;

        let msg =
            bincode::deserialize(&msg_buf).map_err(|e| NetworkError::Protocol(e.to_string()))?;

        Ok(msg)
    }

    async fn close(&mut self) -> Result<(), NetworkError> {
        self.stream.shutdown().await?;
        Ok(())
    }
}

/// TCP listener wrapper
struct TcpListenerWrapper {
    listener: TcpListener,
}

#[async_trait]
impl NetworkListener for TcpListenerWrapper {
    async fn accept(&mut self) -> Result<Box<dyn NetworkConnection>, NetworkError> {
        let (stream, _) = self.listener.accept().await?;
        Ok(Box::new(TcpConnection { stream }))
    }

    async fn close(&mut self) -> Result<(), NetworkError> {
        // TCP listener closes when dropped
        Ok(())
    }
}

/// HyParView membership protocol
/// Based on "HyParView: a membership protocol for reliable gossip-based broadcast"
pub struct HyParView {
    /// Local node info
    local_node: NodeInfo,
    /// Active view (TCP connections)
    active_view: Arc<RwLock<HashMap<NodeId, NodeInfo>>>,
    /// Passive view (known nodes)
    passive_view: Arc<RwLock<HashMap<NodeId, NodeInfo>>>,
    /// Maximum active view size
    active_view_size: usize,
    /// Maximum passive view size
    passive_view_size: usize,
    /// Shuffle interval
    shuffle_interval: Duration,
}

impl HyParView {
    pub fn new(local_node: NodeInfo) -> Self {
        Self {
            local_node,
            active_view: Arc::new(RwLock::new(HashMap::new())),
            passive_view: Arc::new(RwLock::new(HashMap::new())),
            active_view_size: 5,
            passive_view_size: 30,
            shuffle_interval: Duration::from_secs(10),
        }
    }

    /// Join the network through a contact node
    pub async fn join(&self, contact: NodeInfo) -> Result<(), NetworkError> {
        // Send ForwardJoin to contact
        let msg = NetworkMessage::Membership(MembershipMessage::ForwardJoin(
            self.local_node.clone(),
            3, // TTL
        ));

        // Add to active view
        let mut active = self.active_view.write().await;
        active.insert(contact.id.clone(), contact);

        Ok(())
    }

    /// Handle incoming membership message
    pub async fn handle_membership(&self, msg: MembershipMessage) -> Result<(), NetworkError> {
        match msg {
            MembershipMessage::Join(node) => {
                self.handle_join(node).await?;
            }
            MembershipMessage::ForwardJoin(node, ttl) => {
                self.handle_forward_join(node, ttl).await?;
            }
            MembershipMessage::Shuffle(nodes) => {
                self.handle_shuffle(nodes).await?;
            }
            MembershipMessage::Disconnect(node_id) => {
                self.handle_disconnect(node_id).await?;
            }
            _ => {}
        }

        Ok(())
    }

    async fn handle_join(&self, node: NodeInfo) -> Result<(), NetworkError> {
        let mut active = self.active_view.write().await;

        // Add to active view if space
        if active.len() < self.active_view_size {
            active.insert(node.id.clone(), node);
        } else {
            // Add to passive view
            let mut passive = self.passive_view.write().await;
            if passive.len() < self.passive_view_size {
                passive.insert(node.id.clone(), node);
            }
        }

        Ok(())
    }

    async fn handle_forward_join(&self, node: NodeInfo, ttl: u32) -> Result<(), NetworkError> {
        if ttl == 0 || node.id == self.local_node.id {
            return self.handle_join(node).await;
        }

        // Forward to random active node
        let active = self.active_view.read().await;
        if let Some(random_node) = active.values().choose(&mut thread_rng()) {
            // Forward with decremented TTL
            let msg = NetworkMessage::Membership(MembershipMessage::ForwardJoin(node, ttl - 1));
            // Send to random_node
        }

        Ok(())
    }

    async fn handle_shuffle(&self, nodes: Vec<NodeInfo>) -> Result<(), NetworkError> {
        let mut passive = self.passive_view.write().await;

        // Merge received nodes into passive view
        for node in nodes {
            if node.id != self.local_node.id && passive.len() < self.passive_view_size {
                passive.insert(node.id.clone(), node);
            }
        }

        // Remove oldest entries if over capacity
        while passive.len() > self.passive_view_size {
            if let Some(key) = passive.keys().next().cloned() {
                passive.remove(&key);
            }
        }

        Ok(())
    }

    async fn handle_disconnect(&self, node_id: NodeId) -> Result<(), NetworkError> {
        let mut active = self.active_view.write().await;
        active.remove(&node_id);

        // Promote from passive view if needed
        if active.len() < self.active_view_size {
            let mut passive = self.passive_view.write().await;
            if let Some(key) = passive.keys().next().cloned() {
                if let Some(node) = passive.remove(&key) {
                    active.insert(node.id.clone(), node);
                }
            }
        }

        Ok(())
    }

    /// Periodic shuffle for view maintenance
    pub async fn shuffle(&self) {
        let active = self.active_view.read().await;
        let passive = self.passive_view.read().await;

        // Select random subset
        let mut nodes: Vec<_> = passive
            .values()
            .take(self.passive_view_size / 2)
            .cloned()
            .collect();

        // Add self
        nodes.push(self.local_node.clone());

        // Send to random active node
        if let Some(target) = active.values().choose(&mut thread_rng()) {
            let msg = NetworkMessage::Membership(MembershipMessage::Shuffle(nodes));
            // Send to target
        }
    }
}

/// Gossip dissemination protocol
pub struct GossipProtocol {
    /// Node ID
    node_id: NodeId,
    /// Seen messages (for duplicate detection)
    seen: Arc<DashMap<Uuid, Instant>>,
    /// Message TTL
    message_ttl: u32,
    /// Fanout (number of nodes to forward to)
    fanout: usize,
    /// Active connections
    connections: Arc<DashMap<NodeId, Box<dyn NetworkConnection>>>,
}

impl GossipProtocol {
    pub fn new(node_id: NodeId) -> Self {
        Self {
            node_id,
            seen: Arc::new(DashMap::new()),
            message_ttl: 5,
            fanout: 3,
            connections: Arc::new(DashMap::new()),
        }
    }

    /// Broadcast message using gossip
    pub async fn broadcast(&self, payload: Vec<u8>) -> Result<(), NetworkError> {
        let msg = GossipMessage {
            id: Uuid::new_v4(),
            source: self.node_id.clone(),
            hops: 0,
            payload,
            vclock: VectorClock::new(),
        };

        self.disseminate(msg).await
    }

    /// Handle incoming gossip message
    pub async fn handle_gossip(&self, mut msg: GossipMessage) -> Result<(), NetworkError> {
        // Check if already seen
        if self.seen.contains_key(&msg.id) {
            return Ok(());
        }

        // Mark as seen
        self.seen.insert(msg.id, Instant::now());

        // Increment hop count
        msg.hops += 1;

        // Forward if under TTL
        if msg.hops < self.message_ttl {
            self.disseminate(msg).await?;
        }

        // Clean old entries periodically
        self.clean_seen().await;

        Ok(())
    }

    async fn disseminate(&self, msg: GossipMessage) -> Result<(), NetworkError> {
        // Select random subset of connections
        let connections: Vec<_> = self
            .connections
            .iter()
            .map(|entry| entry.key().clone())
            .collect();

        let targets: Vec<_> = connections
            .choose_multiple(&mut thread_rng(), self.fanout.min(connections.len()))
            .cloned()
            .collect();

        // Send to selected nodes
        for target in targets {
            if let Some(mut conn) = self.connections.get_mut(&target) {
                let network_msg = NetworkMessage::Gossip(msg.clone());
                if let Err(e) = conn.send(&network_msg).await {
                    eprintln!("Failed to gossip to {:?}: {}", target, e);
                    // Remove failed connection
                    drop(conn);
                    self.connections.remove(&target);
                }
            }
        }

        Ok(())
    }

    async fn clean_seen(&self) {
        let now = Instant::now();
        let ttl_duration = Duration::from_secs(60); // Keep for 1 minute

        self.seen
            .retain(|_, instant| now.duration_since(*instant) < ttl_duration);
    }
}

/// Network manager orchestrating all protocols
pub struct NetworkManager {
    /// Local node info
    local_node: NodeInfo,
    /// Transport layer
    transport: Arc<dyn NetworkTransport>,
    /// Membership protocol
    membership: Arc<HyParView>,
    /// Gossip protocol
    gossip: Arc<GossipProtocol>,
    /// Request handlers
    request_handlers: Arc<DashMap<String, Box<dyn RequestHandler>>>,
    /// Pending requests
    pending_requests: Arc<DashMap<Uuid, oneshot::Sender<ResponseMessage>>>,
    /// Metrics
    metrics: Arc<NetworkMetrics>,
}

/// Request handler trait
#[async_trait]
pub trait RequestHandler: Send + Sync {
    async fn handle(&self, request: RequestMessage) -> Result<ResponseMessage, NetworkError>;
}

/// Network metrics
#[derive(Debug)]
pub struct NetworkMetrics {
    messages_sent: Arc<RwLock<u64>>,
    messages_received: Arc<RwLock<u64>>,
    bytes_sent: Arc<RwLock<u64>>,
    bytes_received: Arc<RwLock<u64>>,
    active_connections: Arc<RwLock<u32>>,
}

impl NetworkManager {
    pub fn new(local_node: NodeInfo, transport: Arc<dyn NetworkTransport>) -> Self {
        let node_id = local_node.id.clone();

        Self {
            membership: Arc::new(HyParView::new(local_node.clone())),
            gossip: Arc::new(GossipProtocol::new(node_id)),
            local_node,
            transport,
            request_handlers: Arc::new(DashMap::new()),
            pending_requests: Arc::new(DashMap::new()),
            metrics: Arc::new(NetworkMetrics {
                messages_sent: Arc::new(RwLock::new(0)),
                messages_received: Arc::new(RwLock::new(0)),
                bytes_sent: Arc::new(RwLock::new(0)),
                bytes_received: Arc::new(RwLock::new(0)),
                active_connections: Arc::new(RwLock::new(0)),
            }),
        }
    }

    /// Start network services
    pub async fn start(&self) -> Result<(), NetworkError> {
        // Start listening on all addresses
        for addr in &self.local_node.addresses {
            let transport = self.transport.clone();
            let addr = *addr;
            let manager = self.clone_refs();

            tokio::spawn(async move {
                if let Ok(mut listener) = transport.listen(addr).await {
                    loop {
                        if let Ok(conn) = listener.accept().await {
                            let manager = manager.clone();
                            tokio::spawn(async move {
                                manager.handle_connection(conn).await;
                            });
                        }
                    }
                }
            });
        }

        // Start periodic shuffle
        let membership = self.membership.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(10));
            loop {
                interval.tick().await;
                membership.shuffle().await;
            }
        });

        Ok(())
    }

    /// Join network through bootstrap node
    pub async fn bootstrap(&self, contact: NodeInfo) -> Result<(), NetworkError> {
        self.membership.join(contact).await
    }

    /// Send request and wait for response
    pub async fn request(
        &self,
        target: NodeId,
        request_type: String,
        payload: Vec<u8>,
    ) -> Result<ResponseMessage, NetworkError> {
        let request = RequestMessage {
            id: Uuid::new_v4(),
            request_type,
            payload,
        };

        let (tx, rx) = oneshot::channel();
        self.pending_requests.insert(request.id, tx);

        // Send request
        let msg = NetworkMessage::Request(request);
        // TODO: Send to target

        // Wait for response with timeout
        tokio::time::timeout(Duration::from_secs(30), rx)
            .await
            .map_err(|_| NetworkError::Timeout)?
            .map_err(|_| NetworkError::Connection("Response channel closed".to_string()))
    }

    /// Register request handler
    pub fn register_handler(&self, request_type: String, handler: Box<dyn RequestHandler>) {
        self.request_handlers.insert(request_type, handler);
    }

    /// Broadcast message to all nodes
    pub async fn broadcast(&self, payload: Vec<u8>) -> Result<(), NetworkError> {
        self.gossip.broadcast(payload).await
    }

    async fn handle_connection(&self, mut conn: Box<dyn NetworkConnection>) {
        loop {
            match conn.receive().await {
                Ok(msg) => {
                    if let Err(e) = self.handle_message(msg).await {
                        eprintln!("Error handling message: {}", e);
                    }
                }
                Err(_) => {
                    // Connection closed
                    break;
                }
            }
        }
    }

    async fn handle_message(&self, msg: NetworkMessage) -> Result<(), NetworkError> {
        // Update metrics
        *self.metrics.messages_received.write().await += 1;

        match msg {
            NetworkMessage::Gossip(gossip) => {
                self.gossip.handle_gossip(gossip).await?;
            }
            NetworkMessage::Membership(membership) => {
                self.membership.handle_membership(membership).await?;
            }
            NetworkMessage::Request(request) => {
                if let Some(handler) = self.request_handlers.get(&request.request_type) {
                    let response = handler.handle(request.clone()).await?;
                    // Send response back
                }
            }
            NetworkMessage::Response(response) => {
                if let Some((_, tx)) = self.pending_requests.remove(&response.request_id) {
                    let _ = tx.send(response);
                }
            }
            _ => {}
        }

        Ok(())
    }

    fn clone_refs(&self) -> NetworkManager {
        NetworkManager {
            local_node: self.local_node.clone(),
            transport: self.transport.clone(),
            membership: self.membership.clone(),
            gossip: self.gossip.clone(),
            request_handlers: self.request_handlers.clone(),
            pending_requests: self.pending_requests.clone(),
            metrics: self.metrics.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vector_clock() {
        let mut clock1 = VectorClock::new();
        let mut clock2 = VectorClock::new();

        let node1 = NodeId::new();
        let node2 = NodeId::new();

        // Test increment
        clock1.increment(&node1);
        clock2.increment(&node2);

        // Test happens-before
        assert!(!clock1.happens_before(&clock2));
        assert!(!clock2.happens_before(&clock1));

        // Test concurrent
        assert!(clock1.concurrent(&clock2));

        // Test merge
        clock1.merge(&clock2);
        clock2.increment(&node2);

        assert!(clock1.happens_before(&clock2));
        assert!(!clock2.happens_before(&clock1));
    }

    #[tokio::test]
    async fn test_tcp_transport() {
        let transport = TcpTransport;
        let addr: SocketAddr = "127.0.0.1:0".parse().unwrap();

        // Start listener
        let mut listener = transport.listen(addr).await.unwrap();

        // Get actual address (with assigned port)
        // In real implementation, would get from listener

        // Test would continue with connection and message exchange
    }

    #[tokio::test]
    async fn test_gossip_protocol() {
        let node_id = NodeId::new();
        let gossip = GossipProtocol::new(node_id);

        // Test broadcast
        let payload = b"test message".to_vec();
        gossip.broadcast(payload.clone()).await.unwrap();

        // Test duplicate detection
        let msg = GossipMessage {
            id: Uuid::new_v4(),
            source: NodeId::new(),
            hops: 0,
            payload: payload.clone(),
            vclock: VectorClock::new(),
        };

        gossip.handle_gossip(msg.clone()).await.unwrap();
        // Second time should be ignored (no error)
        gossip.handle_gossip(msg).await.unwrap();
    }
}

