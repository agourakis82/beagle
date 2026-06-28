# Memory Provenance — Phase 1 (memory-pg foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every `memory-pg` record a provenance stamp (who asserted it + what it derives from) and flag distilled records that have no user-stated ancestor, so model fiction can never silently enter the biography — plus a one-shot heuristic backfill of the existing ~83K records.

**Architecture:** Additive, idempotent SQL migration adds `prov_*` columns to `records`. The single ACID write path `captureRecord` (src/capture.mjs) accepts and persists provenance and computes a `prov_orphan` flag (a `model_distilled` record whose `derived_from` contains no `user_stated`/`external_import` ancestor is orphaned). A standalone idempotent script classifies the historical corpus by `source_type`. All Node, all testable against a live memory-pg via `MEMORY_PG_TEST_DSN`.

**Tech Stack:** Node ESM (`.mjs`), `node:test` (`node --test --test-concurrency=1`), `pg` (node-postgres), Postgres 16 + pgvector. Schema applied by `ensureSchema` (src/db.mjs) running `sql/*.sql` in lexical order, idempotently.

**Scope note — what is deliberately NOT in P1:** the *upstream* write-path taggers (the cockpit distill in `apps/project-cockpit/server/memory-ingest.mjs` sending `actor=model_distilled` + `derived_from`, and beagle-core forwarding the actor on its dual-write to memory-pg `/capture`) are **P1.5** — they cross into the Rust service and need their own grounding. P1 builds the foundation those taggers will use: once any writer sends `prov_actor=model_distilled` without a real ancestor, `captureRecord` already flags it. P2 (quorum tiering) and P3 (trust-weighted recall) follow per the design spec `docs/superpowers/specs/2026-06-27-memory-provenance-trust-design.md`.

**Pre-req for running tests — USE A SCRATCH DATABASE, NOT THE LIVE CORPUS.**
Tasks 2–4 `TRUNCATE records CASCADE` and run a global backfill `UPDATE`; pointing them at
the live `memory` DB would wipe/rewrite the ~83K-record corpus. Create a disposable DB
whose name contains `test` and point the tests at it:

```bash
kubectl -n beagle port-forward svc/memory-pg 5432:5432 &
PGPASSWORD=$(kubectl -n beagle exec memory-pg-0 -- printenv POSTGRES_PASSWORD)
psql "postgres://memory:$PGPASSWORD@127.0.0.1:5432/memory" -c "CREATE DATABASE memory_test OWNER memory;"
export MEMORY_PG_TEST_DSN="postgres://memory:$PGPASSWORD@127.0.0.1:5432/memory_test"
```

Every destructive test file below begins with a guard that **refuses to run** unless the
DSN's database name contains `test`, so a mis-set DSN can never nuke production.

---

### Task 1: Provenance migration on `records`

**Files:**
- Create: `apps/memory-pg/sql/004_provenance.sql`
- Test: `apps/memory-pg/test/provenance-schema.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `apps/memory-pg/test/provenance-schema.test.mjs`:

```js
// Asserts the provenance migration adds the prov_* columns + actor CHECK to records.
// Runs against a live memory-pg (DSN via MEMORY_PG_TEST_DSN).
import { test } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
// Safety: these tests mutate/TRUNCATE records — refuse to touch a non-scratch DB.
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

test("records has the prov_* columns with correct types/defaults", async () => {
  await ensureSchema(pool);
  const cols = await pool.query(
    `SELECT column_name, data_type, column_default, is_nullable
       FROM information_schema.columns
      WHERE table_name = 'records' AND column_name LIKE 'prov_%'
      ORDER BY column_name`,
  );
  const byName = Object.fromEntries(cols.rows.map((r) => [r.column_name, r]));
  assert.equal(byName.prov_actor.is_nullable, "NO");
  assert.match(byName.prov_actor.column_default, /model_generated/);
  assert.equal(byName.prov_derived_from.data_type, "ARRAY");
  assert.equal(byName.prov_orphan.data_type, "boolean");
  assert.ok(byName.prov_confidence, "prov_confidence column exists");
  assert.ok(byName.prov_surface, "prov_surface column exists");
  assert.ok(byName.prov_asserted_at, "prov_asserted_at column exists");
});

test("records_prov_actor_chk rejects an actor outside the taxonomy", async () => {
  await ensureSchema(pool);
  await assert.rejects(
    pool.query(
      `INSERT INTO records (source_type, content, content_sha256, prov_actor)
       VALUES ('TestPassage', 'x', 'sha-bad-actor-' || gen_random_uuid()::text, 'gossip')`,
    ),
    /records_prov_actor_chk|check constraint/i,
  );
});

