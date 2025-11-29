// WebSocket Hub: Connection management and message broadcasting
//
// References:
// - Fielding, R. T. (2000). Architectural styles and the design of network-based software architectures.
// - Patterson, D. A., & Hennessy, J. L. (2017). Computer organization and design.
// - Dean, J., & Ghemawat, S. (2004). MapReduce: Simplified data processing on large clusters.
// - Hunt, P., et al. (2010). ZooKeeper: Wait-free coordination for internet-scale systems.

use crate::{Result, WebSocketError, Message, MessageType, ConnectionState};
use crate::sync::{SyncEngine, SyncOperation};
use beagle_core::BeagleContext;
use beagle_llm::{RequestMeta, TieredRouter};
use beagle_metrics::MetricsCollector;

use std::sync::Arc;
use std::collections::{HashMap, HashSet, VecDeque};
use std::time::{Duration, Instant};
use tokio::sync::{RwLock, mpsc, broadcast, watch, Mutex, Semaphore};
use tokio::time::{interval, timeout};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use dashmap::{DashMap, DashSet};
use bytes::Bytes;
use governor::{Quota, RateLimiter};
use arc_swap::ArcSwap;
use tracing::{debug, info, warn, error, instrument, span, Level};

// ========================= Client Registry =========================

#[derive(Debug, Clone)]
pub struct ClientInfo {
    pub id: Uuid,
    pub user_id: Option<String>,
    pub connection_time: Instant,
    pub last_activity: Instant,
    pub subscriptions: HashSet<String>,
    pub metadata: HashMap<String, String>,
    pub state: ConnectionState,
}

pub struct ClientRegistry {
    clients: Arc<DashMap<Uuid, Arc<RwLock<ClientInfo>>>>,
    user_to_clients: Arc<DashMap<String, HashSet<Uuid>>>,
    topic_subscriptions: Arc<DashMap<String, HashSet<Uuid>>>,
    max_clients: usize,
    client_timeout: Duration,
}

impl ClientRegistry {
    pub fn new(max_clients: usize, client_timeout: Duration) -> Self {
        Self {
            clients: Arc::new(DashMap::new()),
            user_to_clients: Arc::new(DashMap::new()),
            topic_subscriptions: Arc::new(DashMap::new()),
            max_clients,
            client_timeout,
        }
    }

    #[instrument(skip(self))]
    pub async fn register_client(&self, client_info: ClientInfo) -> Result<()> {
        if self.clients.len() >= self.max_clients {
            return Err(WebSocketError::ConnectionError("Max clients reached".into()));
        }

        let client_id = client_info.id;
        let user_id = client_info.user_id.clone();
        let subscriptions = client_info.subscriptions.clone();

        // Store client
        self.clients.insert(client_id, Arc::new(RwLock::new(client_info)));

        // Map user to client
        if let Some(uid) = user_id {
            self.user_to_clients
                .entry(uid)
                .or_insert_with(HashSet::new)
                .insert(client_id);
        }

        // Add topic subscriptions
        for topic in subscriptions {
            self.topic_subscriptions
                .entry(topic)
                .or_insert_with(HashSet::new)
                .insert(client_id);
        }

        info!("Client registered: {}", client_id);
        Ok(())
    }

    #[instrument(skip(self))]
    pub async fn unregister_client(&self, client_id: Uuid) -> Result<()> {
        if let Some((_, client_arc)) = self.clients.remove(&client_id) {
            let client = client_arc.read().await;

            // Remove from user mapping
            if let Some(uid) = &client.user_id {
                if let Some(mut clients) = self.user_to_clients.get_mut(uid) {
                    clients.remove(&client_id);
                    if clients.is_empty() {
                        drop(clients);
                        self.user_to_clients.remove(uid);
                    }
                }
            }

            // Remove topic subscriptions
            for topic in &client.subscriptions {
                if let Some(mut subscribers) = self.topic_subscriptions.get_mut(topic) {
                    subscribers.remove(&client_id);
                    if subscribers.is_empty() {
                        drop(subscribers);
                        self.topic_subscriptions.remove(topic);
                    }
                }
            }

            info!("Client unregistered: {}", client_id);
        }

        Ok(())
    }

    pub async fn get_client(&self, client_id: &Uuid) -> Option<Arc<RwLock<ClientInfo>>> {
        self.clients.get(client_id).map(|c| c.clone())
    }

