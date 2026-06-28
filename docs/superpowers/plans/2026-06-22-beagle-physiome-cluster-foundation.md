# Beagle Physiome — Cluster Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Stand up the sovereign server-side foundation for Physiome — a Postgres time-series store, an ingest endpoint the iOS app posts HealthKit/WeatherKit batches to, a NOAA space-weather poller, and a daily digest into the exocortex.

**Architecture:** A small Node ESM app `apps/physiome` (same style/ecosystem as `apps/exocortex-ingest`): an Express ingest service + two bin entrypoints (poller, digest). Raw full-fidelity rows in Postgres (beagle-core's instance); daily summaries distilled into the exocortex via the existing assisted-import contract. 100% self-hosted.

**Tech Stack:** Node 22 ESM + `node:test`; `pg` (Postgres client); Express; beagle-core Postgres; LiteLLM router (`qwen2.5-14b`) for the digest prose; exocortex assisted-import (`apps/exocortex-ingest/src/contracts.mjs` pattern); K8s CronJob + kaniko (registry `192.168.3.207:5003`).

**Spec:** `docs/superpowers/specs/2026-06-22-beagle-physiome-foundation-design.md`

**Sibling plan (separate, Mac/Xcode session):** iOS `HealthSyncEngine` + `WeatherSyncEngine` + `PhysiomeUploader` in `beagle-ios/BeagleSuite` — posts to the endpoint this plan builds.

---

## File Structure (this plan)
- Create `apps/physiome/package.json` — ESM, `pg` dep, `node:test`.
- Create `apps/physiome/sql/001_schema.sql` — `health_samples`, `weather_obs`, `space_weather`.
- Create `apps/physiome/src/db.mjs` — Postgres pool + `ensureSchema()` + typed upserts (pure-ish, testable against a test DB).
- Create `apps/physiome/src/validate.mjs` — validate/normalize incoming sample batches (pure, TDD).
- Create `apps/physiome/src/spaceweather.mjs` — parse NOAA SWPC JSON → rows (pure, TDD).
- Create `apps/physiome/src/digest.mjs` — `buildPhysiomeSummary(rows)` (pure, TDD) + `generateDigest()` (router + assisted-import).
- Create `apps/physiome/bin/serve.mjs` — Express `POST /api/physiome/ingest`.
- Create `apps/physiome/bin/run-poller.mjs`, `bin/run-digest.mjs`.
- Create `apps/physiome/test/validate.test.mjs`, `test/spaceweather.test.mjs`, `test/digest.test.mjs`.
- Create `k8s/physiome/` — Deployment+Service (ingest), CronJobs (poller, digest), Dockerfile.

---

### Task 0: Discover Postgres connection + confirm reachability

- [ ] **Step 1:** Find beagle-core's Postgres DSN.
Run:
```bash
export KUBECONFIG=/home/devsounio/.kube/config
kubectl -n beagle get svc | grep -iE 'postgres|pgvector'
kubectl -n beagle get secret beagle-postgres-secret -o jsonpath='{.data}' 2>/dev/null | tr ',' '\n' | sed 's/[":{].*//'
```
Expected: a Postgres service + a secret with the password key. Note `PHYSIOME_PG_DSN` (e.g. `postgres://beagle:<pw>@postgres.beagle.svc:5432/beagle`).

- [ ] **Step 2:** Confirm connect (port-forward + `psql` or a tiny node `pg` script). Record the DSN for env. Commit nothing yet.

---

### Task 1: package.json + schema

- [ ] **Step 1:** Write `apps/physiome/package.json`
```json
{ "name": "physiome", "type": "module", "version": "0.1.0",
  "scripts": { "test": "node --test" },
  "dependencies": { "pg": "^8.13.0", "express": "^4.21.0" } }
```
- [ ] **Step 2:** Write `apps/physiome/sql/001_schema.sql`
```sql
CREATE TABLE IF NOT EXISTS health_samples (
  uuid UUID PRIMARY KEY, ts TIMESTAMPTZ NOT NULL, end_ts TIMESTAMPTZ,
  type TEXT NOT NULL, value DOUBLE PRECISION, unit TEXT, source TEXT, device TEXT,
  metadata JSONB DEFAULT '{}'::jsonb);
CREATE INDEX IF NOT EXISTS health_samples_type_ts ON health_samples(type, ts);
CREATE TABLE IF NOT EXISTS weather_obs (
  ts TIMESTAMPTZ NOT NULL, lat DOUBLE PRECISION, lon DOUBLE PRECISION,
  temp_c DOUBLE PRECISION, pressure_hpa DOUBLE PRECISION, humidity DOUBLE PRECISION,
  uv_index DOUBLE PRECISION, precip DOUBLE PRECISION, aqi DOUBLE PRECISION,
  condition TEXT, metadata JSONB DEFAULT '{}'::jsonb,
  PRIMARY KEY (ts, lat, lon));
CREATE TABLE IF NOT EXISTS space_weather (
  ts TIMESTAMPTZ PRIMARY KEY, kp DOUBLE PRECISION, f107 DOUBLE PRECISION,
  solar_wind_speed DOUBLE PRECISION, bz DOUBLE PRECISION, source TEXT);
```
- [ ] **Step 3:** Commit `package.json` + schema.

---

### Task 2: Validation (pure, TDD)

- [ ] **Step 1: failing test** `test/validate.test.mjs`
```js
import { test } from "node:test"; import assert from "node:assert/strict";
import { validateHealthSample, validateBatch } from "../src/validate.mjs";
test("valid health sample passes + normalizes", () => {
  const s = validateHealthSample({ uuid:"11111111-1111-1111-1111-111111111111", ts:"2026-06-22T08:00:00Z", type:"HKQuantityTypeIdentifierHeartRate", value:62, unit:"count/min", source:"Watch" });
  assert.equal(s.type, "HKQuantityTypeIdentifierHeartRate"); assert.equal(s.value, 62);
});
test("rejects sample missing uuid/ts/type", () => {
  assert.equal(validateHealthSample({ value:1 }), null);
});
test("validateBatch drops invalid, keeps valid", () => {
  const r = validateBatch({ health_samples:[ {uuid:"x"}, {uuid:"22222222-2222-2222-2222-222222222222",ts:"2026-06-22T08:00:00Z",type:"HKQuantityTypeIdentifierStepCount",value:10,unit:"count"} ] });
  assert.equal(r.health_samples.length, 1);
});
```
- [ ] **Step 2:** Run `cd apps/physiome && node --test test/validate.test.mjs` → FAIL (module missing).
- [ ] **Step 3:** Implement `src/validate.mjs`
```js
const UUID_RE = /^[0-9a-fA-F-]{36}$/;
export function validateHealthSample(s) {
  if (!s || !UUID_RE.test(s.uuid || "") || !s.ts || !s.type) return null;
  return { uuid:s.uuid, ts:s.ts, end_ts:s.end_ts || null, type:String(s.type),
    value: s.value==null?null:Number(s.value), unit: s.unit||null,
    source: s.source||null, device: s.device||null, metadata: s.metadata||{} };
}
export function validateWeatherObs(w) {
  if (!w || !w.ts) return null;
  return { ts:w.ts, lat:num(w.lat), lon:num(w.lon), temp_c:num(w.temp_c), pressure_hpa:num(w.pressure_hpa),
    humidity:num(w.humidity), uv_index:num(w.uv_index), precip:num(w.precip), aqi:num(w.aqi),
    condition:w.condition||null, metadata:w.metadata||{} };
}
function num(v){ return v==null?null:Number(v); }
export function validateBatch(body){
  const hs = Array.isArray(body?.health_samples)?body.health_samples:[];
  const wo = Array.isArray(body?.weather_obs)?body.weather_obs:[];
  return { health_samples: hs.map(validateHealthSample).filter(Boolean),
           weather_obs: wo.map(validateWeatherObs).filter(Boolean) };
}
```
- [ ] **Step 4:** Run test → PASS. **Step 5:** Commit.

---

### Task 3: NOAA space-weather parser (pure, TDD)

- [ ] **Step 1: failing test** `test/spaceweather.test.mjs` — feed NOAA-shaped fixtures (planetary Kp array `[["time_tag","kp",...],...]`, F10.7, solar wind plasma/mag) and assert `parseKp`, `parseF107`, `parseSolarWind` return `{ts,value}` rows; `mergeSpaceWeather` joins by nearest ts into `{ts,kp,f107,solar_wind_speed,bz}`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `src/spaceweather.mjs` — pure parsers over the NOAA JSON shapes (SWPC `planetary_k_index_1m.json`, `f107_cm_flux.json`, `solar-wind/plasma-1-day.json` + `mag-1-day.json`), tolerant of missing fields.
- [ ] **Step 4:** Run → PASS. **Step 5:** Commit.

---

### Task 4: Digest summary (pure assembly, TDD) + generator

- [ ] **Step 1: failing test** `test/digest.test.mjs`
```js
import { test } from "node:test"; import assert from "node:assert/strict";
import { buildPhysiomeSummary } from "../src/digest.mjs";
test("summary mentions sleep, HRV, pressure trend, Kp", () => {
  const s = buildPhysiomeSummary({
    date:"2026-06-22",
    health:{ sleepHours:5.2, hrvMs:38, restingHr:58, steps:8200, activeKcal:430 },
    weather:{ tempMinC:14, tempMaxC:23, pressureTrendHpa:-6, uvMax:8, aqi:42 },
    space:{ kpMax:5, f107:142, solarWindSpeed:620 } });
  for (const frag of ["5.2","38","-6","Kp"]) assert.ok(s.includes(frag), frag);
  assert.ok(s.length < 1200);
});
```
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `src/digest.mjs`: `buildPhysiomeSummary(agg)` → deterministic compact pt-BR line; `generateDigest(dsn, deps)` → SQL day-aggregate (queries the 3 tables) → `buildPhysiomeSummary` → optional `routerChat("qwen2.5-14b", …)` polish → `assistedImport({ importScope:"physiome_digest", tags:["physiome-digest","pinned"], privacyClass:"sensitive", turns:[{role:"user",content:summary,…}] })` (import from `../../exocortex-ingest/src/contracts.mjs` or inline a copy).
- [ ] **Step 4:** Run → PASS. **Step 5:** Commit.

---

### Task 5: db.mjs (pool + ensureSchema + upserts) + ingest server

- [ ] **Step 1:** Implement `src/db.mjs` — `pool(dsn)`, `ensureSchema(pool)` (runs `sql/001_schema.sql`), `upsertHealthSamples(pool, rows)` (`INSERT … ON CONFLICT (uuid) DO UPDATE`), `upsertWeather`, `upsertSpaceWeather`.
- [ ] **Step 2:** Implement `bin/serve.mjs` — Express; `POST /api/physiome/ingest` → auth check (`X-Beagle-Consumer` + Bearer `PHYSIOME_INGEST_TOKEN`) → `validateBatch` → `upsert*` → `{ok, ingested:{health, weather}}`. `GET /healthz`.
- [ ] **Step 3: integration test** (`test/db.test.mjs`, gated on `PHYSIOME_TEST_DSN`): ensureSchema → upsert a sample twice → assert one row (idempotent).
- [ ] **Step 4:** Live smoke: port-forward Postgres, `ensureSchema`, run `serve.mjs`, `curl POST /api/physiome/ingest` a 2-sample batch → 200 + rows present + idempotent on repeat.
- [ ] **Step 5:** Commit.

---

### Task 6: bin entrypoints (poller, digest) + live smoke

- [ ] **Step 1:** `bin/run-poller.mjs` — fetch the NOAA SWPC URLs → `parse*`/`mergeSpaceWeather` → `upsertSpaceWeather`. `bin/run-digest.mjs` — `generateDigest(dsn, …)`.
- [ ] **Step 2:** Live smoke poller: run against real NOAA → rows in `space_weather` (verify via SQL). Fail-soft if NOAA unreachable.
- [ ] **Step 3:** Live smoke digest: seed a day of rows → run digest → assert a `physiome-digest` doc is recallable from the exocortex (`/api/memory/query` tags `physiome-digest`).
- [ ] **Step 4:** Commit.

---

### Task 7: Package + deploy (kaniko + K8s)

- [ ] **Step 1:** `apps/physiome/Dockerfile` (node:22-alpine, copy app, `npm ci --omit=dev`). Default CMD `node bin/serve.mjs`.
- [ ] **Step 2:** `k8s/physiome/`: Deployment+Service for the ingest server (env `PHYSIOME_PG_DSN`, `PHYSIOME_INGEST_TOKEN`; seccomp Unconfined per cluster standard); CronJob `physiome-space-weather` (every 1–3h → `run-poller.mjs`); CronJob `physiome-digest` (daily → `run-digest.mjs`). Mirror an existing build-job for kaniko conventions; poll the **registry tag**, not the Job.
- [ ] **Step 3:** kaniko build → registry `192.168.3.207:5003/physiome:0.1.0`. Apply manifests. Expose the ingest endpoint to the device (tailnet/CF route to the Service, like the existing cockpit routes).
- [ ] **Step 4:** Verify: `curl` the live endpoint with a sample batch → 200 + row in Postgres; run the poller CronJob once → rows; run the digest CronJob once → recallable digest.
- [ ] **Step 5:** Commit.

---

## Self-review (done)
- **Spec coverage:** schema (T1), ingest endpoint (T5), NOAA poller (T3,T6), digest→exocortex (T4,T6), sovereignty (token auth + self-hosted PG/exocortex; no commercial path), deploy (T7). iOS sync engines → sibling plan (noted). Clinical/FHIR + grounding/insights/dashboard → out of scope (spec).
- **Placeholders:** pure-logic tasks (T2,T3,T4) carry real code/tests; I/O tasks (T5,T6,T7) specify exact endpoints, SQL shapes, env, and live-smoke verification (legitimate — DB/k8s wiring is verified by running, not unit fixtures).
- **Type consistency:** `validateBatch`/`validateHealthSample` (T2) feed `upsert*` (T5); `buildPhysiomeSummary` (T4) consumes the aggregate shape produced in `generateDigest` (T4); `assistedImport` reuses the exocortex-ingest contract. Names consistent across tasks.
