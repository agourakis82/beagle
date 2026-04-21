# B23.2 — GO / NO-GO

## GO

- promotion policy is explicit and queryable
- retention policy is explicit and queryable
- at least one bounded promotion event is preserved
- GraphRAG query-mode routing is live for `local`, `global`, or `drift`
- context packets surface promotion and mode metadata coherently
- restart preserves the same Beagle-owned identity
- cluster stays green
- `Slurmctld(primary)` stays `UP`

## NO-GO

- promotion or retention policy stays implicit
- GraphRAG mode routing is only documented and not live
- promoted memory cannot be evaluated or preserved across restart
- context packets drop policy or mode metadata
- cluster or Slurm health regresses
