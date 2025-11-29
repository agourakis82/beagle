// WebSocket integration tests with Q1 SOTA standards

use beagle_websocket::*;
use beagle_core::BeagleContext;
use tokio::time::{sleep, Duration};
use uuid::Uuid;
use std::sync::Arc;
use std::collections::HashSet;

#[tokio::test]
async fn test_websocket_hub_registration() {
    let context = Arc::new(BeagleContext::new_with_mock());
    let metrics = Arc::new(WebSocketMetrics::new());
    let hub = WebSocketHub::new(context, 100, Duration::from_secs(300), metrics);

    let client_info = ClientInfo {
        id: Uuid::new_v4(),
        user_id: Some("test_user".to_string()),
        connection_time: std::time::Instant::now(),
        last_activity: std::time::Instant::now(),
        subscriptions: HashSet::new(),
        metadata: std::collections::HashMap::new(),
        state: ConnectionState::Connected,
    };

    // Register client
    assert!(hub.register_client(client_info.clone()).await.is_ok());

    // Verify registration
    let registry = hub.get_registry();
    let client = registry.get_client(&client_info.id).await;
    assert!(client.is_some());

    // Unregister client
    assert!(hub.unregister_client(client_info.id).await.is_ok());

    // Verify unregistration
    let client = registry.get_client(&client_info.id).await;
    assert!(client.is_none());
}

#[tokio::test]
async fn test_topic_subscription() {
    let context = Arc::new(BeagleContext::new_with_mock());
    let metrics = Arc::new(WebSocketMetrics::new());
    let hub = WebSocketHub::new(context, 100, Duration::from_secs(300), metrics);

    let client_id = Uuid::new_v4();
    let client_info = ClientInfo {
        id: client_id,
        user_id: None,
        connection_time: std::time::Instant::now(),
        last_activity: std::time::Instant::now(),
        subscriptions: HashSet::new(),
        metadata: std::collections::HashMap::new(),
        state: ConnectionState::Connected,
    };

    hub.register_client(client_info).await.unwrap();

    let registry = hub.get_registry();

    // Subscribe to topic
    registry.subscribe_to_topic(client_id, "test_topic".to_string()).await.unwrap();

    // Verify subscription
    let subscribers = registry.get_topic_subscribers("test_topic").await;
    assert_eq!(subscribers.len(), 1);
    assert!(subscribers.contains(&client_id));

    // Unsubscribe
    registry.unsubscribe_from_topic(client_id, "test_topic").await.unwrap();

    // Verify unsubscription
    let subscribers = registry.get_topic_subscribers("test_topic").await;
    assert_eq!(subscribers.len(), 0);
}

#[tokio::test]
async fn test_message_broadcast() {
    let context = Arc::new(BeagleContext::new_with_mock());
    let metrics = Arc::new(WebSocketMetrics::new());
    let hub = WebSocketHub::new(context, 100, Duration::from_secs(300), metrics);

    // Register multiple clients
    for i in 0..3 {
        let client_info = ClientInfo {
            id: Uuid::new_v4(),
            user_id: Some(format!("user_{}", i)),
            connection_time: std::time::Instant::now(),
            last_activity: std::time::Instant::now(),
            subscriptions: HashSet::new(),
            metadata: std::collections::HashMap::new(),
            state: ConnectionState::Connected,
        };

        hub.register_client(client_info).await.unwrap();
    }

    let message = Message {
        id: Uuid::new_v4(),
        message_type: MessageType::Text,
        payload: b"broadcast test".to_vec(),
        timestamp: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64,
        metadata: std::collections::HashMap::new(),
    };

    // Broadcast should succeed
    assert!(hub.broadcast(message).await.is_ok());
}

#[tokio::test]
async fn test_sync_engine() {
    use beagle_websocket::sync::*;

    let context = Arc::new(BeagleContext::new_with_mock());
    let metrics = Arc::new(WebSocketMetrics::new());

    let engine = SyncEngine::new(
        SyncStrategy::Hybrid,
        context,
        Duration::from_millis(100),
        1000,
        metrics,
    );

    let operation = SyncOperation {
        id: Uuid::new_v4(),
        operation_type: OperationType::Create,
        target: "test_object".to_string(),
        payload: b"test data".to_vec(),
        vector_clock: VectorClock::new(),
        timestamp: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64,
        source_node: "node1".to_string(),
    };

    // Apply operation should succeed
    assert!(engine.apply_operation(operation).await.is_ok());
}

#[tokio::test]
async fn test_crdt_vector_clock() {
    use beagle_websocket::sync::VectorClock;

    let mut clock1 = VectorClock::new();
    clock1.increment("node1");
    clock1.increment("node1");

    let mut clock2 = VectorClock::new();
    clock2.increment("node1");
    clock2.increment("node2");

    // Test concurrent detection
    assert!(clock1.concurrent_with(&clock2));

    // Test merge
    clock1.merge(&clock2);

    // After merge, clock1 should have max values
    // This is tested indirectly through happens_before
    let mut clock3 = VectorClock::new();
    clock3.increment("node1");
    assert!(clock3.happens_before(&clock1));
}

