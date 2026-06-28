# Memory Provenance — Phase 2 (trust tiers + quorum) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A claim about the user becomes "known" only with independent corroboration. Every graph `fact` gets a `trust_tier` computed from how many INDEPENDENT user-stated sources support it (distinct `(session, day)`), so a single fabricated mention stays `claimed` (hedged downstream) and one conversation restating something 10× counts as ONE source — never `known`.

**Architecture:** Facts dedup on the claim hash, discarding source multiplicity, so a new `fact_supports(fact_id, source_record_id)` table records EVERY source→claim pairing (even when the fact already exists). The graph extractor writes a support per extraction; a one-shot backfill seeds one support per existing fact from its `source_record_id`. A promotion module recomputes `facts.trust_tier` (idempotent, full-table) by counting distinct `(session, day)` among the `user_stated` supporting records, and gives each `record` a base tier from its own actor/orphan flag. P3 (recall) will read these tiers; this phase only materializes them.

**Tech Stack:** Node ESM (`.mjs`), `node:test`, `pg`, Postgres 16. memory-pg stack in `apps/memory-pg/`. Schema applied by `ensureSchema` (runs `sql/*.sql` lexically, idempotent). Graph extractor: `src/graph-extract.mjs` (runs in the `memory-pg-graph-worker` deploy, image `memory-pg-embed-worker:v4`, cmd `node bin/graph-worker.mjs`).

**Pre-req for tests — SCRATCH DB (these tests TRUNCATE):** as in P1,
```
export MEMORY_PG_TEST_DSN="postgres://memory:$PGPASSWORD@127.0.0.1:5432/memory_test"
```
and run with the wrapper `bash /tmp/run-mpg-test.sh test/<file>.test.mjs` (manages the port-forward). Every test file guards that the DSN db-name contains `test`.

**Grounded facts:**
- `facts(id, subject_id, predicate, object_id, object_literal, source_record_id→records SET NULL, content_sha256 UNIQUE, provenance jsonb, confidence)`. Insert is `ON CONFLICT (content_sha256) DO NOTHING RETURNING id` — when the claim exists, `rowCount=0` and no id is returned, so the support writer must look the id up.
- 372K facts / 184K entities live; graph worker actively draining `pending_graph`.
- `session_id` lives in `metadata->>'session_id'` (P1.5 writes) OR `metadata->'provenance'->>'session_id'` (historical). The session key is `COALESCE(NULLIF(metadata->>'session_id',''), metadata->'provenance'->>'session_id', id::text)` (fall back to the record id so an unkeyed record is its own session, never falsely merged).
- `records` already has `prov_actor`, `prov_orphan` (P1).

---

### Task 1: Migration 005 — `fact_supports` + `trust_tier`

**Files:**
- Create: `apps/memory-pg/sql/005_trust.sql`
- Test: `apps/memory-pg/test/trust-schema.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `apps/memory-pg/test/trust-schema.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

test("fact_supports table + trust_tier columns exist with the tier CHECK", async () => {
  await ensureSchema(pool);
  const fs = await pool.query(
    "SELECT to_regclass('public.fact_supports') AS t");
  assert.equal(fs.rows[0].t, "fact_supports");
  const cols = await pool.query(
    `SELECT table_name, column_name FROM information_schema.columns
      WHERE column_name = 'trust_tier' AND table_name IN ('facts','records')`);
  const tabs = cols.rows.map((r) => r.table_name).sort();
  assert.deepEqual(tabs, ["facts", "records"]);
  // tier CHECK rejects a bad value. Use an INSERT (always writes a row -> always fires
  // the CHECK); an UPDATE on an empty table touches zero rows and never validates.
  await assert.rejects(
    pool.query(
      `INSERT INTO records (source_type, content, content_sha256, trust_tier)
       VALUES ('T', 'x', 'sha-' || gen_random_uuid()::text, 'famous')`),
    /records_trust_tier_chk|check constraint/i,
  );
});

