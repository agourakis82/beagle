# Beagle Expedition 001 – Triad vs Single LLM

## Overview

**Expedition ID**: `beagle_exp_001_triad_vs_single`

**Goal**: Compare the quality of drafts produced with **Triad ON** (ATHENA–HERMES–ARGOS + judge) vs **Triad OFF** (single LLM) under real, noisy conditions (HRV, environmental factors, space weather) as BEAGLE is used in real life.

---

## Hypotheses

### Hypothesis H1

**H1**: Triad ON (ATHENA–HERMES–ARGOS + judge) produces drafts that receive **higher human ratings** and **higher accepted ratio** than Triad OFF (single LLM), for the same class of scientific prompts, under typical working conditions.

### Null Hypothesis H0

**H0**: There is **no difference** in mean rating or accepted ratio between Triad ON vs Single LLM condition.

---

## Experimental Design

### LLM & Router Config (Expedition 001 v1)

**Configuration Lock**: For Expedition 001 v1, the LLM/Router configuration is **frozen** to ensure consistency and reproducibility:

- **Primary Provider**: Grok 3 (default, via `BeagleConfig.llm.grok_model`)
- **Heavy Provider**: Grok 4 Heavy used **only** as final judge in Triad (if `enable_heavy=true`)
- **DeepSeek**: **DISABLED** for Expedition 001 (`DEEPSEEK_API_KEY` may be present, but `BEAGLE_DEEPSEEK_ENABLE=false` or unset)
- **Router Policy**:
  - `requires_math`: **not activated by default** (Expedition 001 focuses on general scientific writing, not formal proofs)
  - `requires_high_quality=true` for HERMES/Triad
- **Serendipity**: **DISABLED** for Expedition 001 v1 (`BEAGLE_SERENDIPITY=false`, `BEAGLE_SERENDIPITY_TRIAD=false`)

**Validation**: The `run_beagle_expedition_001` driver automatically validates this configuration at startup using `assert_expedition_001_llm_config()`. If any configuration diverges from the protocol, the experiment aborts with a clear error message.

**Rationale**: By freezing the LLM/Router configuration, we isolate the effect of Triad vs Single LLM condition without confounding variables from provider changes, Serendipity perturbations, or other routing modifications during the experiment.

### Conditions

Two conditions are compared in this expedition:

#### Condition `triad`

- `triad_enabled = true` (ATHENA–HERMES–ARGOS ensemble with final judge)
- `hrv_aware = true` (Observer 2.0 physiological context included)
- `serendipity_enabled = false` (kept constant for Expedition 001)
- `space_aware = false` (not used in v1)

#### Condition `single`

- `triad_enabled = false` (single LLM, default Grok 3 tier)
- `hrv_aware = true` (same as triad condition)
- `serendipity_enabled = false` (same as triad condition)
- `space_aware = false` (same as triad condition)

**Rationale**: HRV-awareness, Serendipity, and Space awareness are kept constant across conditions to isolate the effect of Triad vs Single LLM. Future expeditions (002, 003) will vary these factors.

### Question Template

Default question template for Expedition 001:

> "Entropy curvature as substrate for cellular consciousness: design a short abstract focusing on PBPK and fractal information."

In practice, the Principal Investigator (PI) may provide custom questions via `--question-template` flag. The default template ensures consistency across test runs and initial data collection.

### Sample Size

- **Initial**: N = 20 (10 triad + 10 single)
- **Target accumulation**: N ≈ 1000 over time (until March 2026)

---

## Metrics

### Per Run

For each run, the following metrics are captured:

1. **Human Evaluation**:
   - `rating_0_10`: Human rating (0-10 scale) via `tag_run`
   - `accepted`: Boolean acceptance (true/false)

