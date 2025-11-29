// WebSocket request handlers with Axum integration
//
// References:
// - Vinoski, S. (2007). Advanced Message Queuing Protocol. IEEE Internet Computing.
// - Eugster, P. T., et al. (2003). The many faces of publish/subscribe. ACM Computing Surveys.

use crate::{
    Result, WebSocketError, WebSocketConfig, WebSocketHub,
    Message, MessageType, MessageCodec, JsonCodec,
    ClientInfo, ConnectionState,
};
use beagle_core::BeagleContext;
use beagle_llm::{RequestMeta, TieredRouter};

use axum::{
    extract::{
        ws::{WebSocket, WebSocketUpgrade},
        State, Query, Path,
    },
    response::Response,
    http::StatusCode,
};
use axum_extra::TypedHeader;
use headers::authorization::Bearer;
use headers::Authorization;

use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::collections::HashMap;
use tokio::sync::{RwLock, mpsc};
use tokio::time::{timeout, interval};
use futures_util::{SinkExt, StreamExt};
use uuid::Uuid;
use serde::{Deserialize, Serialize};
use tracing::{debug, info, warn, error, instrument, span, Level};

// ========================= WebSocket Handler =========================

pub struct WebSocketHandler {
    hub: Arc<WebSocketHub>,
    context: Arc<BeagleContext>,
    config: Arc<WebSocketConfig>,
    codec: Arc<dyn MessageCodec>,
}

impl WebSocketHandler {
    pub fn new(
        hub: Arc<WebSocketHub>,
        context: Arc<BeagleContext>,
        config: Arc<WebSocketConfig>,
    ) -> Self {
        Self {
            hub,
            context,
            config,
            codec: Arc::new(JsonCodec),
        }
    }

    #[instrument(skip(self, ws, auth))]
    pub async fn handle_upgrade(
        self: Arc<Self>,
        ws: WebSocketUpgrade,
        auth: Option<TypedHeader<Authorization<Bearer>>>,
        query: Query<ConnectionParams>,
    ) -> Response {
        // Validate authentication if required
        if self.config.security.require_auth {
            if let Some(auth) = auth {
                if !self.validate_token(auth.token()).await {
                    return (StatusCode::UNAUTHORIZED, "Invalid token").into_response();
                }
            } else {
                return (StatusCode::UNAUTHORIZED, "Authentication required").into_response();
            }
        }

        // Accept WebSocket connection
        ws.on_upgrade(move |socket| self.handle_socket(socket, query.0))
    }

    #[instrument(skip(self, socket))]
    async fn handle_socket(
        self: Arc<Self>,
        socket: WebSocket,
        params: ConnectionParams,
    ) {
        let client_id = Uuid::new_v4();
        let (mut sender, mut receiver) = socket.split();

        // Create client info
        let client_info = ClientInfo {
            id: client_id,
            user_id: params.user_id.clone(),
            connection_time: Instant::now(),
            last_activity: Instant::now(),
            subscriptions: params.topics.clone().unwrap_or_default().into_iter().collect(),
            metadata: HashMap::new(),
            state: ConnectionState::Connected,
        };

        // Register client
        if let Err(e) = self.hub.register_client(client_info).await {
            error!("Failed to register client {}: {}", client_id, e);
            return;
        }

        info!("WebSocket client connected: {}", client_id);

        // Create channels for bidirectional communication
        let (tx, mut rx) = mpsc::channel::<Message>(1000);

        // Subscribe to broadcasts
        let mut broadcast_rx = self.hub.get_manager().get_broadcast_receiver();

        // Spawn sender task
        let handler_clone = self.clone();
        let sender_task = tokio::spawn(async move {
            loop {
                tokio::select! {
                    // Send queued messages
                    Some(msg) = rx.recv() => {
                        let encoded = handler_clone.codec.encode(&msg).unwrap();
                        if sender.send(axum::extract::ws::Message::Binary(encoded.to_vec())).await.is_err() {
                            break;
                        }
                    }

                    // Send broadcast messages
                    Ok(msg) = broadcast_rx.recv() => {
                        let encoded = handler_clone.codec.encode(&msg).unwrap();
                        if sender.send(axum::extract::ws::Message::Binary(encoded.to_vec())).await.is_err() {
                            break;
                        }
                    }

                    else => break,
                }
            }
        });

        // Spawn heartbeat task
        let hub_clone = self.hub.clone();
        let heartbeat_task = tokio::spawn(async move {
            let mut interval = interval(Duration::from_secs(30));

            loop {
                interval.tick().await;
                hub_clone.get_registry().update_activity(client_id).await;

                let ping = Message {
                    id: Uuid::new_v4(),
                    message_type: MessageType::Ping,
                    payload: vec![],
                    timestamp: SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap()
                        .as_millis() as u64,
                    metadata: HashMap::new(),
                };

                if tx.send(ping).await.is_err() {
                    break;
                }
            }
        });

        // Handle incoming messages
        while let Some(msg) = receiver.next().await {
            match msg {
                Ok(axum::extract::ws::Message::Binary(data)) => {
                    if let Ok(message) = self.codec.decode(&data) {
                        if let Err(e) = self.handle_message(client_id, message).await {
                            error!("Error handling message: {}", e);
                        }
                    }
                }

                Ok(axum::extract::ws::Message::Text(text)) => {
                    let message = Message {
                        id: Uuid::new_v4(),
                        message_type: MessageType::Text,
                        payload: text.into_bytes(),
                        timestamp: SystemTime::now()
                            .duration_since(UNIX_EPOCH)
                            .unwrap()
                            .as_millis() as u64,
                        metadata: HashMap::new(),
                    };

                    if let Err(e) = self.handle_message(client_id, message).await {
                        error!("Error handling message: {}", e);
                    }
                }

                Ok(axum::extract::ws::Message::Close(_)) => {
                    info!("Client {} closing connection", client_id);
                    break;
                }

                Ok(axum::extract::ws::Message::Pong(_)) => {
                    self.hub.get_registry().update_activity(client_id).await;
                }

                Err(e) => {
                    error!("WebSocket error for client {}: {}", client_id, e);
                    break;
                }

                _ => {}
            }
        }

        // Cleanup
        sender_task.abort();
        heartbeat_task.abort();

        if let Err(e) = self.hub.unregister_client(client_id).await {
            error!("Failed to unregister client {}: {}", client_id, e);
        }

        info!("WebSocket client disconnected: {}", client_id);
    }

