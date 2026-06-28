# Memory Provenance — Phase 1.5 (companion write-path tagging) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the companion's personal turns land in the canonical memory-pg store **provenance-tagged at the source** — the user turn as `user_stated`, the assistant turn as `model_generated`, and each distilled atom as `model_distilled` linked (`prov_derived_from`) to the user turn — so a fabricated atom with no real user source is flagged orphan and never laundered into biography (the path that produced the Teobaldo incident).

**Architecture:** The cockpit already reaches `memory-pg-serve` (it queries `/query` for recall). P1.5 adds a small provenance-aware capture endpoint to `memory-pg-serve` and has the cockpit's `ingestPersonalTurn` write the personal turns + atoms directly to it with full provenance. `captureRecord` (P1) does the rest: validates the actor, computes the orphan flag, dedups on content hash. The existing beagle-core `ingest_chat` path is kept in parallel (it feeds the Claude Desktop bridge); dedup means the provenance-tagged write is authoritative on the canonical store.

**Tech Stack:** Node ESM (`.mjs`), `node:test`. memory-pg-serve = Express (`apps/memory-pg/bin/serve.mjs`, `createApp(deps)` with injectable `captureFn`/`embedFn`/`rerankFn`). Cockpit ingest = `apps/project-cockpit/server/memory-ingest.mjs`. **All P1.5 tests are dependency-injected — no database and no port-forward needed.** Run cockpit tests with `cd apps/project-cockpit && node --test --test-concurrency=1 server/<file>.test.mjs`; memory-pg tests with `cd apps/memory-pg && node --test --test-concurrency=1 test/<file>.test.mjs`.

**Grounded facts:**
- `memory-pg-serve` `/capture` is export-shaped (`{kind, record}`, stamps `migrated_from`), so P1.5 adds a clean sibling route instead of overloading it.
- `ingestAuthed(req)` returns `true` when `ingestToken` is unset; the live `memory-pg-serve` deploy has NO `MEMORY_PG_INGEST_TOKEN`, so in-cluster capture is open (no token wiring needed). The new route still honors `ingestToken` if ever set.
- The cockpit reaches memory-pg via `process.env.MEMORY_PG_QUERY_URL || "http://memory-pg-serve.beagle.svc.cluster.local"` (already used in `auth-bridge.mjs`).
- `captureRecord` (P1) already accepts `prov_actor`, `prov_surface`, `prov_derived_from`, `prov_confidence` and computes `prov_orphan`. The default `captureFn` in `createApp` passes the whole record object straight to `captureRecord`, so provenance fields flow through unchanged.

---

### Task 1: Provenance-aware capture endpoint on memory-pg-serve

**Files:**
- Modify: `apps/memory-pg/bin/serve.mjs` (add a `POST /capture_turn` route inside `createApp`, next to `POST /capture`)
- Test: `apps/memory-pg/test/capture-turn.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `apps/memory-pg/test/capture-turn.test.mjs`:

```js
// /capture_turn persists ONE provenance-tagged record. DI'd: a stub captureFn records
// the records handed to it, so we assert provenance pass-through without a database.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../bin/serve.mjs";

function mkStubs() {
  const seen = [];
  const captureFn = async (recs) => {
    seen.push(...recs);
    return recs.map((_, i) => ({ id: `rec-${i}`, created: true, chunk_count: 1 }));
  };
  return {
    seen,
    deps: {
      pool: {},
      embedFn: async () => [[0.1]],
      rerankFn: async () => [],
      captureFn,
    },
  };
}

function listen(app) {
  return new Promise((resolve) => { const s = app.listen(0, () => resolve(s)); });
}
async function jpost(base, path, body) {
  return fetch(base + path, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
  });
}

