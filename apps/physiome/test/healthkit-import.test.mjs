import { test } from "node:test";
import assert from "node:assert/strict";
import { Readable } from "node:stream";
import { parseHealthExportStream, recordToSample, KEPT_TYPES, RAW_TYPES, AGG_TYPES, importHealthExport } from "../src/healthkit-import.mjs";

const FIXTURE = `<?xml version="1.0" encoding="UTF-8"?>
<HealthData locale="en_US">
 <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" sourceName="Watch" unit="ms" startDate="2026-03-15 08:00:00 +0000" endDate="2026-03-15 08:00:00 +0000" value="45.2"/>
 <Record type="HKQuantityTypeIdentifierRestingHeartRate" sourceName="Watch" unit="count/min" startDate="2026-03-15 06:00:00 +0000" endDate="2026-03-15 06:00:00 +0000" value="58"/>
 <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Watch" startDate="2026-03-15 00:00:00 +0000" endDate="2026-03-15 07:30:00 +0000" value="HKCategoryValueSleepAnalysisAsleepCore">
   <MetadataEntry key="x" value="y"/>
 </Record>
 <Record type="HKQuantityTypeIdentifierDietaryWater" sourceName="App" unit="mL" startDate="2026-03-15 10:00:00 +0000" value="250"/>
</HealthData>`;

test("parseHealthExportStream: keeps only the aggregate types, parses attrs", async () => {
  const got = [];
  // feed in awkward chunks to exercise the cross-chunk buffer
  const chunks = [];
  for (let i = 0; i < FIXTURE.length; i += 37) chunks.push(FIXTURE.slice(i, i + 37));
  await parseHealthExportStream(Readable.from(chunks), (a) => got.push(a));
  const types = got.map((a) => a.type);
  assert.ok(types.includes("HKQuantityTypeIdentifierHeartRateVariabilitySDNN"));
  assert.ok(types.includes("HKCategoryTypeIdentifierSleepAnalysis"));
  assert.ok(!types.includes("HKQuantityTypeIdentifierDietaryWater"), "non-aggregate type dropped");
  assert.equal(got.length, 3, "HRV + RestingHR + Sleep kept (water + step missing from fixture types? step absent here)");
});

test("recordToSample: deterministic uuid, sleep value→1 + end_ts, hrv value parsed", () => {
  const hrv = recordToSample({ type: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", startDate: "2026-03-15 08:00:00 +0000", endDate: "2026-03-15 08:00:00 +0000", value: "45.2", unit: "ms", sourceName: "Watch" });
  assert.equal(hrv.value, 45.2);
  assert.match(hrv.uuid, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  const hrv2 = recordToSample({ type: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", startDate: "2026-03-15 08:00:00 +0000", endDate: "2026-03-15 08:00:00 +0000", value: "45.2", unit: "ms", sourceName: "Watch" });
  assert.equal(hrv.uuid, hrv2.uuid, "same record → same uuid (idempotent re-import)");

  const sleep = recordToSample({ type: "HKCategoryTypeIdentifierSleepAnalysis", startDate: "2026-03-15 00:00:00 +0000", endDate: "2026-03-15 07:30:00 +0000", value: "HKCategoryValueSleepAnalysisAsleepCore" });
  assert.equal(sleep.value, 1, "categorical sleep value coerced to 1 (duration = end_ts−ts)");
  assert.equal(sleep.end_ts, "2026-03-15 07:30:00 +0000");
});

test("importHealthExport: daily-aggregates Steps/Energy, keeps raw, respects cutoff", async () => {
  const xml = `<HealthData>
 <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" startDate="2026-03-15 08:00:00 +0000" endDate="2026-03-15 08:00:00 +0000" value="45" unit="ms" sourceName="W"/>
 <Record type="HKQuantityTypeIdentifierStepCount" startDate="2026-03-15 08:00:00 +0000" value="100" sourceName="P"/>
 <Record type="HKQuantityTypeIdentifierStepCount" startDate="2026-03-15 09:00:00 +0000" value="200" sourceName="P"/>
 <Record type="HKQuantityTypeIdentifierStepCount" startDate="2026-03-16 08:00:00 +0000" value="50" sourceName="P"/>
 <Record type="HKQuantityTypeIdentifierStepCount" startDate="2026-06-23 08:00:00 +0000" value="999" sourceName="P"/>
</HealthData>`;
  const inserted = [];
  const pool = {
    query: async (_sql, params) => {
      // params come in groups of 8 (uuid, ts, end_ts, type, value, unit, source, device)
      for (let i = 0; i < params.length; i += 8) {
        inserted.push({ ts: params[i + 1], type: params[i + 3], value: params[i + 4], source: params[i + 6] });
      }
      return { rowCount: params.length / 8 };
    },
  };
  const { Readable } = await import("node:stream");
  const stats = await importHealthExport(pool, Readable.from([xml]), { before: "2026-06-01", batch: 100 });

  // Jun-23 step is after the cutoff → dropped
  assert.ok(!inserted.some((r) => r.value === 999), "post-cutoff sample skipped (no live double-count)");
  // raw HRV kept
  assert.ok(inserted.some((r) => r.type.endsWith("SDNN") && r.value === 45));
  // steps collapsed to one daily-total per day: 03-15 → 300, 03-16 → 50
  const steps = inserted.filter((r) => r.type.endsWith("StepCount"));
  assert.equal(steps.length, 2, "two daily-total step rows, not four raw");
  assert.deepEqual(steps.map((r) => r.value).sort((a, b) => a - b), [50, 300]);
  assert.equal(stats.dailyRows, 2);
});

test("type policy: raw for low-volume, daily-agg for high-volume, HeartRate dropped", () => {
  // raw (resolution matters, low volume)
  assert.ok(RAW_TYPES.has("HKQuantityTypeIdentifierHeartRateVariabilitySDNN"));
  assert.ok(RAW_TYPES.has("HKQuantityTypeIdentifierRestingHeartRate"));
  assert.ok(RAW_TYPES.has("HKCategoryTypeIdentifierSleepAnalysis"));
  // daily-aggregated (high volume, SUMmed anyway)
  assert.ok(AGG_TYPES.has("HKQuantityTypeIdentifierStepCount"));
  assert.ok(AGG_TYPES.has("HKQuantityTypeIdentifierActiveEnergyBurned"));
  // raw HeartRate (millions of samples, unused by aggregateDay) is DROPPED
  assert.ok(!KEPT_TYPES.has("HKQuantityTypeIdentifierHeartRate"), "raw HeartRate excluded (volume)");
});
