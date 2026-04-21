# B24.5 — Known Limits

- `B24.5` dispatches a bounded continuation but does not create an autonomous infinite execution loop
- one continuation chain is tracked per current workspace execution thread
- the live smoke exercises the canonical `approved` continuation path; alternative review actions remain covered by repo-native tests
- no new ingress, HA, or external workflow plane is introduced