#[tokio::test]
async fn test_or_set_crdt() {
    use beagle_websocket::sync::ORSet;

    let mut set1 = ORSet::<String>::new();
    let id1 = set1.add("item1".to_string());
    let id2 = set1.add("item2".to_string());

    assert!(set1.contains(&"item1".to_string()));
    assert!(set1.contains(&"item2".to_string()));

    // Remove item1
    set1.remove(&"item1".to_string());
    assert!(!set1.contains(&"item1".to_string()));
    assert!(set1.contains(&"item2".to_string()));

    // Create another set and merge
    let mut set2 = ORSet::<String>::new();
    set2.add("item3".to_string());

    set1.merge(&set2);
    assert!(set1.contains(&"item3".to_string()));
}

#[tokio::test]
async fn test_conflict_resolver() {
    use beagle_websocket::sync::{ConflictResolver, ConflictResolution};

    let context = Arc::new(BeagleContext::new_with_mock());
    let resolver = ConflictResolver::new(ConflictResolution::LastWriteWins, context);

    let values = vec![
        b"value1".to_vec(),
        b"value2".to_vec(),
        b"value3".to_vec(),
    ];

    let result = resolver.resolve(values).await.unwrap();
    assert_eq!(result, b"value3");
}

#[tokio::test]
async fn test_authentication() {
    use beagle_websocket::auth::AuthProvider;

    let provider = AuthProvider::new("test_secret".to_string(), Duration::from_secs(3600));

    // Test password hashing
    let password = "test_password";
    let hash = provider.hash_password(password).unwrap();
    assert!(provider.verify_password(password, &hash).unwrap());
    assert!(!provider.verify_password("wrong_password", &hash).unwrap());

    // Test token generation and validation
    let token = provider.generate_token(
        "user123",
        vec!["admin".to_string()],
        vec!["read".to_string(), "write".to_string()],
    ).unwrap();

    let claims = provider.validate_token(&token).unwrap();
    assert_eq!(claims.sub, "user123");
    assert!(claims.roles.contains(&"admin".to_string()));
    assert!(claims.permissions.contains(&"read".to_string()));
}

#[tokio::test]
async fn test_compression() {
    use beagle_websocket::compression::{CompressionManager, CompressionStrategy, CompressionLevel};

    let manager = CompressionManager::new(
        CompressionStrategy::Gzip,
        CompressionLevel::Default,
        100,
    );

    let data = b"Hello World! This is a test message that should be compressed.".repeat(10);

    let compressed = manager.compress(&data).unwrap();
    assert!(compressed.len() < data.len()); // Should be smaller

    let decompressed = manager.decompress(&compressed).unwrap();
    assert_eq!(&decompressed[..], &data[..]);
}

#[tokio::test]
async fn test_message_codec() {
    use beagle_websocket::message::{Message, MessageType, JsonCodec};

    let codec = JsonCodec;

    let message = Message {
        id: Uuid::new_v4(),
        message_type: MessageType::Text,
        payload: b"test payload".to_vec(),
        timestamp: 12345,
        metadata: std::collections::HashMap::new(),
    };

    let encoded = codec.encode(&message).unwrap();
    let decoded = codec.decode(&encoded).unwrap();

    assert_eq!(decoded.id, message.id);
    assert_eq!(decoded.message_type, message.message_type);
    assert_eq!(decoded.payload, message.payload);
    assert_eq!(decoded.timestamp, message.timestamp);
}

#[tokio::test]
async fn test_connection_manager() {
    use beagle_websocket::connection::{ConnectionManager, WebSocketConnection};

    let manager = ConnectionManager::new(10, Duration::from_secs(60));

    let connection = Arc::new(WebSocketConnection::new());
    let conn_id = connection.id;

    // Add connection
    manager.add_connection(connection.clone()).await.unwrap();
    assert_eq!(manager.connection_count(), 1);

    // Get connection
    let retrieved = manager.get_connection(conn_id).await;
    assert!(retrieved.is_some());
    assert_eq!(retrieved.unwrap().id, conn_id);

    // Remove connection
    let removed = manager.remove_connection(conn_id).await;
    assert!(removed.is_some());
    assert_eq!(manager.connection_count(), 0);
}

#[tokio::test]
async fn test_event_ordering() {
    use beagle_websocket::sync::{EventOrdering, Event, VectorClock};

    let ordering = EventOrdering::new(1000, Duration::from_secs(30));

    // Create events
    let event1 = Event {
        id: Uuid::new_v4(),
        timestamp: 1,
        vector_clock: VectorClock::new(),
        node_id: "node1".to_string(),
        payload: vec![1, 2, 3],
        dependencies: vec![],
        metadata: std::collections::HashMap::new(),
    };

    let event2 = Event {
        id: Uuid::new_v4(),
        timestamp: 2,
        vector_clock: VectorClock::new(),
        node_id: "node2".to_string(),
        payload: vec![4, 5, 6],
        dependencies: vec![event1.id],
        metadata: std::collections::HashMap::new(),
    };

    // Submit events
    ordering.submit_event(event2.clone()).await.unwrap(); // Will be pending
    ordering.submit_event(event1.clone()).await.unwrap(); // Will deliver both

    // Allow some time for processing
    sleep(Duration::from_millis(100)).await;

    // Get ordered events
    let events = ordering.get_ordered_events(0).await;
    assert_eq!(events.len(), 2);
    assert_eq!(events[0].timestamp, 1);
    assert_eq!(events[1].timestamp, 2);
}