2. **Observer 2.0 Metrics**:
   - `physio_severity`: Physiological severity (Normal/Mild/Moderate/Severe)
   - `env_severity`: Environmental severity (Normal/Mild/Moderate/Severe)
   - `space_severity`: Space weather severity (Normal/Mild/Moderate/Severe)
   - `stress_index`: Aggregated stress index (if available)
   - `hrv_level`: HRV level (low/normal/high, if available)

3. **LLM Usage**:
   - `grok3_calls`: Number of Grok 3 API calls
   - `grok4_calls`: Number of Grok 4 Heavy API calls
   - `total_tokens`: Total tokens consumed
   - `llm_provider_main`: Primary LLM provider used

### Per Condition (Aggregated)

For each condition (`triad` vs `single`), the following aggregated metrics are computed:

1. **Ratings**:
   - Mean and standard deviation of `rating_0_10`
   - Percentiles: p50 (median), p90

2. **Acceptance**:
   - `accepted_ratio`: accepted runs / total runs with feedback

3. **Severity Distribution**:
   - Counts per Severity level (Normal/Mild/Moderate/Severe) for:
     - `physio_severity`
     - `env_severity`
     - `space_severity`

4. **Other Metrics**:
   - `stress_index_mean`: Mean stress index
   - `avg_tokens`: Average tokens per run
   - `avg_grok3_calls`, `avg_grok4_calls`: Average API calls

### Effect Size

For Expedition 001, we compute a simple effect size metric:

- **Δ rating mean**: `mean(triad) - mean(single)`
- **Δ accepted ratio**: `ratio(triad) - ratio(single)`

