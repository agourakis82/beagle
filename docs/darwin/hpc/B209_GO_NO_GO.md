# B20.9 GO / NO-GO

`GO` when:

- one explicit cross-subagent handoff is recorded
- source and target remain inside the same Beagle-owned workspace/session
- target subagent receives coherent propagated context
- restart preserves the same identity and handoff continuity
- cluster stays green
- `Slurmctld(primary)` stays `UP`

`NO-GO` when:

- the handoff creates a second canonical workspace/session path
- handoff intent is lost across restart
- target routing breaks identity coherence
