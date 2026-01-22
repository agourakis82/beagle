//! Universal Observer example.
//!
//! Demonstrates creating an observer, subscribing to the event stream, and emitting a few events.

use beagle_observer::{Event, UniversalObserver};
use std::time::Duration;
use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("beagle_observer=info")
        .init();

    let observer = UniversalObserver::new_async().await?;
    let mut rx = observer.subscribe();

    observer.start_full_surveillance().await?;

    for i in 0..5usize {
        let message = format!("tick {}", i);
        observer
            .system_observer()
            .record_event(Event::log("example", "info", &message))
            .await;

        let event = rx.recv().await?;
        info!("event: {} | {}", event.source, event.message);

        tokio::time::sleep(Duration::from_millis(200)).await;
    }

    Ok(())
}
