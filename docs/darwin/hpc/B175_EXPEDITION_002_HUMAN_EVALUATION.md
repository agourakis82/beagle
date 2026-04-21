# B17.5 — Expedition 002 Human Judgment Layer

Status: STAGED / READY FOR HUMAN EVAL

## Objective

Add a bounded, repo-native, auditable human evaluation layer to `Expedition 002`
so the canonical `hrv_aware` vs `hrv_blind` comparison stops being only
physiological/operational and becomes human-reviewable.

## Canonical Scope

This phase adds:

- a frozen human judgment protocol for `Expedition 002`
- a blinded packet generator
- a canonical rating contract
- persistent human judgment recording through `beagle-feedback`
- updated experiment analysis that aggregates human judgments by condition

This phase does not add:

- public UI
- new infra
- new topology
- clinical analytics
- a broad experiment platform redesign

## Repo-native Insertion Points

- `crates/beagle-feedback/src/lib.rs`
- `crates/beagle-experiments/src/exp002.rs`
- `crates/beagle-experiments/src/analysis.rs`
- `crates/beagle-experiments/src/bin/prepare_expedition_002_human_eval.rs`
- `crates/beagle-experiments/src/bin/apply_expedition_002_human_eval.rs`
- `crates/beagle-experiments/src/bin/analyze_experiments.rs`
- `scripts/infrastructure/darwin-hpc/run_expedition_002_human_eval.sh`
- `scripts/infrastructure/darwin-hpc/validate_expedition_002_human_eval.sh`

## Frozen Human Judgment Protocol

The canonical protocol version is:

- `b17.5-expedition-002-human-eval-v1`

Each blinded item is evaluated with:

- `accepted`
- `rating_global_0_10`
- `clarity_0_10`
- `adequacy_of_tone_0_10`
- `usefulness_0_10`
- `safety_or_emotional_fit_0_10`
- `notes`

The evaluator sees only:

- `blinded_item_id`
- the original prompt
- the markdown draft text

The evaluator does not need the hidden condition. The condition mapping remains in
the audit key.

## Expected Artifacts

Artifact root:

- `beagle/.artifacts/darwin-hpc/expedition-002-human-eval/`

Minimum artifact set:

- `human-eval-packet.json`
- `human-eval-key.json`
- `human-eval-template.json`
- `human-eval-source-summary.json`
- `analysis-summary.json`
- `analysis-summary.csv`
- `smoke.json`
- `final-cluster-health.txt`

## Canonical Live Readiness Proof

Artifact root:

- `beagle/.artifacts/darwin-hpc/expedition-002-human-eval/`

Current canonical readiness batch:

- `session_id = b175-exp002-human-eval-0322153547`
- `experiment_id = beagle_exp_002_hrv_aware_vs_blind`
- `packet_id = b175-exp002-human-eval-0322153547`
- `items = 4`
- `ratings_applied = 0`
- `status = ready_for_human_eval`

Frozen readiness facts:

- the blinded packet exists and hides condition labels from the evaluator-facing view
- the audit key exists and preserves `run_id -> condition` mapping
- the fillable template exists with the full canonical rubric
- comparative analysis now reports `n_with_feedback = 0` honestly for both conditions until real human judgments are added
- cluster stayed green
- `Slurmctld(primary)` stayed `UP`

## Promotion Rule

Promote `B17.5` to `GO` only after a real human evaluator fills the blinded
packet and the resulting ratings are persisted canonically and reflected in the
comparative analysis.
