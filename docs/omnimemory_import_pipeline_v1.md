# OmniMemory Import Pipeline v1

Last updated: 2026-04-26

## Purpose

OmniMemory Import Pipeline v1 turns explicit exports from ChatGPT, Claude, Grok, Gemini, and similar agents into a canonical, auditable import corpus for Beagle Exocortex.

This is not scraping. The user exports or supplies conversation files intentionally. Beagle normalizes them, validates them, deduplicates them, classifies privacy/provenance, and prepares them for Chronoself-linked ingestion.

## Strategic Role

MCP public access proved that external agents can talk to Beagle. The next bottleneck is memory density: Beagle must remember its own history, design philosophy, decisions, research threads, and agent interactions.

The priority sequence remains:

1. OmniMemory import of historical conversations.
2. ChatGPT connector readiness.
3. Apple Home Exocortex backed by living memory.

Apple UI should not outrun memory. The Home screen must render continuity, not a pretty empty shell.

## Inputs

Accepted v1 input forms:

- `.json`
- `.jsonl`
- `.txt`
- `.md`

Expected source platforms:

- `chatgpt`
- `claude`
- `grok`
- `gemini`
- `manual`

The pipeline is intentionally tolerant because exports differ by vendor and change over time.

## Canonical Record

Each normalized record is written as JSONL with this shape:

```json
{
  "record_id": "sha256:...",
  "source_platform": "chatgpt",
  "source_file": "conversations.json",
  "source_conversation_id": "optional",
  "source_title": "optional",
  "source_created_at": "optional ISO-8601-ish string",
  "source_updated_at": "optional ISO-8601-ish string",
  "canonical_text": "user/assistant transcript",
  "turns": [
    {
      "role": "user",
      "content": "..."
    }
  ],
  "content_hash": "sha256:...",
  "privacy_class": "public|sensitive|restricted",
  "privacy_tags": ["..."],
  "provenance": {
    "imported_via": "omnimemory_import_pipeline_v1",
    "explicit_user_export": true
  },
  "metadata": {}
}
```

## Phase 1: Collect And Validate

Run:

```bash
python3 scripts/omnimemory_import_v1.py prepare \
  --input ~/Downloads/beagle_exports \
  --source-platform chatgpt \
  --output .beagle/omnimemory-import/chatgpt-20260426
```

Outputs:

- `canonical_records.jsonl`
- `duplicates.jsonl`
- `manifest.json`
- `validation_report.json`

Validation includes:

- UTF-8 readability
- null byte rejection
- minimum text presence
- stable content hash
- source/provenance metadata
- privacy classification coverage

## Phase 2: Deduplicate

Deduplication v1 has two levels:

1. Exact SHA-256 over canonical source platform, title, text, and turns.
2. Optional fuzzy similarity using Python standard library `SequenceMatcher`.

Default fuzzy threshold is `0.985`. Keep it conservative. False merges are worse than duplicated memories.

## Phase 3: Privacy And Provenance

Privacy classes:

- `public`: low personal sensitivity.
- `sensitive`: personal, medical, legal, financial, identity, or project-confidential material.
- `restricted`: obvious credentials, secrets, keys, tokens, account identifiers, or high-risk PII.

Every record gets:

- `source_platform`
- `source_file`
- `content_hash`
- `privacy_class`
- `privacy_tags`
- `provenance.explicit_user_export = true`

## Phase 4: Chronoself Linking

Before full ingestion, create:

- one parent Chronoself commit describing the import decision;
- one batch commit per 500-1000 records;
- a batch merkle root from record hashes.

The import should be traceable without trusting the importer.

## Phase 5: Ingest

The next implementation step is a batch ingester that reads `canonical_records.jsonl` and calls Beagle core or MCP tools:

- `beagle_omnimemory_import`
- `beagle_memory_ingest_chat`
- `beagle_chronoself_create_commit`

For v1, ingest should be incremental:

1. 10-record smoke.
2. 100-record pilot.
3. one full source platform.
4. all approved sources.

## Acceptance Criteria

- `validation_report.json.status == "pass"` for smoke and pilot.
- 100% records have privacy class and content hash.
- Duplicate removal is reported, not silent.
- Restricted records are excluded unless explicitly allowed.
- Chronoself parent and batch commit IDs are recorded before full ingest.
- Post-ingest `search` finds known decisions from imported history.

## Do Not Do

- Do not scrape accounts.
- Do not import browser caches silently.
- Do not merge fuzzy duplicates below a conservative threshold.
- Do not ingest restricted records by default.
- Do not let Apple UI depend on unvalidated memory.
