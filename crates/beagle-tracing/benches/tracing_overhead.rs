//! Tracing overhead benchmarks
//!
//! Measures the performance impact of distributed tracing

use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_span_creation(c: &mut Criterion) {
    c.bench_function("span_creation", |b| {
        b.iter(|| {
            let span = tracing::info_span!("test_span");
            let _guard = span.enter();
            black_box(42)
        })
    });
}

fn bench_trace_context_propagation(c: &mut Criterion) {
    use std::collections::HashMap;
    
    c.bench_function("trace_context_inject", |b| {
        b.iter(|| {
            let mut headers: HashMap<String, String> = HashMap::new();
            headers.insert("traceparent".to_string(), "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01".to_string());
            black_box(headers)
        })
    });
}

criterion_group!(benches, bench_span_creation, bench_trace_context_propagation);
criterion_main!(benches);