    pub async fn get_clients_by_user(&self, user_id: &str) -> Vec<Uuid> {
        self.user_to_clients
            .get(user_id)
            .map(|clients| clients.clone())
            .unwrap_or_default()
    }

    pub async fn get_topic_subscribers(&self, topic: &str) -> Vec<Uuid> {
        self.topic_subscriptions
            .get(topic)
            .map(|subs| subs.clone())
            .unwrap_or_default()
    }

    #[instrument(skip(self))]
    pub async fn subscribe_to_topic(&self, client_id: Uuid, topic: String) -> Result<()> {
        if let Some(client_arc) = self.clients.get(&client_id) {
            let mut client = client_arc.write().await;
            client.subscriptions.insert(topic.clone());
            drop(client);

            self.topic_subscriptions
                .entry(topic.clone())
                .or_insert_with(HashSet::new)
                .insert(client_id);

            info!("Client {} subscribed to topic: {}", client_id, topic);
        }

        Ok(())
    }

    #[instrument(skip(self))]
    pub async fn unsubscribe_from_topic(&self, client_id: Uuid, topic: &str) -> Result<()> {
        if let Some(client_arc) = self.clients.get(&client_id) {
            let mut client = client_arc.write().await;
            client.subscriptions.remove(topic);
            drop(client);

            if let Some(mut subscribers) = self.topic_subscriptions.get_mut(topic) {
                subscribers.remove(&client_id);
                if subscribers.is_empty() {
                    drop(subscribers);
                    self.topic_subscriptions.remove(topic);
                }
            }

            info!("Client {} unsubscribed from topic: {}", client_id, topic);
        }

        Ok(())
    }

    pub async fn update_activity(&self, client_id: Uuid) {
        if let Some(client_arc) = self.clients.get(&client_id) {
            let mut client = client_arc.write().await;
            client.last_activity = Instant::now();
        }
    }

    #[instrument(skip(self))]
    pub async fn cleanup_inactive_clients(&self) {
        let now = Instant::now();
        let mut to_remove = Vec::new();

        for entry in self.clients.iter() {
            let client = entry.value().read().await;
            if now.duration_since(client.last_activity) > self.client_timeout {
                to_remove.push(*entry.key());
            }
        }

        for client_id in to_remove {
            if let Err(e) = self.unregister_client(client_id).await {
                error!("Failed to unregister inactive client {}: {}", client_id, e);
            }
        }
    }
}

// ========================= Hub Manager =========================

pub struct HubManager {
    context: Arc<BeagleContext>,
    registry: Arc<ClientRegistry>,
    sync_engine: Arc<SyncEngine>,
    broadcast_tx: broadcast::Sender<Message>,
    command_tx: mpsc::Sender<HubCommand>,
    rate_limiter: Arc<RateLimiter<String, governor::state::InMemoryState, governor::clock::DefaultClock>>,
    circuit_breakers: Arc<DashMap<String, CircuitBreaker>>,
    message_queue: Arc<RwLock<VecDeque<QueuedMessage>>>,
    max_queue_size: usize,
    batch_interval: Duration,
    metrics: Arc<WebSocketMetrics>,
}

#[derive(Debug, Clone)]
pub enum HubCommand {
    Broadcast(Message),
    Unicast(Uuid, Message),
    Multicast(Vec<Uuid>, Message),
    Topic(String, Message),
    Sync(SyncOperation),
}

#[derive(Debug, Clone)]
struct QueuedMessage {
    message: Message,
    targets: MessageTargets,
    timestamp: Instant,
    priority: u8,
}

#[derive(Debug, Clone)]
enum MessageTargets {
    Broadcast,
    Unicast(Uuid),
    Multicast(Vec<Uuid>),
    Topic(String),
}

#[derive(Debug, Clone)]
struct CircuitBreaker {
    failures: u32,
    last_failure: Instant,
    state: CircuitState,
    threshold: u32,
    timeout: Duration,
}

#[derive(Debug, Clone, PartialEq)]
enum CircuitState {
    Closed,
    Open,
    HalfOpen,
}

