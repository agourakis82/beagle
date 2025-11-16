//! Estratégias de resiliência e tolerância a falhas para operações assíncronas.

pub mod retry;

pub use retry::{CircuitBreakerConfig, RetryConfig, RetryError, RetryPolicy};
