# BEAGLE v0.1 — Quick Start Guide

**Get up and running in 5 minutes** 🚀

---

## Prerequisites

- **Rust 1.70+**: Install from https://rustup.rs
- **Grok API Key**: Get from https://x.ai

---

## Step 1: Clone & Build (2 minutes)

```bash
git clone https://github.com/your-org/beagle-remote.git
cd beagle-remote

# Build (first time takes ~5-10 minutes)
cargo build --release
```

---

## Step 2: Configure (1 minute)

```bash
# Required settings
export BEAGLE_PROFILE="lab"                      # dev | lab | prod
export BEAGLE_SAFE_MODE="true"                   # Always true for safety
export BEAGLE_DATA_DIR="$HOME/beagle-data"       # Where data lives
export XAI_API_KEY="xai-your-key-here"           # Your Grok API key

# Optional: Enable Grok 4 Heavy (for critical sections)
export BEAGLE_HEAVY_ENABLE="true"
export BEAGLE_HEAVY_MAX_CALLS_PER_RUN="5"
```

**Pro tip:** Save these to `~/.beagle_env` and run `source ~/.beagle_env`

---

## Step 3: Create Data Directory (30 seconds)

```bash
mkdir -p $BEAGLE_DATA_DIR/{papers/drafts,logs/beagle-pipeline,triad,feedback}
```

---

## Step 4: Run Your First Pipeline (2 minutes)

```bash
# Start the core server (Terminal 1)
cargo run --bin beagle-monorepo --release

# In another terminal (Terminal 2)
source ~/.beagle_env
cargo run --bin pipeline --package beagle-monorepo -- \
  "PBPK modeling of novel antidepressants in treatment-resistant depression"
```

**Output:**
```
🚀 Pipeline BEAGLE v0.1 iniciado
📊 Fase 1: Darwin GraphRAG + Self-RAG
🏥 Fase 2: Observer (contexto completo)
📝 Fase 3: HERMES (síntese)
💾 Fase 4: Escrita de artefatos

✅ Draft MD salvo: ~/beagle-data/papers/drafts/20250115_550e8400.md
✅ Draft PDF salvo: ~/beagle-data/papers/drafts/20250115_550e8400.pdf
✅ Run report salvo: ~/beagle-data/logs/beagle-pipeline/20250115_550e8400.json

Run ID: 550e8400-e29b-41d4-a716-446655440000
```

---

## Step 5: Review Your Draft

```bash
# View in terminal
cat ~/beagle-data/papers/drafts/20250115_550e8400.md

# Or open in your editor
code ~/beagle-data/papers/drafts/20250115_550e8400.md
```

---

## Step 6: (Optional) Run Adversarial Review

```bash
RUN_ID="550e8400-e29b-41d4-a716-446655440000"  # Your actual run_id

cargo run --bin triad_review --package beagle-triad -- \
  --run-id $RUN_ID \
  --draft ~/beagle-data/papers/drafts/20250115_${RUN_ID}.md
```

**This will take 3-5 minutes** and produce a reviewed version at:
```
~/beagle-data/triad/$RUN_ID/final_draft.md
```

---

## Step 7: Tag with Feedback

```bash
# After reviewing, tag the run
cargo run --bin tag_run --package beagle-feedback -- \
  $RUN_ID \
  1 \
  9 \
  "Excellent quality, minor edits needed"

# Arguments: <run_id> <accepted:0|1> <rating:0-10> "<notes>"
```

---

## Step 8: View All Runs

```bash
cargo run --bin list_runs --package beagle-feedback
```

**Output:**
```
=== BEAGLE Pipeline Runs ===

RUN_ID                                 DATE                 QUESTION                          PIPE  TRIAD  FEEDBK  RATING  ACCEPTED
550e8400-e29b-41d4-a716-446655440000   2025-01-15 14:32    PBPK modeling of novel anti...    Y     Y      Y       9/10    ✓

1 total runs found
```

---

## Quick Reference

### Essential Commands

```bash
# Start server
cargo run --bin beagle-monorepo --release

# Run pipeline
cargo run --bin pipeline --package beagle-monorepo -- "Your question"

# Run Triad review
cargo run --bin triad_review --package beagle-triad -- --run-id <ID> --draft <PATH>

# Tag run
cargo run --bin tag_run --package beagle-feedback -- <ID> 1 9 "Notes"

# List all runs
cargo run --bin list_runs --package beagle-feedback

# Analyze feedback
cargo run --bin analyze_feedback --package beagle-feedback

# Export LoRA dataset (after 50+ runs)
cargo run --bin export_lora_dataset --package beagle-feedback
```

### Check System Health

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

## Environment Profiles