test.after(async () => { await pool.end(); });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/provenance-schema.test.mjs`
Expected: FAIL — the `prov_*` columns do not exist yet (the column query returns 0 rows; `byName.prov_actor` is undefined → throws).

- [ ] **Step 3: Write the migration**

Create `apps/memory-pg/sql/004_provenance.sql`:

```sql
-- 004_provenance.sql
-- P1: per-record provenance (design spec 2026-06-27-memory-provenance-trust).
-- Additive + idempotent (IF NOT EXISTS). prov_actor defaults to the conservative
-- 'model_generated' so existing rows and untagged writers never auto-enter biography.

ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_actor text NOT NULL DEFAULT 'model_generated';
ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_surface text;
ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_derived_from uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_confidence real;
ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_asserted_at timestamptz;
ALTER TABLE records ADD COLUMN IF NOT EXISTS prov_orphan boolean NOT NULL DEFAULT false;

-- Closed actor taxonomy. Drop-then-add so re-running picks up any edit idempotently.
ALTER TABLE records DROP CONSTRAINT IF EXISTS records_prov_actor_chk;
ALTER TABLE records ADD CONSTRAINT records_prov_actor_chk
  CHECK (prov_actor IN ('user_stated','model_generated','model_distilled','external_import','system'));

CREATE INDEX IF NOT EXISTS records_prov_actor_idx ON records (prov_actor);
CREATE INDEX IF NOT EXISTS records_prov_orphan_idx ON records (prov_orphan) WHERE prov_orphan;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/provenance-schema.test.mjs`
Expected: PASS — both tests green (columns present; bad actor rejected by the CHECK).

- [ ] **Step 5: Commit**

```bash
git add apps/memory-pg/sql/004_provenance.sql apps/memory-pg/test/provenance-schema.test.mjs
git commit -m "feat(memory-pg): provenance columns on records (P1 migration)"
```

---

### Task 2: `captureRecord` accepts and persists provenance

**Files:**
- Modify: `apps/memory-pg/src/capture.mjs` (the `captureRecord` destructure + the records INSERT)
- Test: `apps/memory-pg/test/provenance-capture.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `apps/memory-pg/test/provenance-capture.test.mjs`:

```js
// captureRecord persists provenance; defaults to model_generated; validates the actor.
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { captureRecord } from "../src/capture.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
// Safety: these tests mutate/TRUNCATE records — refuse to touch a non-scratch DB.
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records CASCADE"); });
after(async () => { await pool.end(); });

test("user_stated provenance is persisted", async () => {
  const { id } = await captureRecord(pool, {
    source_type: "TestPassage",
    content: "I run every morning before work.",
    prov_actor: "user_stated",
    prov_surface: "companion-ios",
    prov_confidence: 1.0,
  });
  const row = (await pool.query(
    "SELECT prov_actor, prov_surface, prov_confidence FROM records WHERE id = $1", [id],
  )).rows[0];
  assert.equal(row.prov_actor, "user_stated");
  assert.equal(row.prov_surface, "companion-ios");
  assert.equal(row.prov_confidence, 1);
});

test("absent provenance defaults to model_generated", async () => {
  const { id } = await captureRecord(pool, { source_type: "TestPassage", content: "untagged content" });
  const row = (await pool.query("SELECT prov_actor FROM records WHERE id = $1", [id])).rows[0];
  assert.equal(row.prov_actor, "model_generated");
});

test("an invalid actor is rejected before any write", async () => {
  await assert.rejects(
    captureRecord(pool, { source_type: "TestPassage", content: "x", prov_actor: "rumor" }),
    /invalid prov_actor/,
  );
  const n = (await pool.query("SELECT count(*) FROM records")).rows[0].count;
  assert.equal(n, "0");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/provenance-capture.test.mjs`
Expected: FAIL — `captureRecord` ignores `prov_actor` (column stays at the DB default for the persisted test, and the invalid-actor test does not throw).

- [ ] **Step 3: Implement provenance in `captureRecord`**

In `apps/memory-pg/src/capture.mjs`, replace the destructure block at the top of `captureRecord` (currently `const { source_type, content, metadata = {}, occurred_at = null, privacy_class = "sensitive", decay_class = "identity" } = rec;`) with:

