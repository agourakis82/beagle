# Beagle Temporal Awareness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Personal-space beagle aware of real wall-clock time every turn — it knows the user's local *now* + how long since they last talked, and situates recalled memories in time ("ontem", "há 3 dias").

**Architecture:** Prompt-layer (Approach A). A pure Node module builds a `TEMPO AGORA` block + stamps memory snippets; `mobile-routes.mjs` injects them into the personal system prompt after `PERSONAL_PERSONA`. The iOS client sends `clientTime`/`timezone`/`lastContactAt`. Dated recall wires the existing `memory-pg /query` (which already returns `occurred_at` and recency-blends) into the chat. No model training, no retrieval-ranking change.

**Tech Stack:** Node ESM (`.mjs`), `node:test`/`node:assert` (matches `apps/memory-pg`), Express (`mobile-routes.mjs`), Swift (`BeagleClient`/`ConversationStore`).

Spec: `docs/superpowers/specs/2026-06-26-beagle-temporal-awareness-design.md`.

---

### Task 1: Pure relative-time phrasing (`relativeTime` + `parteDoDia`)

**Files:**
- Create: `apps/project-cockpit/server/temporal-context.mjs`
- Test: `apps/project-cockpit/server/temporal-context.test.mjs`

- [ ] **Step 1: Write the failing test**

```js
// apps/project-cockpit/server/temporal-context.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { parteDoDia, relativeTime } from "./temporal-context.mjs";

const TZ = "America/Sao_Paulo"; // UTC-03
const at = (iso) => new Date(iso);

test("parteDoDia by local hour", () => {
  assert.equal(parteDoDia(2), "madrugada");
  assert.equal(parteDoDia(9), "manhã");
  assert.equal(parteDoDia(15), "tarde");
  assert.equal(parteDoDia(21), "noite");
});

test("relativeTime coarsens with distance (tz-correct)", () => {
  const now = at("2026-06-26T23:00:00-03:00");
  assert.equal(relativeTime(at("2026-06-26T22:40:00-03:00"), now, TZ), "agora há pouco"); // <45min
  assert.equal(relativeTime(at("2026-06-26T09:00:00-03:00"), now, TZ), "hoje de manhã");
  assert.equal(relativeTime(at("2026-06-25T15:00:00-03:00"), now, TZ), "ontem");
  assert.equal(relativeTime(at("2026-06-23T10:00:00-03:00"), now, TZ), "há 3 dias");
  assert.equal(relativeTime(at("2026-06-18T10:00:00-03:00"), now, TZ), "semana passada");
  assert.equal(relativeTime(at("2026-06-09T10:00:00-03:00"), now, TZ), "há algumas semanas");
  assert.equal(relativeTime(at("2026-03-09T10:00:00-03:00"), now, TZ), "faz meses");
});

test("relativeTime clamps future/skew to agora há pouco", () => {
  const now = at("2026-06-26T12:00:00-03:00");
  assert.equal(relativeTime(at("2026-06-26T12:30:00-03:00"), now, TZ), "agora há pouco");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test server/temporal-context.test.mjs`
Expected: FAIL — `Cannot find module './temporal-context.mjs'`.

- [ ] **Step 3: Write minimal implementation**

