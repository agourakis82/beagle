# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Start Commands

### Environment Setup
```bash
# Set profile (dev, lab, or prod)
export BEAGLE_PROFILE=dev
export BEAGLE_DATA_DIR=~/beagle-data
export XAI_API_KEY=your-grok-api-key

# Load environment
source .env.example
```

### Building & Running
```bash
# Build all crates
cargo build
cargo build --release  # Optimized build with LTO

# Build specific crate
cargo build -p <crate-name>

# Check syntax without building
cargo check

# Run main server
cargo run -p beagle-monorepo --bin core_server

# Run CLI pipeline
cargo run -p beagle-monorepo --bin pipeline -- --question "Your question"
```

### Testing
```bash
# All tests
cargo test --all

# Tests for specific crate
cargo test -p <crate-name>

# Single test with output
cargo test test_name -- --nocapture

# With logging
RUST_LOG=debug cargo test -- --nocapture

# Integration tests
cargo test --test '*'
```

### Code Quality (Required Before Commit)
```bash
# Format code
cargo fmt

# Lint code
cargo clippy --all-targets

# Full pre-commit check
cargo fmt && cargo clippy --all-targets && cargo test --all
```

### Database & Services
```bash
# Start development environment
docker-compose -f docker-compose.dev.yml up -d

# View logs
docker-compose logs -f postgres redis

# Run migrations
cargo run --bin migrate
```

## Project Structure

### Working Directory (beagle-remote v0.10.0)
This is the primary development version with all recent features:
- 60+ specialized Rust crates in `crates/`
- Main binaries in `apps/beagle-monorepo/`
- TypeScript MCP server in `beagle-mcp-server/`
- Julia integration in `beagle-julia/`
- Comprehensive documentation in `docs/`
- Kubernetes manifests in `k8s/`
- Docker configs in `docker/`

### Reference Version
- `../beagle/` (v0.4) - Older version, use only for reference

### Key Crates (In Priority Order)
- `crates/beagle-monorepo/` - Main HTTP server and CLI binaries
- `crates/beagle-core/` - Dependency injection (BeagleContext)
- `crates/beagle-llm/` - Multi-LLM client abstraction
- `crates/beagle-smart-router/` - TieredRouter for intelligent provider routing
- `crates/beagle-config/` - Configuration management with profiles
- `crates/beagle-agents/` - 40+ agent architectures
- `crates/beagle-triad/` - Adversarial debate (ATHENA, HERMES, ARGOS, Judge)
- `crates/beagle-feedback/` - Feedback collection and learning system
- `crates/beagle-hypergraph/` - Knowledge graph storage abstraction
- `crates/beagle-memory/` - Episodic/semantic memory with RAG

## High-Level Architecture

### Core System Design
```
HTTP API (Axum)
    ↓
BeagleContext (Dependency Injection Container)
    ├─ TieredRouter (LLM Provider Selection)
    ├─ Agent Orchestration (40+ agent types)
    └─ Memory/Storage Backends
    ↓
LLM Providers (Grok 3/4, Claude, local)
    ↓
Scientific Pipelines (Julia: PBPK, Heliobiology, symbolic reasoning)
```

### LLM Routing Tier System
**TieredRouter** intelligently selects LLM providers based on request properties:

1. **Tier 1 (Grok 3)** - Default, unlimited calls, cost-effective
   - Used for 80-90% of requests
   - Fast completion, good quality for standard tasks

2. **Tier 2 (Grok 4 Heavy)** - Premium, limited calls, highest quality
   - Used only for critical/complex tasks
   - Debate, proofs, method descriptions
   - Enforced limits: max calls/tokens per run and per day
   - Requires explicit flag: `requires_phd_level_reasoning`, `high_bias_risk`, `critical_section`

3. **Tier 3 (Math/Specialized)** - Domain-specific providers
   - For mathematical proofs, symbolic reasoning
   - Fallback when Grok unavailable

