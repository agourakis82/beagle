use tokio::time::{interval, Duration};

use super::discover_serendipity;

/// Periodic scheduler to trigger serendipity discovery.
/// Intended to be spawned from the Tauri runtime on app startup.
pub struct SerendipityScheduler {
    focus_project: String,
    check_interval_hours: u64,
}

impl SerendipityScheduler {
    pub fn new(focus_project: String, check_interval_hours: u64) -> Self {
        Self {
            focus_project,
            check_interval_hours,
        }
    }

    /// Starts the periodic loop. Non-blocking when spawned via `tokio::spawn`.
    pub async fn start(&self) {
        let mut ticker = interval(Duration::from_secs(self.check_interval_hours * 3600));
        loop {
            ticker.tick().await;
            self.check_for_connections().await;
        }
    }

    async fn check_for_connections(&self) {
        // Invoke the same Tauri command logic to compute connections.
        // Note: We ignore the result here; UI surfaces results on-demand.
        let _ = discover_serendipity(self.focus_project.clone()).await;
        // TODO: Optional: emit event to frontend with high-novelty highlights
    }
}


