//! Universal Observer integration tests.

use beagle_observer::{Event, UniversalObserver};
use std::time::Duration;
use tokio::time::timeout;

#[tokio::test]
async fn test_event_broadcast_stream() -> anyhow::Result<()> {
    let observer = UniversalObserver::new_async().await?;
    let mut rx = observer.subscribe();

    observer
        .system_observer()
        .record_event(Event::log("test", "info", "hello"))
        .await;

    let event = timeout(Duration::from_secs(2), rx.recv()).await??;
    assert_eq!(event.source, "test");

    Ok(())
}
