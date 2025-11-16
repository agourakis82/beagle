//! Benchmark suite para o Beagle Hypergraph utilizando Criterion.
//! Foca em operações críticas (construção de nós, serialização,
//! mutações de hiperarcos, validação e alocação) para detectar regressões.

use std::sync::Arc;

use beagle_hypergraph::models::{ContentType, Hyperedge, Node, NodeBuilder, ValidationError};
use criterion::{
    black_box, criterion_group, criterion_main, BatchSize, Bencher, BenchmarkId, Criterion,
    Throughput,
};
use serde_json::json;
use uuid::Uuid;

// ============================
// Helpers
// ============================

fn build_embedding(dimension: usize) -> Vec<f32> {
    (0..dimension).map(|i| (i as f32) * 0.0001).collect()
}

fn build_node_with_size(size: usize) -> Node {
    Node::builder()
        .content("A".repeat(size))
        .content_type(ContentType::Note)
        .device_id("device")
        .build()
        .expect("valid node")
}

fn build_hyperedge_with_size(size: usize) -> Hyperedge {
    let nodes: Vec<Uuid> = (0..size).map(|_| Uuid::new_v4()).collect();
    Hyperedge::new("benchmark-edge", nodes, false, "device").expect("valid hyperedge")
}

fn bench_builder_reuse(b: &mut Bencher, template: Arc<NodeBuilder>) {
    b.iter(|| {
        let builder = NodeBuilder::new()
            .content(black_box("Test content"))
            .content_type(black_box(ContentType::Thought))
            .device_id(black_box("device-id"));
        let mut reused = template.clone();
        reused
            .content(black_box("Test content"))
            .content_type(black_box(ContentType::Memory))
            .device_id(black_box("device-id-reused"));
        let node_direct = builder.clone().build().unwrap();
        let node_reused = reused.build().unwrap();
        black_box((node_direct, node_reused));
    });
}

// ============================
// Node Construction Benchmarks
// ============================

fn bench_node_creation(c: &mut Criterion) {
    let mut group = c.benchmark_group("node_creation");

    group.bench_function("minimal_node", |b| {
        b.iter(|| {
            Node::builder()
                .content(black_box("Test content"))
                .content_type(black_box(ContentType::Thought))
                .device_id(black_box("device-id"))
                .build()
                .unwrap()
        });
    });

    group.bench_function("node_with_metadata", |b| {
        let metadata = json!({
            "priority": 5,
            "tags": ["important", "urgent"],
            "context": "benchmark test"
        });

        b.iter(|| {
            Node::builder()
                .content(black_box("Test content"))
                .content_type(black_box(ContentType::Task))
                .metadata(black_box(metadata.clone()))
                .device_id(black_box("device-id"))
                .build()
                .unwrap()
        });
    });

    group.bench_function("node_with_embedding_1536", |b| {
        let embedding = build_embedding(1536);

        b.iter(|| {
            Node::builder()
                .content(black_box("Test content"))
                .content_type(black_box(ContentType::Memory))
                .embedding(black_box(embedding.clone()))
                .device_id(black_box("device-id"))
                .build()
                .unwrap()
        });
    });

    group.bench_function("node_with_large_metadata", |b| {
        let metadata = json!({
            "tags": ["hypergraph", "benchmark", "performance", "serialization"],
            "authors": ["Ada", "Turing", "Lovelace", "Babbage"],
            "notes": "Extensive metadata payload to stress builder"
        });

        b.iter(|| {
            Node::builder()
                .content(black_box("Test content with metadata"))
                .content_type(black_box(ContentType::Context))
                .metadata(black_box(metadata.clone()))
                .device_id(black_box("device-id"))
                .build()
                .unwrap()
        });
    });

    group.bench_function("node_builder_reuse", |b| {
        let template = Arc::new(
            Node::builder()
                .content("Template")
                .content_type(ContentType::Memory)
                .metadata(json!({"seed": true}))
                .device_id("template-device"),
        );
        bench_builder_reuse(b, template);
    });

    group.bench_function("node_clone", |b| {
        let node = Node::builder()
            .content("Clone me")
            .content_type(ContentType::Thought)
            .device_id("device")
            .build()
            .unwrap();

        b.iter(|| node.clone());
    });

    group.finish();
}