test("POST /capture_turn passes provenance through to captureRecord and returns the id", async () => {
  const { seen, deps } = mkStubs();
  const app = createApp(deps);
  const s = await listen(app);
  const base = `http://127.0.0.1:${s.address().port}`;
  try {
    const r = await jpost(base, "/capture_turn", {
      source_type: "MemoryAtom",
      content: "Demetrios runs marathons.",
      prov_actor: "model_distilled",
      prov_surface: "companion-ios",
      prov_derived_from: ["11111111-1111-1111-1111-111111111111"],
      prov_confidence: 0.7,
      metadata: { space: "personal" },
    });
    assert.equal(r.status, 200);
    const body = await r.json();
    assert.equal(body.id, "rec-0");
    assert.equal(body.created, true);
    assert.equal(seen.length, 1);
    assert.equal(seen[0].source_type, "MemoryAtom");
    assert.equal(seen[0].prov_actor, "model_distilled");
    assert.deepEqual(seen[0].prov_derived_from, ["11111111-1111-1111-1111-111111111111"]);
    assert.equal(seen[0].prov_confidence, 0.7);
  } finally { s.close(); }
});

test("POST /capture_turn defaults actor to model_generated and derived_from to []", async () => {
  const { seen, deps } = mkStubs();
  const app = createApp(deps);
  const s = await listen(app);
  const base = `http://127.0.0.1:${s.address().port}`;
  try {
    await jpost(base, "/capture_turn", { source_type: "ConversationPassage", content: "hi" });
    assert.equal(seen[0].prov_actor, "model_generated");
    assert.deepEqual(seen[0].prov_derived_from, []);
  } finally { s.close(); }
});

