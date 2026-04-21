# B21.5 — Go / No-Go

## GO Criteria

- one canonical campaign generates an external staging bundle
- DataCite test staging payload is present and coherent
- Crossref dry-run bundle is present and coherent
- readiness remains explicit
- restart remains coherent
- cluster stays green
- `Slurmctld(primary)` stays `UP`

## No-Go Triggers

- any real registry call is attempted
- readiness gaps are hidden
- identity drifts across workstream, workspace, or session
