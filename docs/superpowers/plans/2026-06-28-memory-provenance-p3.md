# Memory Provenance — Phase 3 (trust-weighted recall + grounding enforcement) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the loop — make recall actually USE the trust tiers. `memory-pg-serve /query` returns each hit's `trust_tier`; the companion grounding EXCLUDES `unverified` memories from "what I know about Demetrios" (so an orphaned/fabricated atom — the Teobaldo class — can be recalled but is never injected into his biography), keeping the trusted ones.

**Architecture:** Two small changes. (1) `retrieve.mjs` carries `records.trust_tier` (+ `prov_actor`) through the ranking CTEs into each returned hit, so `/query` exposes it transparently. (2) The cockpit companion grounding (`mobile-routes.mjs`) filters the recalled memories through a pure `filterTrustedMemories()` helper that drops `unverified` hits before they are stamped into the "## O que ele já te contou" section. The quorum tiers (P2) and provenance (P1/P1.5) feed this; nothing else changes.

**Tech Stack:** Node ESM (`.mjs`), `node:test`. memory-pg retrieve in `apps/memory-pg/src/retrieve.mjs`; companion grounding in `apps/project-cockpit/server/mobile-routes.mjs` (helper alongside `stampMemories` in `apps/project-cockpit/server/temporal-context.mjs`).

**Test envs:** memory-pg tests use the scratch DB via `bash /tmp/run-mpg-test.sh test/<file>.test.mjs`. Cockpit tests are dependency-injected (no DB): `cd apps/project-cockpit && node --test --test-concurrency=1 server/<file>.test.mjs`.

**Grounded facts:**
- `retrieve.mjs` final shape: a `scored` CTE `JOIN records r`; the final `SELECT chunk_id, record_id, text, dense_rank, bm25_rank, occurred_at, score` → `res.rows.map(row => ({chunk_id, record_id, text, score, dense_rank, bm25_rank, occurred_at}))`. No `trust_tier` yet.
- `retrieve.test.mjs` seeds `records`+`chunks`+`embeddings` directly with one-hot 1024-dim halfvecs, then calls `retrieve(pool, ...)`.
- `records.trust_tier` exists (P2) with values `unverified|claimed|corroborated|known` (default `unverified`).
- Companion grounding (`mobile-routes.mjs` ~754-772): `fetchRecentMemories(userText,{k:4})` → `stampMemories(memoryResults, now, tz).slice(0,4)` → pushed under "## O que ele já te contou".
- `stampMemories(results, now, tz)` (`temporal-context.mjs:95`) reads `r.text` + `r.occurred_at` only — so the trust filter must run BEFORE it, on the raw hits (which now carry `trust_tier`).

---

### Task 1: `retrieve` exposes `trust_tier` per hit

**Files:**
- Modify: `apps/memory-pg/src/retrieve.mjs` (the `scored` CTE, the final SELECT, and the `rows.map`)
- Test: `apps/memory-pg/test/retrieve-trust.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `apps/memory-pg/test/retrieve-trust.test.mjs`:

```js
// retrieve() returns each hit's trust_tier (added in P3). One-hot halfvecs, like retrieve.test.mjs.
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { retrieve } from "../src/retrieve.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

// A 1024-dim one-hot unit halfvec literal with a 1 at `axis`.
function oneHot(axis) {
  const v = new Array(1024).fill(0);
  v[axis] = 1;
  return "[" + v.join(",") + "]";
}

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records, chunks, embeddings CASCADE"); });
after(async () => { await pool.end(); });

async function seed({ axis, text, tier }) {
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, trust_tier)
     VALUES ('T', $1, 'sha-'||gen_random_uuid()::text, $2) RETURNING id`, [text, tier]);
  const c = await pool.query(
    `INSERT INTO chunks (record_id, chunk_index, text, content_sha256)
     VALUES ($1, 0, $2, 'cs-'||gen_random_uuid()::text) RETURNING id`, [r.rows[0].id, text]);
  await pool.query(
    `INSERT INTO embeddings (chunk_id, embedding, model_version)
     VALUES ($1, $2::halfvec, 'bge-m3')`, [c.rows[0].id, oneHot(axis)]);
  return c.rows[0].id;
}

test("each hit carries its record's trust_tier", async () => {
  await seed({ axis: 0, text: "the user runs marathons", tier: "claimed" });
  const hits = await retrieve(pool, { queryEmbedding: oneHot(0), queryText: "marathons", k: 5 });
  assert.ok(hits.length >= 1, "expected at least one hit");
  assert.equal(hits[0].trust_tier, "claimed");
});
```

