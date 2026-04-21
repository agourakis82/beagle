# Critical Paths & Dependencies

**Generated:** 2026-04-02  
**Purpose:** Document system-wide critical paths and their dependencies for troubleshooting and capacity planning.

---

## Core Critical Path: User Query → Response

```
User Input
    ↓
MCP Server (beagle-mcp-server)
    ↓
BEAGLE Core HTTP API (beagle-monorepo)
    ↓
LLM Router (beagle_llm crate)
    ↓
External LLM Provider (Claude/DeepSeek/etc)
    ↓
Response Streaming/Chunking
    ↓
User Output
```

### SLO Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| P50 Latency | < 2s | End-to-end query time |
| P99 Latency | < 10s | 99th percentile query time |
| Error Rate | < 1% | 5xx errors / total requests |
| Availability | 99.9% | Uptime over 30-day window |

---

## Critical Path 1: LLM Completion

### Flow
```
beagle_llm_complete tool
    ↓
POST /api/llm/complete
    ↓
RouterAgentLlmClient
    ↓
TieredRouter.select_provider()
    ↓
Provider-specific client
    ↓
External API (Anthropic/OpenAI/DeepSeek)
```

### Dependencies
| Component | Failure Impact | Fallback |
|-----------|---------------|----------|
| TieredRouter | High | Use default tier |
| Provider API | Medium | Retry next provider |
| Auth token | Critical | Return 503 |
| Network | Medium | Retry with backoff |

### Time Budgets
| Stage | Budget | Actual (typical) |
|-------|--------|------------------|
| Routing decision | 50ms | 10-30ms |
| Provider API call | 5s | 2-5s |
| Response processing | 100ms | 20-50ms |
| Total | 5.15s | 2.1-5.1s |

---

## Critical Path 2: Memory RAG Query

### Flow
```
beagle_memory_query tool
    ↓
POST /api/memory/query
    ↓
MemoryEngine (beagle-memory)
    ↓
Qdrant vector search (if available)
    ↓
Postgres text search (fallback)
    ↓
Reranking (if results > top_k)
    ↓
Return results
```

### Dependencies
| Component | Failure Impact | Fallback |
|-----------|---------------|----------|
| Qdrant | Medium | Postgres text search |
| Postgres | Critical | Return empty results |
| Embedding model | Medium | Use stored vectors |

### Time Budgets
| Stage | Budget | Actual (typical) |
|-------|--------|------------------|
| Embedding generation | 500ms | 200-400ms |
| Qdrant search | 200ms | 50-150ms |
| Postgres query | 100ms | 20-50ms |
| Reranking | 100ms | 30-80ms |
| Total | 900ms | 300-680ms |

---

## Critical Path 3: Pipeline Execution

### Flow
```
beagle_pipeline_run tool
    ↓
POST /api/pipeline/start
    ↓
Pipeline orchestrator
    ↓
Concurrent: LLM calls + Memory queries
    ↓
Checkpoint save
    ↓
Artifact generation (draft.md, summary.json)
    ↓
Status: completed
```

### Dependencies
| Component | Failure Impact | Recovery |
|-----------|---------------|----------|
| Pipeline state | High | Resume from checkpoint |
| LLM provider | Medium | Retry with fallback |
| Storage | Critical | Pipeline fails |
| Triad (if enabled) | Low | Continue without triad |

### Time Budgets
| Stage | Budget | Actual (typical) |
|-------|--------|------------------|
| Init + checkpoint | 200ms | 50-100ms |
| Research phase | 30s | 10-20s |
| Draft generation | 30s | 10-15s |
| Summary generation | 10s | 3-5s |
| Total | 70s | 23-40s |

---

## Critical Path 4: Void Navigation (Feature Flag)

### Flow (when `void` feature enabled)
```
/dev/void endpoint or deadlock detected
    ↓
handle_deadlock_with_void()
    ↓
VoidOrchestrator.journey()
    ↓
VoidNavigator.navigate()
    ↓
ExtractionEngine.extract() [multiple types]
    ↓
VoidProbe.probe()
    ↓
Compile insights + return
```

### Dependencies
| Component | Failure Impact | Fallback |
|-----------|---------------|----------|
| VoidOrchestrator | Low | Fallback message |
| Random generator | Low | Deterministic fallback |
| Async runtime | Medium | Sync fallback |

### Time Budgets
| Stage | Budget | Actual (typical) |
|-------|--------|------------------|
| Navigation | 100ms | 10-50ms |
| Extractions | 50ms | 5-20ms |
| Probing | 20ms | 5-10ms |
| Total | 170ms | 20-80ms |

---

## Infrastructure Dependencies

### Required (System Down If Unavailable)

| Service | Health Check | Failure Mode |
|---------|-------------|--------------|
| Postgres | `SELECT 1` | All operations fail |
| BEAGLE Core process | HTTP /health | 503 on all requests |

### Optional (Graceful Degradation)

| Service | Health Check | Degradation Mode |
|---------|-------------|------------------|
| Qdrant | HTTP /health | Use Postgres text search |
| Redis (if enabled) | PING | Disable caching |
| External LLM | API probe | Use next provider |
| Tavily API | N/A | Skip web search |

---

## Failure Scenarios & Mitigations

### Scenario 1: LLM Provider Outage
**Impact:** All completions fail  
**Detection:** Error rate > 10%  
**Mitigation:**
1. Auto-retry with exponential backoff
2. Failover to next provider in tier
3. Downgrade to lower tier if needed
4. Return 503 with error details

### Scenario 2: Qdrant Unavailable
**Impact:** Vector search fails, RAG degraded  
**Detection:** Health check fails  
**Mitigation:**
1. Automatic fallback to Postgres text search
2. Log degradation event
3. Display warning in response
4. Queue re-indexing when Qdrant returns

### Scenario 3: Memory Exhaustion
**Impact:** Slow queries, potential OOM  
**Detection:** Memory usage > 80%  
**Mitigation:**
1. Enable circuit breaker for non-critical paths
2. Reduce cache TTL
3. Return 503 with "system under load" message
4. Alert operator

### Scenario 4: Deadlock in Pipeline
**Impact:** Pipeline stuck, user waiting  
**Detection:** No progress for > 30s  
**Mitigation:**
1. DeadlockState tracking in pipeline_void
2. Auto-trigger VoidNavigator (if feature enabled)
3. Return partial results with explanation
4. Log for analysis

---

## Monitoring Checkpoints

| Checkpoint | Metric | Alert Threshold |
|------------|--------|-----------------|
| LLM Router | p99 latency | > 8s |
| Memory Query | Error rate | > 5% |
| Pipeline | Completion time | > 60s |
| Qdrant | Connection failures | > 3 in 5min |
| Auth | Failed attempts | > 10/min |

---

## Scaling Vectors

| Component | Current Bottleneck | Scale Strategy |
|-----------|-------------------|----------------|
| LLM Router | External API rate limits | Add provider diversity |
| Memory Query | Qdrant connection pool | Add Qdrant replicas |
| Pipeline | Sequential LLM calls | Parallelize where possible |
| MCP Server | Single process | Add HTTP transport instances |

---

*Document generated via audit process. Update when adding new critical paths or changing SLOs.*