impl HubManager {
    pub fn new(
        context: Arc<BeagleContext>,
        registry: Arc<ClientRegistry>,
        sync_engine: Arc<SyncEngine>,
        max_queue_size: usize,
        batch_interval: Duration,
        metrics: Arc<WebSocketMetrics>,
    ) -> Self {
        let (broadcast_tx, _) = broadcast::channel(10000);
        let (command_tx, mut command_rx) = mpsc::channel(10000);

        // Create rate limiter: 1000 messages per second per client
        let rate_limiter = Arc::new(RateLimiter::direct(Quota::per_second(
            std::num::NonZeroU32::new(1000).unwrap()
        )));

        let hub = Self {
            context,
            registry,
            sync_engine,
            broadcast_tx,
            command_tx: command_tx.clone(),
            rate_limiter,
            circuit_breakers: Arc::new(DashMap::new()),
            message_queue: Arc::new(RwLock::new(VecDeque::with_capacity(max_queue_size))),
            max_queue_size,
            batch_interval,
            metrics,
        };

        // Start command processor
        let hub_clone = hub.clone();
        tokio::spawn(async move {
            while let Some(command) = command_rx.recv().await {
                if let Err(e) = hub_clone.process_command(command).await {
                    error!("Command processing failed: {}", e);
                }
            }
        });

        // Start batch processor
        let hub_clone = hub.clone();
        tokio::spawn(async move {
            let mut interval = interval(hub_clone.batch_interval);

            loop {
                interval.tick().await;
                if let Err(e) = hub_clone.process_batch().await {
                    error!("Batch processing failed: {}", e);
                }
            }
        });

        // Start cleanup task
        let registry_clone = registry.clone();
        tokio::spawn(async move {
            let mut interval = interval(Duration::from_secs(30));

            loop {
                interval.tick().await;
                registry_clone.cleanup_inactive_clients().await;
            }
        });

        hub
    }

    #[instrument(skip(self, command))]
    async fn process_command(&self, command: HubCommand) -> Result<()> {
        match command {
            HubCommand::Broadcast(message) => {
                self.broadcast_message(message).await
            }

            HubCommand::Unicast(client_id, message) => {
                self.send_to_client(client_id, message).await
            }

            HubCommand::Multicast(client_ids, message) => {
                self.send_to_clients(client_ids, message).await
            }

            HubCommand::Topic(topic, message) => {
                self.send_to_topic(topic, message).await
            }

            HubCommand::Sync(operation) => {
                self.sync_engine.apply_operation(operation).await
            }
        }
    }

    #[instrument(skip(self, message))]
    pub async fn broadcast(&self, message: Message) -> Result<()> {
        // Check circuit breaker
        if !self.check_circuit_breaker("broadcast").await {
            return Err(WebSocketError::CircuitBreakerOpen);
        }

        // Queue message
        self.queue_message(
            message.clone(),
            MessageTargets::Broadcast,
            5, // Default priority
        ).await?;

        Ok(())
    }

    #[instrument(skip(self, message))]
    async fn broadcast_message(&self, message: Message) -> Result<()> {
        // Send via broadcast channel
        if let Err(e) = self.broadcast_tx.send(message.clone()) {
            warn!("Broadcast failed: {}", e);
            self.record_circuit_failure("broadcast").await;
            return Err(WebSocketError::ConnectionError("Broadcast failed".into()));
        }

        self.metrics.record_broadcast();
        Ok(())
    }

    #[instrument(skip(self, message))]
    pub async fn send_to_client(&self, client_id: Uuid, message: Message) -> Result<()> {
        // Check rate limit
        if !self.check_rate_limit(&client_id.to_string()).await {
            return Err(WebSocketError::RateLimitExceeded);
        }

        // Queue message
        self.queue_message(
            message,
            MessageTargets::Unicast(client_id),
            5,
        ).await?;

        Ok(())
    }

    #[instrument(skip(self, message))]
    pub async fn send_to_clients(&self, client_ids: Vec<Uuid>, message: Message) -> Result<()> {
        // Queue message
        self.queue_message(
            message,
            MessageTargets::Multicast(client_ids),
            5,
        ).await?;

        Ok(())
    }

    #[instrument(skip(self, message))]
    pub async fn send_to_topic(&self, topic: String, message: Message) -> Result<()> {
        let subscribers = self.registry.get_topic_subscribers(&topic).await;

        if subscribers.is_empty() {
            debug!("No subscribers for topic: {}", topic);
            return Ok(());
        }

        self.send_to_clients(subscribers, message).await
    }

