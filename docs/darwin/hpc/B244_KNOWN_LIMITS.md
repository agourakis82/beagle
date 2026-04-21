# B24.4 — Known Limits

- `B24.4` materializes follow-on plans but does not execute them automatically
- the live smoke exercises the canonical `approve` path; `edit` and `reject` stay covered through bounded repo-native tests
- review decisions are scoped to the latest execution thread per workspace
- no new ingress, HA, or external workflow plane is introduced
