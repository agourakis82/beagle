use async_trait::async_trait;
use beagle_events::{
    BeagleEvent, BeaglePulsar, EventHandler, EventPublisher, EventSubscriber, EventType, Result,
};

struct SimpleHandler;

#[async_trait]
impl EventHandler for SimpleHandler {
    async fn handle(&self, event: BeagleEvent) -> Result<()> {
        println!("Received event: {:?}", event.event_type);
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Connect to Pulsar
    let pulsar = BeaglePulsar::new("pulsar://localhost:6650", None).await?;

    // Create publisher
    let mut publisher = EventPublisher::new(&pulsar, "beagle.test").await?;

    // Create subscriber
    let mut subscriber = EventSubscriber::new(&pulsar, "beagle.test", "test-subscription").await?;

    // Publish test event
    let event = BeagleEvent::new(EventType::ResearchStarted {
        query: "Test query".to_string(),
        agent_id: "agent-1".to_string(),
    });

    publisher.publish(&event).await?;

    // Consume events (blocks)
    subscriber.consume(SimpleHandler).await?;

    Ok(())
}
