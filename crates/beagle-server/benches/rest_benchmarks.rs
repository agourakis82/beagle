use criterion::{criterion_group, criterion_main, Criterion};
use reqwest::Client;
use serde_json::json;

async fn benchmark_rest_dispatch() {
    let client = Client::new();
    // Measure lightweight REST path: events health
    let _ = client
        .get("http://localhost:3000/api/v1/events/health")
        .send()
        .await
        .unwrap();
}

fn criterion_benchmark(c: &mut Criterion) {
    let rt = tokio::runtime::Runtime::new().unwrap();
    c.bench_function("rest_dispatch_task", |b| {
        b.to_async(&rt).iter(|| benchmark_rest_dispatch())
    });
}

criterion_group!(benches, criterion_benchmark);
criterion_main!(benches);
