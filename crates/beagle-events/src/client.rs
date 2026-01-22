use crate::{Authentication, Result};

#[cfg(feature = "pulsar")]
use crate::EventError;

#[cfg(feature = "pulsar")]
use pulsar::{Pulsar, TokioExecutor};

/// Pulsar client wrapper for BEAGLE
pub struct BeaglePulsar {
    enabled: bool,
    #[cfg(feature = "pulsar")]
    client: Pulsar<TokioExecutor>,
}

impl BeaglePulsar {
    /// Create new Pulsar client
    ///
    /// # Arguments
    /// * `broker_url` - Pulsar broker URL (e.g., "pulsar://localhost:6650")
    /// * `auth` - Optional authentication
    pub async fn new(broker_url: impl Into<String>, auth: Option<Authentication>) -> Result<Self> {
        #[cfg(not(feature = "pulsar"))]
        {
            let _ = broker_url.into();
            let _ = auth;
            tracing::warn!("beagle-events built without feature 'pulsar' (events are disabled)");
            return Ok(Self { enabled: false });
        }

        #[cfg(feature = "pulsar")]
        let mut builder = Pulsar::builder(broker_url, TokioExecutor);

        #[cfg(feature = "pulsar")]
        if let Some(authentication) = auth {
            builder = builder.with_auth(authentication);
        }

        #[cfg(feature = "pulsar")]
        let client = builder
            .build()
            .await
            .map_err(|e| EventError::ConnectionError(e.to_string()))?;

        #[cfg(feature = "pulsar")]
        Ok(Self {
            enabled: true,
            client,
        })
    }

    /// Get reference to underlying Pulsar client
    #[cfg(feature = "pulsar")]
    pub fn client(&self) -> &Pulsar<TokioExecutor> {
        &self.client
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled
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
