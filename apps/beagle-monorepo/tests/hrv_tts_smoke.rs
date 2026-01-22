use axum::{
    body::{to_bytes, Body},
    http::{Request, StatusCode},
};
use beagle_config::BeagleConfig;
use beagle_core::BeagleContext;
use beagle_monorepo::{build_router, DarwinJobRegistry, JobRegistry, ScienceJobRegistry};
use beagle_observer::UniversalObserver;
use serde_json::json;
use std::sync::{Arc, OnceLock};
use tokio::sync::Mutex;
use tower::ServiceExt;

static ENV_LOCK: OnceLock<std::sync::Mutex<()>> = OnceLock::new();

fn lock_env() -> std::sync::MutexGuard<'static, ()> {
    ENV_LOCK.get_or_init(|| std::sync::Mutex::new(())).lock().unwrap()
}

async fn build_test_state(data_dir: &std::path::Path) -> beagle_monorepo::AppState {
    std::env::set_var("BEAGLE_DATA_DIR", data_dir.to_string_lossy().to_string());
    std::env::set_var("BEAGLE_PROFILE", "dev");
    std::env::set_var("BEAGLE_SAFE_MODE", "true");

    let cfg = BeagleConfig {
        profile: "dev".to_string(),
        safe_mode: true,
        api_token: None,
        llm: Default::default(),
        storage: beagle_config::StorageConfig {
            data_dir: data_dir.to_string_lossy().to_string(),
        },
        graph: Default::default(),
        hermes: Default::default(),
        advanced: Default::default(),
        observer: Default::default(),
    };

    let ctx = BeagleContext::new_with_mocks(cfg);
    let observer = UniversalObserver::new_async().await.unwrap();

    beagle_monorepo::AppState {
        ctx: Arc::new(Mutex::new(ctx)),
        jobs: Arc::new(JobRegistry::new()),
        science_jobs: Arc::new(ScienceJobRegistry::new()),
        darwin_jobs: Arc::new(DarwinJobRegistry::new()),
        observer: Arc::new(observer),
    }
}

#[tokio::test(flavor = "current_thread")]
async fn hrv_compat_updates_observer_context() {
    let _guard = lock_env();
    let dir = tempfile::tempdir().unwrap();

    let state = build_test_state(dir.path()).await;
    let app = build_router(state);

    // 1) Send legacy HRV payload.
    let req = Request::builder()
        .method("POST")
        .uri("/api/hrv")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({
                "hrv": 55.2,
                "state": "NORMAL",
                "timestamp": 1737369000.123
            })
            .to_string(),
        ))
        .unwrap();

    let resp = app.clone().oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let body = to_bytes(resp.into_body(), usize::MAX).await.unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["status"], "ok");
    assert!(v["speed_multiplier"].as_f64().unwrap_or_default() > 0.0);

    // 2) Verify observer context got updated.
    let req = Request::builder()
        .method("GET")
        .uri("/api/observer/context")
        .body(Body::empty())
        .unwrap();
    let resp = app.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let body = to_bytes(resp.into_body(), usize::MAX).await.unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["physio"]["hrv_level"], "normal");
}

#[tokio::test(flavor = "current_thread")]
async fn voice_tts_endpoint_responds() {
    let _guard = lock_env();
    let dir = tempfile::tempdir().unwrap();

    let state = build_test_state(dir.path()).await;
    let app = build_router(state);

    let req = Request::builder()
        .method("POST")
        .uri("/api/voice/tts")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({
                "text": "Hello from BEAGLE.",
                "language": "en-US"
            })
            .to_string(),
        ))
        .unwrap();

    let resp = app.oneshot(req).await.unwrap();

    // TTS requires system binaries; if unavailable return 503.
    if resp.status() == StatusCode::SERVICE_UNAVAILABLE {
        return;
    }

    assert_eq!(resp.status(), StatusCode::OK);
    assert_eq!(
        resp.headers()
            .get(axum::http::header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default(),
        "audio/wav"
    );

    let body = to_bytes(resp.into_body(), usize::MAX).await.unwrap();
    assert!(body.len() > 32);
    assert!(body.starts_with(b"RIFF"));
}
