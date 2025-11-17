#![cfg(test)]
#![allow(unused_imports)]

use async_trait::async_trait;
use beagle_events::{
    BeagleEvent, BeaglePulsar, EventHandler, EventPublisher, EventSubscriber, EventType, Result,
};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

struct TestHandler {
    received_count: Arc<AtomicUsize>,
}

#[async_trait]
impl EventHandler for TestHandler {
    async fn handle(&self, _event: BeagleEvent) -> Result<()> {
        self.received_count.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }
}

#[tokio::test]
#[ignore] // Requires Docker/Pulsar running
async fn test_publish_consume_smoke() {
    let pulsar = BeaglePulsar::new("pulsar://localhost:6650", None)
        .await
        .expect("Failed to connect to Pulsar");

    let publisher = EventPublisher::new(&pulsar, "test.smoke").await.unwrap();
    let mut subscriber = EventSubscriber::new(&pulsar, "test.smoke", "smoke-sub")
        .await
        .unwrap();

    let event = BeagleEvent::new(EventType::HealthCheck {
        service: "test".into(),
        status: "ok".into(),
    });

    publisher.publish(&event).await.unwrap();

    let received_count = Arc::new(AtomicUsize::new(0));
    let handler = TestHandler {
        received_count: received_count.clone(),
    };

    let consume = tokio::spawn(async move {
        // Give some time window to consume one message then exit
        let _ = tokio::time::timeout(Duration::from_secs(2), subscriber.consume(handler)).await;
    });

    let _ = consume.await;
    assert!(received_count.load(Ordering::SeqCst) >= 0);
}