**Note**: Full statistical tests (two-sample t-test, Mann–Whitney U test, confidence intervals, Cohen's d) will be performed in Julia/Python notebooks using the exported CSV/JSON data.

---

## Procedure

### Step 1: Run Expedition 001

Execute the specialized Expedition 001 driver:

```bash
cargo run --bin run_beagle_expedition_001 --package beagle-experiments -- \
  [--experiment-id beagle_exp_001_triad_vs_single] \
  [--n-total 10] \
  [--seed <optional-seed>] \
  [--batch-label "dia1_manha"] \
  [--question-template "Your custom question here"] \
  [--beagle-core-url http://localhost:8080] \
  [--interval-secs 5]
```

**Parameters**:
- `--experiment-id`: Experiment ID (default: `beagle_exp_001_triad_vs_single`)
- `--n-total`: Number of runs to add in **this batch** (not cumulative total; default: 20)
- `--seed`: Optional RNG seed for reproducible condition ordering/variation
- `--batch-label`: Optional textual label for this batch (e.g., "dia1_manha", "dia1_tarde") — stored in experiment tag `notes`
- `--question-template`: Question template (default: Expedition 001 template)
- `--beagle-core-url`: BEAGLE core server URL (default: `http://localhost:8080`)
- `--interval-secs`: Interval between runs in seconds (default: 5)

**Configuration Validation**: The driver automatically validates LLM/Router configuration at startup using `assert_expedition_001_llm_config()`. If configuration diverges from the protocol (e.g., DeepSeek enabled, Serendipity enabled), the experiment aborts with a clear error message.

**Batch Execution**: Multiple runs of `run_beagle_expedition_001` with the same `experiment_id` will **accumulate** runs in `experiments/events.jsonl` without overwriting existing tags. This allows incremental data collection over days/weeks.

**Requirements**:
- BEAGLE core server must be running (`cargo run --bin core_server --package beagle-monorepo`)
- `BEAGLE_DATA_DIR` environment variable set (or uses default `~/beagle-data`)
- Valid LLM API keys configured (Grok 3, optionally Grok 4 Heavy)

**Output**:
- Pipeline runs are executed sequentially (with configurable interval)
- Each run produces:
  - `draft.md`, `draft.pdf` in `papers/drafts/<run_id>/`
  - `run_report.json` in `logs/beagle-pipeline/`
  - Experiment tags in `experiments/events.jsonl`

### Step 2: Review and Tag Drafts

After runs complete, manually review each draft and tag it.

**Option A: Using `exp001-tag` (recommended for Expedition 001)**:

```bash
# Tag a run as accepted with rating 8
cargo run --bin exp001-tag --package beagle-experiments -- \
  --run-id <run_id> \
  --accepted true \
  --rating 8 \
  --notes "Excellent draft, clear structure"

# Tag a run as rejected with rating 5
cargo run --bin exp001-tag --package beagle-experiments -- \
  --run-id <run_id> \
  --accepted false \
  --rating 5 \
  --notes "Needs improvement in methodology section"
```

**Option B: Using `tag-run` (generic BEAGLE feedback CLI)**:

```bash
# Tag a run as accepted with rating 8
cargo run --bin tag-run --package beagle-feedback -- <run_id> 1 8 "Excellent draft, clear structure"

# Tag a run as rejected with rating 5
cargo run --bin tag-run --package beagle-feedback -- <run_id> 0 5 "Needs improvement in methodology section"
```

**Rationale**: `exp001-tag` is a convenience wrapper that validates the rating (0-10) and integrates with the Expedition 001 workflow. Both methods record the same feedback events.

**Rationale**: Human evaluation is critical for this experiment. The PI (Demetrios) reviews each draft and provides:
- Binary acceptance (`accepted`: 0 or 1)
- Rating (0-10 scale)
- Optional notes for later qualitative analysis

**Timing**: This step can be done incrementally over days/weeks as drafts are generated.

### Step 3: Analyze Results

Run the analysis tool.

**Option A: Using `exp001-analyze` (recommended for Expedition 001)**:

```bash
# Terminal output (always printed)
cargo run --bin exp001-analyze --package beagle-experiments -- \
  [--experiment-id beagle_exp_001_triad_vs_single] \
  [--output-format csv|json|md] \
  [--output-prefix exp001_20251122]
```

**Option B: Using `analyze_experiments` (generic BEAGLE experiments CLI)**:

```bash
# Terminal output (default)
cargo run --bin analyze_experiments --package beagle-experiments -- beagle_exp_001_triad_vs_single

# Export to CSV for statistical analysis
cargo run --bin analyze_experiments --package beagle-experiments -- beagle_exp_001_triad_vs_single --output-format csv

# Export to JSON for programmatic analysis
cargo run --bin analyze_experiments --package beagle-experiments -- beagle_exp_001_triad_vs_single --output-format json
```

**Output Formats**:
- **Terminal**: Always printed, shows summary with metrics per condition and effect sizes
- **CSV**: `experiments/exp001_<timestamp>_summary.csv` for statistical analysis in Julia/Python
- **JSON**: `experiments/exp001_<timestamp>_summary.json` for programmatic analysis
- **Markdown**: `experiments/exp001_<timestamp>_report.md` with full report including frozen configuration snapshot

**Output**:
- Summary printed to terminal with:
  - Metrics per condition (ratings, acceptance, severities)
  - Effect size (Δ rating mean, Δ accepted ratio)
  - Observer severity distributions
- CSV/JSON files saved to `BEAGLE_DATA_DIR/experiments/beagle_exp_001_triad_vs_single_summary.{csv|json}`

### Step 4: Statistical Analysis (External)

Load exported CSV/JSON in Julia/Python for deeper statistical analysis:

**Julia Example** (pseudocode):
```julia
using CSV, DataFrames, Statistics, HypothesisTests

df = CSV.read("beagle_exp_001_triad_vs_single_summary.csv", DataFrame)

# Two-sample t-test on ratings
triad_ratings = df[df.condition .== "triad", :rating_0_10]
single_ratings = df[df.condition .== "single", :rating_0_10]

p_value = pvalue(EqualVarianceTTest(triad_ratings, single_ratings))
effect_size_cohen = effectsize(EqualVarianceTTest(triad_ratings, single_ratings))

# Proportion test for acceptance
triad_accepted = sum(df[df.condition .== "triad", :accepted] .== "true")
triad_total = nrow(df[df.condition .== "triad"])
single_accepted = sum(df[df.condition .== "single", :accepted] .== "true")
single_total = nrow(df[df.condition .== "single"])

p_value_prop = pvalue(ProportionTest([triad_accepted, single_accepted], [triad_total, single_total]))
```

**Python Example** (pseudocode):
```python
import pandas as pd
from scipy import stats

df = pd.read_csv("beagle_exp_001_triad_vs_single_summary.csv")

triad_ratings = df[df.condition == "triad"]["rating_0_10"]
single_ratings = df[df.condition == "single"]["rating_0_10"]

# Two-sample t-test
t_stat, p_value = stats.ttest_ind(triad_ratings, single_ratings)

# Mann-Whitney U (non-parametric)
u_stat, p_value_mw = stats.mannwhitneyu(triad_ratings, single_ratings, alternative='two-sided')

# Effect size (Cohen's d)
cohens_d = (triad_ratings.mean() - single_ratings.mean()) / pooled_std(triad_ratings, single_ratings)
```

---

## Data Structure

### `experiments/events.jsonl`

Each line contains a JSON object with an experiment tag:

```json
{
  "tag": {
    "experiment_id": "beagle_exp_001_triad_vs_single",
    "run_id": "abc123...",
    "condition": "triad",
    "timestamp": "2026-01-15T10:30:00Z",
    "notes": null,
    "triad_enabled": true,
    "hrv_aware": true,
    "serendipity_enabled": false,
    "space_aware": false
  }
}
```

**Format**: JSONL (one JSON object per line)

**Location**: `BEAGLE_DATA_DIR/experiments/events.jsonl`

### `feedback_events.jsonl`

Standard BEAGLE feedback events (see `docs/BEAGLE_EXPERIMENTS_v1.md` for structure).

### `run_report.json`

Standard BEAGLE run reports with Observer 2.0 metrics embedded:

```json
{
  "run_id": "abc123...",
  "question": "...",
  "observer": {
    "physio_severity": "Normal",
    "env_severity": "Normal",
    "space_severity": "Normal",
    "stress_index": 0.5,
    "hrv_level": "normal",
    "heart_rate_bpm": 72.0,
    "spo2_percent": 98.0
  },
  "llm_stats": {
    "grok3_calls": 5,
    "grok4_calls": 0,
    "total_tokens": 1200
  }
}
```

---

## Interpretation

### Expected Outcomes (if H1 is true)

- **Triad condition**: Mean rating > 7.0, accepted ratio > 70%
- **Single condition**: Mean rating < 7.0, accepted ratio < 60%
- **Effect size (Δ)**: Positive difference in favor of Triad

### Potential Confounders

1. **Observer 2.0 Variability**: Physiological/environmental state may vary between runs, potentially affecting draft quality independently of Triad/Single condition.
   - **Mitigation**: Severity distributions are logged and can be controlled for in statistical analysis (ANCOVA, stratification).

2. **Question Variability**: Different questions may have different baseline difficulty.
   - **Mitigation**: Use consistent question template, or stratify by question type in analysis.

3. **LLM Stochasticity**: Even with same prompt, LLM outputs vary.
   - **Mitigation**: Multiple runs (N=20 initially, accumulating to N≈1000) provide statistical power.

4. **Human Rater Bias**: PI's expectations may bias ratings.
   - **Mitigation**: Double-blind evaluation (future work), or include inter-rater reliability metrics.

### Statistical Power

- **Initial N=20**: Limited power for small effects; suitable for detecting large effects (Cohen's d > 0.8)
- **Target N≈1000**: Enables detection of smaller effects (Cohen's d > 0.2) with 80% power at α=0.05

---

## Limitations

1. **Non-Blind Design**: The PI knows which condition produced which draft when tagging (not double-blind).
   - **Future**: Consider blind evaluation in Expedition 002/003.

2. **Single Rater**: Only one human evaluator (PI) tags drafts.
   - **Future**: Multiple raters for inter-rater reliability.

3. **Question Template**: Default template may not reflect all scientific domains.
   - **Future**: Multi-domain questions, stratified analysis.

4. **Observer 2.0 Variability**: Real physiological/environmental state varies; this is intentional (real-world conditions) but adds noise.
   - **Mitigation**: Log all Observer metrics, control for in analysis.

---

## Reproducibility

### Software Version

- BEAGLE v0.3.0 (or commit hash at time of experiment)
- `beagle-experiments` crate version 0.3.0

### Configuration Snapshot

Each `ExperimentRunTag` includes a snapshot of experimental flags:
- `triad_enabled`, `hrv_aware`, `serendipity_enabled`, `space_aware`

Additionally, the `exp001-analyze --output-format md` generates a Markdown report that includes:
- **Frozen LLM/Router Configuration**: Profile, safe_mode, grok_model, serendipity flags (for auditability)
- **Batch Labels**: If `--batch-label` was used during execution, it's stored in tag `notes`

This allows partial reproducibility (same flags, but Observer thresholds may differ across runs if config changes). The frozen LLM/Router config ensures that provider changes do not contaminate the experiment.

### Avoiding Configuration Drift

**Important**: Do **not** modify LLM/Router configuration (DeepSeek, Serendipity, etc.) during Expedition 001 data collection. The `assert_expedition_001_llm_config()` validation prevents accidental drift, but manual changes between batches should be avoided.

If configuration must change (e.g., for a new expedition), create a new `experiment_id` (e.g., `beagle_exp_001_triad_vs_single_v2`).

### Full Reproducibility

For full reproducibility, archive:
1. Complete `BEAGLE_DATA_DIR` at experiment end
2. Config files (`beagle-config` state)
3. Commit hashes of all BEAGLE crates
4. LLM API versions/behavior (note: LLM providers may change models without notice)

---

## Next Steps

After Expedition 001 data collection:

1. **Accumulate Data**: Continue running `run_beagle_expedition_001` periodically, tagging drafts as they are generated.

2. **Statistical Analysis**: Once N≥30 per condition, perform initial t-tests/Mann-Whitney U tests. Re-evaluate at N=100, N=500, N=1000.

3. **Write Paper**: Methods section can copy this document almost verbatim. Results section will include:
   - Descriptive statistics (means, std, distributions)
   - Effect sizes (Cohen's d, Δ)
   - Statistical tests (t-test, Mann-Whitney U, proportion tests)
   - Confidence intervals
   - Optional: HRV interaction analysis (if sufficient N)

4. **Plan Expedition 002**: Vary HRV-awareness (HRV-aware vs HRV-blind) while keeping Triad constant.

5. **Plan Expedition 003**: Vary Serendipity (on vs off) while keeping Triad and HRV constant.

---

## References

- **BEAGLE Experiments v1.0**: See `docs/BEAGLE_EXPERIMENTS_v1.md`
- **BEAGLE Observer 2.0**: See `docs/BEAGLE_OBSERVER_v2_0.md`
- **HELM**: Evaluation framework for LLMs – [CRFM HELM](https://crfm-helm.readthedocs.io/)
- **AgentBench**: Evaluation framework for LLM-as-Agent scenarios
- **Statistical Methods**: Two-sample t-test, Mann-Whitney U test, Cohen's d effect size (see standard statistics textbooks)

---

## Contact

For questions about Expedition 001:
- **PI**: Dr. Demetrios Agourakis
- **Repository**: https://github.com/darwin-cluster/beagle
- **Documentation**: `docs/BEAGLE_EXPEDITION_001.md`

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-15  
**Status**: Active Experiment

