use crate::Result;
use backoff::{backoff::Backoff, ExponentialBackoff, ExponentialBackoffBuilder};
use std::time::Duration;
use tracing::warn;

/// Retry configuration
#[derive(Debug, Clone)]
pub struct RetryConfig {
    pub max_retries: u32,
    pub initial_interval: Duration,
    pub max_interval: Duration,
    pub multiplier: f64,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_retries: 5,
            initial_interval: Duration::from_millis(100),
            max_interval: Duration::from_secs(30),
            multiplier: 2.0,
        }
    }
}

impl RetryConfig {
    pub fn to_backoff(&self) -> ExponentialBackoff {
        ExponentialBackoffBuilder::new()
            .with_initial_interval(self.initial_interval)
            .with_max_interval(self.max_interval)
            .with_multiplier(self.multiplier)
            .with_max_elapsed_time(Some(self.initial_interval * self.max_retries))
            .build()
    }
}

/// Retry with exponential backoff
pub async fn retry_with_backoff<F, Fut, T>(
    mut operation: F,
    config: RetryConfig,
) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
{
    let mut backoff = config.to_backoff();
    let mut attempts = 0;

    loop {
        attempts += 1;

        match operation().await {
            Ok(result) => return Ok(result),
            Err(e) if attempts >= config.max_retries => {
                return Err(e);
            }
            Err(e) => {
                if let Some(duration) = backoff.next_backoff() {
                    warn!(
                        attempt = attempts,
                        retry_after_ms = duration.as_millis(),
                        error = %e,
                        "Operation failed, retrying"
                    );
                    tokio::time::sleep(duration).await;
                } else {
                    return Err(e);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::sync::Arc;

    #[tokio::test]
    async fn test_retry_success_after_failures() {
        let attempts = Arc::new(AtomicU32::new(0));
        let attempts_clone = attempts.clone();

        let config = RetryConfig {
            max_retries: 3,
            initial_interval: Duration::from_millis(10),
            ..Default::default()
        };

        let result = retry_with_backoff(
            || {
                let attempts = attempts_clone.clone();
                async move {
                    let count = attempts.fetch_add(1, Ordering::SeqCst);
                    if count < 2 {
                        Err(EventError::PublishError("Temporary failure".into()))
                    } else {
                        Ok(42)
                    }
                }
            },
            config,
        )
        .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
        assert_eq!(attempts.load(Ordering::SeqCst), 3);
    }
}