### Dev Profile (Default - Safe)
```bash
export BEAGLE_PROFILE="dev"
# - Grok 4 Heavy: DISABLED
# - Safe Mode: FORCED ON
# - Use for: Testing, development
```

### Lab Profile (Recommended)
```bash
export BEAGLE_PROFILE="lab"
export BEAGLE_HEAVY_ENABLE="true"
# - Grok 4 Heavy: Max 5 calls/run, 100k tokens
# - Safe Mode: Recommended ON
# - Use for: Real research with cost control
```

### Prod Profile (Advanced)
```bash
export BEAGLE_PROFILE="prod"
export BEAGLE_HEAVY_ENABLE="true"
# - Grok 4 Heavy: Max 10 calls/run, 200k tokens
# - Safe Mode: Optional
# - Use for: Publication-ready papers
```

---

## What's Happening Under the Hood?

### Pipeline Flow
```
Question → Darwin (GraphRAG) → Observer (HRV/Physio) → 
HERMES (Synthesis) → Artifacts (MD/PDF/JSON) → 
Feedback Event Logged
```

### LLM Routing Strategy
- **Grok 3 (Tier 1):** ~94% of requests (unlimited, fast, cost ≈ 0)
- **Grok 4 Heavy (Tier 2):** Critical sections only (anti-bias vaccine)
  - Triggered by: `high_bias_risk` OR `critical_section` OR `phd_level_reasoning`
  - Automatic fallback to Grok 3 when limits exceeded

### Triad Review
```
Original Draft → 
  ATHENA (Literature Review) → 
  HERMES (Rewrite) → 
  ARGOS (Critical Review, uses Heavy) → 
  Judge (Final Arbitration) → 
Final Draft
```

---

## Troubleshooting

### "XAI_API_KEY not found"
```bash
export XAI_API_KEY="xai-..."
echo $XAI_API_KEY  # Verify
```

### "Address already in use"
```bash
# Find and kill process on port 8080
lsof -i :8080
kill -9 <PID>
```

### "Permission denied" on data directory
```bash
chmod -R u+rwX ~/beagle-data
```

### Pipeline hangs or times out
```bash
# Use mock mode for testing
export BEAGLE_LLM_MOCK="true"
cargo run --bin pipeline --package beagle-monorepo -- "Test"
```

### Heavy never used (always Grok 3)
```bash
# Check profile (should NOT be "dev")
echo $BEAGLE_PROFILE

# Enable Heavy
export BEAGLE_HEAVY_ENABLE="true"

# Verify in run_report.json
cat ~/beagle-data/logs/beagle-pipeline/*.json | jq '.llm_stats'
```

---

## Next Steps

1. **Read Full Documentation**
   - `docs/COMPLETE_WORKFLOW_GUIDE.md` — Step-by-step tutorial
   - `docs/BEAGLE_v0_1_CORE.md` — Complete architecture reference
   - `COMPLETION_SUMMARY.md` — Feature status

2. **Generate Multiple Papers**
   - Run 10-20 pipelines
   - Tag each with feedback
   - Build your dataset

3. **Export LoRA Dataset**
   - After 50-100 runs with feedback
   - Use for fine-tuning custom models

4. **Optimize Your Setup**
   - Add Claude API key for Tier 0 quality
   - Configure GitHub Copilot (Tier -1)
   - Tune Heavy limits for your needs

---

## Key Features ✨

- ✅ **Cloud-first LLM**: GPUs stay free for compute (PBPK, MD, FEA)
- ✅ **Smart Routing**: 8 tiers (Claude, Copilot, Grok 3, Heavy, Local)
- ✅ **Anti-bias Vaccine**: Heavy for critical/high-risk sections
- ✅ **Observer 2.0**: Multi-modal context (physio, env, space weather)
- ✅ **Honest AI Triad**: Adversarial review (ATHENA-HERMES-ARGOS)
- ✅ **Continuous Learning**: Feedback loop → LoRA dataset
- ✅ **Production-grade**: Safe mode, profiles, rate limits

---

## Performance

- **Pipeline:** ~60-120 seconds (typical)
- **Triad Review:** ~3-5 minutes
- **Concurrent:** 50 runs in ~10 seconds (5 concurrent, with mocks)
- **Token efficiency:** ~15k-25k tokens per paper

---

## Help & Support

- **Issues:** GitHub Issues
- **Docs:** `docs/` directory
- **Status:** `COMPLETION_SUMMARY.md`
- **Architecture:** `docs/BEAGLE_v0_1_CORE.md`

---

**Happy researching! 🐕🔬**

_BEAGLE v0.1 — Freeing your GPUs for science, one paper at a time_