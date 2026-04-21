# B22.9 — Known Limits

- The feedback loop is bounded to the returned top-k and does not rewrite the
  underlying vector store.
- The current evaluation report is intentionally compact and not a full MTEB
  replacement.
- Voyage-backed lanes still inherit provider rate limits, so live smoke keeps
  API-heavy calls bounded.
- The policy artifact is evidence-backed, but still only as strong as the live
  cases included in the evaluation run.