test("POST /capture_turn rejects a missing source_type/content with 400", async () => {
  const { deps } = mkStubs();
  const app = createApp(deps);
  const s = await listen(app);
  const base = `http://127.0.0.1:${s.address().port}`;
  try {
    const r = await jpost(base, "/capture_turn", { content: "no source_type" });
    assert.equal(r.status, 400);
  } finally { s.close(); }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/capture-turn.test.mjs`
Expected: FAIL — `/capture_turn` does not exist (404 → `r.status` is 404, assertions fail).

- [ ] **Step 3: Add the route**

In `apps/memory-pg/bin/serve.mjs`, inside `createApp`, immediately AFTER the existing `app.post("/capture", ...)` route block and BEFORE `return app;`, add:

```js
  // Provenance-aware single-record capture. Unlike /capture (export-shaped), this takes
  // one clean record with explicit provenance and routes it straight through captureRecord
  // (which validates the actor + computes the orphan flag). Used by the companion to tag
  // its turns at the source: user_stated / model_generated / model_distilled(+derived_from).
  app.post("/capture_turn", async (req, res) => {
    if (!ingestAuthed(req)) return res.status(401).json({ error: "unauthorized" });
    const b = req.body || {};
    if (typeof b.source_type !== "string" || !b.source_type ||
        typeof b.content !== "string" || !b.content) {
      return res.status(400).json({ error: "source_type (string) and content (string) required" });
    }
    try {
      const rec = {
        source_type: b.source_type,
        content: b.content,
        occurred_at: b.occurred_at ?? null,
        metadata: (b.metadata && typeof b.metadata === "object") ? b.metadata : {},
        prov_actor: b.prov_actor ?? "model_generated",
        prov_surface: b.prov_surface ?? null,
        prov_derived_from: Array.isArray(b.prov_derived_from) ? b.prov_derived_from : [],
        prov_confidence: typeof b.prov_confidence === "number" ? b.prov_confidence : null,
      };
      const [out] = await captureFn([rec]);
      res.json({ id: out.id, created: out.created });
    } catch (e) {
      res.status(500).json({ error: String(e?.message || e) });
    }
  });
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/capture-turn.test.mjs`
Expected: PASS (3 tests green).

- [ ] **Step 5: Confirm no regression in serve tests**

Run: `cd apps/memory-pg && node --test --test-concurrency=1 test/serve.test.mjs`
Expected: PASS (the new route is additive).

- [ ] **Step 6: Commit**

```bash
cd /home/devsounio/beagle
git add apps/memory-pg/bin/serve.mjs apps/memory-pg/test/capture-turn.test.mjs
git commit -m "feat(memory-pg): provenance-aware /capture_turn endpoint"
```

---

### Task 2: `captureProvenanced` client helper in the cockpit

**Files:**
- Modify: `apps/project-cockpit/server/memory-ingest.mjs` (add an exported `captureProvenanced` function)
- Test: `apps/project-cockpit/server/memory-ingest-capture.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `apps/project-cockpit/server/memory-ingest-capture.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { captureProvenanced } from "./memory-ingest.mjs";

test("captureProvenanced POSTs the record to /capture_turn and returns {id, created}", async () => {
  let seenUrl, seenBody;
  const fetchImpl = async (url, opts) => {
    seenUrl = url; seenBody = JSON.parse(opts.body);
    return { ok: true, json: async () => ({ id: "rec-9", created: true }) };
  };
  const out = await captureProvenanced(
    { source_type: "MemoryAtom", content: "x", prov_actor: "model_distilled", prov_derived_from: ["u1"] },
    { memoryPgUrl: "http://memory-pg", fetchImpl },
  );
  assert.equal(seenUrl, "http://memory-pg/capture_turn");
  assert.equal(seenBody.prov_actor, "model_distilled");
  assert.deepEqual(seenBody.prov_derived_from, ["u1"]);
  assert.deepEqual(out, { id: "rec-9", created: true });
});

test("captureProvenanced is best-effort: returns null on !ok and never throws", async () => {
  const bad = await captureProvenanced({ source_type: "X", content: "y" }, {
    memoryPgUrl: "http://memory-pg", fetchImpl: async () => ({ ok: false, json: async () => ({}) }),
  });
  assert.equal(bad, null);
  const threw = await captureProvenanced({ source_type: "X", content: "y" }, {
    memoryPgUrl: "http://memory-pg", fetchImpl: async () => { throw new Error("down"); },
  });
  assert.equal(threw, null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test --test-concurrency=1 server/memory-ingest-capture.test.mjs`
Expected: FAIL — `captureProvenanced` is not exported (import yields undefined → call throws).

- [ ] **Step 3: Implement the helper**

In `apps/project-cockpit/server/memory-ingest.mjs`, add this exported function (place it after `ingestVerbatim`):

```js
/**
 * POST one provenance-tagged record to memory-pg-serve /capture_turn. Best-effort:
 * returns the {id, created} JSON, or null on any error/non-2xx (never throws — ingestion
 * must never affect the chat).
 * @param {{source_type:string, content:string, prov_actor?:string, prov_surface?:string,
 *          prov_derived_from?:string[], prov_confidence?:number, occurred_at?:string|null,
 *          metadata?:object}} rec
 */
export async function captureProvenanced(rec, { memoryPgUrl, fetchImpl = fetch, ingestToken, timeoutMs = 8000 } = {}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetchImpl(`${memoryPgUrl}/capture_turn`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(ingestToken ? { authorization: `Bearer ${ingestToken}` } : {}),
      },
      body: JSON.stringify(rec),
      signal: ctrl.signal,
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/project-cockpit && node --test --test-concurrency=1 server/memory-ingest-capture.test.mjs`
Expected: PASS (2 tests green).

- [ ] **Step 5: Commit**

```bash
cd /home/devsounio/beagle
git add apps/project-cockpit/server/memory-ingest.mjs apps/project-cockpit/server/memory-ingest-capture.test.mjs
git commit -m "feat(cockpit): captureProvenanced client for memory-pg /capture_turn"
```

---

### Task 3: Wire `ingestPersonalTurn` to write provenance to memory-pg

**Files:**
- Modify: `apps/project-cockpit/server/memory-ingest.mjs` (the `ingestPersonalTurn` function)
- Test: `apps/project-cockpit/server/memory-ingest-personal-prov.test.mjs`

The personal exchange is written to the canonical store with provenance: user turn → `user_stated` (capture its id), assistant turn → `model_generated`, each atom → `model_distilled` with `prov_derived_from = [userId]`. To stay unit-testable, `ingestPersonalTurn` gains two injectable deps: `distillFn` (defaults to the real `distillSalient`) and `captureFn` (defaults to the real `captureProvenanced`). The existing beagle-core `ingestVerbatim` calls are kept unchanged.

- [ ] **Step 1: Write the failing test**

Create `apps/project-cockpit/server/memory-ingest-personal-prov.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { ingestPersonalTurn } from "./memory-ingest.mjs";

test("ingestPersonalTurn writes provenance: user_stated, model_generated, model_distilled+derived_from", async () => {
  const captures = [];
  const deps = {
    // swallow the beagle-core verbatim path (return ok)
    fetchImpl: async () => ({ ok: true, json: async () => ({}) }),
    tokenFn: async () => "tok",
    memoryPgUrl: "http://memory-pg",
    distillFn: async () => ["Demetrios runs marathons."],
    captureFn: async (rec) => {
      captures.push(rec);
      // the user turn must come back with an id so the atom can link to it
      if (rec.prov_actor === "user_stated") return { id: "user-rec-1", created: true };
      return { id: `rec-${captures.length}`, created: true };
    },
  };
  await ingestPersonalTurn(
    { sessionId: "home:companion", userText: "I run marathons", assistantText: "Nice!", clientTime: null, timezone: null },
    deps,
  );

  const byActor = (a) => captures.filter((c) => c.prov_actor === a);
  assert.equal(byActor("user_stated").length, 1);
  assert.equal(byActor("user_stated")[0].content, "I run marathons");
  assert.equal(byActor("model_generated").length, 1);
  const atoms = byActor("model_distilled");
  assert.equal(atoms.length, 1);
  assert.equal(atoms[0].content, "Demetrios runs marathons.");
  // the atom links to the user turn's record id → not an orphan
  assert.deepEqual(atoms[0].prov_derived_from, ["user-rec-1"]);
});

test("ingestPersonalTurn is fail-soft: a capture error never throws", async () => {
  await ingestPersonalTurn(
    { sessionId: "s", userText: "hi", assistantText: "ok" },
    {
      fetchImpl: async () => ({ ok: true, json: async () => ({}) }),
      tokenFn: async () => "t",
      memoryPgUrl: "http://memory-pg",
      distillFn: async () => [],
      captureFn: async () => { throw new Error("capture down"); },
    },
  );
  assert.ok(true); // reached here without throwing
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test --test-concurrency=1 server/memory-ingest-personal-prov.test.mjs`
Expected: FAIL — `ingestPersonalTurn` does not call `captureFn`/`distillFn` deps yet (captures stays empty; `byActor(...)` length assertions fail).

- [ ] **Step 3: Wire the provenance writes**

In `apps/project-cockpit/server/memory-ingest.mjs`, modify `ingestPersonalTurn`. First, extend its `deps` destructure to add `memoryPgUrl`, `ingestToken`, `distillFn`, and `captureFn` (keep all existing keys):

```js
  const {
    baseUrl = process.env.BEAGLE_INTERNAL_URL || "http://beagle-core.beagle.svc.cluster.local:8080",
    routerUrl = process.env.PROJECT_COCKPIT_LITELLM_ROUTER_URL || "http://router.llm-router.svc.cluster.local:4000",
    model = process.env.PROJECT_COCKPIT_DISTILL_MODEL || "qwen2.5-14b",
    memoryPgUrl = process.env.MEMORY_PG_QUERY_URL || "http://memory-pg-serve.beagle.svc.cluster.local",
    ingestToken = process.env.MEMORY_PG_INGEST_TOKEN,
    fetchImpl = fetch,
    tokenFn,
    distillFn = distillSalient,
    captureFn = captureProvenanced,
  } = deps;
```

Then REPLACE the body of the `try { ... }` block (currently: build verbatim → ingestVerbatim → `const atoms = await distillSalient(...)` → `if (atoms.length) { ingestVerbatim(atoms…) }`) with:

```js
  try {
    const verbatim = buildVerbatimPayload({ sessionId, userText, assistantText, clientTime, timezone });
    if (!verbatim) return;
    // Existing path: verbatim transcript to beagle-core (feeds the Claude Desktop bridge).
    await ingestVerbatim(verbatim, { baseUrl, fetchImpl, tokenFn });

    const atoms = await distillFn({ userText, assistantText }, { routerUrl, model, fetchImpl });
    if (atoms.length) {
      await ingestVerbatim({
        source: "companion-personal",
        session_id: verbatim.session_id,
        turns: atoms.map((a) => ({ role: "assistant", content: a })),
        tags: ["companion", "personal", "distill"],
        metadata: { space: "personal", client_time: clean(clientTime), timezone: clean(timezone) },
      }, { baseUrl, fetchImpl, tokenFn });
    }

    // Provenance-tagged write to the canonical store (memory-pg). The user turn is
    // user_stated; the assistant turn model_generated; each atom is model_distilled linked
    // to the user turn — so an atom with no real user source is flagged orphan (P1) and
    // never laundered into biography.
    const capDeps = { memoryPgUrl, fetchImpl, ingestToken };
    const u = clean(userText), a = clean(assistantText);
    const sid = verbatim.session_id;
    let userId = null;
    if (u) {
      const r = await captureFn(
        { source_type: "ConversationPassage", content: u, prov_actor: "user_stated",
          prov_surface: "companion-ios", prov_confidence: 1.0,
          metadata: { space: "personal", session_id: sid, role: "user" } },
        capDeps,
      );
      userId = r && r.id ? r.id : null;
    }
    if (a) {
      await captureFn(
        { source_type: "ConversationPassage", content: a, prov_actor: "model_generated",
          prov_surface: "companion-ios",
          metadata: { space: "personal", session_id: sid, role: "assistant" } },
        capDeps,
      );
    }
    for (const atom of atoms) {
      await captureFn(
        { source_type: "MemoryAtom", content: atom, prov_actor: "model_distilled",
          prov_surface: "companion-ios",
          prov_derived_from: userId ? [userId] : [],
          metadata: { space: "personal", session_id: sid, kind: "distill" } },
        capDeps,
      );
    }
  } catch {
    // fail-soft — ingestion must never affect the chat
  }
```

(The `clean`, `buildVerbatimPayload`, `ingestVerbatim`, `distillSalient`, `captureProvenanced` symbols are all defined in this same module — no new imports needed.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/project-cockpit && node --test --test-concurrency=1 server/memory-ingest-personal-prov.test.mjs`
Expected: PASS (2 tests green).

- [ ] **Step 5: Confirm no regression in the existing memory-ingest tests**

Run: `cd apps/project-cockpit && node --test --test-concurrency=1 server/memory-ingest.test.mjs server/memory-ingest-endpoint.test.mjs`
Expected: PASS (existing behaviour unchanged; the beagle-core path is untouched).

- [ ] **Step 6: Commit**

```bash
cd /home/devsounio/beagle
git add apps/project-cockpit/server/memory-ingest.mjs apps/project-cockpit/server/memory-ingest-personal-prov.test.mjs
git commit -m "feat(cockpit): ingestPersonalTurn writes provenance to canonical memory-pg"
```

---

### Task 4: Deploy + live verification

**Files:** none (operational).

- [ ] **Step 1: Build + roll the cockpit** with the new code (kaniko build of `apps/project-cockpit/Dockerfile` from the current `reconcile/unify-beagle` HEAD → registry `192.168.3.207:5003/project-cockpit:<tag>`, then `kubectl -n beagle set image deploy/project-cockpit app=...`, Recreate strategy). This mirrors the prior cockpit deploys in this branch.

- [ ] **Step 2: Send a live personal turn** through the deployed cockpit (`POST /api/mobile/v1/chat` with `space:"personal"`, a distinctive user statement, e.g. `"Para o teste de proveniência: eu corro de manhã."`).

- [ ] **Step 3: Verify provenance in memory-pg** (via `kubectl -n beagle exec memory-pg-0 -- psql`):
```sql
SELECT prov_actor, prov_orphan, left(content, 50)
  FROM records
 WHERE metadata->>'session_id' LIKE 'home:%'
   AND created_at > now() - interval '5 min'
 ORDER BY created_at;
```
Expected: the user statement as `user_stated`; the assistant reply as `model_generated`; any distilled atom as `model_distilled` with `prov_orphan=false` (it links to the real user turn). A genuine user-grounded atom must NOT be an orphan; an atom the model invents with no basis in the user turn would be (that is the safeguard).

## Self-review (P1.5 → spec coverage)

- Spec §3 "distill tags model_distilled + derived_from" → Task 3 (atoms tagged + linked to the user turn id).
- Spec §3 "beagle-core forwards the actor" → **superseded** by the cleaner direct-write architecture (user-approved 2026-06-27): the cockpit writes provenance straight to the canonical store; beagle-core stays in parallel for the bridge. No Rust change needed.
- Spec §1 orphan invariant → enforced by P1's `captureRecord`; Task 3 supplies the `derived_from` that makes it meaningful on this path.
- Tiers/recall (§2/§4) remain P2/P3.