```js
// apps/project-cockpit/server/temporal-context.mjs
// Pure temporal context for the Personal-space companion. No I/O and no implicit
// "now" — the caller passes Date objects — so every function is deterministic and
// unit-testable. All phrasing is pt-BR.

function localParts(date, tz) {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
  });
  const p = Object.fromEntries(fmt.formatToParts(date).map((x) => [x.type, x.value]));
  return { y: +p.year, m: +p.month, d: +p.day, hour: +p.hour, minute: +p.minute };
}

function localDayNumber(date, tz) {
  const { y, m, d } = localParts(date, tz);
  return Math.floor(Date.UTC(y, m - 1, d) / 86400000);
}

const HOJE_PREP = { madrugada: "de madrugada", manhã: "de manhã", tarde: "à tarde", noite: "à noite" };

/** Bare part-of-day word from a local hour. */
export function parteDoDia(hour) {
  if (hour < 5) return "madrugada";
  if (hour < 12) return "manhã";
  if (hour < 18) return "tarde";
  return "noite";
}

/** pt-BR relative phrasing of `from` seen from `to`, in IANA `tz`. Coarsens with
 *  distance; clamps future/skew to "agora há pouco". */
export function relativeTime(from, to, tz = "UTC") {
  const deltaMs = to.getTime() - from.getTime();
  if (deltaMs < 45 * 60 * 1000) return "agora há pouco";
  const days = localDayNumber(to, tz) - localDayNumber(from, tz);
  if (days <= 0) return "hoje " + HOJE_PREP[parteDoDia(localParts(from, tz).hour)];
  if (days === 1) return "ontem";
  if (days < 7) return `há ${days} dias`;
  if (days < 14) return "semana passada";
  if (days < 30) return "há algumas semanas";
  return "faz meses";
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/project-cockpit && node --test server/temporal-context.test.mjs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/temporal-context.mjs apps/project-cockpit/server/temporal-context.test.mjs
git commit -m "feat(temporal): pure relativeTime + parteDoDia (pt-BR, tz-correct)"
```

---

### Task 2: `buildTemporalContext` + `formatTempoAgora` + `stampMemories`

**Files:**
- Modify: `apps/project-cockpit/server/temporal-context.mjs`
- Test: `apps/project-cockpit/server/temporal-context.test.mjs`

- [ ] **Step 1: Add failing tests**

Append to `temporal-context.test.mjs`:

```js
import { buildTemporalContext, formatTempoAgora, stampMemories } from "./temporal-context.mjs";

test("buildTemporalContext: now label + since-last", () => {
  const ctx = buildTemporalContext({
    now: at("2026-06-26T23:47:00-03:00"),
    timezone: TZ,
    lastContactAt: at("2026-06-23T10:00:00-03:00"),
  });
  assert.equal(ctx.diaDaSemana, "sexta");
  assert.equal(ctx.parteDoDia, "noite");
  assert.match(ctx.nowLabel, /sexta, 26\/jun, 23h47/);
  assert.equal(ctx.desdeUltimo, "há 3 dias");
});

test("buildTemporalContext: first contact has no since-last", () => {
  const ctx = buildTemporalContext({ now: at("2026-06-26T08:00:00-03:00"), timezone: TZ, lastContactAt: null });
  assert.equal(ctx.desdeUltimo, null);
});

test("formatTempoAgora renders the block", () => {
  const block = formatTempoAgora({ nowLabel: "sexta, 26/jun, 23h47", parteDoDia: "noite", desdeUltimo: "há 3 dias" });
  assert.match(block, /^TEMPO AGORA: sexta, 26\/jun, 23h47 \(noite, fuso dele\)\./);
  assert.match(block, /Última vez que se falaram: há 3 dias\./);
  assert.equal(formatTempoAgora(null), "");
});

test("formatTempoAgora first contact line", () => {
  const block = formatTempoAgora({ nowLabel: "sexta, 26/jun, 08h00", parteDoDia: "manhã", desdeUltimo: null });
  assert.match(block, /Primeira vez que vocês se falam\./);
});

test("stampMemories prefixes occurred_at, skips missing, drops empties", () => {
  const now = at("2026-06-26T23:00:00-03:00");
  const out = stampMemories([
    { text: "ele falou da apresentação", occurred_at: "2026-06-25T15:00:00-03:00" },
    { text: "sem data", occurred_at: null },
    { text: "   ", occurred_at: "2026-06-25T15:00:00-03:00" },
  ], now, TZ);
  assert.deepEqual(out, ["[ontem] ele falou da apresentação", "sem data"]);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/project-cockpit && node --test server/temporal-context.test.mjs`
Expected: FAIL — `buildTemporalContext is not a function` (et al.).

- [ ] **Step 3: Implement**

