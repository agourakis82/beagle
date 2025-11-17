use beagle_grpc::generated::agent_service_client::AgentServiceClient;
use beagle_grpc::generated::DispatchTaskRequest;
use criterion::{criterion_group, criterion_main, Criterion};

async fn benchmark_grpc_dispatch() {
    let mut client = AgentServiceClient::connect("http://127.0.0.1:50051")
        .await
        .expect("connect gRPC");
    let req = DispatchTaskRequest {
        agent_id: "agent-1".into(),
        task_id: uuid::Uuid::new_v4().to_string(),
        task_type: "benchmark".into(),
        parameters: Default::default(),
    };
    let _ = client.dispatch_task(req).await.unwrap();
}

fn criterion_benchmark(c: &mut Criterion) {
    let rt = tokio::runtime::Runtime::new().unwrap();
    c.bench_function("grpc_dispatch_task", |b| {
        b.to_async(&rt).iter(|| benchmark_grpc_dispatch())
    });
}

criterion_group!(benches, criterion_benchmark);
criterion_main!(benches);
