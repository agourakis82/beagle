# B24.18 Known Limits

- B24.18 does not promote `manuscript` to canary.
- The manuscript promotion gate can still remain `keep-shadow` even after this phase, because the purpose here is diagnosis and tuning, not rollout expansion.
- The tuned manuscript policy recommendation is bounded and shadow-only. It is not a live promotion by itself.
- The quality eval depends on the current execution trajectory and context packet. If the live manuscript path is still inheriting analysis-oriented defaults, B24.18 will surface that as misfit rather than masking it.
- Editorial readiness remains an explicit HITL problem. Operator-visible approve / edit / reject behavior is preserved and not bypassed by this phase.