4. **Tier 4 (Local/Offline)** - Last resort
   - Local LLM or cached responses
   - When internet unavailable or API limits hit

**Routing Decision Logic**:
```rust
RequestMeta {
    requires_math: bool,
    requires_high_quality: bool,
    requires_phd_level_reasoning: bool,
    high_bias_risk: bool,
    critical_section: bool,
    offline_required: bool,
}
```

### Key Traits & Abstractions
1. **LlmClient** - Unified interface for any LLM provider with `complete()` method
2. **HypergraphStorage** - Pluggable storage (PostgreSQL, Redis, Neo4j, in-memory)
3. **Agent** - Capability-based agent composition system
4. **TieredRouter** - Provider selection with usage limits and fallbacks

### Configuration System
**Profiles** (`BEAGLE_PROFILE=dev|lab|prod`):
- `dev` - No Heavy calls, debug logging, safe mode optional
- `lab` - Heavy calls enabled with conservative limits, tracing enabled
- `prod` - Heavy calls with higher limits, minimal logging, full optimization

**Other Key Variables**:
- `BEAGLE_DATA_DIR` - Central location for all output artifacts (required)
- `BEAGLE_SAFE_MODE` - Restricts risky operations (Heavy, fallback chains)
- `XAI_API_KEY` - Grok API key (required for Tier 1/2)
- `ANTHROPIC_API_KEY` - Claude API key (for fallback/comparison)
- `DATABASE_URL` - PostgreSQL connection string
- `REDIS_URL` - Redis connection string

**Never hardcode values.** All configuration comes from environment or `BeagleConfig`.

## Development Workflow

### Adding Features
1. **Read existing code first** - Understand patterns in relevant crates
2. **Use trait abstractions** - Never couple business logic to specific LLM/storage
3. **Write tests early** - Use mocks for external services (see `MockLlmClient`)
4. **Respect configuration** - Use `BEAGLE_DATA_DIR` for paths, `RequestMeta` for routing
5. **Run quality checks** - `cargo fmt && cargo clippy --all-targets && cargo test --all`
6. **Commit with context** - Explain the "why" in commit messages

### Implementation Rules (Critical)
1. **Never** hardcode API keys, paths, or provider names
2. **Never** bypass `TieredRouter` for LLM calls (always use it)
3. **Never** create output files outside `BEAGLE_DATA_DIR`
4. **Always** pass `RequestMeta` with meaningful properties for routing decisions
5. **Always** add `run_id` to logging spans for traceability
6. **Always** test with mocks before using real LLM APIs

