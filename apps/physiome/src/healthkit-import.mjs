// healthkit-import.mjs — ingest a historical Apple Health Export (export.xml) into
// physiome's health_samples. Unblocks the cognitive×physiome correlation: it gives
// physiome the months of HRV/sleep/HR history that overlap the dialogue telemetry.
//
// The export.xml is huge (often GBs), so we STREAM it: each `<Record .../>` opening
// tag carries all attributes we need (type, startDate, endDate, value, unit,
// sourceName, device). We keep only the types aggregateDay() reads, map them 1:1 to
// health_samples rows, and upsert idempotently on a DETERMINISTIC uuid (so re-import
// is a no-op). No XML library — a chunk-buffered regex over the Record opening tags.

import crypto from "node:crypto";

// ROBUSTNESS: keep only what aggregateDay() reads, at the resolution it needs.
//  - RAW (low-volume, resolution matters): HRV-SDNN, RestingHR, SleepAnalysis.
//  - DAILY-AGGREGATED (high-volume; aggregateDay SUMs them anyway): StepCount,
//    ActiveEnergyBurned → collapsed to one daily-total row per day, so a multi-year
//    export adds ~days rows instead of millions.
//  - DROPPED: raw HeartRate — MILLIONS of samples that aggregateDay never uses
//    (it uses RestingHeartRate). Keeping it would bloat the shared beagle-pg for nothing.
export const RAW_TYPES = new Set([
  "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
  "HKQuantityTypeIdentifierRestingHeartRate",
  "HKCategoryTypeIdentifierSleepAnalysis",
]);
export const AGG_TYPES = new Set([
  "HKQuantityTypeIdentifierStepCount",
  "HKQuantityTypeIdentifierActiveEnergyBurned",
]);
export const KEPT_TYPES = new Set([...RAW_TYPES, ...AGG_TYPES]);

function detUuid(key) {
  const h = crypto.createHash("sha256").update(key).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

function parseAttrs(s) {
  const out = {};
  const re = /(\w+)="([^"]*)"/g;
  let m;
  while ((m = re.exec(s)) !== null) out[m[1]] = m[2];
  return out;
}

/** Map an Apple Health Record's attributes to a health_samples row. */
export function recordToSample(attrs) {
  const v = parseFloat(attrs.value);
  return {
    uuid: detUuid(`${attrs.type}|${attrs.startDate}|${attrs.value ?? ""}|${attrs.sourceName ?? ""}`),
    ts: attrs.startDate,
    end_ts: attrs.endDate || null,
    type: attrs.type,
    value: Number.isFinite(v) ? v : 1, // SleepAnalysis value is categorical; duration = end-ts−ts
    unit: attrs.unit || null,
    source: attrs.sourceName || null,
    device: attrs.device || null,
  };
}

/**
 * Stream an export.xml readable, awaiting onRecord(attrs) for each kept <Record>
 * (await so the consumer can do async DB flushes mid-stream).
 * @param {AsyncIterable<Buffer|string>} readable
 * @param {(attrs:object)=>(void|Promise<void>)} onRecord
 * @param {{types?:Set<string>}} [opts]
 */
export async function parseHealthExportStream(readable, onRecord, opts = {}) {
  const types = opts.types ?? KEPT_TYPES;
  let buf = "";
  const re = /<Record\b([^>]*?)\/?>/g;
  for await (const chunk of readable) {
    buf += chunk.toString();
    re.lastIndex = 0;
    let m;
    let lastEnd = 0;
    while ((m = re.exec(buf)) !== null) {
      const attrs = parseAttrs(m[1]);
      if (attrs.type && (!types || types.has(attrs.type)) && attrs.startDate) await onRecord(attrs);
      lastEnd = re.lastIndex;
    }
    buf = lastEnd > 0 ? buf.slice(lastEnd) : buf;
    if (buf.length > 1_000_000) buf = buf.slice(-200_000); // safety: never let the tail blow up
  }
}

/**
 * Import an export.xml stream into health_samples (idempotent, batched).
 * @param {import("pg").Pool} pool
 * @param {AsyncIterable} readable
 * @param {{batch?:number, onProgress?:(n:number)=>void}} [opts]
 * @returns {Promise<{seen:number, inserted:number}>}
 */
export async function importHealthExport(pool, readable, opts = {}) {
  const batchSize = opts.batch ?? 1000;
  // CUTOFF: only import history strictly BEFORE this instant, so the historical
  // import never overlaps (double-counts) the live iOS ingest. Default: the earliest
  // existing sample (the live ingest fills forward; history fills the gap behind it).
  const beforeTs = opts.before != null ? new Date(opts.before).getTime() : Infinity;
  const stats = { seen: 0, inserted: 0, dailyRows: 0 };
  let batch = [];
  const dailySums = new Map(); // `${type}|${day}` → summed value (Steps/Energy)

  const flushRows = async (rows) => {
    if (!rows.length) return 0;
    const vals = [];
    const params = [];
    let p = 1;
    for (const s of rows) {
      vals.push(`($${p++},$${p++},$${p++},$${p++},$${p++},$${p++},$${p++},$${p++})`);
      params.push(s.uuid, s.ts, s.end_ts, s.type, s.value, s.unit, s.source, s.device);
    }
    const r = await pool.query(
      `INSERT INTO health_samples (uuid, ts, end_ts, type, value, unit, source, device)
       VALUES ${vals.join(",")} ON CONFLICT (uuid) DO NOTHING`,
      params,
    );
    return r.rowCount;
  };

  await parseHealthExportStream(readable, async (attrs) => {
    const ts = Date.parse(attrs.startDate);
    if (Number.isFinite(ts) && ts >= beforeTs) return; // skip the live-ingest range
    stats.seen++;
    if (AGG_TYPES.has(attrs.type)) {
      const day = String(attrs.startDate).slice(0, 10);
      const key = `${attrs.type}|${day}`;
      dailySums.set(key, (dailySums.get(key) || 0) + (parseFloat(attrs.value) || 0));
    } else {
      batch.push(recordToSample(attrs));
      if (batch.length >= batchSize) {
        stats.inserted += await flushRows(batch);
        batch = [];
        if (opts.onProgress) opts.onProgress(stats.seen);
      }
    }
  });
  stats.inserted += await flushRows(batch);

  // emit one daily-total row per (type, day) for the aggregated types
  const aggRows = [];
  for (const [key, sum] of dailySums) {
    const [type, day] = key.split("|");
    aggRows.push({
      uuid: detUuid(`${type}|${day}|daily`),
      ts: `${day}T12:00:00Z`, end_ts: null, type, value: sum, unit: null,
      source: "healthkit-import-daily", device: null,
    });
  }
  for (let i = 0; i < aggRows.length; i += batchSize) {
    stats.inserted += await flushRows(aggRows.slice(i, i + batchSize));
  }
  stats.dailyRows = aggRows.length;
  return stats;
}

export default importHealthExport;
