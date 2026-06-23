import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const __dir = path.dirname(fileURLToPath(import.meta.url));
const SCHEMA_PATH = path.join(__dir, "..", "sql", "001_schema.sql");

export function makePool(dsn = process.env.PHYSIOME_PG_DSN) {
  if (!dsn) throw new Error("PHYSIOME_PG_DSN not set");
  return new pg.Pool({ connectionString: dsn, max: 4 });
}

export async function ensureSchema(pool) {
  const sql = await readFile(SCHEMA_PATH, "utf8");
  await pool.query(sql);
}

// Build a multi-row "($1,$2,...),($n,...)" placeholder list for `cols` columns over `count` rows.
function placeholders(count, cols) {
  const rows = [];
  let p = 1;
  for (let i = 0; i < count; i++) {
    rows.push("(" + Array.from({ length: cols }, () => `$${p++}`).join(",") + ")");
  }
  return rows.join(",");
}

export async function upsertHealthSamples(pool, rows) {
  if (!rows.length) return 0;
  const cols = 9;
  const vals = [];
  for (const r of rows) vals.push(r.uuid, r.ts, r.end_ts, r.type, r.value, r.unit, r.source, r.device, JSON.stringify(r.metadata || {}));
  const q = `INSERT INTO health_samples (uuid, ts, end_ts, type, value, unit, source, device, metadata)
    VALUES ${placeholders(rows.length, cols)}
    ON CONFLICT (uuid) DO UPDATE SET
      ts=EXCLUDED.ts, end_ts=EXCLUDED.end_ts, type=EXCLUDED.type, value=EXCLUDED.value,
      unit=EXCLUDED.unit, source=EXCLUDED.source, device=EXCLUDED.device, metadata=EXCLUDED.metadata`;
  await pool.query(q, vals);
  return rows.length;
}

export async function upsertWeather(pool, rows) {
  if (!rows.length) return 0;
  const cols = 11;
  const vals = [];
  for (const r of rows) vals.push(r.ts, r.lat, r.lon, r.temp_c, r.pressure_hpa, r.humidity, r.uv_index, r.precip, r.aqi, r.condition, JSON.stringify(r.metadata || {}));
  const q = `INSERT INTO weather_obs (ts, lat, lon, temp_c, pressure_hpa, humidity, uv_index, precip, aqi, condition, metadata)
    VALUES ${placeholders(rows.length, cols)}
    ON CONFLICT (ts, lat, lon) DO UPDATE SET
      temp_c=EXCLUDED.temp_c, pressure_hpa=EXCLUDED.pressure_hpa, humidity=EXCLUDED.humidity,
      uv_index=EXCLUDED.uv_index, precip=EXCLUDED.precip, aqi=EXCLUDED.aqi,
      condition=EXCLUDED.condition, metadata=EXCLUDED.metadata`;
  await pool.query(q, vals);
  return rows.length;
}

export async function upsertSpaceWeather(pool, row) {
  if (!row || !row.ts) return 0;
  await pool.query(
    `INSERT INTO space_weather (ts, kp, f107, solar_wind_speed, bz, source)
     VALUES ($1,$2,$3,$4,$5,$6)
     ON CONFLICT (ts) DO UPDATE SET
       kp=EXCLUDED.kp, f107=EXCLUDED.f107, solar_wind_speed=EXCLUDED.solar_wind_speed,
       bz=EXCLUDED.bz, source=EXCLUDED.source`,
    [row.ts, row.kp, row.f107, row.solar_wind_speed, row.bz, row.source || "noaa-swpc"]
  );
  return 1;
}