test.after(async () => { await pool.end(); });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/run-mpg-test.sh test/trust-schema.test.mjs`
Expected: FAIL — `fact_supports` is null; `trust_tier` columns absent.

- [ ] **Step 3: Write the migration**

Create `apps/memory-pg/sql/005_trust.sql`:

```sql
-- 005_trust.sql
-- P2: trust tiers + the fact_supports multiplicity table (design spec §2/§3).
-- Additive + idempotent.

CREATE TABLE IF NOT EXISTS fact_supports (
  fact_id uuid NOT NULL REFERENCES facts(id) ON DELETE CASCADE,
  source_record_id uuid NOT NULL REFERENCES records(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (fact_id, source_record_id)
);
CREATE INDEX IF NOT EXISTS fact_supports_record_idx ON fact_supports (source_record_id);

ALTER TABLE facts   ADD COLUMN IF NOT EXISTS trust_tier text NOT NULL DEFAULT 'unverified';
ALTER TABLE facts   ADD COLUMN IF NOT EXISTS independent_user_sources int NOT NULL DEFAULT 0;
ALTER TABLE records ADD COLUMN IF NOT EXISTS trust_tier text NOT NULL DEFAULT 'unverified';

ALTER TABLE facts   DROP CONSTRAINT IF EXISTS facts_trust_tier_chk;
ALTER TABLE facts   ADD CONSTRAINT facts_trust_tier_chk
  CHECK (trust_tier IN ('unverified','claimed','corroborated','known'));
ALTER TABLE records DROP CONSTRAINT IF EXISTS records_trust_tier_chk;
ALTER TABLE records ADD CONSTRAINT records_trust_tier_chk
  CHECK (trust_tier IN ('unverified','claimed','corroborated','known'));

CREATE INDEX IF NOT EXISTS facts_trust_tier_idx   ON facts   (trust_tier);
CREATE INDEX IF NOT EXISTS records_trust_tier_idx ON records (trust_tier);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/run-mpg-test.sh test/trust-schema.test.mjs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/devsounio/beagle
git add apps/memory-pg/sql/005_trust.sql apps/memory-pg/test/trust-schema.test.mjs
git commit -m "feat(memory-pg): fact_supports table + trust_tier columns (P2 migration)"
```

---

### Task 2: Promotion module — independence-counted tiering

**Files:**
- Create: `apps/memory-pg/src/promote.mjs`
- Test: `apps/memory-pg/test/promote.test.mjs`

The heart of P2. `promoteFacts` recomputes every fact's tier; `promoteRecords` gives each record a base tier from its actor. Independence = distinct `(session, day)` among `user_stated` supporters. Tiers: 0 → `unverified`, 1 → `claimed`, ≥2 → `corroborated`, ≥2 spanning ≥ `knownSpanDays` → `known`.

- [ ] **Step 1: Write the failing test**

Create `apps/memory-pg/test/promote.test.mjs`. It inserts records/facts/supports with controlled `created_at` + session (raw SQL, so it does not depend on captureRecord), then asserts tiers:

```js
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { promoteFacts, promoteRecords } from "../src/promote.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records, chunks, entities, facts, fact_supports CASCADE"); });
after(async () => { await pool.end(); });