// ============================
// Serialization Benchmarks
// ============================

fn bench_serialization(c: &mut Criterion) {
    let mut group = c.benchmark_group("serialization");

    let node = Node::builder()
        .content("A".repeat(1000))
        .content_type(ContentType::Note)
        .metadata(json!({"key": "value"}))
        .device_id("device-test")
        .build()
        .unwrap();

    let node_large = Node::builder()
        .content("B".repeat(50_000))
        .content_type(ContentType::Context)
        .metadata(json!({"blob": "x".repeat(1024)}))
        .device_id("device-test")
        .build()
        .unwrap();

    group.throughput(Throughput::Bytes(
        serde_json::to_string(&node).unwrap().len() as u64,
    ));

    group.bench_function("node_to_json", |b| {
        b.iter(|| serde_json::to_string(black_box(&node)).unwrap());
    });

    let json_str = serde_json::to_string(&node).unwrap();
    group.bench_function("node_from_json", |b| {
        b.iter(|| serde_json::from_str::<Node>(black_box(&json_str)).unwrap());
    });

    group.bench_function("node_to_json_large", |b| {
        b.iter(|| serde_json::to_string(black_box(&node_large)).unwrap());
    });

    let json_str_large = serde_json::to_string(&node_large).unwrap();
    group.bench_function("node_from_json_large", |b| {
        b.iter(|| serde_json::from_str::<Node>(black_box(&json_str_large)).unwrap());
    });

    group.bench_function("node_clone_large", |b| {
        b.iter(|| node_large.clone());
    });

    group.finish();
}

// ============================
// Hyperedge Operations Benchmarks
// ============================

fn bench_hyperedge_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("hyperedge_operations");

    group.bench_function("add_node", |b| {
        b.iter_batched(
            || {
                let mut edge = build_hyperedge_with_size(3);
                let new_id = Uuid::new_v4();
                (edge, new_id)
            },
            |(mut edge, new_id)| {
                black_box(edge.add_node(black_box(new_id)));
            },
            BatchSize::SmallInput,
        );
    });

    group.bench_function("add_nodes_bulk", |b| {
        b.iter_batched(
            || {
                let mut edge = build_hyperedge_with_size(4);
                let bulk: Vec<Uuid> = (0..4).map(|_| Uuid::new_v4()).collect();
                (edge, bulk)
            },
            |(mut edge, bulk)| {
                black_box(edge.add_nodes(black_box(bulk)));
            },
            BatchSize::SmallInput,
        );
    });

    group.bench_function("contains_node", |b| {
        let edge = build_hyperedge_with_size(10);
        let target = edge.node_ids[0];
        b.iter(|| black_box(edge.contains_node(black_box(target))));
    });

    group.bench_function("contains_any_node", |b| {
        let edge = build_hyperedge_with_size(10);
        let subset = edge.node_ids[0..3].to_vec();
        b.iter(|| black_box(edge.contains_any_node(black_box(&subset))));
    });

    group.bench_function("remove_node", |b| {
        b.iter_batched(
            || {
                let mut edge = build_hyperedge_with_size(5);
                let target = edge.node_ids[2];
                (edge, target)
            },
            |(mut edge, target)| {
                let result = edge.remove_node(black_box(target));
                black_box(result.unwrap_or(false));
            },
            BatchSize::SmallInput,
        );
    });

    group.bench_function("replace_node", |b| {
        b.iter_batched(
            || {
                let mut edge = build_hyperedge_with_size(6);
                let old = edge.node_ids[3];
                let new_id = Uuid::new_v4();
                (edge, old, new_id)
            },
            |(mut edge, old, new_id)| {
                let result = edge.replace_node(black_box(old), black_box(new_id));
                black_box(result.unwrap_or(false));
            },
            BatchSize::SmallInput,
        );
    });

    let node_ids: Vec<Uuid> = (0..20).map(|_| Uuid::new_v4()).collect();
    let edge = Hyperedge::new(
        "test-edge".into(),
        node_ids[0..10].to_vec(),
        false,
        "device".into(),
    )
    .expect("valid hyperedge");

    let edge2 = Hyperedge::new(
        "test-edge-2".into(),
        node_ids[10..20].to_vec(),
        false,
        "device".into(),
    )
    .expect("valid hyperedge");

    group.bench_function("intersection", |b| {
        b.iter(|| black_box(edge.intersection(black_box(&edge2))));
    });

    group.bench_function("union", |b| {
        b.iter(|| black_box(edge.union(black_box(&edge2))));
    });

    group.bench_function("difference", |b| {
        b.iter(|| black_box(edge.difference(black_box(&edge2))));
    });

    group.bench_function("symmetric_difference", |b| {
        b.iter(|| black_box(edge.symmetric_difference(black_box(&edge2))));
    });

    group.bench_function("overlap_degree", |b| {
        b.iter(|| black_box(edge.overlap_degree(black_box(&edge2))));
    });

    group.finish();
}

