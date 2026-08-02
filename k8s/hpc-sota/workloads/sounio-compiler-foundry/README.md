# Sounio Compiler Foundry Workload

This workload is the Slurm-side execution layer for:

```bash
/home/devsounio/projects/sounio/sounio-forge submit full-compiler --source wip --gpu auto
```

Use `orientation` for the first smoke. It creates the same run packet/snapshot
and executes only environment discovery plus `bin/souc info`.

Use `corpus-smoke` for the second smoke. It runs `orientation` plus a filtered
test-suite probe (`--filter basic_math`) with JUnit and per-test JSON redirected
to the run artifact root.

The workspace submits a run packet and source snapshot. The Slurm job extracts
that snapshot into isolated local scratch and publishes structured artifacts
back to OrangeFS.

## Boundary

- workspace: submit only
- job scratch: execution allowed
- artifact root: read/report only

Jobs must not write to `/workspace/sounio`.

## Runner

```text
sounio-foundry-runner.sh <run_packet.json> cpu|gpu
```

The runner exports:

```text
SOUNIO_RUN_ID
SOUNIO_SOURCE
SOUNIO_SCRATCH
SOUNIO_ARTIFACTS
SOUNIO_PROFILE
SOUNIO_TEST_JUNIT_FILE
SOUNIO_TEST_RESULTS_DIR
```

CPU lane artifacts:

- `summary.json`
- `results.tsv`
- `junit.xml`
- `test-suite-junit.xml` when corpus phases run
- `test-results/` when corpus phases run:
  - `result_<n>.json` compact per-test status
  - `result_<n>.log` full stdout/stderr for executed tests
- `artifact_hashes.tsv`
- `logs/`

The bootstrap fixed-point phase requires a host C compiler (`cc`) on the Slurm
worker lane. If the script exists but `cc` is absent, the runner records
`bootstrap_fixed_point` as `not_run` with a lane dependency note instead of
misclassifying it as a compiler failure.

GPU lane artifacts:

- `summary-gpu.json`
- `results-gpu.tsv`
- `junit-gpu.xml`
- `artifact_hashes-gpu.tsv`
- `logs/`

## Smoke

Control-plane dry-run:

```bash
/home/devsounio/projects/sounio/sounio-forge submit full-compiler \
  --dry-run \
  --no-snapshot \
  --run-id plan-mode-smoke \
  --artifact-root /tmp/sounio-foundry-plan
```

Snapshot smoke:

```bash
/home/devsounio/projects/sounio/sounio-forge submit orientation \
  --dry-run \
  --run-id snapshot-smoke-$(date -u +%Y%m%dT%H%M%SZ) \
  --artifact-root /tmp/sounio-foundry-plan \
  --snapshot-timeout 300
```