```js
  const {
    source_type,
    content,
    metadata = {},
    occurred_at = null,
    privacy_class = "sensitive",
    decay_class = "identity",
    prov_actor = "model_generated",
    prov_surface = null,
    prov_derived_from = [],
    prov_confidence = null,
    prov_asserted_at = null,
  } = rec;

  const VALID_ACTORS = new Set([
    "user_stated", "model_generated", "model_distilled", "external_import", "system",
  ]);
  if (!VALID_ACTORS.has(prov_actor)) {
    throw new Error(`captureRecord: invalid prov_actor ${prov_actor}`);
  }
```

Then replace the records INSERT (the `INSERT INTO records (source_type, content, metadata, occurred_at, content_sha256, privacy_class, decay_class) VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7) ON CONFLICT ...` call) with:

```js
    const ins = await client.query(
      `INSERT INTO records
         (source_type, content, metadata, occurred_at, content_sha256, privacy_class, decay_class,
          prov_actor, prov_surface, prov_derived_from, prov_confidence, prov_asserted_at)
       VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7, $8, $9, $10::uuid[], $11, $12)
       ON CONFLICT (content_sha256) DO NOTHING
       RETURNING id`,
      [
        source_type,
        safeContent,
        JSON.stringify(safeMetadata),
        occurred_at,
        content_sha256,
        privacy_class,
        decay_class,
        prov_actor,
        prov_surface,
        prov_derived_from,
        prov_confidence,
        prov_asserted_at,
      ],
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/provenance-capture.test.mjs`
Expected: PASS — all three tests green.

- [ ] **Step 5: Run the existing capture test to confirm no regression**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/capture.test.mjs`
Expected: PASS — the additive params are all optional; existing behaviour unchanged.

- [ ] **Step 6: Commit**

```bash
git add apps/memory-pg/src/capture.mjs apps/memory-pg/test/provenance-capture.test.mjs
git commit -m "feat(memory-pg): captureRecord persists + validates provenance"
```

---

### Task 3: Flag distilled orphans at write time

**Files:**
- Modify: `apps/memory-pg/src/capture.mjs` (inside the transaction, before the records INSERT)
- Test: `apps/memory-pg/test/provenance-orphan.test.mjs`

The rule (design spec §1): a `model_distilled` record whose `prov_derived_from` contains **no** `user_stated` or `external_import` ancestor is an orphan. This is the mechanism that would have caught the Teobaldo amplification — distilled atoms with no genuine user origin are flagged and (in P3) excluded from biography.

- [ ] **Step 1: Write the failing test**

Create `apps/memory-pg/test/provenance-orphan.test.mjs`:

```js
// A model_distilled record is flagged prov_orphan unless an ancestor is user_stated/external_import.
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { captureRecord } from "../src/capture.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
// Safety: these tests mutate/TRUNCATE records — refuse to touch a non-scratch DB.
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records CASCADE"); });
after(async () => { await pool.end(); });

async function orphanOf(id) {
  return (await pool.query("SELECT prov_orphan FROM records WHERE id = $1", [id])).rows[0].prov_orphan;
}

test("distilled atom with a user_stated ancestor is NOT an orphan", async () => {
  const src = await captureRecord(pool, {
    source_type: "TestPassage", content: "I have run marathons since 2015.", prov_actor: "user_stated",
  });
  const atom = await captureRecord(pool, {
    source_type: "TestAtom", content: "Demetrios is a long-distance runner.",
    prov_actor: "model_distilled", prov_derived_from: [src.id],
  });
  assert.equal(await orphanOf(atom.id), false);
});

test("distilled atom with NO user-stated ancestor IS an orphan (the Teobaldo class)", async () => {
  const asst = await captureRecord(pool, {
    source_type: "TestPassage", content: "The assistant invented a detail here.", prov_actor: "model_generated",
  });
  const atom = await captureRecord(pool, {
    source_type: "TestAtom", content: "Fabricated intimate fact.",
    prov_actor: "model_distilled", prov_derived_from: [asst.id],
  });
  assert.equal(await orphanOf(atom.id), true);
});

test("distilled atom with empty derived_from IS an orphan", async () => {
  const atom = await captureRecord(pool, {
    source_type: "TestAtom", content: "Floating claim, no source.", prov_actor: "model_distilled",
  });
  assert.equal(await orphanOf(atom.id), true);
});

