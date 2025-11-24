# BEAGLE v0.1 — Complete Workflow Guide

**Quick Start:** Research Question → Draft → Review → Feedback → Dataset

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Workflow Overview](#workflow-overview)
4. [Step-by-Step Guide](#step-by-step-guide)
5. [Environment Variables Reference](#environment-variables-reference)
6. [Common Scenarios](#common-scenarios)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

- **Rust 1.70+** → Install: https://rustup.rs
- **Git** → For cloning the repository

### Required API Keys

At minimum, you need:

```bash
export XAI_API_KEY="xai-your-api-key-here"
```

### Optional Enhancements

```bash
# Claude Direct (Tier 0, best quality)
export ANTHROPIC_API_KEY="sk-ant-..."

# GitHub Copilot (Tier -1, uses existing subscription)
export GITHUB_TOKEN="ghp_..."

# Cursor AI (Tier -1)
export CURSOR_API_KEY="cursor_..."

# DeepSeek Math (for mathematical reasoning)
export DEEPSEEK_API_KEY="sk-..."
```

---

## Initial Setup

### 1. Clone and Build

```bash
# Clone repository
git clone https://github.com/your-org/beagle-remote.git
cd beagle-remote

# Build all binaries (takes 5-10 minutes first time)
cargo build --release
```

### 2. Configure Environment

Create a file `~/.beagle_env`:

```bash
# Core configuration
export BEAGLE_PROFILE="lab"                    # dev | lab | prod
export BEAGLE_SAFE_MODE="true"                 # Always true for safety
export BEAGLE_DATA_DIR="$HOME/beagle-data"     # Where all data lives

# LLM providers
export XAI_API_KEY="xai-..."                   # Required

# Optional providers
export ANTHROPIC_API_KEY="sk-ant-..."          # Claude Direct
export GITHUB_TOKEN="ghp_..."                  # Copilot

# Heavy limits (for lab profile)
export BEAGLE_HEAVY_ENABLE="true"
export BEAGLE_HEAVY_MAX_CALLS_PER_RUN="5"
export BEAGLE_HEAVY_MAX_TOKENS_PER_RUN="100000"

# Server configuration
export BEAGLE_CORE_ADDR="0.0.0.0:8080"
export BEAGLE_API_TOKEN="your-secure-token"    # For HTTP API auth
```

Load environment:

```bash
source ~/.beagle_env
```

### 3. Bootstrap Data Directory

```bash
# Create directory structure
mkdir -p $BEAGLE_DATA_DIR/{papers/{drafts,final},logs/{beagle-pipeline,observer},triad,feedback,embeddings,datasets,experiments,jobs,models}

# Verify structure
tree -L 2 $BEAGLE_DATA_DIR
```

Expected output:
```
/home/user/beagle-data
├── datasets
├── embeddings
├── experiments
├── feedback
├── jobs
├── logs
│   ├── beagle-pipeline
│   └── observer
├── models
├── papers
│   ├── drafts
│   └── final
└── triad
```

---

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    BEAGLE v0.1 Workflow                     │
└─────────────────────────────────────────────────────────────┘

Step 1: START CORE SERVER
   │
   │   cargo run --bin beagle-monorepo --release
   │
   └──▶ Server running on http://localhost:8080
        Health check: curl http://localhost:8080/health

Step 2: RUN PIPELINE
   │
   │   cargo run --bin pipeline -- "Research question"
   │
   ├──▶ Darwin: GraphRAG context retrieval
   ├──▶ Observer: HRV + physiological state
   ├──▶ Serendipity: Cross-domain connections (optional)
   ├──▶ HERMES: Draft synthesis
   ├──▶ Void: Deadlock detection (optional)
   └──▶ Artifacts: draft.md, draft.pdf, run_report.json

Step 3: RUN TRIAD (Adversarial Review)
   │
   │   cargo run --bin triad_review -- --run-id <ID> --draft <PATH>
   │
   ├──▶ ATHENA: Literature review
   ├──▶ HERMES: Rewrite for clarity
   ├──▶ ARGOS: Critical review (uses Heavy)
   ├──▶ Judge: Final arbitration
   └──▶ Output: final_draft.md, triad_report.json

Step 4: HUMAN REVIEW & FEEDBACK
   │
   │   Read final_draft.md
   │   Decide: Accept or Reject?
   │   Rate: 0-10
   │
   └──▶ cargo run --bin tag_run -- <ID> <0|1> <rating> "notes"

Step 5: ANALYZE & EXPORT
   │
   ├──▶ cargo run --bin list_runs
   ├──▶ cargo run --bin analyze_feedback
   └──▶ cargo run --bin export_lora_dataset
        (After collecting 50-100 high-quality runs)

Step 6: TRAIN LORA (External)
   │
   └──▶ Use lora_dataset.jsonl with Axolotl, LLaMA-Factory, etc.
```

---

## Step-by-Step Guide

### Step 1: Start the Core Server

**Terminal 1** (leave running):

```bash
source ~/.beagle_env
cd beagle-remote
cargo run --bin beagle-monorepo --release
```

Expected output:
```
🚀 BEAGLE Core v0.1 starting...
   Profile: lab
   Safe Mode: true
   Heavy: enabled (max 5 calls/run)
   Data Dir: /home/user/beagle-data

✅ Router initialized | profile=lab | heavy_enabled=true
✅ Server listening on 0.0.0.0:8080

Endpoints:
  - GET  /health
  - POST /api/llm/complete
  - POST /api/pipeline/start
  - GET  /api/pipeline/status/:run_id
  ...
```

**Verify health:**

```bash
curl http://localhost:8080/health | jq
```

Expected:
```json
{
  "status": "ok",
  "service": "beagle-core",
  "profile": "lab",
  "safe_mode": true,
  "data_dir": "/home/user/beagle-data",
  "xai_api_key_present": true
}
```

---

### Step 2: Run the Pipeline

**Terminal 2:**

```bash
source ~/.beagle_env
cd beagle-remote

# Run pipeline with your research question
cargo run --bin pipeline --package beagle-monorepo -- \
  "PBPK modeling of entropic scaffolds for targeted drug delivery in neuropsychiatric disorders"
```

**What happens:**

1. **Darwin Phase** (~10-30s): Retrieves relevant context from knowledge graph
   ```
   📊 Fase 1: Darwin GraphRAG + Self-RAG
   Contexto Darwin gerado | chunks=5432 | snippets=15
   ```

2. **Observer Phase** (~1-5s): Captures your physiological state
   ```
   🏥 Fase 2: Observer (contexto completo - Observer 2.0)
   Contexto do usuário capturado | physio=HRV normal (70ms), HR 68bpm, SpO₂ 98%
   ```

3. **Serendipity Phase** (optional, ~5-15s): Discovers cross-domain connections
   ```
   🔮 Fase 1.5: Serendipity (descoberta de conexões)
   ✅ Serendipity: 3 acidentes férteis injetados (score: 0.60)
   ```

4. **HERMES Synthesis** (~30-60s): Generates draft paper
   ```
   📝 Fase 3: HERMES (síntese)
   Draft gerado | len=12453
   ```

5. **Artifact Writing** (~1-5s): Saves files
   ```
   💾 Fase 4: Escrita de artefatos
   ✅ Draft MD salvo: /home/user/beagle-data/papers/drafts/20250115_550e8400.md
   ✅ Draft PDF salvo: /home/user/beagle-data/papers/drafts/20250115_550e8400.pdf
   ✅ Run report salvo: /home/user/beagle-data/logs/beagle-pipeline/20250115_550e8400.json
   📊 Feedback event logado para Continuous Learning
   ```

**Save the Run ID** from output:
```
Run ID: 550e8400-e29b-41d4-a716-446655440000
```

**Total time:** ~60-120 seconds (depending on context size)

---

### Step 3: Review the Draft

```bash
# View draft in terminal
cat ~/beagle-data/papers/drafts/20250115_550e8400.md | less

# Or open in editor
code ~/beagle-data/papers/drafts/20250115_550e8400.md
```

**Look for:**
- Title and Abstract
- Introduction with proper context
- Methodology (should reference PBPK, KEC, etc.)
- Results (may be placeholder if purely theoretical)
- Discussion with interdisciplinary connections
- Conclusions
- References

**Check LLM usage:**

```bash
cat ~/beagle-data/logs/beagle-pipeline/20250115_550e8400.json | jq '.llm_stats'
```

Example output:
```json
{
  "grok3_calls": 4,
  "grok3_tokens_in": 8234,
  "grok3_tokens_out": 12453,
  "grok4_calls": 0,
  "grok4_tokens_in": 0,
  "grok4_tokens_out": 0,
  "total_calls": 4,
  "total_tokens": 20687
}
```

---

### Step 4: Run Triad Review

```bash
RUN_ID="550e8400-e29b-41d4-a716-446655440000"  # Your actual run_id

cargo run --bin triad_review --package beagle-triad -- \
  --run-id $RUN_ID \
  --draft ~/beagle-data/papers/drafts/20250115_${RUN_ID}.md
```

**What happens:**

1. **ATHENA** (~30-45s): Literature review
   ```
   🔬 Executando ATHENA...
   ✅ ATHENA concluído - Score: 0.82 | Provider: grok-3
   ```

2. **HERMES** (~45-60s): Rewrite for clarity
   ```
   ✍️  Executando HERMES...
   ✅ HERMES concluído - Score: 0.87 | Provider: grok-3
   ```

3. **ARGOS** (~60-90s): Critical adversarial review
   ```
   ⚔️  Executando ARGOS...
   ✅ ARGOS concluído - Score: 0.91 | Provider: grok-4-heavy
   ```
   *Note: ARGOS typically uses Heavy due to high_bias_risk + critical_section flags*

4. **Judge** (~30-45s): Final arbitration
   ```
   ⚖️  Executando Juiz Final...
   ✅ Juiz Final concluído - Draft final: 14823 chars | Provider: grok-3
   ```

**Output:**
```
Triad review complete!

Artifacts saved:
  - /home/user/beagle-data/triad/550e8400/triad_report.json
  - /home/user/beagle-data/triad/550e8400/final_draft.md
  - /home/user/beagle-data/triad/550e8400/athena_opinion.md
  - /home/user/beagle-data/triad/550e8400/hermes_opinion.md
  - /home/user/beagle-data/triad/550e8400/argos_opinion.md

LLM Stats:
  Grok 3:      7 calls, 34251 tokens
  Grok 4 Heavy: 1 call,  8943 tokens
```

**Total time:** ~3-5 minutes

---

### Step 5: Review Triad Output

```bash
# Read final draft
cat ~/beagle-data/triad/${RUN_ID}/final_draft.md | less

# Compare with original
diff ~/beagle-data/papers/drafts/20250115_${RUN_ID}.md \
     ~/beagle-data/triad/${RUN_ID}/final_draft.md | less

# Read ARGOS critique (most important)
cat ~/beagle-data/triad/${RUN_ID}/argos_opinion.md
```

**ARGOS typically identifies:**
- Claims without empirical support
- Confusion between metaphor and mechanism
- Missing testable predictions
- Logical inconsistencies
- Overgeneralization

---

### Step 6: Tag with Human Feedback

Based on your review, tag the run:

**High Quality (Accept):**
```bash
cargo run --bin tag_run --package beagle-feedback -- \
  $RUN_ID \
  1 \
  9 \
  "Excellent interdisciplinary synthesis. Methods section strong. Minor Discussion edits needed."
```

**Medium Quality (Accept with reservations):**
```bash
cargo run --bin tag_run --package beagle-feedback -- \
  $RUN_ID \
  1 \
  7 \
  "Good structure but Methods need more PBPK detail. Results section is placeholder."
```

**Low Quality (Reject):**
```bash
cargo run --bin tag_run --package beagle-feedback -- \
  $RUN_ID \
  0 \
  4 \
  "Too vague. Missing key references. Methods inadequate."
```

**Parameters:**
- `run_id`: UUID from pipeline output
- `accepted`: `1` (yes) or `0` (no)
- `rating`: `0-10` (see rating scale below)
- `notes`: Free text (quote if contains spaces)

**Rating Scale:**
- **9-10:** Publication-ready or very close
- **7-8:** Good quality, minor revisions needed
- **5-6:** Acceptable, moderate revisions
- **3-4:** Poor quality, major issues
- **0-2:** Unusable

---

### Step 7: List and Analyze Runs

**List all runs:**

```bash
cargo run --bin list_runs --package beagle-feedback
```

Output:
```
=== BEAGLE Pipeline Runs ===

RUN_ID                                 DATE                 QUESTION                                             PIPE    TRIAD   FEEDBK  RATING  ACCEPTED
================================================================================================================================
550e8400-e29b-41d4-a716-446655440000   2025-01-15 14:32    PBPK modeling of entropic scaffolds...                Y       Y       Y       9/10    ✓
3f8d9e2a-1b5c-4a8f-9c3d-7e6f5a4b3c2d   2025-01-15 10:15    Neuroplasticity and computational psych...            Y       Y       Y       7/10    ✓
7a2b4c8d-3e5f-4a1c-9d8e-6f7a5b4c3d2e   2025-01-14 16:45    Fractal holographic storage in hippocampus...         Y       -       Y       4/10    ✗
...

23 total runs found

=== SUMMARY ===
Pipeline runs:     23
Triad reviews:     18
Human feedback:    20
  Accepted:        15
  Rejected:        5
  Avg rating:      6.8/10
```

**Analyze feedback:**

```bash
cargo run --bin analyze_feedback --package beagle-feedback
```

Output:
```
=== Feedback Analysis ===

Total events: 61
  - PipelineRun:    23
  - TriadCompleted: 18
  - HumanFeedback:  20

Human Feedback Summary:
  Accepted:   15 (75%)
  Rejected:   5 (25%)
  
  Ratings:
    p50 (median): 7/10
    p90:          9/10
    mean:         6.8/10

Heavy Usage:
  Runs using Heavy:  12 (52%)
  Avg Heavy calls:   1.8 per run
  Max Heavy calls:   4 (run: 3f8d9e2a...)

Top Questions (by rating):
  1. [9/10] PBPK modeling of entropic scaffolds...
  2. [9/10] Computational psychiatry and KEC integration...
  3. [8/10] Biomaterial synthesis for neural tissue...
```

---

### Step 8: Export LoRA Dataset

**When to export:**
- After collecting **50-100+ runs**
- At least **30-50 accepted runs** with rating ≥ 8

```bash
cargo run --bin export_lora_dataset --package beagle-feedback
```

Output:
```
=== LoRA Dataset Export ===

Loading feedback events...
Found 23 total runs

Filtering criteria:
  - Must have PipelineRun + TriadCompleted + HumanFeedback
  - accepted = true
  - rating >= 8

Qualified runs: 12

Exporting to lora_dataset.jsonl...

Example entries:
  1. run_id: 550e8400... | rating: 9/10
     input: [question + original draft]
     output: [triad final draft]
  
  2. run_id: 3f8d9e2a... | rating: 9/10
     ...

✅ Exported 12 training examples to:
   /home/user/beagle-data/datasets/lora_dataset.jsonl

Next steps:
  1. Review lora_dataset.jsonl
  2. Train LoRA adapter using Axolotl or LLaMA-Factory
  3. Fine-tune on scientific writing style
```

---

## Environment Variables Reference

### Minimal Configuration

```bash
# Required
export XAI_API_KEY="xai-..."
export BEAGLE_DATA_DIR="$HOME/beagle-data"

# Recommended
export BEAGLE_PROFILE="lab"
export BEAGLE_SAFE_MODE="true"
```

### Complete Configuration

```bash
# ============================================================================
# CORE
# ============================================================================
export BEAGLE_PROFILE="lab"                    # dev | lab | prod
export BEAGLE_SAFE_MODE="true"                 # true | false
export BEAGLE_DATA_DIR="$HOME/beagle-data"     # Data directory path

# ============================================================================
# LLM PROVIDERS
# ============================================================================
export XAI_API_KEY="xai-..."                   # Grok (required)
export ANTHROPIC_API_KEY="sk-ant-..."          # Claude Direct (optional)
export GITHUB_TOKEN="ghp_..."                  # GitHub Copilot (optional)
export CURSOR_API_KEY="cursor_..."             # Cursor AI (optional)
export DEEPSEEK_API_KEY="sk-..."               # DeepSeek Math (optional)

# ============================================================================
# HEAVY LIMITS (Grok 4)
# ============================================================================
export BEAGLE_HEAVY_ENABLE="true"              # Enable Heavy tier
export BEAGLE_HEAVY_MAX_CALLS_PER_RUN="5"     # Max calls per pipeline run
export BEAGLE_HEAVY_MAX_TOKENS_PER_RUN="100000" # Max tokens per run
export BEAGLE_HEAVY_MAX_CALLS_PER_DAY="200"   # Daily limit (future)

# ============================================================================
# SERVER
# ============================================================================
export BEAGLE_CORE_ADDR="0.0.0.0:8080"        # HTTP server address
export BEAGLE_API_TOKEN="your-secure-token"    # Bearer token for API

# ============================================================================
# ADVANCED MODULES
# ============================================================================
export BEAGLE_SERENDIPITY_ENABLE="false"       # Cross-domain discovery
export BEAGLE_VOID_ENABLE="false"              # Deadlock detection
export BEAGLE_MEMORY_RETRIEVAL_ENABLE="false"  # Memory RAG injection

# ============================================================================
# OBSERVER THRESHOLDS
# ============================================================================
export BEAGLE_HRV_LOW_MS="30.0"                # Low HRV threshold
export BEAGLE_HRV_HIGH_MS="80.0"               # High HRV (flow state)
export BEAGLE_HR_TACHY_BPM="110.0"             # Tachycardia threshold
export BEAGLE_SPO2_WARNING="94.0"              # SpO2 warning level

# ============================================================================
# DEBUGGING
# ============================================================================
export RUST_LOG="info"                          # Logging level
# export RUST_LOG="debug"                       # Verbose debugging
# export RUST_LOG="beagle_llm=debug,beagle_monorepo=info"  # Selective
```

---

## Common Scenarios

### Scenario 1: Quick Draft (No Triad)

```bash
# Just need a quick draft, skip review
cargo run --bin pipeline --package beagle-monorepo -- "Question"

# Review manually
cat ~/beagle-data/papers/drafts/*.md

# Tag if satisfied
cargo run --bin tag_run --package beagle-feedback -- $RUN_ID 1 7 "Quick draft, acceptable"
```

### Scenario 2: High-Stakes Paper (Full Workflow)

```bash
# 1. Generate draft
cargo run --bin pipeline --package beagle-monorepo -- \
  "Novel PBPK model for antipsychotic drug kinetics in treatment-resistant schizophrenia"

# 2. Run Triad review
cargo run --bin triad_review --package beagle-triad -- \
  --run-id $RUN_ID \
  --draft ~/beagle-data/papers/drafts/20250115_${RUN_ID}.md

# 3. Manual review + edits in external editor
code ~/beagle-data/triad/${RUN_ID}/final_draft.md

# 4. Tag after careful review
cargo run --bin tag_run --package beagle-feedback -- $RUN_ID 1 9 "Publication-ready"
```

### Scenario 3: Batch Processing

```bash
# Process multiple questions
QUESTIONS=(
  "Entropy and neuroplasticity"
  "PBPK for novel antidepressants"
  "Biomaterial scaffolds in neural repair"
  "Computational models of consciousness"
)

for Q in "${QUESTIONS[@]}"; do
  echo "Processing: $Q"
  cargo run --bin pipeline --package beagle-monorepo -- "$Q"
  sleep 5  # Rate limiting
done

# Review all at once
cargo run --bin list_runs --package beagle-feedback
```

### Scenario 4: A/B Testing HRV Awareness

```bash
# Run with HRV-aware mode (default)
cargo run --bin pipeline --package beagle-monorepo -- "Question"

# Run with HRV-blind mode (experimental control)
# (Future: via CLI flag --hrv-aware=false)
# Currently: set via API
curl -X POST http://localhost:8080/api/pipeline/start \
  -H "Authorization: Bearer $BEAGLE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "question": "Question",
    "hrv_aware": false,
    "experiment_id": "hrv_ablation_001"
  }'
```

---

## Troubleshooting

### Problem: Pipeline fails with "XAI_API_KEY not set"

**Solution:**
```bash
export XAI_API_KEY="xai-your-key"
echo $XAI_API_KEY  # Verify it's set
```

### Problem: "Heavy always falls back to Grok 3"

**Check:**
```bash
# 1. Profile should be lab or prod
echo $BEAGLE_PROFILE  # Should NOT be "dev"

# 2. Heavy should be enabled
echo $BEAGLE_HEAVY_ENABLE  # Should be "true"

# 3. Check if limits exceeded
cat ~/beagle-data/logs/beagle-pipeline/*_${RUN_ID}.json | jq '.llm_stats'
```

### Problem: "Server won't start - address already in use"

**Solution:**
```bash
# Find process using port 8080
lsof -i :8080

# Kill it
kill -9 <PID>

# Or use different port
export BEAGLE_CORE_ADDR="0.0.0.0:8081"
```

### Problem: "Permission denied" when writing to data dir

**Solution:**
```bash
# Check ownership
ls -la ~/beagle-data

# Fix permissions
chmod -R u+rwX ~/beagle-data
```

### Problem: Triad crashes with "draft not found"

**Solution:**
```bash
# Verify draft exists
ls -la ~/beagle-data/papers/drafts/

# Use full absolute path
cargo run --bin triad_review --package beagle-triad -- \
  --run-id $RUN_ID \
  --draft $HOME/beagle-data/papers/drafts/20250115_${RUN_ID}.md
```

### Problem: Feedback not logged

**Check:**
```bash
# 1. Directory exists and writable
ls -la ~/beagle-data/feedback/

# 2. File is being appended
tail ~/beagle-data/feedback/feedback_events.jsonl

# 3. Check for errors in pipeline logs
grep -i error ~/beagle-data/logs/beagle-pipeline/*.json
```

### Problem: "No runs found" in list_runs

**Cause:** Feedback events not logged yet.

**Solution:**
```bash
# Run a pipeline first
cargo run --bin pipeline --package beagle-monorepo -- "Test question"

# Verify feedback file exists
cat ~/beagle-data/feedback/feedback_events.jsonl | jq
```

---

## Performance Tips

### Speed Up Iterations

```bash
# Use mock LLM for testing
export BEAGLE_LLM_MOCK="true"
cargo run --bin pipeline --package beagle-monorepo -- "Test"
```

### Reduce Heavy Usage (Save Costs)

```bash
# Lower limits
export BEAGLE_HEAVY_MAX_CALLS_PER_RUN="2"
export BEAGLE_HEAVY_MAX_TOKENS_PER_RUN="50000"
```

### Parallel Processing (Advanced)

```bash
# Stress test with mocks
export BEAGLE_STRESS_RUNS="10"
export BEAGLE_STRESS_CONCURRENCY="3"
export BEAGLE_LLM_MOCK="true"
cargo run --bin stress_pipeline --package beagle-stress-test
```

---

## Next Steps

1. **Run your first pipeline** following Step 2
2. **Review with Triad** (Step 4)
3. **Tag 10+ runs** to build feedback dataset
4. **Export dataset** after 50+ runs
5. **Train LoRA** using external tools

**Questions?** See `docs/BEAGLE_v0_1_CORE.md` for full architecture reference.

**Happy researching! 🐕🔬**