// Insert a record with an explicit actor / session / day; returns its id.
async function rec({ actor = "user_stated", session = "s1", day = "2026-06-01", content }) {
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, prov_actor, created_at, metadata)
     VALUES ('T', $1, 'sha-' || gen_random_uuid()::text, $2, $3::timestamptz,
             jsonb_build_object('session_id', $4))
     RETURNING id`,
    [content, actor, `${day}T12:00:00Z`, session],
  );
  return r.rows[0].id;
}
// A subject entity + a fact, returns the fact id.
async function fact(predicate = "likes", literal = "green") {
  const e = await pool.query(
    `INSERT INTO entities (name, norm_name, type, content_sha256)
     VALUES ('Demetrios','demetrios','person','e-'||gen_random_uuid()::text) RETURNING id`);
  const f = await pool.query(
    `INSERT INTO facts (subject_id, predicate, object_literal, content_sha256)
     VALUES ($1, $2, $3, 'f-'||gen_random_uuid()::text) RETURNING id`,
    [e.rows[0].id, predicate, literal]);
  return f.rows[0].id;
}
async function support(factId, recordId) {
  await pool.query("INSERT INTO fact_supports (fact_id, source_record_id) VALUES ($1,$2)", [factId, recordId]);
}
async function tierOf(factId) {
  return (await pool.query("SELECT trust_tier, independent_user_sources FROM facts WHERE id=$1", [factId])).rows[0];
}

test("10 user_stated supports from ONE session+day count as 1 → claimed (kills amplification)", async () => {
  const f = await fact();
  for (let i = 0; i < 10; i++) {
    await support(f, await rec({ session: "sX", day: "2026-06-01", content: `c${i}` }));
  }
  await promoteFacts(pool);
  const t = await tierOf(f);
  assert.equal(t.independent_user_sources, 1);
  assert.equal(t.trust_tier, "claimed");
});

test("2 distinct sessions on 2 days within a week → corroborated", async () => {
  const f = await fact();
  await support(f, await rec({ session: "comp", day: "2026-06-01", content: "a" }));
  await support(f, await rec({ session: "cd",   day: "2026-06-03", content: "b" }));
  await promoteFacts(pool);
  const t = await tierOf(f);
  assert.equal(t.independent_user_sources, 2);
  assert.equal(t.trust_tier, "corroborated");
});

test("2 independent sources spanning ≥7 days → known", async () => {
  const f = await fact();
  await support(f, await rec({ session: "comp", day: "2026-06-01", content: "a" }));
  await support(f, await rec({ session: "cd",   day: "2026-06-10", content: "b" }));
  await promoteFacts(pool);
  assert.equal((await tierOf(f)).trust_tier, "known");
});

test("a fact with only non-user_stated supports stays unverified", async () => {
  const f = await fact();
  await support(f, await rec({ actor: "model_generated", content: "x" }));
  await support(f, await rec({ actor: "model_distilled", content: "y" }));
  await promoteFacts(pool);
  const t = await tierOf(f);
  assert.equal(t.independent_user_sources, 0);
  assert.equal(t.trust_tier, "unverified");
});

test("promoteRecords sets a base tier from actor/orphan", async () => {
  const u = await rec({ actor: "user_stated", content: "u" });
  const g = await rec({ actor: "model_generated", content: "g" });
  const o = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, prov_actor, prov_orphan)
     VALUES ('T','orf','sha-'||gen_random_uuid()::text,'model_distilled',true) RETURNING id`);
  await promoteRecords(pool);
  const tier = async (id) => (await pool.query("SELECT trust_tier FROM records WHERE id=$1",[id])).rows[0].trust_tier;
  assert.equal(await tier(u), "claimed");
  assert.equal(await tier(g), "unverified");
  assert.equal(await tier(o.rows[0].id), "unverified"); // orphaned distilled
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/run-mpg-test.sh test/promote.test.mjs`
Expected: FAIL — `../src/promote.mjs` does not exist (import error).

- [ ] **Step 3: Write the promotion module**

Create `apps/memory-pg/src/promote.mjs`:

```js
// promote.mjs — materialize trust tiers (design spec §2/§3). Idempotent + full-table,
// so it both promotes and demotes as supporting evidence changes.

// Session key: P1.5 writes metadata.session_id; historical uses metadata.provenance.session_id.
// Fall back to the record id so an unkeyed record is its own session (never falsely merged).
const SESSION_KEY =
  "COALESCE(NULLIF(r.metadata->>'session_id',''), r.metadata->'provenance'->>'session_id', r.id::text)";

/**
 * Recompute every fact's trust_tier from the count of INDEPENDENT user_stated supporters,
 * where independence = a distinct (session, day) pair. Resets first so it demotes too.
 * @param {import("pg").Pool} pool
 * @param {{knownSpanDays?: number}} [opts]
 */