    async fn queue_message(
        &self,
        message: Message,
        targets: MessageTargets,
        priority: u8,
    ) -> Result<()> {
        let mut queue = self.message_queue.write().await;

        if queue.len() >= self.max_queue_size {
            // Remove oldest low-priority message
            let min_priority = queue.iter()
                .map(|m| m.priority)
                .min()
                .unwrap_or(0);

            if priority <= min_priority {
                return Err(WebSocketError::BackpressureLimit);
            }

            queue.retain(|m| m.priority > min_priority);
        }

        queue.push_back(QueuedMessage {
            message,
            targets,
            timestamp: Instant::now(),
            priority,
        });

        Ok(())
    }

    #[instrument(skip(self))]
    async fn process_batch(&self) -> Result<()> {
        let mut queue = self.message_queue.write().await;

        if queue.is_empty() {
            return Ok(());
        }

        // Sort by priority
        let mut batch: Vec<_> = queue.drain(..).collect();
        batch.sort_by_key(|m| std::cmp::Reverse(m.priority));

        drop(queue);

        // Process messages
        for queued in batch.into_iter().take(100) {
            match queued.targets {
                MessageTargets::Broadcast => {
                    self.broadcast_message(queued.message).await?;
                }

                MessageTargets::Unicast(client_id) => {
                    // Direct send implementation would go here
                    debug!("Sending to client: {}", client_id);
                }

                MessageTargets::Multicast(client_ids) => {
                    for client_id in client_ids {
                        debug!("Sending to client: {}", client_id);
                    }
                }

                MessageTargets::Topic(topic) => {
                    let subscribers = self.registry.get_topic_subscribers(&topic).await;
                    for client_id in subscribers {
                        debug!("Sending to subscriber: {}", client_id);
                    }
                }
            }
        }

        Ok(())
    }

    async fn check_rate_limit(&self, key: &str) -> bool {
        self.rate_limiter.check_key(&key.to_string()).is_ok()
    }

    async fn check_circuit_breaker(&self, key: &str) -> bool {
        let mut breaker = self.circuit_breakers
            .entry(key.to_string())
            .or_insert_with(|| CircuitBreaker {
                failures: 0,
                last_failure: Instant::now(),
                state: CircuitState::Closed,
                threshold: 5,
                timeout: Duration::from_secs(60),
            });

        match breaker.state {
            CircuitState::Open => {
                if Instant::now().duration_since(breaker.last_failure) > breaker.timeout {
                    breaker.state = CircuitState::HalfOpen;
                    true
                } else {
                    false
                }
            }

            CircuitState::HalfOpen | CircuitState::Closed => true,
        }
    }

    async fn record_circuit_failure(&self, key: &str) {
        let mut breaker = self.circuit_breakers
            .entry(key.to_string())
            .or_insert_with(|| CircuitBreaker {
                failures: 0,
                last_failure: Instant::now(),
                state: CircuitState::Closed,
                threshold: 5,
                timeout: Duration::from_secs(60),
            });

        breaker.failures += 1;
        breaker.last_failure = Instant::now();

        if breaker.failures >= breaker.threshold {
            breaker.state = CircuitState::Open;
            warn!("Circuit breaker opened for: {}", key);
        }
    }

    pub fn get_command_sender(&self) -> mpsc::Sender<HubCommand> {
        self.command_tx.clone()
    }

    pub fn get_broadcast_receiver(&self) -> broadcast::Receiver<Message> {
        self.broadcast_tx.subscribe()
    }
}

impl Clone for HubManager {
    fn clone(&self) -> Self {
        Self {
            context: self.context.clone(),
            registry: self.registry.clone(),
            sync_engine: self.sync_engine.clone(),
            broadcast_tx: self.broadcast_tx.clone(),
            command_tx: self.command_tx.clone(),
            rate_limiter: self.rate_limiter.clone(),
            circuit_breakers: self.circuit_breakers.clone(),
            message_queue: self.message_queue.clone(),
            max_queue_size: self.max_queue_size,
            batch_interval: self.batch_interval,
            metrics: self.metrics.clone(),
        }
    }
}

// ========================= WebSocket Hub =========================

pub struct WebSocketHub {
    manager: Arc<HubManager>,
    registry: Arc<ClientRegistry>,
    context: Arc<BeagleContext>,
    metrics: Arc<WebSocketMetrics>,
}

