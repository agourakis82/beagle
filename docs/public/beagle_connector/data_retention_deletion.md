# Beagle Exocortex Data Retention and Deletion

Last updated: 2026-04-26

## Retention Model

Beagle uses append-only logs for memory, Chronoself, audit events, and agent observations. Append-only storage preserves provenance and makes agent behavior reviewable.

## Derived Indexes

Search indexes, summaries, embeddings, and cached snapshots are derived data. They can be rebuilt from canonical append-only logs and should not be treated as independent sources of truth.

## Deletion Requests

For private/personal deployments, deletion is handled by the Beagle operator. A deletion workflow should:

1. Identify canonical records matching the request.
2. Add a deletion or redaction event to the audit log.
3. Remove or redact the canonical payload where policy requires it.
4. Rebuild derived indexes and caches.
5. Verify that `search` and `fetch` no longer return deleted payloads.

## Connector Review Data

Reviewer/test-account data must be sanitized and may be reset at any time. It should not include real credentials, private medical details, financial records, or sensitive third-party information.

## Health Context

Health/body context is retained only as configured by the Beagle operator and should remain deletable on request. It is not used for diagnosis or emergency response.