export async function promoteFacts(pool, { knownSpanDays = 7 } = {}) {
  await pool.query(
    "UPDATE facts SET trust_tier = 'unverified', independent_user_sources = 0");
  await pool.query(
    `UPDATE facts f SET
       independent_user_sources = a.n,
       trust_tier = CASE
         WHEN a.n = 1 THEN 'claimed'
         WHEN a.span_days >= $1 THEN 'known'
         ELSE 'corroborated'
       END
     FROM (
       SELECT fact_id,
              COUNT(*)                         AS n,
              MAX(day) - MIN(day)              AS span_days
         FROM (
           SELECT DISTINCT fs.fact_id, ${SESSION_KEY} AS sess, r.created_at::date AS day
             FROM fact_supports fs
             JOIN records r ON r.id = fs.source_record_id
            WHERE r.prov_actor = 'user_stated'
         ) distinct_pairs
        GROUP BY fact_id
     ) a
     WHERE f.id = a.fact_id`,
    [knownSpanDays],
  );
}

/**
 * Give every record a base tier from its own provenance (no corroboration counting):
 * orphaned distilled or model_generated/system → unverified; user_stated / external_import /
 * non-orphan distilled → claimed. The quorum (corroborated/known) lives on facts.
 * @param {import("pg").Pool} pool
 */
export async function promoteRecords(pool) {
  await pool.query(
    `UPDATE records SET trust_tier = CASE
       WHEN prov_orphan THEN 'unverified'
       WHEN prov_actor IN ('user_stated','external_import','model_distilled') THEN 'claimed'
       ELSE 'unverified'
     END`);
}

export default { promoteFacts, promoteRecords };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/run-mpg-test.sh test/promote.test.mjs`
Expected: PASS (5 tests green).

- [ ] **Step 5: Commit**

```bash
cd /home/devsounio/beagle
git add apps/memory-pg/src/promote.mjs apps/memory-pg/test/promote.test.mjs
git commit -m "feat(memory-pg): trust-tier promotion with independence-counted quorum"
```

---

### Task 3: Graph extractor records every fact support

**Files:**
- Modify: `apps/memory-pg/src/graph-extract.mjs` (after the facts INSERT)
- Test: `apps/memory-pg/test/graph-supports.test.mjs`

Each extraction must write a `fact_supports(fact_id, source_record_id)` row — including when the fact already existed (dedup), which is exactly the corroboration we must not lose. After the `ON CONFLICT DO NOTHING RETURNING id` insert, resolve the fact id (returned, or looked up by `content_sha256` on conflict), then upsert the support.

- [ ] **Step 1: Write the failing test**

Create `apps/memory-pg/test/graph-supports.test.mjs`:

```js
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { applyExtraction } from "../src/graph-extract.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records, chunks, entities, facts, fact_supports CASCADE"); });
after(async () => { await pool.end(); });

async function mkRecord(content) {
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, prov_actor)
     VALUES ('T', $1, 'sha-'||gen_random_uuid()::text, 'user_stated') RETURNING id`, [content]);
  return r.rows[0].id;
}

// Same shape the existing graph-extract.test.mjs uses: { entities, facts } where each fact
// is { subject, predicate, object, statement }. applyExtraction resolves entities + embeddings
// internally; opts carries the recordId we want recorded as the support.
const extraction = {
  entities: [{ name: "Demetrios", type: "person" }],
  facts: [{ subject: "Demetrios", predicate: "likes", object: "moss green",
            statement: "Demetrios likes moss green" }],
};

test("two records asserting the SAME fact yield ONE fact but TWO supports", async () => {
  const r1 = await mkRecord("first mention");
  const r2 = await mkRecord("second mention");
  await applyExtraction(pool, extraction, { recordId: r1 });
  await applyExtraction(pool, extraction, { recordId: r2 });

  const nFacts = (await pool.query("SELECT count(*) FROM facts")).rows[0].count;
  const nSupports = (await pool.query("SELECT count(*) FROM fact_supports")).rows[0].count;
  assert.equal(nFacts, "1");    // deduped on the claim hash
  assert.equal(nSupports, "2"); // but BOTH sources are recorded
});
```

