# B24.11 Known Limits

- B24.11 does not activate analysis live by default.
- The promotion gate can remain `keep-shadow` when the soak window is still sample-limited.
- Manuscript remains on the control policy in all cases.
- The soak window is intentionally bounded; it does not create an unbounded historical runtime.
- If regression is detected, B24.11 records rollback or hold behavior only; it does not introduce an autonomous recovery loop.
