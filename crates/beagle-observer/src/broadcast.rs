//! Sistema de broadcast para observações e eventos
//!
//! Permite múltiplos subscribers receberem as mesmas observações e eventos

use super::events::Event;
use std::sync::Arc;
use tokio::sync::broadcast;
use tokio::sync::Mutex;

/// Observation data for legacy compatibility
#[derive(Debug, Clone)]
pub struct Observation {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub source: String,
    pub data: serde_json::Value,
}

impl Default for Observation {
    fn default() -> Self {
        Self {
            timestamp: chrono::Utc::now(),
            source: String::new(),
            data: serde_json::Value::Null,
        }
    }
}

impl From<Event> for Observation {
    fn from(event: Event) -> Self {
        Self {
            timestamp: event.timestamp,
            source: event.source,
            data: serde_json::to_value(&event.data).unwrap_or(serde_json::Value::Null),
        }
    }
}

impl From<Observation> for Event {
    fn from(obs: Observation) -> Self {
        Event::new(
            super::events::EventType::Custom("observation".to_string()),
            &obs.source,
            "Legacy observation",
        )
    }
}

/// Broadcast channel for events
pub struct ObservationBroadcast {
    sender: broadcast::Sender<Event>,
}

impl ObservationBroadcast {
    /// Create new broadcast channel
    pub fn new() -> Self {
        let (sender, _) = broadcast::channel(1000);
        Self { sender }
    }

    /// Create with custom capacity
    pub fn with_capacity(capacity: usize) -> Self {
        let (sender, _) = broadcast::channel(capacity);
        Self { sender }
    }

    /// Subscribe to events
    pub fn subscribe(&self) -> broadcast::Receiver<Event> {
        self.sender.subscribe()
    }

    /// Send an event to all subscribers
    pub fn send(&self, event: Event) {
        // Ignore errors if no subscribers
        let _ = self.sender.send(event);
    }

    /// Broadcast an observation (legacy compatibility)
    pub fn broadcast_observation(&self, obs: Observation) {
        self.send(obs.into());
    }

    /// Get number of active receivers
    pub fn receiver_count(&self) -> usize {
        self.sender.receiver_count()
    }
}

impl Default for ObservationBroadcast {
    fn default() -> Self {
        Self::new()
    }
}

impl Clone for ObservationBroadcast {
    fn clone(&self) -> Self {
        Self {
            sender: self.sender.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_broadcast() {
        let broadcast = ObservationBroadcast::new();

        let mut rx1 = broadcast.subscribe();
        let mut rx2 = broadcast.subscribe();

        let event = Event::new(
            super::super::events::EventType::Metric,
            "test",
            "test event",
        );
        broadcast.send(event.clone());

        let received1 = rx1.recv().await.unwrap();
        let received2 = rx2.recv().await.unwrap();

        assert_eq!(received1.source, "test");
        assert_eq!(received2.source, "test");
    }

    #[tokio::test]
    async fn test_receiver_count() {
        let broadcast = ObservationBroadcast::new();
        assert_eq!(broadcast.receiver_count(), 0);

        let _rx1 = broadcast.subscribe();
        assert_eq!(broadcast.receiver_count(), 1);

        let _rx2 = broadcast.subscribe();
        assert_eq!(broadcast.receiver_count(), 2);
    }
}