(`retrieve(pool, { queryEmbedding, queryText, k })` is the real signature; `queryEmbedding` is the one-hot halfvec literal string, exactly as `apps/memory-pg/test/retrieve.test.mjs` uses it.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/run-mpg-test.sh test/retrieve-trust.test.mjs`
Expected: FAIL — `hits[0].trust_tier` is `undefined`.

- [ ] **Step 3: Carry `trust_tier` through retrieve**

In `apps/memory-pg/src/retrieve.mjs`:
1. In the `scored` CTE SELECT list (which has `r.occurred_at`), add `r.trust_tier`:
```sql
    r.occurred_at,
    r.trust_tier,
```
2. In the final SELECT list (`chunk_id, record_id, text, dense_rank, bm25_rank, occurred_at, ... AS score`), add `trust_tier`:
```sql
  chunk_id, record_id, text, dense_rank, bm25_rank, occurred_at, trust_tier,
```
3. In `res.rows.map(...)`, add the field:
```js
      occurred_at: row.occurred_at,
      trust_tier: row.trust_tier,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/run-mpg-test.sh test/retrieve-trust.test.mjs`
Expected: PASS.

- [ ] **Step 5: No regression**

Run: `bash /tmp/run-mpg-test.sh test/retrieve.test.mjs test/serve.test.mjs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/devsounio/beagle
git add apps/memory-pg/src/retrieve.mjs apps/memory-pg/test/retrieve-trust.test.mjs
git commit -m "feat(memory-pg): retrieve exposes trust_tier per hit"
```

---

### Task 2: Companion grounding excludes `unverified` memories

**Files:**
- Modify: `apps/project-cockpit/server/temporal-context.mjs` (add exported `filterTrustedMemories`)
- Modify: `apps/project-cockpit/server/mobile-routes.mjs` (wire it before `stampMemories`)
- Test: `apps/project-cockpit/server/filter-trusted.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `apps/project-cockpit/server/filter-trusted.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { filterTrustedMemories } from "./temporal-context.mjs";

test("drops unverified hits, keeps claimed/corroborated/known", async () => {
  const hits = [
    { text: "fabricated orphan atom", trust_tier: "unverified" },
    { text: "you said you run marathons", trust_tier: "claimed" },
    { text: "confirmed across sessions", trust_tier: "corroborated" },
    { text: "a known fact", trust_tier: "known" },
  ];
  const kept = filterTrustedMemories(hits);
  const texts = kept.map((h) => h.text);
  assert.deepEqual(texts, [
    "you said you run marathons",
    "confirmed across sessions",
    "a known fact",
  ]);
});

test("a hit with no trust_tier is kept (fail-open for non-personal recall)", async () => {
  const kept = filterTrustedMemories([{ text: "untiered", trust_tier: undefined }]);
  assert.equal(kept.length, 1);
});

test("non-array input yields an empty array", async () => {
  assert.deepEqual(filterTrustedMemories(null), []);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test --test-concurrency=1 server/filter-trusted.test.mjs`
Expected: FAIL — `filterTrustedMemories` is not exported.

- [ ] **Step 3: Implement + wire the filter**

In `apps/project-cockpit/server/temporal-context.mjs`, add (next to `stampMemories`):

```js
/**
 * Trust gate for biography grounding (provenance design §4): drop `unverified`
 * memories (orphaned/model-generated content) so they are never injected as
 * "what I know about him". A hit with no tier is kept (fail-open: non-personal
 * recall and pre-P2 rows are not penalized).
 * @param {Array<{trust_tier?: string}>} results
 */
export function filterTrustedMemories(results) {
  if (!Array.isArray(results)) return [];
  return results.filter((r) => r?.trust_tier !== "unverified");
}
```

In `apps/project-cockpit/server/mobile-routes.mjs`, import it (add `filterTrustedMemories` to the existing import from `./temporal-context.mjs`), and change the stamping line in the grounding block from:
```js
      const stamped = stampMemories(memoryResults, now, tz).slice(0, 4);
```
to:
```js
      const stamped = stampMemories(filterTrustedMemories(memoryResults), now, tz).slice(0, 4);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/project-cockpit && node --test --test-concurrency=1 server/filter-trusted.test.mjs`
Expected: PASS (3 tests).

- [ ] **Step 5: No regression + syntax check**

Run: `cd apps/project-cockpit && node --check server/mobile-routes.mjs && node --test --test-concurrency=1 server/temporal-context.test.mjs 2>/dev/null || node --check server/temporal-context.mjs`
Expected: syntax OK; any existing temporal-context tests still pass.

- [ ] **Step 6: Commit**

```bash
cd /home/devsounio/beagle
git add apps/project-cockpit/server/temporal-context.mjs apps/project-cockpit/server/mobile-routes.mjs apps/project-cockpit/server/filter-trusted.test.mjs
git commit -m "feat(cockpit): exclude unverified memories from companion biography grounding"
```

---

### Task 3: Deploy + live verification

**Files:** none (operational — the orchestrator runs this).

- [ ] **Step 1: Rebuild + roll memory-pg-serve** with the new `retrieve.mjs` (buildah overlay of the shared image with `src/`, like P2; roll `memory-pg-serve`).
- [ ] **Step 2: Rebuild + roll the cockpit** with the grounding filter (kaniko build from HEAD → set image, Recreate).
- [ ] **Step 3: Verify `/query` exposes the tier:** a direct `POST /query` to memory-pg-serve returns hits each carrying `trust_tier`.
- [ ] **Step 4: Live end-to-end check:** seed (via the live companion or a direct provenance write) one `user_stated`/`claimed` memory and one `unverified` (orphan) memory with overlapping content, send a personal chat that would recall both, and confirm (cockpit logs or a grounding probe) that the unverified one is NOT in the injected "## O que ele já te contou" section while the trusted one is.

## Self-review (P3 → spec coverage)

- Spec §4 "/query returns trust_tier" → Task 1.
- Spec §4 "unverified → excluded from what I know about you" → Task 2 (the core enforcement; closes the Teobaldo loop end-to-end at recall).
- Spec §4 "claimed → hedged / corroborated-known → asserted" and "ranking weights by tier" → **P3.5** (a refinement: needs fact-tier assertion + per-tier framing; record tiers from P2 are claimed/unverified, so the high-value exclusion lands now and the assert/hedge nuance follows).
- The MCP bridge (`beagle_memory_query`, which hits beagle-core not memory-pg) enforcing tiers → **P3.5** (separate surface).
