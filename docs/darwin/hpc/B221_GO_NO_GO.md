# B22.1 GO / NO-GO

## GO

- One canonical retrieval collection contract exists repo-natively.
- One canonical memory point contract exists repo-natively.
- One canonical retrieval query/result contract exists repo-natively.
- The runtime exposes hybrid retrieval with dense + sparse fusion and payload-aware filtering.
- Workstream context packets consume retrieval hits coherently.
- Live smoke proves restart coherence.
- Cluster remains green.
- `Slurmctld(primary)` remains `UP`.

## NO-GO

- Retrieval remains legacy-query-only.
- Payload is implicit or not filterable.
- Context packets do not consume retrieval hits.
- Restart drops retrieval coherence.
- Cluster or Slurm health regresses.