Append to `temporal-context.mjs`:

```js
const DIAS = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"];
const MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

/** Build the temporal context object from a real `now` (Date), IANA tz, and the
 *  client-supplied last-contact timestamp (Date|null). */
export function buildTemporalContext({ now, timezone = "UTC", lastContactAt = null }) {
  const lp = localParts(now, timezone);
  const dow = new Date(Date.UTC(lp.y, lp.m - 1, lp.d)).getUTCDay();
  const hh = String(lp.hour).padStart(2, "0");
  const mm = String(lp.minute).padStart(2, "0");
  return {
    nowLabel: `${DIAS[dow]}, ${lp.d}/${MESES[lp.m - 1]}, ${hh}h${mm}`,
    diaDaSemana: DIAS[dow],
    parteDoDia: parteDoDia(lp.hour),
    desdeUltimo: lastContactAt ? relativeTime(lastContactAt, now, timezone) : null,
  };
}

/** Render the injected TEMPO AGORA block, or "" when there is no context. */
export function formatTempoAgora(ctx) {
  if (!ctx || !ctx.nowLabel) return "";
  const lines = [`TEMPO AGORA: ${ctx.nowLabel} (${ctx.parteDoDia}, fuso dele).`];
  lines.push(ctx.desdeUltimo
    ? `Última vez que se falaram: ${ctx.desdeUltimo}.`
    : "Primeira vez que vocês se falam.");
  return lines.join("\n");
}

/** Prefix each memory snippet with its relative date; drop empties; leave
 *  date-less snippets unstamped. `results` = memory-pg /query `.results`. */
export function stampMemories(results, now, tz = "UTC") {
  if (!Array.isArray(results)) return [];
  return results
    .map((r) => {
      const text = typeof r?.text === "string" ? r.text.trim() : "";
      if (!text) return null;
      const when = r?.occurred_at ? new Date(r.occurred_at) : null;
      const valid = when && !Number.isNaN(when.getTime());
      return valid ? `[${relativeTime(when, now, tz)}] ${text}` : text;
    })
    .filter(Boolean);
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/project-cockpit && node --test server/temporal-context.test.mjs`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/temporal-context.mjs apps/project-cockpit/server/temporal-context.test.mjs
git commit -m "feat(temporal): buildTemporalContext + formatTempoAgora + stampMemories"
```

---

### Task 3: Wire a `test` script for project-cockpit

**Files:**
- Modify: `apps/project-cockpit/package.json`

- [ ] **Step 1: Add the test script**

In `apps/project-cockpit/package.json`, inside `"scripts"`, add a `test` entry next to `check`:

```json
    "test": "node --test --test-concurrency=1 server/",
```

(Node's `--test` discovers `server/*.test.mjs`. Matches the `apps/memory-pg` convention.)

- [ ] **Step 2: Run the suite**

Run: `cd apps/project-cockpit && npm test`
Expected: PASS (8 tests, temporal-context).

- [ ] **Step 3: Commit**

```bash
git add apps/project-cockpit/package.json
git commit -m "chore(project-cockpit): add node --test script"
```

---

### Task 4: `fetchRecentMemories` — best-effort memory-pg `/query` wrapper

**Files:**
- Modify: `apps/project-cockpit/server/auth-bridge.mjs` (next to `fetchBiographyDigest`/`fetchPhysiomeDigest`, ~line 703)
- Test: `apps/project-cockpit/server/auth-bridge.test.mjs`

- [ ] **Step 1: Write the failing test (inject a stub fetch — no cluster)**

```js
// apps/project-cockpit/server/auth-bridge.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { fetchRecentMemories } from "./auth-bridge.mjs";

test("fetchRecentMemories returns results array on 200", async () => {
  const stub = async () => ({
    ok: true,
    json: async () => ({ results: [{ text: "a", occurred_at: "2026-06-25T10:00:00Z" }] }),
  });
  const out = await fetchRecentMemories("oi", { baseUrl: "http://x", token: "", k: 5, fetchImpl: stub });
  assert.deepEqual(out, [{ text: "a", occurred_at: "2026-06-25T10:00:00Z" }]);
});

test("fetchRecentMemories is fail-soft: empty array on error", async () => {
  const stub = async () => { throw new Error("down"); };
  const out = await fetchRecentMemories("oi", { baseUrl: "http://x", fetchImpl: stub });
  assert.deepEqual(out, []);
});

test("fetchRecentMemories empty query → no call, empty array", async () => {
  let called = false;
  const stub = async () => { called = true; return { ok: true, json: async () => ({ results: [] }) }; };
  const out = await fetchRecentMemories("  ", { baseUrl: "http://x", fetchImpl: stub });
  assert.equal(called, false);
  assert.deepEqual(out, []);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/project-cockpit && node --test server/auth-bridge.test.mjs`
Expected: FAIL — `fetchRecentMemories is not a function`.

- [ ] **Step 3: Implement**

Add to `apps/project-cockpit/server/auth-bridge.mjs` (export it):

```js
/**
 * Best-effort episodic recall from memory-pg /query. Returns the raw results
 * array ([{ text, occurred_at, ... }]) or [] on any failure — never throws, so
 * the chat is never blocked. fetchImpl is injectable for tests.
 */