### Testing Patterns
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_your_feature() {
        // Arrange: Mock LLM and storage
        let mock_context = BeagleContext::new_with_mock();
        let input = prepare_test_input();

        // Act: Call function with test data
        let result = your_function(mock_context, input).await;

        // Assert: Verify behavior without touching real APIs
        assert!(result.is_ok());
        assert_eq!(result.unwrap().field, expected_value);
    }
}
```

Key testing resources:
- `beagle-llm` provides `MockLlmClient` for testing
- `testcontainers` for database tests (PostgreSQL/Redis)
- `proptest` for property-based randomized testing

### Database Changes
- Create migration files in `crates/beagle-db/migrations/` (naming: `NNN_description.sql`)
- SQLx validates all queries at compile time against schema
- Run: `cargo sqlx prepare --database-url=$DATABASE_URL`
- Test with: `cargo test -p beagle-db`

## Core Components Reference

### BeagleContext (Dependency Injection)
**Location**: `crates/beagle-core/`

Central container holding all major services. Pass this to functions instead of individual clients.

```rust
pub struct BeagleContext {
    config: BeagleConfig,
    router: Arc<TieredRouter>,
    storage: Arc<dyn HypergraphStorage>,
    agents: HashMap<String, Arc<dyn Agent>>,
    // ... more services
}
```

**Usage Pattern**:
```rust
async fn process_request(ctx: &BeagleContext, input: RequestInput) -> Result<Output> {
    let meta = RequestMeta { /* ... */ };
    let (client, tier) = ctx.router.choose_with_limits(&meta, &stats)?;
    let response = client.complete(&prompt).await?;
    // ... handle response
}
```

### TieredRouter (LLM Routing)
**Location**: `crates/beagle-smart-router/`

**Key Methods**:
- `choose_with_limits(meta: &RequestMeta, stats: &LlmCallsStats) -> Result<(Arc<dyn LlmClient>, ProviderTier)>`
  - Takes request properties and current usage stats
  - Returns appropriate LLM client and tier label
  - Respects per-tier limits; gracefully falls back when exceeded

**Usage**:
```rust
let meta = RequestMeta {
    requires_high_quality: true,
    requires_phd_level_reasoning: true,
    critical_section: true,
    ..Default::default()
};
let (client, tier) = router.choose_with_limits(&meta, &run_stats)?;
let output = client.complete(&prompt).await?;
```

### Pipeline System
**Main Entrypoint**: `cargo run -p beagle-monorepo --bin pipeline`

**Stages**:
1. Question validation and parsing
2. Research search (PubMed, arXiv APIs)
3. Draft generation with LLM + context
4. Optional Triad review (adversarial debate for critical decisions)
5. Feedback recording and statistics
6. Output to `BEAGLE_DATA_DIR/<run_id>/`

**Output Files**:
- `draft.md` - Markdown draft
- `draft.pdf` - PDF export
- `run_report.json` - Metadata, stats, LLM usage

### Triad System (Adversarial Debate)
**Location**: `crates/beagle-triad/`

Three-agent debate for validating critical outputs:
- **ATHENA** - Research specialist, high accuracy focus
- **HERMES** - Communication expert, clarity and structure
- **ARGOS** - Critical reviewer, bias and error detection
- **Judge** - Final arbitration and decision

Each agent gets routing hints:
```rust
// ATHENA
RequestMeta { requires_high_quality: true, requires_phd_level_reasoning: true, .. }

// ARGOS & Judge
RequestMeta { high_bias_risk: true, requires_phd_level_reasoning: true, critical_section: true, .. }
```

### Feedback System
**Location**: `crates/beagle-feedback/`

Collects three event types:
1. **PipelineRun** - Auto-recorded when pipeline completes
2. **TriadCompleted** - Auto-recorded after adversarial review
3. **HumanFeedback** - User ratings and annotations

Used for:
- Learning (LoRA training datasets)
- Analysis (quality metrics, performance trends)
- Continuous improvement

## Important Files & Locations

### Configuration Files
- `.env.example` - Template for all environment variables
- `.cursorrules` - Senior developer role & 30 primary TODOs (Portuguese)

### Database & Migrations
- `crates/beagle-db/migrations/` - PostgreSQL schema migrations (SQLx)
- `docker-compose.dev.yml` - PostgreSQL 16 + Redis 7 + observability
- `docker-compose.yml` - Production services

### Deployment
- `k8s/deployment.yaml` - Kubernetes manifests with health checks
- `docker/Dockerfile` - Production Docker image

### Documentation
- `docs/BEAGLE_COMPLETE_FEATURE_INVENTORY.md` - Catalog of all 60+ crates
- `docs/BEAGLE_PROJECT_MAP_v2_COMPLETE.md` - Visual project hierarchy
- `docs/BEAGLE_ROUTER_IMPLEMENTATION.md` - Router internals and tuning
- `docs/CONFIG_OVERVIEW_BEAGLE.md` - Configuration reference
- `RELEASE_NOTES_v0.10.0.md` - Latest version changes

## Debugging & Troubleshooting

### Enable Detailed Logging
```bash
# Debug level for all
RUST_LOG=debug cargo run -p beagle-monorepo --bin core_server

# Trace specific crates
RUST_LOG=beagle_llm=trace,beagle_smart_router=trace cargo run ...