NOTE for the implementer: `applyExtraction(pool, { entities, facts }, { recordId })` is the real exported function (mirror the existing `test/graph-extract.test.mjs` usage). If a different embedding/opt shape is required, match that file — keep the assertions (1 fact, 2 supports).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/run-mpg-test.sh test/graph-supports.test.mjs`
Expected: FAIL — `fact_supports` count is 0 (the extractor does not write supports yet).

- [ ] **Step 3: Add the support write**

In `apps/memory-pg/src/graph-extract.mjs`, after the `const ins = await client.query(\`INSERT INTO facts ... ON CONFLICT (content_sha256) DO NOTHING RETURNING id\`, [...])` call and BEFORE `await client.query("COMMIT")`, add:

```js
      // Record the source→claim support for the quorum, even when the fact already
      // existed (rowCount 0). This is the corroboration multiplicity the dedup discards.
      const factId = ins.rowCount > 0
        ? ins.rows[0].id
        : (await client.query("SELECT id FROM facts WHERE content_sha256 = $1", [content_sha256])).rows[0]?.id;
      if (factId && recordId) {
        await client.query(
          `INSERT INTO fact_supports (fact_id, source_record_id)
           VALUES ($1, $2) ON CONFLICT (fact_id, source_record_id) DO NOTHING`,
          [factId, recordId],
        );
      }
```

(`recordId` and `content_sha256` are already in scope in this block — confirm the variable names when you read the file and match them.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/run-mpg-test.sh test/graph-supports.test.mjs`
Expected: PASS (1 fact, 2 supports).

- [ ] **Step 5: No regression in graph tests**

Run: `bash /tmp/run-mpg-test.sh test/graph-extract.test.mjs test/graph.test.mjs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/devsounio/beagle
git add apps/memory-pg/src/graph-extract.mjs apps/memory-pg/test/graph-supports.test.mjs
git commit -m "feat(memory-pg): graph extractor records every fact support (quorum multiplicity)"
```

---

### Task 4: Backfill `fact_supports` + promotion runner

**Files:**
- Create: `apps/memory-pg/src/trust-backfill.mjs`
- Create: `apps/memory-pg/bin/promote-worker.mjs`
- Test: `apps/memory-pg/test/trust-backfill.test.mjs`

`backfillFactSupports` seeds one support per existing fact from its `source_record_id` (the only source the dedup kept). `bin/promote-worker.mjs` backfills then runs the promotion once (extend to a loop later if desired).

- [ ] **Step 1: Write the failing test**

Create `apps/memory-pg/test/trust-backfill.test.mjs`:

```js
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { backfillFactSupports } from "../src/trust-backfill.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records, chunks, entities, facts, fact_supports CASCADE"); });
after(async () => { await pool.end(); });

