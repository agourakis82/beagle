use crate::{BeagleEvent, BeaglePulsar, EventError, Result};
use async_trait::async_trait;
use pulsar::consumer::{Consumer, ConsumerOptions};
use pulsar::{SubType, TokioExecutor};
use tracing::{debug, error, info};
use futures_util::TryStreamExt;

/// Event handler trait
#[async_trait]
pub trait EventHandler: Send + Sync {
    async fn handle(&self, event: BeagleEvent) -> Result<()>;
}

/// Event subscriber
pub struct EventSubscriber {
    consumer: Consumer<Vec<u8>, TokioExecutor>,
}

impl EventSubscriber {
    /// Create new event subscriber
    ///
    /// # Arguments
    /// * `pulsar` - Pulsar client
    /// * `topic` - Topic to subscribe (e.g., "beagle.research.events")
    /// * `subscription` - Subscription name (consumer group)
    pub async fn new(
        pulsar: &BeaglePulsar,
        topic: impl Into<String>,
        subscription: impl Into<String>,
    ) -> Result<Self> {
        let consumer = pulsar
            .client()
            .consumer()
            .with_topic(topic)
            .with_subscription(subscription)
            .with_subscription_type(SubType::Shared)
            .with_options(ConsumerOptions::default())
            .build()
            .await
            .map_err(|e| EventError::SubscribeError(e.to_string()))?;

        Ok(Self { consumer })
    }

    /// Start consuming events
    ///
    /// This method blocks indefinitely, processing events as they arrive.
    pub async fn consume<H>(&mut self, handler: H) -> Result<()>
    where
        H: EventHandler,
    {
        info!("Starting event consumer");

        loop {
            match self.consumer.try_next().await {
                Ok(Some(msg)) => {
                    let event: BeagleEvent = match serde_json::from_slice(&msg.payload.data) {
                        Ok(e) => e,
                        Err(e) => {
                            error!("Failed to deserialize event: {}", e);
                            self.consumer.ack(&msg).await.map_err(|e| EventError::SubscribeError(e.to_string()))?;
                            continue;
                        }
                    };

                    debug!(
                        event_id = %event.metadata.event_id,
                        "Received event"
                    );

                    match handler.handle(event).await {
                        Ok(_) => {
                            self.consumer.ack(&msg).await.map_err(|e| EventError::SubscribeError(e.to_string()))?;
                        }
                        Err(e) => {
                            error!("Handler failed: {}", e);
                            // TODO: Implement retry logic or DLQ
                            self.consumer.nack(&msg).await.map_err(|e| EventError::SubscribeError(e.to_string()))?;
                        }
                    }
                }
                Err(e) => {
                    error!("Consumer error: {}", e);
                    return Err(EventError::PulsarError(e));
                }
                _ => {}
            }
        }

        Ok(())
    }
}


