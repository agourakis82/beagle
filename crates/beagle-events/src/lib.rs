//! Beagle Events - Event-Driven Architecture via Apache Pulsar
//!
//! Provides pub/sub capabilities for asynchronous communication between
//! BEAGLE agents, services, and external systems.

mod client;
mod events;
mod publisher;
mod subscriber;
mod error;
pub mod resilience;
pub mod metrics;

pub use client::BeaglePulsar;
pub use events::{BeagleEvent, EventType, EventMetadata};
pub use publisher::EventPublisher;
pub use subscriber::{EventSubscriber, EventHandler};
pub use error::{EventError, Result};

// Re-export pulsar types for convenience
pub use pulsar::{
    Authentication, Pulsar, TokioExecutor,
    producer::{Message, SendFuture},
    consumer::{Consumer, ConsumerOptions},
};


