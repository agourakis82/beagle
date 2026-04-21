# B17.4 — GO / NO-GO

Status: GO

Canonical promotion basis:

- artifact root: `beagle/.artifacts/darwin-hpc/expedition-002-live-execution/`
- batch session: `b174-exp002-0322124804`
- experiment id: `beagle_exp_002_hrv_aware_vs_blind`
- validator: `validate_expedition_002.sh = OK`

## GO

Promote `B17.4` to `GO` only if the live batch proves:

- `hrv_aware` and `hrv_blind` both ran successfully
- the same canonical `experiment_id` is present in run metadata
- `pipeline_physio.snapshot_available = true` is preserved
- `pipeline_physio.used_in_pipeline = true` only for `hrv_aware`
- comparison artifacts are produced in JSON and CSV
- cluster health stays green
- `Slurmctld(primary)` stays `UP`

The canonical live batch satisfied those conditions:

- `hrv_aware` runs = `2`
- `hrv_blind` runs = `2`
- `snapshot_available = 4/4`
- `used_in_pipeline = 2/4`, bounded exactly to the aware condition
- JSON + CSV comparative outputs were produced
- cluster and Slurm finished green

## NO-GO

Remain below `GO` if any of the following occurs:

- one condition does not run
- experiment metadata is missing from run reports
- blind runs accidentally consume physio context
- aware runs fail to attach canonical physio
- analysis output is missing or incoherent
- cluster or Slurm degrade
