# B24.10 Known Limits

- B24.10 does not activate an analysis canary by default.
- The analysis candidate remains shadow-only in this phase.
- Manuscript remains on the control policy in all cases.
- The decision is calibrated from the current canonical replay-plus-shadow dataset, so analysis evidence can still be sample-limited.
- If regression is detected, the phase only records rollback/hold behavior; it does not introduce a new autonomous recovery loop.