test("backfill seeds one support per existing fact from its source_record_id, idempotently", async () => {
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, prov_actor)
     VALUES ('T','x','sha-'||gen_random_uuid()::text,'user_stated') RETURNING id`);
  const e = await pool.query(
    `INSERT INTO entities (name, norm_name, type, content_sha256)
     VALUES ('D','d','person','e-'||gen_random_uuid()::text) RETURNING id`);
  await pool.query(
    `INSERT INTO facts (subject_id, predicate, object_literal, source_record_id, content_sha256)
     VALUES ($1,'likes','green',$2,'f-'||gen_random_uuid()::text)`,
    [e.rows[0].id, r.rows[0].id]);
  // a fact with NULL source_record_id must be skipped (no record to attribute it to)
  await pool.query(
    `INSERT INTO facts (subject_id, predicate, object_literal, content_sha256)
     VALUES ($1,'knows','nobody','f-'||gen_random_uuid()::text)`, [e.rows[0].id]);

  const first = await backfillFactSupports(pool);
  const second = await backfillFactSupports(pool);
  assert.equal(first.inserted, 1);   // only the fact with a source
  assert.equal(second.inserted, 0);  // idempotent
  assert.equal((await pool.query("SELECT count(*) FROM fact_supports")).rows[0].count, "1");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/run-mpg-test.sh test/trust-backfill.test.mjs`
Expected: FAIL — `../src/trust-backfill.mjs` does not exist.

- [ ] **Step 3: Write the backfill module**

Create `apps/memory-pg/src/trust-backfill.mjs`:

```js
// trust-backfill.mjs — seed fact_supports for facts created before P2, from the single
// source the dedup kept (facts.source_record_id). Idempotent (ON CONFLICT DO NOTHING).

/**
 * @param {import("pg").Pool} pool
 * @returns {Promise<{inserted: number}>}
 */
export async function backfillFactSupports(pool) {
  const res = await pool.query(
    `INSERT INTO fact_supports (fact_id, source_record_id)
     SELECT id, source_record_id FROM facts
      WHERE source_record_id IS NOT NULL
     ON CONFLICT (fact_id, source_record_id) DO NOTHING`);
  return { inserted: res.rowCount };
}

export default backfillFactSupports;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/run-mpg-test.sh test/trust-backfill.test.mjs`
Expected: PASS.

- [ ] **Step 5: Write the worker entrypoint**

Create `apps/memory-pg/bin/promote-worker.mjs`:

```js
#!/usr/bin/env node
// One-shot: seed fact_supports from existing facts, then recompute all trust tiers.
//   MEMORY_PG_DSN=... node bin/promote-worker.mjs
import { makePool } from "../src/db.mjs";
import { backfillFactSupports } from "../src/trust-backfill.mjs";
import { promoteFacts, promoteRecords } from "../src/promote.mjs";

const pool = makePool();
try {
  const bf = await backfillFactSupports(pool);
  await promoteRecords(pool);
  await promoteFacts(pool);
  const dist = await pool.query(
    "SELECT trust_tier, count(*) FROM facts GROUP BY 1 ORDER BY 2 DESC");
  console.log(`promote-worker: backfilled ${bf.inserted} supports`);
  for (const r of dist.rows) console.log(`  facts ${r.trust_tier}: ${r.count}`);
} finally {
  await pool.end();
}
```

- [ ] **Step 6: Commit**

```bash
cd /home/devsounio/beagle
git add apps/memory-pg/src/trust-backfill.mjs apps/memory-pg/bin/promote-worker.mjs apps/memory-pg/test/trust-backfill.test.mjs
git commit -m "feat(memory-pg): fact_supports backfill + promote-worker entrypoint"
```

---

### Task 5: Deploy + live promotion

**Files:** none (operational — the orchestrator runs this).

- [ ] **Step 1: Rebuild the shared memory-pg image** with the new `src/` + `bin/` (via buildah overlay on t560, as for P1.5: `buildah --root /tmp/bstore from memory-pg-embed-worker:v4`, `copy src /app/src`, `copy bin /app/bin`, `copy sql /app/sql`, commit + push as `memory-pg-embed-worker:p2-<sha>`).
- [ ] **Step 2: Roll `memory-pg-graph-worker`** to the new image (so live extractions write `fact_supports` going forward).
- [ ] **Step 3: Apply migration + run the promotion once** against the live `memory` DB: `MEMORY_PG_DSN=... node bin/promote-worker.mjs` (it calls ensureSchema indirectly via the workers, or apply 006 first like P1). Expect it to backfill ~372K supports and print the fact tier distribution.
- [ ] **Step 4: Verify** the distribution is sane: most historical facts `unverified` or `claimed` (single source), a small set `corroborated`/`known` only where genuinely multi-session/day. Spot-check:
```sql
SELECT trust_tier, count(*) FROM facts GROUP BY 1 ORDER BY 2 DESC;
SELECT trust_tier, count(*) FROM records WHERE prov_surface='companion-ios' GROUP BY 1;
```

## Self-review (P2 → spec coverage)

- Spec §2 tiers + independence rule → Task 2 (`promoteFacts`, distinct `(session, day)`).
- Spec §3 promotion job + fact provenance via supporting records → Tasks 2–4 (`fact_supports` + the JOIN to `records.prov_actor`).
- Spec §3 "fact tier = min tier of supporting records" → realized more precisely as: tier = function of the COUNT of independent user_stated supporters (the operational form of the same intent).
- Spec §4 trust-weighted recall + grounding enforcement → **P3** (separate plan): the companion/bridge read `trust_tier` to assert (`known`/`corroborated`), hedge (`claimed`), or exclude (`unverified`).
- Independence simplification noted: "distinct session AND day" is implemented as distinct `(session, day)` PAIRS — kills same-session amplification (the primary goal); tunable in review.
