// WebSocket connection management
//
// References:
// - Stevens, W. R., et al. (2003). UNIX Network Programming, Volume 1.
// - Tanenbaum, A. S., & Wetherall, D. J. (2010). Computer Networks.

use crate::{Result, WebSocketError, Message, MessageCodec};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{RwLock, mpsc, Mutex};
use uuid::Uuid;
use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::WebSocketStream;
use std::collections::HashMap;
use tracing::{debug, info, warn, error, instrument};

#[derive(Debug, Clone, PartialEq)]
pub enum ConnectionState {
    Connecting,
    Connected,
    Authenticated,
    Disconnecting,
    Disconnected,
    Error,
}

pub struct WebSocketConnection {
    pub id: Uuid,
    pub state: Arc<RwLock<ConnectionState>>,
    pub created_at: Instant,
    pub last_activity: Arc<RwLock<Instant>>,
    pub metadata: Arc<RwLock<HashMap<String, String>>>,
    sender: mpsc::Sender<Message>,
    receiver: Arc<Mutex<mpsc::Receiver<Message>>>,
}

impl WebSocketConnection {
    pub fn new() -> Self {
        let (sender, receiver) = mpsc::channel(1000);

        Self {
            id: Uuid::new_v4(),
            state: Arc::new(RwLock::new(ConnectionState::Connecting)),
            created_at: Instant::now(),
            last_activity: Arc::new(RwLock::new(Instant::now())),
            metadata: Arc::new(RwLock::new(HashMap::new())),
            sender,
            receiver: Arc::new(Mutex::new(receiver)),
        }
    }

    pub async fn send(&self, message: Message) -> Result<()> {
        self.sender.send(message).await
            .map_err(|_| WebSocketError::ConnectionError("Channel closed".into()))?;

        let mut last_activity = self.last_activity.write().await;
        *last_activity = Instant::now();

        Ok(())
    }

    pub async fn receive(&self) -> Option<Message> {
        let mut receiver = self.receiver.lock().await;
        receiver.recv().await
    }

    pub async fn set_state(&self, state: ConnectionState) {
        let mut current_state = self.state.write().await;
        *current_state = state;
    }

    pub async fn get_state(&self) -> ConnectionState {
        self.state.read().await.clone()
    }

    pub async fn is_active(&self) -> bool {
        matches!(
            self.get_state().await,
            ConnectionState::Connected | ConnectionState::Authenticated
        )
    }

    pub async fn update_activity(&self) {
        let mut last_activity = self.last_activity.write().await;
        *last_activity = Instant::now();
    }

    pub async fn idle_time(&self) -> Duration {
        let last_activity = self.last_activity.read().await;
        Instant::now().duration_since(*last_activity)
    }
}

pub struct ConnectionManager {
    connections: Arc<DashMap<Uuid, Arc<WebSocketConnection>>>,
    max_connections: usize,
    idle_timeout: Duration,
}

impl ConnectionManager {
    pub fn new(max_connections: usize, idle_timeout: Duration) -> Self {
        Self {
            connections: Arc::new(DashMap::new()),
            max_connections,
            idle_timeout,
        }
    }

    #[instrument(skip(self, connection))]
    pub async fn add_connection(&self, connection: Arc<WebSocketConnection>) -> Result<()> {
        if self.connections.len() >= self.max_connections {
            return Err(WebSocketError::ConnectionError("Max connections reached".into()));
        }

        self.connections.insert(connection.id, connection.clone());
        info!("Connection added: {}", connection.id);

        Ok(())
    }

    #[instrument(skip(self))]
    pub async fn remove_connection(&self, id: Uuid) -> Option<Arc<WebSocketConnection>> {
        self.connections.remove(&id).map(|(_, conn)| {
            info!("Connection removed: {}", id);
            conn
        })
    }

    pub async fn get_connection(&self, id: Uuid) -> Option<Arc<WebSocketConnection>> {
        self.connections.get(&id).map(|entry| entry.clone())
    }

    pub async fn get_all_connections(&self) -> Vec<Arc<WebSocketConnection>> {
        self.connections.iter()
            .map(|entry| entry.value().clone())
            .collect()
    }

    #[instrument(skip(self))]
    pub async fn cleanup_idle_connections(&self) {
        let mut to_remove = Vec::new();

        for entry in self.connections.iter() {
            let connection = entry.value();
            if connection.idle_time().await > self.idle_timeout {
                to_remove.push(connection.id);
            }
        }

        for id in to_remove {
            self.remove_connection(id).await;
        }
    }

    pub fn connection_count(&self) -> usize {
        self.connections.len()
    }

    #[instrument(skip(self))]
    pub async fn broadcast(&self, message: Message) -> Result<()> {
        let connections = self.get_all_connections().await;
        let mut failed = 0;

        for connection in connections {
            if connection.is_active().await {
                if let Err(e) = connection.send(message.clone()).await {
                    warn!("Failed to send to {}: {}", connection.id, e);
                    failed += 1;
                }
            }
        }

        if failed > 0 {
            warn!("Broadcast failed for {} connections", failed);
        }

        Ok(())
    }
}

use dashmap::DashMap;
