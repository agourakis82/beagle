//! Universal Observer E2E smoke tests.
//!
//! These tests are ignored by default because they write to `BEAGLE_DATA_DIR`
//! and may depend on host capabilities.

use beagle_observer::{PhysioEvent, UniversalObserver};
use std::time::Duration;
use tokio::time::timeout;

#[tokio::test]
#[ignore]
async fn test_physio_event_logs_alert() -> anyhow::Result<()> {
    let data_dir = std::env::temp_dir().join(format!("beagle-observer-e2e-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&data_dir)?;
    std::env::set_var("BEAGLE_DATA_DIR", data_dir.to_string_lossy().to_string());

    let observer = UniversalObserver::new_async().await?;

    let event = PhysioEvent {
        source: "test_watch".to_string(),
        spo2_percent: Some(88.0),
        ..Default::default()
    };

    let severity = observer.record_physio_event(event, None).await?;
    assert!(severity >= beagle_observer::Severity::Moderate);

    let alerts_file = data_dir.join("alerts").join("physio.jsonl");
    let content = timeout(Duration::from_secs(2), async { std::fs::read_to_string(&alerts_file) })
        .await??;
    assert!(content.contains("\"severity\":\"Severe\"") || content.contains("\"severity\":\"Moderate\""));

    let events_file = data_dir.join("observer").join("physio_events.jsonl");
    let events_content =
        timeout(Duration::from_secs(2), async { std::fs::read_to_string(&events_file) }).await??;
    assert!(events_content.contains("\"source\":\"test_watch\""));

    Ok(())
}
