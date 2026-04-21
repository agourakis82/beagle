# B19.3 — GO / NO-GO

Status: GO

## GO Criteria

- one canonical evidence pack exists
- one canonical campaign assembles coherently into it
- result refs, memory refs, physio refs, recipe refs, and provenance are all
  present and bounded
- citation-ready metadata is present
- restart preserves workspace/session coherence
- cluster stays green
- Slurm stays green

## No-Go Conditions

- the evidence pack cannot resolve a canonical campaign
- evidence refs are incoherent or missing
- provenance or citation blocks are absent
- restart loses coherence
- the live smoke or validator fails

## Canonical Result

- live smoke: `OK`
- validator: `OK`
- campaign evidence pack assembled successfully for `expedition-002-hrv-aware`
- restart preserved `workspace_id=b193-evidence-pack-0323055639`
- cluster remained green
- `Slurmctld(primary)` remained `UP`