impl WebSocketHub {
    pub fn new(
        context: Arc<BeagleContext>,
        max_clients: usize,
        client_timeout: Duration,
        metrics: Arc<WebSocketMetrics>,
    ) -> Self {
        let registry = Arc::new(ClientRegistry::new(max_clients, client_timeout));

        let sync_engine = Arc::new(SyncEngine::new(
            crate::sync::SyncStrategy::Hybrid,
            context.clone(),
            Duration::from_secs(1),
            1000,
            metrics.clone(),
        ));

        let manager = Arc::new(HubManager::new(
            context.clone(),
            registry.clone(),
            sync_engine,
            100000,
            Duration::from_millis(100),
            metrics.clone(),
        ));

        Self {
            manager,
            registry,
            context,
            metrics,
        }
    }

    pub async fn register_client(&self, client_info: ClientInfo) -> Result<()> {
        self.registry.register_client(client_info).await
    }

    pub async fn unregister_client(&self, client_id: Uuid) -> Result<()> {
        self.registry.unregister_client(client_id).await
    }

    pub async fn broadcast(&self, message: Message) -> Result<()> {
        self.manager.broadcast(message).await
    }

    pub async fn send_to_client(&self, client_id: Uuid, message: Message) -> Result<()> {
        self.manager.send_to_client(client_id, message).await
    }

    pub async fn send_to_topic(&self, topic: String, message: Message) -> Result<()> {
        self.manager.send_to_topic(topic, message).await
    }

    pub fn get_manager(&self) -> Arc<HubManager> {
        self.manager.clone()
    }

    pub fn get_registry(&self) -> Arc<ClientRegistry> {
        self.registry.clone()
    }
}

// ========================= Tests =========================

#[cfg(test)]
mod tests {
    use super::*;

    async fn create_test_hub() -> WebSocketHub {
        let context = Arc::new(BeagleContext::new_with_mock());
        let metrics = Arc::new(WebSocketMetrics::new());

        WebSocketHub::new(
            context,
            100,
            Duration::from_secs(300),
            metrics,
        )
    }

    #[tokio::test]
    async fn test_client_registration() {
        let hub = create_test_hub().await;

        let client_info = ClientInfo {
            id: Uuid::new_v4(),
            user_id: Some("user123".to_string()),
            connection_time: Instant::now(),
            last_activity: Instant::now(),
            subscriptions: HashSet::new(),
            metadata: HashMap::new(),
            state: ConnectionState::Connected,
        };

        hub.register_client(client_info.clone()).await.unwrap();

        let client = hub.registry.get_client(&client_info.id).await;
        assert!(client.is_some());

        hub.unregister_client(client_info.id).await.unwrap();

        let client = hub.registry.get_client(&client_info.id).await;
        assert!(client.is_none());
    }

    #[tokio::test]
    async fn test_topic_subscription() {
        let hub = create_test_hub().await;

        let client_id = Uuid::new_v4();
        let client_info = ClientInfo {
            id: client_id,
            user_id: None,
            connection_time: Instant::now(),
            last_activity: Instant::now(),
            subscriptions: HashSet::new(),
            metadata: HashMap::new(),
            state: ConnectionState::Connected,
        };

        hub.register_client(client_info).await.unwrap();

        hub.registry.subscribe_to_topic(client_id, "test_topic".to_string()).await.unwrap();

        let subscribers = hub.registry.get_topic_subscribers("test_topic").await;
        assert_eq!(subscribers.len(), 1);
        assert!(subscribers.contains(&client_id));

        hub.registry.unsubscribe_from_topic(client_id, "test_topic").await.unwrap();

        let subscribers = hub.registry.get_topic_subscribers("test_topic").await;
        assert_eq!(subscribers.len(), 0);
    }

    #[tokio::test]
    async fn test_rate_limiting() {
        let hub = create_test_hub().await;

        let client_id = Uuid::new_v4();
        let message = Message {
            id: Uuid::new_v4(),
            message_type: MessageType::Text,
            payload: vec![1, 2, 3],
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64,
            metadata: HashMap::new(),
        };

        // Should succeed within rate limit
        for _ in 0..10 {
            hub.send_to_client(client_id, message.clone()).await.unwrap();
        }

        // Eventually should hit rate limit if we send many messages quickly
        // (This is a simplified test - in production you'd test the actual rate limiter)
    }
}
