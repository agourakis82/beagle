# B24.12 Known Limits

- B24.12 does not activate analysis live by default, even if the recheck reaches `stage-analysis-canary`.
- Sample accumulation is bounded and auditable; it does not introduce an unbounded history runtime.
- Manuscript remains on the control policy in all cases.
- If regression is detected, B24.12 records rollback or hold behavior only; it does not create an autonomous recovery loop.
- The recheck uses the canonical bounded comparison set and does not invent new operator-invisible evidence.
