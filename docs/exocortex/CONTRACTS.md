# Exocortex Grounding — Discovered API Contracts (Task 0)

> **Source of truth: the LIVE deployed pod**, not the repo source. The deployed
> `beagle-core` (`core-server` container, ns `beagle`) is built from a different
> binary than the `crates/beagle-server` routes in this checkout. All shapes below
> were probed against `svc/beagle-core:8080` and `svc/router:4000` on 2026-06-20.

## Auth (all beagle-core calls)

- Header `X-Beagle-Consumer: beagle-operator`
- Header `Authorization: Bearer <operator-token>`
- Token source: secret `beagle-core-tokens`, key `operator-token` (58 bytes).
  (Also `research-token`.) See memory `project_beagle_core_api_auth`.
- LiteLLM router takes `Authorization: Bearer noauth`.

## Internal cluster URLs

- beagle-core: `http://beagle-core.beagle.svc.cluster.local:8080`
- LiteLLM router: `http://router.llm-router.svc.cluster.local:4000`

---

## 1. Memory QUERY — `POST /api/memory/query`

**Deployed reality: it is `POST`, not `GET`** (the `crates/beagle-server`
`GET /api/memory/query` is a different, non-deployed binary).

Request:
```json
{ "query": "sounio", "k": 5 }
```

Response (matches the plan's `highlights[].snippet/date` assumption):
```json
{
  "summary": "Found 5 HyperMemory match(es) across 2 episode(s) ... for 'sounio'.",
  "highlights": [
    {
      "source": "omnimemory",
      "date": "2026-06-19T09:40:55.074163Z",
      "snippet": "...",
      "run_id": null,
      "session_id": "claude-code-daemon-...",
      "relevance": 1.0
    }
  ]
}
```

→ The cockpit's `fetchBiographyDigest()` (Task 6) queries this with the
`biography-digest` tag/term and reads `highlights[].snippet`.

**Tag filtering works (verified).** Plain `{query,k}` does NOT reliably surface a
freshly-stored pinned doc (semantic rank loses to the larger corpus). Adding
`"tags":["biography-digest"]` (and/or `"scope":"biography_digest"`) to the body
deterministically returns the digest as the **top** highlight:
```json
{ "query": "biografia viva Demetrios", "k": 3, "tags": ["biography-digest"] }
```
→ `fetchBiographyDigest()` uses this and takes the most-recent highlight snippet.

---

## 2. Memory INGEST — `POST /api/exocortex/v1/memory/assisted-import`

**This is the canonical ingest path. The plan's assumed `/api/memory/ingest`
and `/api/memory/documents` both return 404 on the deployed pod.**

Probe results (deployed):
| Route | POST result |
|---|---|
| `/api/memory/ingest` | 404 (does not exist) |
| `/api/memory/documents` | 404 (does not exist) |
| `/api/memory/episodes` | 404 (does not exist) |
| `/api/memory/ingest_chat` | 422 (exists — low-level `ChatSession`) |
| `/api/exocortex/v1/memory/assisted-import` | 422 (exists — **use this**) |

Request body (from the cockpit caller `workspace-routes.mjs`):
```json
{
  "source_platform": "beagle-apple",
  "source_surface": "beagle-workbench",
  "import_scope": "workbench_terminal_block",
  "session_id": "<id>",
  "project_ref": "<slug>",
  "privacy_class": "sensitive",
  "title": "<short title>",
  "confidence_score": 0.82,
  "create_chronoself_commit": false,
  "turns": [
    { "role": "user", "content": "...", "timestamp": "<iso>", "metadata": {} },
    { "role": "assistant", "content": "...", "timestamp": "<iso>", "metadata": {} }
  ],
  "tags": ["..."],
  "metadata": { "remembered_from": "...", "restricted_leak_check": "passed" }
}
```

Response (success): includes `memory_event_id`.

### KEY CONSEQUENCE — server-side embedding

beagle-core **embeds the content server-side**. The ingest tool sends **text
only** — it does **NOT** compute or send vectors. → The plan's per-chunk
`embed()` via `bge-m3` is **unnecessary for storage** and is dropped from Task 3.

### How corpus files map onto this contract

Each ingested file/chunk becomes one assisted-import with a single `turns`
entry carrying the content. Recommended field values for Tier-1 disk ingestion:
- `source_platform: "exocortex-ingest"`, `source_surface: "disk-corpus"`
- `import_scope: "biographical_corpus"`
- `privacy_class: "sensitive"` (it's his personal corpus)
- `create_chronoself_commit: false`
- `turns: [{ role: "user", content: <chunk>, timestamp: <file mtime/now>, metadata: { path, chunk_index } }]`
- `tags: ["exocortex", "tier1", "disk", "signal:<weight>"]`
- `metadata: { path, weight, restricted_leak_check: "passed", remembered_from: "exocortex-ingest" }`

The biography digest (Task 4) is stored the same way with
`import_scope: "biography_digest"`, `tags: ["biography-digest", "pinned"]`,
`title: "Biografia viva — <date>"`.

---

## 3. Embeddings (router) — `POST /v1/embeddings`  *(not needed for storage)*

Available (`bge-m3`) but **unused** for ingestion because beagle-core embeds
server-side. Documented for completeness only.
```json
{ "model": "bge-m3", "input": "text" }   →   { "data": [ { "embedding": [ ... ] } ] }
```

---

## 4. Chat completions (router) — `POST /v1/chat/completions`

OpenAI-compatible. Used by the digest distiller (Task 4) and the muse→voice
ensemble (Task 6).

**Models confirmed live on `svc/router:4000` (2026-06-20):**
`qwen2.5-14b`, `qwen2.5-coder-32b`, `hermes-4`, `hunyuan-7b`,
`falcon-mamba-7b`, `internlm2.5-7b`, `dynamo-qwen3`, `bge-m3`.

Role assignment for Phase 2:
- **Digest distill:** `qwen2.5-14b`
- **Muse (silent seeds):** `hunyuan-7b`
- **Voice (streamed reply):** `hermes-4` (default), `qwen2.5-14b` (fallback/toggle)

All on-cluster / self-hosted — satisfies the sovereignty guardrail (no commercial
provider in the Personal path).

---

## Net changes vs. the plan's assumptions

1. **Ingest endpoint:** `/api/memory/ingest` → **`/api/exocortex/v1/memory/assisted-import`** (structured turns body).
2. **No client-side embedding for storage** — server embeds; send text only. Drop `embed()` from the ingest pipeline.
3. **Query is POST** (`/api/memory/query`), response `highlights[].snippet/date` — as assumed. ✓
4. Router models all present — digest + ensemble model choices stand. ✓
