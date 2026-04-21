# B25.7 — GO / NO-GO

## GO criteria

- The latest replay request is readable and includes source run plus code-state facts.
- One bounded replay execution can be submitted through the canonical workbench run lane.
- One bounded branch fork execution can be submitted through the same lane.
- Replay/fork execution receipts preserve the same Beagle-owned `workstream/workspace/session`.
- The latest run capsule and run diff remain coherent after replay/fork execution.
- Restart recovery keeps the latest replay execution receipt coherent.
- Cluster stays green.
- Slurm stays green.

## No-go triggers

- Replay/fork execution creates a second execution or identity plane outside Beagle.
- The replay execution path bypasses the existing bounded workbench orchestration flow.
- Source lineage is lost between the replay request and the replay/fork receipt.
- Replay/fork execution breaks restart coherence for the latest run capsule or receipt.
