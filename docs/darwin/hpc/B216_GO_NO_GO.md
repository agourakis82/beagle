# B21.6 — Go / No-Go

## GO Criteria

- one canonical campaign executes real network handshakes against the
  DataCite test API and the Crossref test deposit endpoint
- both receipts are preserved coherently in a registry submission ledger
- readiness remains explicit
- restart remains coherent
- cluster stays green
- `Slurmctld(primary)` stays `UP`

## No-Go Triggers

- no real sandbox registry roundtrip is attempted
- receipts are not preserved canonically
- identity drifts across workstream, workspace, or session
- `claim-linked-human-eval-pending` is hidden or softened
