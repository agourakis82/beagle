use crate::{EventError, Result};
use pulsar::{Authentication, Pulsar, TokioExecutor};

/// Pulsar client wrapper for BEAGLE
pub struct BeaglePulsar {
    client: Pulsar<TokioExecutor>,
}

impl BeaglePulsar {
    /// Create new Pulsar client
    ///
    /// # Arguments
    /// * `broker_url` - Pulsar broker URL (e.g., "pulsar://localhost:6650")
    /// * `auth` - Optional authentication
    pub async fn new(broker_url: impl Into<String>, auth: Option<Authentication>) -> Result<Self> {
        let mut builder = Pulsar::builder(broker_url, TokioExecutor);

        if let Some(authentication) = auth {
            builder = builder.with_auth(authentication);
        }

        let client = builder
            .build()
            .await
            .map_err(|e| EventError::ConnectionError(e.to_string()))?;

        Ok(Self { client })
    }

    /// Get reference to underlying Pulsar client
    pub fn client(&self) -> &Pulsar<TokioExecutor> {
        &self.client
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires Pulsar running
    async fn test_connection() {
        let _pulsar = BeaglePulsar::new("pulsar://localhost:6650", None)
            .await
            .expect("Failed to connect to Pulsar");
        // Connection established if construction succeeded.
        assert!(true);
    }
}
