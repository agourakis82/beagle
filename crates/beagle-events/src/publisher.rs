use crate::{metrics, resilience::RetryConfig, BeagleEvent, BeaglePulsar, EventError, Result};
use backoff::{backoff::Backoff, ExponentialBackoffBuilder};
use pulsar::producer::{Message, Producer};
use pulsar::TokioExecutor;
use std::time::Instant;
use tracing::{debug, error};

/// Event publisher
pub struct EventPublisher {
    producer: Producer<TokioExecutor>,
    retry_config: RetryConfig,
}

impl EventPublisher {
    /// Create new event publisher
    ///
    /// # Arguments
    /// * `pulsar` - Pulsar client
    /// * `topic` - Topic name (e.g., "beagle.research.events")
    pub async fn new(pulsar: &BeaglePulsar, topic: impl Into<String>) -> Result<Self> {
        let producer = pulsar
            .client()
            .producer()
            .with_topic(topic)
            .with_name("beagle-publisher")
            .build()
            .await
            .map_err(|e| EventError::PublishError(e.to_string()))?;

        Ok(Self {
            producer,
            retry_config: RetryConfig::default(),
        })
    }

    /// Publish event
    pub async fn publish(&mut self, event: &BeagleEvent) -> Result<()> {
        let start = Instant::now();

        // Inline retry with exponential backoff to avoid borrow issues in async closures
        let mut result: Result<()> = Ok(());
        let mut backoff = ExponentialBackoffBuilder::new()
            .with_initial_interval(self.retry_config.initial_interval)
            .with_max_interval(self.retry_config.max_interval)
            .with_multiplier(self.retry_config.multiplier)
            .with_max_elapsed_time(Some(
                self.retry_config.initial_interval * self.retry_config.max_retries,
            ))
            .build();
        let mut attempts = 0u32;
        loop {
            attempts += 1;
            let payload = match serde_json::to_vec(event) {
                Ok(p) => p,
                Err(e) => {
                    result = Err(EventError::SerializationError(e));
                    break;
                }
            };
            let send_res: Result<()> = self
                .producer
                .send_non_blocking(Message {
                    payload,
                    ..Default::default()
                })
                .await
                .map(|_| ())
                .map_err(|e| EventError::PublishError(e.to_string()));
            if send_res.is_ok() {
                result = Ok(());
                break;
            } else if attempts >= self.retry_config.max_retries {
                result = send_res;
                break;
            } else if let Some(wait) = backoff.next_backoff() {
                tokio::time::sleep(wait).await;
                continue;
            } else {
                result = send_res;
                break;
            }
        }

        // Record metrics
        let duration = start.elapsed().as_secs_f64();
        metrics::EventMetrics::observe_publish_duration(duration);

        if result.is_ok() {
            metrics::EventMetrics::inc_published();
            debug!(
                event_id = %event.metadata.event_id,
                duration_ms = duration * 1000.0,
                "Event published successfully"
            );
        } else {
            error!(
                event_id = %event.metadata.event_id,
                "Failed to publish event after retries"
            );
        }

        result
    }
}
