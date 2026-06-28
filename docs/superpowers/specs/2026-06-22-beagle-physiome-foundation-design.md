# Beagle Physiome — HealthKit + WeatherKit + Space Weather Foundation

**Status:** Design approved 2026-06-22. Foundation project (data pipeline). The
*uses* (companion grounding, correlation insights, dashboard) are separate specs
built on top of this.

## Goal

Give Beagle a sovereign, full-fidelity record of the user's **body** (Apple
HealthKit, complete) and **environment** (Apple WeatherKit + space weather), as a
time-series foundation. Raw samples land in a dedicated store for research
(HSN / heliobiology); compact daily summaries are distilled into the exocortex so
the Personal companion can later be grounded in them. 100% self-hosted — health
data never reaches a commercial LLM.

## Why

The user is a psychiatrist/researcher (heliobiology, computational psychiatry).
A companion that knows his real biology and environment ("as real as it gets")
needs this data; his research needs the raw time-series to study mood × sleep ×
barometric pressure × geomagnetic activity. This is the **Tier-3 ambient** layer
of the Personal Companion ([[project_beagle_personal_companion]]), built
foundation-first.

## Architecture

```
iOS HealthKit (HKAnchoredObjectQuery + HKObserverQuery + background delivery) ┐
iOS WeatherKit (current + forecast, by current location, periodic) ───────────┼→ POST /api/physiome/ingest
                                                                              │     (beagle-core; auth: operator token + X-Beagle-Consumer)
                                                                              │        └→ Postgres: health_samples / weather_obs
NOAA SWPC poller (CronJob, server-side, public APIs) ──────────────────────────────→ Postgres: space_weather
                                                                                    │
                          physiome-digest (CronJob daily + on-demand):
                             raw (SQL aggregate of the day) → compact pt-BR summary → exocortex
                             (assisted-import, tag `physiome-digest`, privacy `sensitive`)
```

- **Raw, full fidelity** → Postgres (the instance beagle-core already runs) — queryable via SQL for research, exportable to Parquet later if bulk analysis needs it.
- **Distilled summaries** → exocortex (same `assisted-import` path as the biography digest) — for companion grounding. One small doc/day: no index-scale pressure (lesson from [[project_exocortex_ingest_constraints]]).
- **Sovereign:** every byte stays on the self-hosted cluster.

### Chosen approach (A) and rejected alternatives
- **A (chosen):** Postgres raw store + ingest endpoint + digest job. Reuses existing infra, SQL-queryable, sovereign, no new service to keep robust.
- **B (rejected):** Parquet on Ceph/orangefs — great for batch analytics but incremental append is awkward, no ad-hoc query. (Can export to Parquet later.)
- **C (rejected):** dedicated TimescaleDB — purpose-built for time-series but overkill for one person's volume and another fragile service to operate. (Can migrate later if volume demands.)

## Components

### iOS (BeagleSuite, Swift) — extends existing `PhysioStore` / `BeagleHRV` / `BeagleWatch`
- **`HealthSyncEngine`** — requests authorization for the complete HealthKit type set (quantity: heart rate, HRV SDNN, resting/walking HR, respiratory rate, blood oxygen, steps, distance, active/basal energy, flights, VO2max, etc.; category: sleep analysis, mindful sessions; workouts). Uses `HKAnchoredObjectQuery` with **persisted per-type anchors** for incremental deltas, `HKObserverQuery` + `enableBackgroundDelivery` for near-real-time, and a catch-up sync on foreground.
- **`WeatherSyncEngine`** — `WeatherKit.WeatherService` for current conditions + hourly/daily forecast at the current location; periodic (hourly) + on significant location change.
- **`PhysiomeUploader`** — batches samples → `POST /api/physiome/ingest`; backoff retry; **idempotent by sample UUID**; persists last-acked anchor (no loss/dup across launches or reinstall, modulo a one-time full re-anchor); offline queue flushed on connectivity.
- **Entitlements:** HealthKit + WeatherKit + HealthKit background delivery (extend `Entitlements/BeagleCockpit.entitlements`).
- **Out of initial scope:** `HKClinicalType` / FHIR clinical records (separate Apple entitlement) — addable later.