    #[instrument(skip(self, message))]
    async fn handle_message(&self, client_id: Uuid, message: Message) -> Result<()> {
        self.hub.get_registry().update_activity(client_id).await;

        match message.message_type {
            MessageType::Subscribe => {
                if let Ok(topic) = String::from_utf8(message.payload.clone()) {
                    self.hub.get_registry()
                        .subscribe_to_topic(client_id, topic)
                        .await?;
                }
            }

            MessageType::Unsubscribe => {
                if let Ok(topic) = String::from_utf8(message.payload.clone()) {
                    self.hub.get_registry()
                        .unsubscribe_from_topic(client_id, &topic)
                        .await?;
                }
            }

            MessageType::Sync => {
                // Handle sync operation
                self.handle_sync_message(client_id, message).await?;
            }

            MessageType::Text | MessageType::Binary => {
                // Process with LLM if needed
                self.process_with_llm(client_id, message).await?;
            }

            _ => {
                debug!("Received message type: {:?}", message.message_type);
            }
        }

        Ok(())
    }

    async fn handle_sync_message(&self, client_id: Uuid, message: Message) -> Result<()> {
        // Parse sync operation
        if let Ok(sync_op) = serde_json::from_slice::<crate::sync::SyncOperation>(&message.payload) {
            // Apply through sync engine
            let manager = self.hub.get_manager();
            let command = crate::hub::HubCommand::Sync(sync_op);

            manager.get_command_sender()
                .send(command)
                .await
                .map_err(|e| WebSocketError::SyncError(e.to_string()))?;
        }

        Ok(())
    }

    async fn process_with_llm(&self, client_id: Uuid, message: Message) -> Result<()> {
        // Convert message to text
        let text = String::from_utf8(message.payload.clone())
            .unwrap_or_else(|_| format!("{:?}", message.payload));

        // Use TieredRouter for processing
        let meta = RequestMeta {
            requires_low_latency: true,  // WebSocket needs fast responses
            ..Default::default()
        };

        let router = &self.context.router;
        let stats = beagle_llm::LlmCallStats::default();
        let (client, _tier) = router.choose_with_limits(&meta, &stats)
            .map_err(|e| WebSocketError::ConnectionError(e.to_string()))?;

        let prompt = format!("Process WebSocket message: {}", text);
        let response = client.complete(&prompt).await
            .map_err(|e| WebSocketError::ConnectionError(e.to_string()))?;

        // Send response back to client
        let response_msg = Message {
            id: Uuid::new_v4(),
            message_type: MessageType::Text,
            payload: response.content.into_bytes(),
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64,
            metadata: message.metadata,
        };

        self.hub.send_to_client(client_id, response_msg).await?;

        Ok(())
    }

    async fn validate_token(&self, token: &str) -> bool {
        // Implement JWT validation
        // For now, simple check
        !token.is_empty()
    }
}

#[derive(Debug, Deserialize)]
pub struct ConnectionParams {
    pub user_id: Option<String>,
    pub topics: Option<Vec<String>>,
    pub protocol_version: Option<String>,
}

// ========================= Message Handler =========================

#[async_trait::async_trait]
pub trait MessageHandler: Send + Sync {
    async fn handle(&self, message: Message) -> Result<Option<Message>>;
}

pub struct DefaultMessageHandler {
    context: Arc<BeagleContext>,
}

#[async_trait::async_trait]
impl MessageHandler for DefaultMessageHandler {
    async fn handle(&self, message: Message) -> Result<Option<Message>> {
        // Default message processing
        Ok(Some(message))
    }
}

// ========================= Event Handler =========================

#[async_trait::async_trait]
pub trait EventHandler: Send + Sync {
    async fn on_connect(&self, client_id: Uuid) -> Result<()>;
    async fn on_disconnect(&self, client_id: Uuid) -> Result<()>;
    async fn on_message(&self, client_id: Uuid, message: Message) -> Result<()>;
    async fn on_error(&self, client_id: Uuid, error: WebSocketError) -> Result<()>;
}

pub struct DefaultEventHandler;

#[async_trait::async_trait]
impl EventHandler for DefaultEventHandler {
    async fn on_connect(&self, client_id: Uuid) -> Result<()> {
        info!("Client connected: {}", client_id);
        Ok(())
    }

    async fn on_disconnect(&self, client_id: Uuid) -> Result<()> {
        info!("Client disconnected: {}", client_id);
        Ok(())
    }

    async fn on_message(&self, client_id: Uuid, message: Message) -> Result<()> {
        debug!("Message from {}: {:?}", client_id, message.message_type);
        Ok(())
    }

    async fn on_error(&self, client_id: Uuid, error: WebSocketError) -> Result<()> {
        error!("Error for client {}: {}", client_id, error);
        Ok(())
    }
}