# Watch spans with run_id
RUST_LOG=beagle_llm=debug,beagle_smart_router=debug cargo run ... 2>&1 | grep "run_id=abc123"
```

### Database Inspection
```bash
# Direct connection
psql $DATABASE_URL

# Recent operations
SELECT id, node_type, created_at FROM nodes ORDER BY created_at DESC LIMIT 20;

# Check current indexes
\d nodes
```

### Common Issues & Solutions

| Problem | Solution |
|---------|----------|
| SQLx compile errors | Run `cargo sqlx prepare --database-url=$DATABASE_URL` to regenerate metadata |
| Grok API 401 errors | Verify `XAI_API_KEY` is set, valid, and has available quota |
| Connection timeouts | Ensure `DATABASE_URL` format is correct and Postgres is running (`docker ps`) |
| Type mismatches in router | Check `RequestMeta` fields are set; use IDE type hints to verify |
| Files not found in output | Verify `BEAGLE_DATA_DIR` exists and is writable; check logs for actual path used |

## Performance Optimization Notes

1. **Hypergraph Queries**: Use pgvector indexes for semantic similarity searches
2. **LLM Routing**: Default to Tier 1 (Grok 3); only escalate to Heavy when justified
3. **Memory System**: GraphRAG provides semantic context efficiently
4. **Async Handlers**: All HTTP handlers are async; use `tokio::spawn` for CPU-intensive operations
5. **Connection Pooling**: SQLx manages automatically; don't create manual pools

## CI/CD & Deployment

### Pre-Commit Checklist
```bash
cargo fmt                              # Format code
cargo clippy --all-targets            # Lint
cargo test --all                      # Run tests
cargo test -p <affected-crate>        # Test specific changes
```

### GitHub Actions Workflows
- `.github/workflows/ci-cd.yml` - Test → Build → Deploy pipeline
- `.github/workflows/test-suite.yml` - Complete test execution
- `.github/workflows/benchmarks.yml` - Performance regression detection

### Code Coverage
```bash
cargo tarpaulin --all  # Generate coverage report
```

### Docker Build
```bash
docker build -f docker/Dockerfile -t beagle:latest .
```

## Technology Stack Reference

| Layer | Technology |
|-------|-----------|
| **Language** | Rust 2021 Edition |
| **Secondary** | Julia 1.10+, TypeScript, Swift |
| **Web Framework** | Axum 0.7 + Tower middleware |
| **Async Runtime** | Tokio 1.40 (full features) |
| **Databases** | PostgreSQL 16 + pgvector, Redis 7, Neo4j 5.15 (optional) |
| **LLM Providers** | Grok (XAI), Claude (Anthropic), Gemini (Google) |
| **Message Queue** | Apache Pulsar |
| **RPC** | Tonic + Protocol Buffers |
| **Observability** | OpenTelemetry + Prometheus + Jaeger |
| **Testing** | tokio-test, testcontainers, proptest, criterion |
| **ORM** | SQLx (compile-time validation) |
| **Serialization** | Serde JSON |

## External Integrations

The system connects to:
- **XAI Grok API** - Primary LLM provider (Tier 1/2)
- **Anthropic Claude API** - Reference and fallback (Tier 3)
- **Google Vertex AI** - Alternative provider
- **PubMed API** - Literature search
- **arXiv API** - Research paper indexing
- **PostgreSQL** - Primary knowledge storage
- **Redis** - Caching layer
- **OpenTelemetry Collector** - Observability aggregation

## Key References

For more details, see:
- `.cursorrules` - 30-item implementation roadmap and patterns
- `docs/BEAGLE_CORE_v0_1.md` - Core system architecture
- `RELEASE_NOTES_v0.10.0.md` - Recent features and changes
- `beagle-mcp-server/README.md` - MCP integration guide
- `beagle-julia/README.md` - Julia pipeline documentation
