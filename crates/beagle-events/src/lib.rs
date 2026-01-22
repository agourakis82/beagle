//! Beagle Events - Event-Driven Architecture via Apache Pulsar
//!
//! Provides pub/sub capabilities for asynchronous communication between
//! BEAGLE agents, services, and external systems.

mod client;
mod error;
mod events;
pub mod metrics;
mod publisher;
pub mod resilience;
mod subscriber;

pub use client::BeaglePulsar;
pub use error::{EventError, Result};
pub use events::{BeagleEvent, EventMetadata, EventType};
pub use publisher::EventPublisher;
pub use subscriber::{EventHandler, EventSubscriber};

// Keep BeaglePulsar::new signature stable even when Pulsar integration is disabled.
#[cfg(feature = "pulsar")]
pub use pulsar::Authentication;

#[cfg(not(feature = "pulsar"))]
#[derive(Debug, Clone)]
pub struct Authentication;

// Re-export pulsar types for convenience (only when enabled).
#[cfg(feature = "pulsar")]
pub use pulsar::{
    consumer::{Consumer, ConsumerOptions},
    producer::{Message, SendFuture},
    Pulsar, TokioExecutor,
};
