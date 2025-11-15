
=== BENCHMARK COMPARISON ===

gRPC Latency (mean): 0.59ms
REST Latency (mean): 36.02ms

Speedup: 61.19x faster

gRPC Throughput: 1699 req/s
REST Throughput: 28 req/s

=== TARGET VALIDATION ===

gRPC latency < 50ms: ✅ PASS
REST latency < 200ms: ✅ PASS

✅ gRPC port is JUSTIFIED (>2x speedup + <50ms latency)

=== BENCHMARKS ===

name | mean_ms | median_ms | p95_ms | ci95_low_ms | ci95_high_ms | throughput_rps | speedup_vs_ref | target
----------------------------------------------------------------------------------------------------
grpc_dispatch_task | 0.59 | 0.59 | 0.61 | 0.59 | 0.59 | 1699 | 1.00 | 50.00 ms (PASS)
rest_dispatch_task | 36.02 | 35.98 | 36.24 | 35.99 | 36.05 | 28 | 0.02 | 200.00 ms (PASS)

