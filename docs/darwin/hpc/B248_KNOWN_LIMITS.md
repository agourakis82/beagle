# B24.8 — Known Limits

- guarded rollout evidence is still bounded to replay-plus-shadow evaluation, not a large historical corpus
- `implementation` is only staged as the first guarded canary candidate; it is not promoted globally in `B24.8`
- `analysis` remains on the current live lane and `manuscript` remains review-or-block until later evidence says otherwise
- rollback criteria are explicit, but `B24.8` does not yet automate rollback from live operator action
- rollout quality still depends on the existing `B24.3`, `B24.5`, `B24.6`, and `B24.7` artifacts being present on the same identity