export async function fetchRecentMemories(query, {
  baseUrl = process.env.MEMORY_PG_QUERY_URL || "http://memory-pg-serve.beagle.svc.cluster.local",
  token = process.env.MEMORY_PG_QUERY_TOKEN || "",
  k = 6,
  timeoutMs = 6000,
  fetchImpl = fetch,
} = {}) {
  const q = typeof query === "string" ? query.trim() : "";
  if (!q) return [];
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const headers = { "content-type": "application/json" };
    if (token) headers.authorization = `Bearer ${token}`;
    const res = await fetchImpl(`${baseUrl}/query`, {
      method: "POST",
      headers,
      body: JSON.stringify({ query: q, k }),
      signal: ctrl.signal,
    });
    if (!res.ok) return [];
    const j = await res.json();
    return Array.isArray(j?.results) ? j.results : [];
  } catch {
    return [];
  } finally {
    clearTimeout(timer);
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/project-cockpit && node --test server/auth-bridge.test.mjs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/auth-bridge.mjs apps/project-cockpit/server/auth-bridge.test.mjs
git commit -m "feat(temporal): fetchRecentMemories (best-effort memory-pg /query)"
```

---

### Task 5: Inject TEMPO AGORA + dated memories into the personal system prompt

**Files:**
- Modify: `apps/project-cockpit/server/mobile-routes.mjs` (the `chatSpace === "personal"` block, ~lines 713-742; imports at top)

- [ ] **Step 1: Add imports at the top of `mobile-routes.mjs`**

```js
import { buildTemporalContext, formatTempoAgora, stampMemories } from "./temporal-context.mjs";
import { fetchRecentMemories } from "./auth-bridge.mjs";
```
(If `auth-bridge.mjs` is already imported, add `fetchRecentMemories` to that import instead of a second line.)

- [ ] **Step 2: Build the temporal context just before the personal block**

Immediately before `const sections = [PERSONAL_PERSONA];`, add:

```js
    const clientTime = cleanString(req.body?.clientTime);
    const tz = cleanString(req.body?.timezone) || "UTC";
    const lastContactRaw = cleanString(req.body?.lastContactAt);
    const now = clientTime && !Number.isNaN(Date.parse(clientTime)) ? new Date(clientTime) : new Date();
    const lastContactAt = lastContactRaw && !Number.isNaN(Date.parse(lastContactRaw)) ? new Date(lastContactRaw) : null;
    const tempoAgora = formatTempoAgora(buildTemporalContext({ now, timezone: tz, lastContactAt }));
```

- [ ] **Step 3: Insert TEMPO AGORA right after PERSONAL_PERSONA and fetch+stamp memories**

Replace the existing personal-grounding block:

```js
    const sections = [PERSONAL_PERSONA];
    try {
      const [bioResult, physioResult] = await Promise.all([
        fetchBiographyDigest(),
        fetchPhysiomeDigest()
      ]);
      biographyDigest = cleanString(bioResult?.digest);
      physiomeDigest = cleanString(physioResult?.digest);
      if (physiomeDigest) {
        sections.push("## Estado físico+ambiente recente", physiomeDigest);
      }
      if (biographyDigest) {
        sections.push(
          "## Quem é Demetrios (biografia viva — fale como quem o conhece de verdade, sem genéricos)",
          biographyDigest
        );
      }
    } catch {
      // ignore — proceed ungrounded rather than break the chat
    }
```

with (note `tempoAgora` is inserted right after the persona, and memories are fetched alongside the digests and stamped):

```js
    const sections = [PERSONAL_PERSONA];
    if (tempoAgora) sections.push(tempoAgora);
    try {
      const userText = cleanString(req.body?.prompt);
      const [bioResult, physioResult, memoryResults] = await Promise.all([
        fetchBiographyDigest(),
        fetchPhysiomeDigest(),
        fetchRecentMemories(userText)
      ]);
      biographyDigest = cleanString(bioResult?.digest);
      physiomeDigest = cleanString(physioResult?.digest);
      if (physiomeDigest) {
        sections.push("## Estado físico+ambiente recente", physiomeDigest);
      }
      if (biographyDigest) {
        sections.push(
          "## Quem é Demetrios (biografia viva — fale como quem o conhece de verdade, sem genéricos)",
          biographyDigest
        );
      }
      const stamped = stampMemories(memoryResults, now, tz);
      if (stamped.length) {
        sections.push(
          "## O que ele já te contou (memórias — situe no tempo quando ajudar)",
          stamped.join("\n")
        );
      }
    } catch {
      // ignore — proceed ungrounded rather than break the chat
    }
```

- [ ] **Step 4: Syntax-check**

Run: `cd apps/project-cockpit && node --check server/mobile-routes.mjs`
Expected: no output (exit 0).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/mobile-routes.mjs
git commit -m "feat(temporal): inject TEMPO AGORA + dated memories into personal prompt"
```

---

### Task 6: Teach the persona to use time naturally

**Files:**
- Modify: `apps/project-cockpit/server/mobile-routes.mjs` (`PERSONAL_PERSONA` array, ~line 240)

- [ ] **Step 1: Append the clause**

In the `PERSONAL_PERSONA = [ ... ]` array, add this string as the last element before `].join("\n")`:

```js
  "Você vive no tempo com ele. Sente a hora — madrugada pesa diferente de meio-dia. Nota o intervalo: se sumiu dias, isso conta; se foi agora há pouco, retoma o fio. Situa o que lembra no tempo (\"ontem\", \"semana passada\"). Mas você não é relógio: só traz o tempo quando ele tem peso — tarde da noite, uma ausência longa, ancorar uma lembrança. Na dúvida, sente o tempo sem anunciá-lo.",
```

- [ ] **Step 2: Syntax-check**

Run: `cd apps/project-cockpit && node --check server/mobile-routes.mjs`
Expected: no output (exit 0).

- [ ] **Step 3: Commit**

```bash
git add apps/project-cockpit/server/mobile-routes.mjs
git commit -m "feat(temporal): persona clause — feel time, don't recite the clock"
```

---

### Task 7: iOS — send `clientTime`, `timezone`, `lastContactAt`

**Files:**
- Modify: `beagle-ios/BeagleSuite/Sources/BeagleCore/BeagleClient.swift` (personal chat body, ~lines 1149-1165)
- Modify: `beagle-ios/BeagleSuite/Sources/BeagleCore/ConversationStore.swift` (`sendMessageCloud`, ~line 295; add a `lastContactAt` property)

- [ ] **Step 1: Add the three body fields in BeagleClient**

In the function building the personal chat `body` dict, add the function parameter `lastContactAt: Date? = nil` to its signature, and add to the `body` dict literal right after `"space": "personal"`:

```swift
            "space": "personal",
            "clientTime": ISO8601DateFormatter().string(from: Date()),
            "timezone": TimeZone.current.identifier
```

Then, after the dict, before `postPublicMobileChat`:

```swift
        if let lastContactAt {
            body["lastContactAt"] = ISO8601DateFormatter().string(from: lastContactAt)
        }
```

- [ ] **Step 2: Thread `lastContactAt` from ConversationStore**

In `ConversationStore`, add a stored property and update it per send:

```swift
    private var lastContactAt: Date? = nil
```

In `sendMessageCloud(_:)`, capture the previous value and pass it, then stamp the new one. At the point where it calls the BeagleClient chat function, change:
- capture `let previousContact = lastContactAt` BEFORE the call,
- pass `lastContactAt: previousContact` into the chat call,
- after a successful send, set `lastContactAt = Date()`.

(First send: `previousContact == nil` → server treats as first contact.)

- [ ] **Step 3: Build on the Mac (host offline at plan time — run when reachable)**

Run (on the Mac, from `~/Developer/beagle-ios`):
```
/opt/homebrew/bin/xcodegen generate
xcodebuild -project BeagleSuite.xcodeproj -scheme BeagleCockpit -configuration Debug \
  -destination "platform=iOS Simulator,id=4AF653EA-DBEA-49B7-90C5-D16B56677839" \
  -derivedDataPath /tmp/simdd build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add beagle-ios/BeagleSuite/Sources/BeagleCore/BeagleClient.swift beagle-ios/BeagleSuite/Sources/BeagleCore/ConversationStore.swift
git commit -m "feat(temporal): iOS sends clientTime/timezone/lastContactAt for the companion"
```

---

### Task 8: End-to-end verification (server)

**Files:** none (verification only)

- [ ] **Step 1: Full server test suite green**

Run: `cd apps/project-cockpit && npm test`
Expected: PASS (temporal-context 8 + auth-bridge 3 = 11 tests).

- [ ] **Step 2: Smoke the personal chat with a temporal payload**

With the project-cockpit server reachable (cluster or local), POST a personal-space message including the new fields and confirm the response is coherent and time-aware (and the server does not error). Example:

```bash
curl -sS -X POST "$COCKPIT_BASE/api/mobile/v1/chat" \
  -H "content-type: application/json" -H "authorization: Bearer $TOKEN" \
  -d '{"space":"personal","prompt":"oi, tudo bem?","projectSlug":"sounio",
       "clientTime":"2026-06-26T23:47:00-03:00","timezone":"America/Sao_Paulo",
       "lastContactAt":"2026-06-23T10:00:00-03:00"}' | jq -r '.text // .reply // .'
```
Expected: a coherent reply; the companion may reference the late hour or the 3-day gap (emergent — not asserted). No 5xx.

- [ ] **Step 3: Confirm fail-soft**

Repeat the curl with `MEMORY_PG_QUERY_URL` pointing nowhere (or memory-pg down). Expected: still a 200 reply (memories simply absent) — temporal presence still works.

- [ ] **Step 4 (optional): On-device check once the Mac is back**

Build + run the companion (Task 7), open the Personal space late at night / after a gap, and confirm the voice feels time-aware without reciting the clock.

---

## Notes for the implementer

- **DRY:** all phrasing lives in `temporal-context.mjs`; `mobile-routes.mjs` only orchestrates.
- **Fail-soft everywhere:** missing `clientTime` → server `now`; missing `timezone` → `"UTC"`; memory-pg error → no memories; none of it blocks the chat.
- **YAGNI:** no recency-ranking change (memory-pg already recency-blends), no tool-calling, no proactive follow-up — those are separate future specs.
- **Measure (Task 8/Step 4):** if the episodic memory snippets read as noise in the personal voice, gate the `## O que ele já te contou` section behind an env flag and tune `k`/min-score before leaving it on.