test("non-distilled actors are never orphaned", async () => {
  const r = await captureRecord(pool, {
    source_type: "TestPassage", content: "A plain user statement.", prov_actor: "user_stated",
  });
  assert.equal(await orphanOf(r.id), false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/provenance-orphan.test.mjs`
Expected: FAIL — `prov_orphan` is always the column default `false`; the two orphan cases assert `true` and fail.

- [ ] **Step 3: Implement the orphan check**

In `apps/memory-pg/src/capture.mjs`, inside `captureRecord`, after `await client.query("BEGIN");` and before the records INSERT, add:

```js
    // Orphan check (design spec §1): a distilled record with no user_stated /
    // external_import ancestor cannot be trusted as biography. Computed inside the
    // txn so the flag is consistent with the ancestors that exist at write time.
    let prov_orphan = false;
    if (prov_actor === "model_distilled") {
      if (!Array.isArray(prov_derived_from) || prov_derived_from.length === 0) {
        prov_orphan = true;
      } else {
        const anc = await client.query(
          `SELECT 1 FROM records
            WHERE id = ANY($1::uuid[])
              AND prov_actor IN ('user_stated', 'external_import')
            LIMIT 1`,
          [prov_derived_from],
        );
        prov_orphan = anc.rowCount === 0;
      }
    }
```

Then add `prov_orphan` to the records INSERT from Task 2 — change the column list to end with `prov_asserted_at, prov_orphan)`, the VALUES to `... $12, $13)`, and append `prov_orphan` to the params array after `prov_asserted_at`:

```js
    const ins = await client.query(
      `INSERT INTO records
         (source_type, content, metadata, occurred_at, content_sha256, privacy_class, decay_class,
          prov_actor, prov_surface, prov_derived_from, prov_confidence, prov_asserted_at, prov_orphan)
       VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7, $8, $9, $10::uuid[], $11, $12, $13)
       ON CONFLICT (content_sha256) DO NOTHING
       RETURNING id`,
      [
        source_type, safeContent, JSON.stringify(safeMetadata), occurred_at, content_sha256,
        privacy_class, decay_class, prov_actor, prov_surface, prov_derived_from,
        prov_confidence, prov_asserted_at, prov_orphan,
      ],
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/provenance-orphan.test.mjs`
Expected: PASS — all four tests green.

- [ ] **Step 5: Commit**

```bash
git add apps/memory-pg/src/capture.mjs apps/memory-pg/test/provenance-orphan.test.mjs
git commit -m "feat(memory-pg): flag distilled orphans at write time"
```

---

### Task 4: One-shot heuristic backfill of the historical corpus

**Files:**
- Create: `apps/memory-pg/src/prov-backfill.mjs`
- Create: `apps/memory-pg/bin/prov-backfill.mjs`
- Test: `apps/memory-pg/test/prov-backfill.test.mjs`

Classification (grounded in the live corpus: `source_type` ∈ {`ConversationPassage` 52K, `MemoryAtom` 19.6K, `MemoryEpisode` 10.7K}; roles are not recoverable from `metadata`, so conversation turns stay conservative):
- `MemoryAtom` → `model_distilled` (distilled atoms).
- `MemoryEpisode` → `external_import` (migrated `omnimemory` imports).
- everything else (incl. `ConversationPassage`) → leave at the migration default `model_generated`.

Only rows still at the default are touched, so re-running is idempotent and never overwrites forward-path tags.

- [ ] **Step 1: Write the failing test**

Create `apps/memory-pg/test/prov-backfill.test.mjs`:

```js
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { captureRecord } from "../src/capture.mjs";
import { backfillProvenance } from "../src/prov-backfill.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch memory-pg DSN)");
// Safety: these tests mutate/TRUNCATE records — refuse to touch a non-scratch DB.
if (!/\/[^/]*test[^/]*$/i.test(DSN)) {
  throw new Error("Refusing to run: MEMORY_PG_TEST_DSN must point to a scratch DB whose name contains 'test'");
}
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records CASCADE"); });
after(async () => { await pool.end(); });

async function actorOf(id) {
  return (await pool.query("SELECT prov_actor FROM records WHERE id = $1", [id])).rows[0].prov_actor;
}

test("MemoryAtom → model_distilled, MemoryEpisode → external_import, Passage stays default", async () => {
  const atom = await captureRecord(pool, { source_type: "MemoryAtom", content: "atom one" });
  const epi = await captureRecord(pool, { source_type: "MemoryEpisode", content: "episode one" });
  const pass = await captureRecord(pool, { source_type: "ConversationPassage", content: "passage one" });

  const res = await backfillProvenance(pool);

  assert.equal(await actorOf(atom.id), "model_distilled");
  assert.equal(await actorOf(epi.id), "external_import");
  assert.equal(await actorOf(pass.id), "model_generated");
  assert.equal(res.distilled, 1);
  assert.equal(res.imported, 1);
});

test("backfill never overwrites a forward-path user_stated tag and is idempotent", async () => {
  const u = await captureRecord(pool, {
    source_type: "MemoryAtom", content: "already tagged", prov_actor: "user_stated",
  });
  const first = await backfillProvenance(pool);
  const second = await backfillProvenance(pool);
  assert.equal(await actorOf(u.id), "user_stated"); // untouched (not at default)
  assert.equal(second.distilled, 0); // nothing left at default to change
  assert.equal(second.imported, 0);
  assert.equal(typeof first.distilled, "number");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/prov-backfill.test.mjs`
Expected: FAIL — `../src/prov-backfill.mjs` does not exist (import error).

- [ ] **Step 3: Write the backfill module**

Create `apps/memory-pg/src/prov-backfill.mjs`:

```js
// prov-backfill.mjs — one-shot, idempotent heuristic classification of historical
// records' provenance actor. Only touches rows still at the conservative migration
// default ('model_generated'), so forward-path tags are never overwritten and
// re-running is a no-op. See design spec 2026-06-27-memory-provenance-trust §5.

/**
 * Classify existing records' prov_actor by source_type.
 * @param {import("pg").Pool} pool
 * @returns {Promise<{distilled: number, imported: number}>}
 */
export async function backfillProvenance(pool) {
  const distilled = await pool.query(
    `UPDATE records SET prov_actor = 'model_distilled'
      WHERE source_type = 'MemoryAtom' AND prov_actor = 'model_generated'`,
  );
  const imported = await pool.query(
    `UPDATE records SET prov_actor = 'external_import'
      WHERE source_type = 'MemoryEpisode' AND prov_actor = 'model_generated'`,
  );
  return { distilled: distilled.rowCount, imported: imported.rowCount };
}

export default backfillProvenance;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/prov-backfill.test.mjs`
Expected: PASS — both tests green.

- [ ] **Step 5: Write the runnable entrypoint**

Create `apps/memory-pg/bin/prov-backfill.mjs`:

```js
#!/usr/bin/env node
// Entry point: classify historical record provenance once. Idempotent.
//   MEMORY_PG_DSN=... node bin/prov-backfill.mjs
import { makePool } from "../src/db.mjs";
import { backfillProvenance } from "../src/prov-backfill.mjs";

const pool = makePool();
try {
  const res = await backfillProvenance(pool);
  console.log(`prov-backfill: model_distilled=${res.distilled} external_import=${res.imported}`);
} finally {
  await pool.end();
}
```

- [ ] **Step 6: Commit**

```bash
git add apps/memory-pg/src/prov-backfill.mjs apps/memory-pg/bin/prov-backfill.mjs apps/memory-pg/test/prov-backfill.test.mjs
git commit -m "feat(memory-pg): one-shot heuristic provenance backfill of historical records"
```

---

## Deployment (after all tasks pass)

1. The migration auto-applies on the next `memory-pg-serve` start (it calls `ensureSchema`), or run it explicitly:
   `MEMORY_PG_DSN=... node -e "import('./src/db.mjs').then(m=>{const p=m.makePool();return m.ensureSchema(p).then(()=>p.end())})"`.
2. Run the historical backfill once: `MEMORY_PG_DSN=... node bin/prov-backfill.mjs` → expect roughly `model_distilled=19599 external_import=10741`.
3. Verify: `SELECT prov_actor, count(*) FROM records GROUP BY 1;` shows the three classes; `SELECT count(*) FROM records WHERE prov_orphan;` is 0 (no distilled orphans written yet — they arrive once P1.5 tags the distill).

## Self-review note (P1 → spec coverage)

- Spec §1 provenance fields → Task 1 (columns) + Task 2 (write).
- Spec §1 orphan invariant → Task 3.
- Spec §5 backfill → Task 4.
- Spec §2 tiers, §3 promotion, §4 trust-weighted recall → **P2/P3** (separate plans).
- Spec "write-path tagging" (cockpit distill + beagle-core forward) → **P1.5** (separate plan; crosses into Rust). P1 makes the foundation ready: the moment those taggers send `model_distilled`, Task 3's check flags orphans.