### Beagle (cluster)
- **`POST /api/physiome/ingest`** (beagle-core) — accepts typed batches `{health_samples:[…], weather_obs:[…]}`; validates type/unit; **idempotent upsert** into Postgres keyed on sample uuid; tolerant of partial batches. Auth: operator token + `X-Beagle-Consumer` (mirrors existing memory endpoints).
- **`space-weather-poller`** (CronJob) — pulls NOAA SWPC public JSON: planetary **Kp** index, **F10.7** solar flux, solar wind (speed, **Bz**) from ACE/DSCOVR feeds → upsert `space_weather`. Fail-soft (gaps OK).
- **`physiome-digest`** (CronJob daily + on-demand) — SQL-aggregates the day (sleep duration/quality, HRV, resting HR, steps, energy, workouts; weather min/max + barometric trend + UV + AQI; space weather Kp/F10.7/solar wind) → compact pt-BR summary → exocortex `assisted-import` (tag `physiome-digest`, `import_scope: physiome_digest`, privacy `sensitive`). Reuses `apps/exocortex-ingest` contracts. Fail-soft (skip empty days).

### Storage (Postgres — beagle-core's instance)
- `health_samples(uuid UUID PK, ts timestamptz, end_ts timestamptz, type text, value double precision, unit text, source text, device text, metadata jsonb)` — index `(type, ts)`.
- `weather_obs(ts timestamptz, lat double, lon double, temp_c double, pressure_hpa double, humidity double, uv_index double, precip double, aqi double, condition text, metadata jsonb)` — index `(ts)`.
- `space_weather(ts timestamptz, kp double, f107 double, solar_wind_speed double, bz double, source text)` — index `(ts)`.
- Monthly partitioning only if volume ever warrants (one person → trivial).

## Data flow detail
- **Completeness:** persisted anchors → only new samples upload → idempotent upsert → no loss/dup. Reinstall triggers one full re-anchor backfill.
- **Weather** tagged with location + ts (current-location-at-fetch; dedicated location capture is a separate Tier-3 spec).
- **Digest** is what the companion reads (future), like the biography digest; raw stays in Postgres for research.

## Sovereignty / privacy
- Health + weather + space data live **only** on the self-hosted cluster (Postgres + sovereign exocortex). Digest summaries are injected **only** into the Personal/self-hosted companion path, **never** a commercial LLM (existing Personal-space sovereignty rule, [[project_beagle_personal_companion]]).
- Device→Beagle over tailnet/CF with operator/device token; HTTPS. Biometrics are numeric (no textual PII); digest text still passes the content guardrails.

## Error handling / robustness
- iOS uploader: backoff retry, persisted anchors (no loss), idempotent upsert (no dup), offline queue.
- Ingest endpoint: validates types/units, rejects malformed, partial-batch tolerant.
- NOAA poller + digest: fail-soft (skip on source down / empty day).
- No high-volume exocortex pressure: digest = 1 small doc/day (explicit lesson from the index-scale incident).

## Testing
- iOS: unit-test anchor/batch logic + payload encoding (mock HealthKit/WeatherKit).
- Beagle (TDD where pure): ingest endpoint (typed batch → Postgres rows + idempotency), NOAA poller (parse fixtures), digest (fixture rows → expected summary).

## Build order (phases within this foundation)
1. Postgres schema + `POST /api/physiome/ingest` (the spine).
2. iOS `HealthSyncEngine` + `WeatherSyncEngine` + `PhysiomeUploader` (+ entitlements).
3. `space-weather-poller` CronJob.
4. `physiome-digest` CronJob → exocortex.

## Out of scope (separate specs)
- Companion grounding on the physiome digest (wire into the Personal chat path).
- Correlation/insights engine (mood × sleep × barometric × Kp).
- Dashboard / visualization in the cockpit.
- iPhone location capture; Apple Music metadata (other Tier-3 ambient sources).
- HealthKit clinical/FHIR records.
