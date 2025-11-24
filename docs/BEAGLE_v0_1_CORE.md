# BEAGLE Core v0.1 — Architecture & User Guide

**Version:** 0.1.0  
**Date:** 2025-01  
**Status:** Production Ready

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Directory Structure](#directory-structure)
4. [Configuration](#configuration)
5. [Core Components](#core-components)
6. [Running the System](#running-the-system)
7. [Complete Workflow](#complete-workflow)
8. [Environment Variables](#environment-variables)
9. [Profiles: dev vs lab vs prod](#profiles-dev-vs-lab-vs-prod)
10. [LLM Routing Strategy](#llm-routing-strategy)
11. [Feedback Loop & Continuous Learning](#feedback-loop--continuous-learning)
12. [Command Reference](#command-reference)
13. [Troubleshooting](#troubleshooting)

---

## Overview

BEAGLE v0.1 is a **scientific exocortex** that combines:

- **Cloud-first LLM architecture**: Grok 3 (unlimited, Tier 1) + Grok 4 Heavy (anti-bias vaccine, Tier 2)
- **Multi-modal context**: GraphRAG (Darwin), physiological state (Observer 2.0), serendipity injection
- **Adversarial review**: Honest AI Triad (ATHENA–HERMES–ARGOS + Judge)
- **Continuous learning**: Feedback loop for future LoRA training

**Key Philosophy:**
- Cloud LLMs free local GPUs for compute-intensive work (PBPK, MD, FEA, Deep Learning)
- Grok 3 handles ~94% of requests (unlimited, fast, cost ≈ 0)
- Grok 4 Heavy is a "vaccine" against bias for high-risk/critical sections
- Safe mode prevents accidental publication/costs

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         BEAGLE v0.1 Core                        │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐      ┌──────────────────────────────────────┐
│              │      │                                      │
│    Julia     │─────▶│  BEAGLE Core HTTP (Axum)            │
│  Pipelines   │ HTTP │  Port: 8080                         │
│  (PBPK/KEC)  │      │  Endpoints: /api/llm/complete       │
│              │      │             /api/pipeline/start     │
└──────────────┘      │             /health                 │
                      └──────────────┬───────────────────────┘
                                     │
                      ┌──────────────▼───────────────────────┐
                      │   TieredRouter (Smart LLM Router)   │
                      │   - Grok 3 (Tier 1, default)        │
                      │   - Grok 4 Heavy (Tier 2, critical) │
                      │   - Claude/Copilot/Cursor (Tier 0)  │
                      │   - Local fallback (offline)        │
                      └──────────────┬───────────────────────┘
                                     │
        ┌────────────────────────────┼────────────────────────┐
        │                            │                        │
        ▼                            ▼                        ▼
┌───────────────┐          ┌────────────────┐       ┌────────────────┐
│   Pipeline    │          │     Triad      │       │   Observer     │
│   v0.1        │          │  (Adversarial  │       │   (HRV/Physio) │
│               │          │   Review)      │       │                │
│ 1. Darwin     │          │                │       │ - HealthKit    │
│    (GraphRAG) │          │ • ATHENA       │       │ - Environment  │
│ 2. Observer   │          │ • HERMES       │       │ - Space Weather│
│ 3. HERMES     │◀────────▶│ • ARGOS        │       │                │
│    (Synthesis)│          │ • Judge        │       └────────────────┘
│ 4. Artifacts  │          │                │
│    (MD/PDF)   │          └────────────────┘
└───────┬───────┘                   │
        │                           │
        └───────────┬───────────────┘
                    │
                    ▼
        ┌───────────────────────────┐
        │   Feedback System         │
        │   (feedback_events.jsonl) │
        │                           │
        │ - PipelineRun events      │
        │ - TriadCompleted events   │
        │ - HumanFeedback events    │
        └───────────┬───────────────┘
                    │
                    ▼
        ┌───────────────────────────┐
        │   LoRA Dataset Export     │
        │   (Future training)       │
        └───────────────────────────┘
```

---

## Directory Structure

All data lives under `BEAGLE_DATA_DIR` (default: `~/beagle-data`).

```
$BEAGLE_DATA_DIR/
├── papers/
│   ├── drafts/               # Pipeline outputs (draft.md, draft.pdf)
│   └── final/                # Published papers (future)
├── logs/
│   ├── beagle-pipeline/      # Run reports (JSON)
│   └── observer/             # Observer logs
├── triad/
│   └── <run_id>/             # Triad reports and artifacts
├── feedback/
│   └── feedback_events.jsonl # Continuous learning log
├── embeddings/               # Vector embeddings (FAISS, Qdrant)
├── datasets/                 # Training datasets
├── experiments/              # A/B test data
├── jobs/                     # Background job outputs
├── models/                   # LoRA adapters, local models
└── .beagle-data-path         # Config file (optional)
```

**Note:** Never hardcode `~/beagle-data`. Always use `cfg.storage.data_dir` in code.

---

## Configuration

BEAGLE is configured via:
1. **Environment variables** (highest priority)
2. **Config file** `.beagle-data-path` in repo root (optional)
3. **Defaults** (safest fallbacks)

### Key Config Struct

```rust
pub struct BeagleConfig {
    pub profile: String,              // "dev" | "lab" | "prod"
    pub safe_mode: bool,              // true = never publish, safe for testing
    pub api_token: Option<String>,    // Bearer token for HTTP API
    pub storage: StorageConfig,       // data_dir path
    pub llm: LlmConfig,               // API keys, model names
    pub observer: ObserverThresholds, // HRV/physio thresholds
    // ... (graph, hermes, advanced modules)
}
```

### Loading Config

```rust
use beagle_config::load;

let cfg = load(); // Reads from env + file + defaults
```

---

## Core Components

### 1. **TieredRouter** (LLM Smart Routing)

**Location:** `crates/beagle-llm/src/router_tiered.rs`

**Purpose:** Route LLM requests to the best provider based on:
- Task requirements (math, high quality, bias risk, critical section)
- Current usage stats (Heavy limits)
- Profile (dev/lab/prod)

**Tiers:**
- **Tier -2:** Claude CLI (local, no API key needed)
- **Tier -1:** GitHub Copilot, Cursor AI (existing subscriptions)
- **Tier 0:** Claude Direct (Anthropic API, Claude MAX)
- **Tier 1:** Grok 3 (default, unlimited, fast)
- **Tier 2:** Grok 4 Heavy (anti-bias vaccine, limited usage)
- **Cloud Math:** DeepSeek Math (future)
- **Local Fallback:** Gemma 9B (offline mode)

**Usage:**

```rust
use beagle_llm::{RequestMeta, TieredRouter};

let router = TieredRouter::from_config(&cfg)?;

let meta = RequestMeta {
    high_bias_risk: true,           // Triggers Heavy if available
    requires_phd_level_reasoning: true,
    critical_section: true,
    // ...
};

let stats = ctx.llm_stats.get_or_create(run_id);
let (client, tier) = router.choose_with_limits(&meta, &stats);

let output = client.complete(prompt).await?;
```

### 2. **BeagleContext** (Core System State)

**Location:** `crates/beagle-core/src/context.rs`

**Purpose:** Central struct holding all system components.

```rust
pub struct BeagleContext {
    pub cfg: BeagleConfig,
    pub router: TieredRouter,
    pub llm: Arc<dyn LlmClient>,
    pub vector: Arc<dyn VectorStore>,
    pub graph: Arc<dyn GraphStore>,
    pub llm_stats: Arc<LlmStatsRegistry>, // Tracks Grok3/4 usage per run
    #[cfg(feature = "memory")]
    pub memory: Option<Arc<MemoryEngine>>,
}
```

### 3. **Pipeline v0.1** (Paper Drafting)

**Location:** `apps/beagle-monorepo/src/pipeline.rs`

**Purpose:** Generate scientific paper drafts from a research question.

**Steps:**
1. **Darwin (GraphRAG):** Retrieve relevant context from knowledge graph
2. **Observer (Physio):** Capture user's physiological state (HRV, HR, SpO₂, environment, space weather)
3. **Serendipity (Optional):** Inject cross-domain connections
4. **HERMES (Synthesis):** Generate draft paper
5. **Void (Optional):** Detect and resolve deadlocks
6. **Write Artifacts:** Save draft.md, draft.pdf, run_report.json
7. **Log Feedback Event:** Append to feedback_events.jsonl

### 4. **Triad (Adversarial Review)**

**Location:** `crates/beagle-triad/src/lib.rs`

**Purpose:** Honest AI peer review using three adversarial agents + judge.

**Agents:**
- **ATHENA:** Literature review, strengths/weaknesses, suggest references
- **HERMES:** Rewrite for clarity, incorporate ATHENA feedback
- **ARGOS:** Critical adversarial review (bias detector, uses Heavy)
- **Judge:** Arbitrate final version

**Flow:**
```
Original Draft → ATHENA → HERMES (rewrite) → ARGOS (critique) → Judge → Final Draft
```

### 5. **Observer 2.0** (Multi-modal Context)

**Location:** `crates/beagle-observer/`

**Purpose:** Capture user's complete environmental context.

**Data Sources:**
- **Physiological:** HRV, HR, SpO₂, respiration, skin temp (HealthKit)
- **Environmental:** Location, altitude, barometric pressure, UV index, humidity
- **Space Weather:** Solar activity (Kp index, solar wind, X-ray flux)

**HRV Mapping:**
- **Low HRV (<30ms):** Stress, fatigue → Pipeline uses calmer tone
- **Normal HRV (30-80ms):** Balanced state → Default behavior
- **High HRV (>80ms):** Flow state → More creative, exploratory prompts

### 6. **Feedback System** (Continuous Learning)

**Location:** `crates/beagle-feedback/`

**Purpose:** Log all pipeline/triad runs + human feedback for future LoRA training.

**Event Types:**
1. **PipelineRun:** Logged after pipeline completes
2. **TriadCompleted:** Logged after Triad finishes
3. **HumanFeedback:** Logged via `tag_run` CLI

**Storage:** `$BEAGLE_DATA_DIR/feedback/feedback_events.jsonl`

---

## Running the System

### Prerequisites

1. **Rust:** Install via https://rustup.rs
2. **API Keys:**
   ```bash
   export XAI_API_KEY="your-grok-api-key"
   export ANTHROPIC_API_KEY="your-claude-key"  # Optional
   export GITHUB_TOKEN="ghp_..."                # Optional (Copilot)
   ```
3. **Data Directory:**
   ```bash
   export BEAGLE_DATA_DIR="$HOME/beagle-data"
   ```
4. **Profile:**
   ```bash
   export BEAGLE_PROFILE="dev"  # or "lab" or "prod"
   ```

### 1. Start Core HTTP Server

```bash
cd beagle-remote
cargo run --bin beagle-monorepo --release
```

**Default port:** 8080  
**Health check:** `curl http://localhost:8080/health`

**Expected output:**
```json
{
  "status": "ok",
  "service": "beagle-core",
  "profile": "dev",
  "safe_mode": true,
  "data_dir": "/home/user/beagle-data",
  "xai_api_key_present": true
}
```

### 2. Run Pipeline (CLI)

```bash
cargo run --bin pipeline --package beagle-monorepo -- "Research question here"
```

**Example:**
```bash
cargo run --bin pipeline --package beagle-monorepo -- \
  "Entropic scaffolds for neuroplasticity in computational psychiatry"
```

**Output:**
```
Run ID: 550e8400-e29b-41d4-a716-446655440000
Draft MD:   /home/user/beagle-data/papers/drafts/20250115_550e8400.md
Draft PDF:  /home/user/beagle-data/papers/drafts/20250115_550e8400.pdf
RunReport:  /home/user/beagle-data/logs/beagle-pipeline/20250115_550e8400.json
```

### 3. Run Triad Review

```bash
cargo run --bin triad_review --package beagle-triad -- \
  --run-id 550e8400-e29b-41d4-a716-446655440000 \
  --draft /home/user/beagle-data/papers/drafts/20250115_550e8400.md
```

**Output:**
```
Triad report saved to:
  /home/user/beagle-data/triad/550e8400/triad_report.json
  /home/user/beagle-data/triad/550e8400/final_draft.md
```

### 4. Tag Run with Human Feedback

```bash
cargo run --bin tag_run --package beagle-feedback -- \
  550e8400-e29b-41d4-a716-446655440000 \
  1 \
  9 \
  "Excellent interdisciplinary connections, Methods section needs PBPK details"
```

**Arguments:**
- `run_id`
- `accepted` (1 = yes, 0 = no)
- `rating_0_10` (0-10)
- `notes` (optional)

---

## Complete Workflow

### Scenario: Generate and Review a Paper

```bash
# 1. Set environment
export BEAGLE_PROFILE="lab"
export BEAGLE_DATA_DIR="$HOME/beagle-data"
export XAI_API_KEY="xai-..."

# 2. Start server (in terminal 1)
cargo run --bin beagle-monorepo --release

# 3. Run pipeline (in terminal 2)
cargo run --bin pipeline --package beagle-monorepo -- \
  "PBPK modeling of entropic drug delivery in neuropsychiatric applications"

# Save the run_id from output
RUN_ID="550e8400-e29b-41d4-a716-446655440000"

# 4. Review draft manually
cat ~/beagle-data/papers/drafts/20250115_${RUN_ID}.md

# 5. Run Triad review
cargo run --bin triad_review --package beagle-triad -- \
  --run-id $RUN_ID \
  --draft ~/beagle-data/papers/drafts/20250115_${RUN_ID}.md

# 6. Review Triad output
cat ~/beagle-data/triad/${RUN_ID}/final_draft.md

# 7. Tag with human feedback
cargo run --bin tag_run --package beagle-feedback -- \
  $RUN_ID 1 9 "High quality, minor edits needed in Discussion"

# 8. List all runs
cargo run --bin list_runs --package beagle-feedback

# 9. Analyze feedback stats
cargo run --bin analyze_feedback --package beagle-feedback

# 10. Export LoRA dataset (when you have enough tagged runs)
cargo run --bin export_lora_dataset --package beagle-feedback
```

---

## Environment Variables

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `XAI_API_KEY` | Grok API key | `xai-abc123...` |
| `BEAGLE_DATA_DIR` | Data directory | `/home/user/beagle-data` |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `BEAGLE_PROFILE` | Execution profile | `dev` |
| `BEAGLE_SAFE_MODE` | Prevent real publish | `true` |
| `BEAGLE_HEAVY_ENABLE` | Enable Grok 4 Heavy | `false` (dev), `true` (lab/prod) |
| `BEAGLE_HEAVY_MAX_CALLS_PER_RUN` | Heavy call limit | `5` (lab), `10` (prod) |
| `BEAGLE_HEAVY_MAX_TOKENS_PER_RUN` | Heavy token limit | `100000` (lab), `200000` (prod) |
| `BEAGLE_CORE_ADDR` | HTTP server address | `0.0.0.0:8080` |
| `ANTHROPIC_API_KEY` | Claude Direct API | - |
| `GITHUB_TOKEN` | GitHub Copilot | - |
| `CURSOR_API_KEY` | Cursor AI | - |
| `DEEPSEEK_API_KEY` | DeepSeek Math | - |

### Advanced

| Variable | Description | Default |
|----------|-------------|---------|
| `BEAGLE_SERENDIPITY_ENABLE` | Cross-domain discovery | `false` |
| `BEAGLE_VOID_ENABLE` | Deadlock detection | `false` |
| `BEAGLE_MEMORY_RETRIEVAL_ENABLE` | Memory RAG injection | `false` |
| `BEAGLE_HRV_LOW_MS` | Low HRV threshold | `30.0` |
| `BEAGLE_HRV_HIGH_MS` | High HRV threshold | `80.0` |

---

## Profiles: dev vs lab vs prod

### Dev Profile
- **Purpose:** Local development, testing
- **Heavy:** **DISABLED** (all requests use Grok 3)
- **Safe Mode:** **FORCED ON** (never publish)
- **Use case:** Rapid iteration, debugging, unit tests

```bash
export BEAGLE_PROFILE="dev"
export BEAGLE_SAFE_MODE="true"
```

### Lab Profile
- **Purpose:** Research experiments, A/B tests
- **Heavy:** **ENABLED** with conservative limits
  - Max 5 calls per run
  - Max 100k tokens per run
- **Safe Mode:** Recommended ON
- **Use case:** Real research with cost control

```bash
export BEAGLE_PROFILE="lab"
export BEAGLE_SAFE_MODE="true"  # Recommended
```

### Prod Profile
- **Purpose:** Production paper generation
- **Heavy:** **ENABLED** with higher limits
  - Max 10 calls per run
  - Max 200k tokens per run
- **Safe Mode:** Optional (can be OFF for real publish)
- **Use case:** Final paper drafts for submission

```bash
export BEAGLE_PROFILE="prod"
export BEAGLE_SAFE_MODE="false"  # Only if ready to publish
```

**⚠️ Warning:** Setting `BEAGLE_SAFE_MODE=false` in prod enables real publication and may incur costs. Use with caution.

---

## LLM Routing Strategy

### When does the router choose Heavy?

Grok 4 Heavy is selected when **ALL** of these conditions are met:

1. **Task flags:**
   - `high_bias_risk=true` **OR**
   - `requires_phd_level_reasoning=true` **OR**
   - `critical_section=true`

2. **Heavy is enabled** (`BEAGLE_HEAVY_ENABLE=true`)

3. **Within limits:**
   - `grok4_calls < heavy_max_calls_per_run`
   - `grok4_total_tokens < heavy_max_tokens_per_run`

If any condition fails, **fallback to Grok 3**.

### RequestMeta Examples

**Scenario 1: ARGOS critique (uses Heavy)**
```rust
RequestMeta {
    high_bias_risk: true,           // Claims need scrutiny
    requires_phd_level_reasoning: true,
    critical_section: true,
    // ...
}
// Result: Grok 4 Heavy (if within limits)
```

**Scenario 2: Draft generation (uses Grok 3)**
```rust
RequestMeta {
    high_bias_risk: false,
    requires_phd_level_reasoning: true,
    critical_section: false,
    requires_high_quality: true,
    // ...
}
// Result: Grok 3 (no bias risk or critical flag)
```

**Scenario 3: Math derivation (uses DeepSeek if available)**
```rust
RequestMeta {
    requires_math: true,
    // ...
}
// Result: DeepSeek Math (if API key present), else Grok 3
```

### Observing Router Decisions

Check logs:
```
INFO Router → Grok4Heavy (within limits: 2/10 calls, 15000/200000 tokens)
INFO Router → Grok3 (Heavy limit exceeded)
```

Check run_report.json:
```json
{
  "llm_stats": {
    "grok3_calls": 3,
    "grok3_tokens_in": 5000,
    "grok3_tokens_out": 8000,
    "grok4_calls": 2,
    "grok4_tokens_in": 3000,
    "grok4_tokens_out": 12000
  }
}
```

---

## Feedback Loop & Continuous Learning

### Philosophy

Every pipeline run is a **learning opportunity**. BEAGLE logs:
- Research question
- Generated drafts
- Triad reviews
- LLM provider usage (Grok 3 vs Heavy)
- User's physiological state (HRV level)
- Human judgment (accepted/rejected, rating 0-10)

This data feeds future **LoRA fine-tuning** to improve quality over time.

### Data Flow

```
Pipeline Run → feedback_events.jsonl (PipelineRun)
     ↓
Triad Review → feedback_events.jsonl (TriadCompleted)
     ↓
Human Tags  → feedback_events.jsonl (HumanFeedback)
     ↓
Filter (accepted=true, rating≥8)
     ↓
export_lora_dataset → lora_dataset.jsonl
     ↓
Future LoRA Training (external)
```

### Tagging Best Practices

**Tag immediately after review:**
```bash
# Accepted, high quality
tag_run $RUN_ID 1 9 "Excellent Methods, minor Discussion tweaks"

# Rejected, needs work
tag_run $RUN_ID 0 4 "Methods unclear, Results incomplete"

# Neutral (for later decision)
tag_run $RUN_ID 0 5 "Needs major revision"
```

**Rating scale:**
- **9-10:** Publication-ready (or very close)
- **7-8:** Good, needs minor revisions
- **5-6:** Acceptable, needs moderate work
- **3-4:** Poor quality, major issues
- **0-2:** Unusable

**Goal:** Accumulate 100+ high-quality examples (rating≥8) for LoRA training.

---

## Command Reference

### Pipeline & Triad

```bash
# Run pipeline
cargo run --bin pipeline --package beagle-monorepo -- "Question"

# Run pipeline with Triad automatically (future feature)
cargo run --bin pipeline --package beagle-monorepo -- --with-triad "Question"

# Run Triad separately
cargo run --bin triad_review --package beagle-triad -- \
  --run-id <RUN_ID> \
  --draft <PATH_TO_DRAFT>
```

### Feedback Commands

```bash
# List all runs
cargo run --bin list_runs --package beagle-feedback

# Tag a run
cargo run --bin tag_run --package beagle-feedback -- \
  <RUN_ID> <ACCEPTED> <RATING> "<NOTES>"

# Analyze feedback stats
cargo run --bin analyze_feedback --package beagle-feedback

# Export LoRA training dataset
cargo run --bin export_lora_dataset --package beagle-feedback
```

### Stress Testing

```bash
# Run 50 concurrent pipelines (5 at a time) with mocks
export BEAGLE_STRESS_RUNS=50
export BEAGLE_STRESS_CONCURRENCY=5
export BEAGLE_LLM_MOCK=true
cargo run --bin stress_pipeline --package beagle-stress-test
```

### HTTP API

```bash
# Health check
curl http://localhost:8080/health

# LLM completion (requires Bearer token)
curl -X POST http://localhost:8080/api/llm/complete \
  -H "Authorization: Bearer $BEAGLE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain PBPK modeling",
    "requires_high_quality": true
  }'

# Start pipeline via API
curl -X POST http://localhost:8080/api/pipeline/start \
  -H "Authorization: Bearer $BEAGLE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "question": "Neuroplasticity and entropy",
    "with_triad": true
  }'
```

---

## Troubleshooting

### Issue: "XAI_API_KEY not found"

**Solution:**
```bash
export XAI_API_KEY="your-key-here"
```

Verify:
```bash
echo $XAI_API_KEY
```

### Issue: "Heavy always falls back to Grok 3"

**Check:**
1. Profile is not `dev`:
   ```bash
   export BEAGLE_PROFILE="lab"
   ```
2. Heavy is enabled:
   ```bash
   export BEAGLE_HEAVY_ENABLE="true"
   ```
3. Limits not exceeded (check run_report.json)

### Issue: "Pipeline crashes with Postgres/Neo4j error"

**Cause:** Optional features (HERMES, Neo4j) not configured.

**Solution:** Set safe mode and use mock context:
```bash
export BEAGLE_SAFE_MODE="true"
# Or disable optional features in Cargo.toml
```

### Issue: "Feedback events not logged"

**Check:**
1. Data directory exists:
   ```bash
   mkdir -p $BEAGLE_DATA_DIR/feedback
   ```
2. Permissions:
   ```bash
   ls -la $BEAGLE_DATA_DIR/feedback
   ```
3. Check pipeline logs for errors

### Issue: "Stress test hangs"

**Cause:** Real LLM calls are slow/timing out.

**Solution:** Use mock mode:
```bash
export BEAGLE_LLM_MOCK=true
cargo run --bin stress_pipeline --package beagle-stress-test
```

---

## Development Tips

### Running Tests

```bash
# Unit tests
cargo test -p beagle-llm
cargo test -p beagle-triad
cargo test -p beagle-feedback

# Integration tests (requires mock)
cargo test -p beagle-monorepo --test pipeline_mock
```

### Formatting & Linting

```bash
# Format all code
cargo fmt --all

# Run clippy
cargo clippy --all-targets --all-features

# Fix common issues
cargo clippy --fix --allow-dirty
```

### Debugging LLM Calls

Enable tracing:
```bash
export RUST_LOG="beagle_llm=debug,beagle_monorepo=debug"
cargo run --bin pipeline --package beagle-monorepo -- "Test question"
```

Look for:
```
DEBUG Router → Choosing provider for meta: RequestMeta { ... }
DEBUG Router → Selected Grok4Heavy (high_bias_risk=true)
DEBUG LLM call completed: 2341 tokens in 3.2s
```

---

## Next Steps

1. **Generate your first paper:**
   ```bash
   cargo run --bin pipeline --package beagle-monorepo -- "Your research question"
   ```

2. **Review with Triad:**
   ```bash
   cargo run --bin triad_review --package beagle-triad -- --run-id <ID> --draft <PATH>
   ```

3. **Tag and iterate:**
   ```bash
   cargo run --bin tag_run --package beagle-feedback -- <ID> 1 8 "Good quality"
   ```

4. **After 50+ runs, export dataset:**
   ```bash
   cargo run --bin export_lora_dataset --package beagle-feedback
   ```

5. **Train LoRA adapter** (external, e.g., with Axolotl or LLaMA-Factory)

---

## Support & Contributing

- **Issues:** GitHub Issues
- **Docs:** `docs/` directory
- **Architecture deep-dive:** `BEAGLE_ARCHITECTURE.md`
- **Contributing:** `CONTRIBUTING_BEAGLE.md`

**License:** MIT  
**Maintainer:** BEAGLE Team  
**Version:** v0.1.0 (January 2025)