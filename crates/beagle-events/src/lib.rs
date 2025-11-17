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

// Re-export pulsar types for convenience
pub use pulsar::{
    consumer::{Consumer, ConsumerOptions},
    producer::{Message, SendFuture},
    Authentication, Pulsar, TokioExecutor,
};