// ============================
// Serialization Scaling Benchmarks
// ============================

fn bench_node_serialization_scaling(c: &mut Criterion) {
    let mut group = c.benchmark_group("node_serialization_scaling");

    let sizes = [100usize, 1_000, 10_000, 100_000, 250_000];

    for size in sizes {
        let node = build_node_with_size(size);

        group.throughput(Throughput::Bytes(size as u64));

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| serde_json::to_string(black_box(&node)).unwrap());
        });

        let json_str = serde_json::to_string(&node).unwrap();
        group.bench_with_input(
            BenchmarkId::new("deserialize", size),
            &json_str,
            |b, input| {
                b.iter(|| serde_json::from_str::<Node>(black_box(input)).unwrap());
            },
        );
    }

    group.finish();
}

fn bench_node_validation_scaling(c: &mut Criterion) {
    let mut group = c.benchmark_group("node_validation_scaling");

    let sizes = [16usize, 64, 256, 1024, 4096];

    for &embedding_size in &sizes {
        let content = "signal".repeat(embedding_size / 4);
        let embedding = build_embedding(embedding_size);
        group.throughput(Throughput::Elements(embedding_size as u64));

        group.bench_with_input(
            BenchmarkId::from_parameter(embedding_size),
            &embedding_size,
            |b, _| {
                b.iter(|| {
                    Node::builder()
                        .content(black_box(&content))
                        .content_type(black_box(ContentType::Memory))
                        .embedding(black_box(embedding.clone()))
                        .device_id(black_box("device"))
                        .build()
                });
            },
        );
    }

    group.finish();
}

// ============================
// Hyperedge Scaling Benchmarks
// ============================

fn bench_hyperedge_intersection_scaling(c: &mut Criterion) {
    let mut group = c.benchmark_group("hyperedge_intersection_scaling");

    let sizes = [2usize, 10, 50, 100, 500, 1_000];

    for size in sizes {
        let edge1 = build_hyperedge_with_size(size);
        let edge2 = build_hyperedge_with_size(size);

        group.throughput(Throughput::Elements(size as u64));

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| black_box(edge1.intersection(black_box(&edge2))));
        });
    }

    group.finish();
}

fn bench_hyperedge_union_scaling(c: &mut Criterion) {
    let mut group = c.benchmark_group("hyperedge_union_scaling");

    let sizes = [2usize, 10, 50, 100, 500, 1_000];

    for size in sizes {
        let nodes1: Vec<Uuid> = (0..size).map(|_| Uuid::new_v4()).collect();
        let nodes2: Vec<Uuid> = (0..size).map(|_| Uuid::new_v4()).collect();
        let edge1 = Hyperedge::new("e1".into(), nodes1, false, "d".into()).unwrap();
        let edge2 = Hyperedge::new("e2".into(), nodes2, false, "d".into()).unwrap();

        group.throughput(Throughput::Elements(size as u64));

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| black_box(edge1.union(black_box(&edge2))));
        });
    }

    group.finish();
}

// ============================
// Memory Allocation Benchmarks
// ============================

