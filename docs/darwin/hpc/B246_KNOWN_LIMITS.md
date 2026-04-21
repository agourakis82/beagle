# B24.6 — Known Limits

- `B24.6` only auto-continues the first narrow low-risk analysis lane; broader task families still stay operator-reviewed
- `review-required` still uses the existing bounded `B24.5` continuation dispatch path instead of creating a new runtime
- `blocked` prevents dispatch but does not synthesize a new plan automatically
- the live smoke proves the `auto-continue` path; `review-required` and `blocked` remain covered by repo-native tests plus schema/source validation
