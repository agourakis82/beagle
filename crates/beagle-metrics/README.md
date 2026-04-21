# BEAGLE Prometheus Metrics

Prometheus metrics export for BEAGLE observability. This crate provides comprehensive metrics collection and exposition for the BEAGLE system.

## Features

- **LLM Router Metrics**: Track requests, latency, tokens, and costs across LLM providers
- **Memory Metrics**: Monitor memory queries, index sizes, and Qdrant health
- **Pipeline Metrics**: Measure pipeline runs, durations, and stage performance
- **System Metrics**: Track active connections and rate limiting
- **HTTP Metrics**: Automatic request/response metrics via middleware

## Quick Start

### 1. Add to your `Cargo.toml`:

```toml
[dependencies]
beagle-metrics = { path = "../beagle-metrics" }
```

### 2. Initialize metrics in your application:

```rust
use beagle_metrics::{METRICS, record_llm_request, record_pipeline_start, record_pipeline_end};
use std::time::Duration;

// Record an LLM request
record_llm_request(
    "grok",           // provider
    "standard",       // tier
    "success",        // status
    Duration::from_secs(2),  // duration
    100,              // tokens_in
    150,              // tokens_out
    0.005,            // cost_usd
);

// Record pipeline execution
record_pipeline_start();
// ... run pipeline ...
record_pipeline_end("success", Duration::from_secs(30));
```

### 3. Access metrics endpoint:

The metrics are automatically exposed at `/metrics` in Prometheus text format.

```bash
curl http://localhost:8080/metrics
```

## Metrics Reference

### LLM Router Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `beagle_llm_requests_total` | Counter | `provider`, `tier`, `status` | Total LLM requests |
| `beagle_llm_request_duration_seconds` | Histogram | `provider`, `tier` | Request latency |
| `beagle_llm_tokens_total` | Counter | `provider`, `type` (input/output) | Token usage |
| `beagle_llm_cost_usd_total` | Counter | `provider` | Total cost in USD |
| `beagle_llm_cache_total` | Counter | `status` (hit/miss) | Cache statistics |

### Memory Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `beagle_memory_queries_total` | Counter | `source`, `status` | Memory query count |
| `beagle_memory_query_duration_seconds` | Histogram | `source` | Query latency |
| `beagle_memory_index_size` | Gauge | `index_type` | Index size |
| `beagle_qdrant_health_status` | Gauge | - | Health status (1=healthy, 0=unhealthy) |

### Pipeline Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `beagle_pipeline_runs_total` | Counter | `status` | Pipeline execution count |
| `beagle_pipeline_duration_seconds` | Histogram | `status` | Total duration |
| `beagle_pipeline_stages_duration_seconds` | Histogram | `stage` | Stage duration |
| `beagle_active_pipelines` | Gauge | - | Currently running pipelines |

### System Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `beagle_active_connections` | Gauge | - | Active HTTP connections |
| `beagle_rate_limit_hits_total` | Counter | `identifier` | Rate limit triggers |
| `beagle_http_requests_total` | Counter | `method`, `endpoint`, `status` | HTTP request count |
| `beagle_http_request_duration_seconds` | Histogram | `method`, `endpoint` | HTTP request latency |

## Histogram Buckets

### LLM Request Duration (seconds)
```
0.1, 0.5, 1.0, 2.0, 5.0, 10.0
```

### Memory Query Duration (seconds)
```
0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0
```

### Pipeline Duration (seconds)
```
1.0, 5.0, 10.0, 30.0, 60.0, 120.0, 300.0, 600.0
```

## HTTP Integration (Axum)

The crate provides Axum middleware for automatic metrics collection:

```rust
use beagle_metrics::{metrics_router, metrics_middleware};
use axum::{Router, middleware};

let app = Router::new()
    .merge(my_routes)
    // Add metrics endpoint at /metrics
    .merge(metrics_router())
    // Add automatic HTTP metrics collection
    .layer(middleware::from_fn(metrics_middleware));
```

## Prometheus Configuration

See `../../observability/prometheus/prometheus.yml` for a complete Prometheus configuration including:
- Scrape configuration for BEAGLE metrics
- Alert rules for critical conditions
- Recording rules for aggregated metrics

### Alert Rules Included

- `BeagleHighLLMErrorRate`: LLM error rate > 10%
- `BeagleHighLLMLatency`: 95th percentile latency > 10s
- `BeagleHighPipelineFailureRate`: Pipeline failure rate > 20%
- `BeagleQdrantUnhealthy`: Qdrant health status check
- `BeagleHighRateLimitHits`: Rate limit threshold exceeded
- `BeagleHighLLMCost`: Cost threshold exceeded

## Docker Compose

The observability stack is configured in `docker-compose.observability.yml`:

```bash
docker-compose -f docker-compose.observability.yml up -d
```

Services:
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3001 (admin/admin)

## Testing

Run the built-in tests:

```bash
cargo test -p beagle-metrics
```

Example curl test:

```bash
# After starting the BEAGLE server
curl -s http://localhost:8080/metrics | grep beagle_llm
curl -s http://localhost:8080/metrics/health
```

## License

MIT OR Apache-2.0