fn bench_memory_allocation(c: &mut Criterion) {
    let mut group = c.benchmark_group("memory_allocation");

    group.bench_function("node_allocation_single", |b| {
        b.iter(|| {
            let node = Node::builder()
                .content("Test")
                .content_type(ContentType::Thought)
                .device_id("device")
                .build()
                .unwrap();
            black_box(node);
        });
    });

    group.bench_function("node_allocation_batch_100", |b| {
        b.iter(|| {
            let nodes: Vec<Node> = (0..100)
                .map(|i| {
                    Node::builder()
                        .content(format!("Node {}", i))
                        .content_type(ContentType::Thought)
                        .device_id("device")
                        .build()
                        .unwrap()
                })
                .collect();
            black_box(nodes);
        });
    });

    group.bench_function("node_allocation_batch_1000", |b| {
        b.iter(|| {
            let nodes: Vec<Node> = (0..1_000)
                .map(|i| {
                    Node::builder()
                        .content(format!("Node {}", i))
                        .content_type(ContentType::Thought)
                        .device_id("device")
                        .build()
                        .unwrap()
                })
                .collect();
            black_box(nodes);
        });
    });

    group.bench_function("hyperedge_allocation_10", |b| {
        b.iter(|| {
            let edge = build_hyperedge_with_size(10);
            black_box(edge);
        });
    });

    group.bench_function("hyperedge_allocation_100", |b| {
        b.iter(|| {
            let edge = build_hyperedge_with_size(100);
            black_box(edge);
        });
    });

    group.bench_function("hyperedge_allocation_clone", |b| {
        let edge = build_hyperedge_with_size(50);
        b.iter(|| edge.clone());
    });

    group.finish();
}

// ============================
// Validation Benchmarks
// ============================

fn bench_validation(c: &mut Criterion) {
    let mut group = c.benchmark_group("validation");

    group.bench_function("valid_node", |b| {
        b.iter(|| {
            Node::builder()
                .content(black_box("Valid content"))
                .content_type(black_box(ContentType::Thought))
                .device_id(black_box("device"))
                .build()
        });
    });

    group.bench_function("invalid_node_empty_content", |b| {
        b.iter(|| {
            let result = Node::builder()
                .content(black_box(""))
                .content_type(black_box(ContentType::Thought))
                .device_id(black_box("device"))
                .build();
            assert!(matches!(result, Err(ValidationError::EmptyContent)));
        });
    });

    group.bench_function("invalid_embedding_dimension", |b| {
        b.iter(|| {
            let result = Node::builder()
                .content(black_box("Test"))
                .content_type(black_box(ContentType::Context))
                .embedding(black_box(vec![0.1; 512]))
                .device_id(black_box("device"))
                .build();
            assert!(matches!(
                result,
                Err(ValidationError::InvalidEmbeddingDimension { .. })
            ));
        });
    });

    group.bench_function("invalid_metadata_type", |b| {
        b.iter(|| {
            let result = Node::builder()
                .content(black_box("Test"))
                .content_type(black_box(ContentType::Task))
                .metadata(black_box(json!(["invalid", "array"])))
                .device_id(black_box("device"))
                .build();
            assert!(matches!(result, Err(ValidationError::InvalidMetadata)));
        });
    });

    group.bench_function("hyperedge_invalid_label", |b| {
        b.iter(|| {
            let nodes = vec![Uuid::new_v4(), Uuid::new_v4()];
            let result = Hyperedge::new("", nodes, false, "device");
            assert!(matches!(result, Err(ValidationError::EmptyLabel)));
        });
    });

    group.bench_function("hyperedge_duplicate_node", |b| {
        b.iter(|| {
            let node = Uuid::new_v4();
            let nodes = vec![node, node];
            let result = Hyperedge::new("edge", nodes, false, "device");
            assert!(matches!(result, Err(ValidationError::DuplicateNodeId(_))));
        });
    });

    group.finish();
}

// ============================
// Criterion Entrypoints
// ============================

criterion_group!(
    benches,
    bench_node_creation,
    bench_serialization,
    bench_hyperedge_operations,
    bench_node_serialization_scaling,
    bench_node_validation_scaling,
    bench_hyperedge_intersection_scaling,
    bench_hyperedge_union_scaling,
    bench_memory_allocation,
    bench_validation,
);

criterion_main!(benches);
