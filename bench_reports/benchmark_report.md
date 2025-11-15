# Benchmark Report

- Reference benchmark: `grpc_dispatch_task`
- Unit: `ms` (internal ns)

| name | mean | median | p95 | ci95_low | ci95_high | throughput_rps | speedup_vs_ref | target |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| grpc_dispatch_task | 0.59 | 0.59 | 0.61 | 0.59 | 0.59 | 1699 | 1.00 | 50.00 ms (✓ PASS) |
| rest_dispatch_task | 36.02 | 35.98 | 36.24 | 35.99 | 36.05 | 28 | 0.02 | 200.00 ms (✓ PASS) |

## Target Validation

- `grpc_dispatch_task`: ✓ mean < 50.00 ms
- `rest_dispatch_task`: ✓ mean < 200.00 ms