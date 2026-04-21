# B17.5 — GO / NO-GO

Status: STAGED / READY FOR HUMAN EVAL

Canonical promotion basis:

- artifact root: `beagle/.artifacts/darwin-hpc/expedition-002-human-eval/`
- experiment id: `beagle_exp_002_hrv_aware_vs_blind`
- protocol: `b17.5-expedition-002-human-eval-v1`
- readiness batch: `b175-exp002-human-eval-0322153547`
- validator: `validate_expedition_002_human_eval.sh = OK (ready_for_human_eval)`

## GO

Promote `B17.5` to `GO` only if:

- a blinded packet is generated canonically
- a real human rating batch is filled and persisted canonically
- `analyze_experiments` aggregates those judgments by condition
- the resulting artifacts remain audit-friendly
- cluster health stays green
- `Slurmctld(primary)` stays `UP`

## NO-GO

Remain below `GO` if any of the following occurs:

- no real human ratings are captured
- ratings are captured outside the canonical blinded packet / key / contract path
- analysis cannot separate `hrv_aware` vs `hrv_blind` using the persisted ratings
- the artifact trail is not auditable
- cluster or Slurm degrade
