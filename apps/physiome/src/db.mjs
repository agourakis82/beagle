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

const PG_MAX_PARAMS = 65535;

// Upsert `rows` in ONE transaction, split into param-safe chunks. Postgres rejects a
// statement with >65535 bound params, so a real-time backlog (anchored-query catch-up
// after the phone was offline) would 500 on a single giant INSERT. We chunk to stay
// under the ceiling with margin, and wrap in BEGIN/COMMIT so a batch is all-or-nothing
// (a mid-batch failure ROLLBACKs — the idempotent ON CONFLICT makes a full retry safe).
//   colsPerRow: bound params per row;  toParams(row): the row's param values in order.
async function txChunkedUpsert(pool, { sql, colsPerRow, toParams }, rows) {
  if (!rows.length) return 0;
  const chunkSize = Math.min(5000, Math.floor(PG_MAX_PARAMS / colsPerRow));
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (let i = 0; i < rows.length; i += chunkSize) {
      const slice = rows.slice(i, i + chunkSize);
      const vals = [];
      for (const r of slice) vals.push(...toParams(r));
      await client.query(sql(slice.length), vals);
    }
    await client.query("COMMIT");
    return rows.length;
  } catch (e) {
    try { await client.query("ROLLBACK"); } catch { /* connection may be dead */ }
    throw e;
  } finally {
    client.release();
  }
}

// Same transaction/chunking contract as txChunkedUpsert, but the rows travel as ONE
// ARRAY PER COLUMN instead of one placeholder per cell. A 5000-row chunk goes from
// 45000 bound params to 9, so the driver stops building a 45000-entry parameter list
// and the planner parses one tiny statement instead of a megabyte of VALUES.
//
// MEDIDO (13-ago-2026, dentro do pod, tabela real com WAL e a MESMA estrutura de
// health_samples; 3000 linhas/lote, 7 repeticoes ALTERNADAS, mediana):
//   caminho          VALUES    unnest    ganho
//   INSERT novo      84,8 ms   62,6 ms   1,35x
//   ON CONFLICT UPD  66,9 ms   56,5 ms   1,18x
//
// Duas armadilhas que ja cairam nesta mesma medicao:
//  1. Medir contra tabela TEMP mente — temp table nao escreve WAL, ou seja, remove
//     exatamente o custo que domina.
//  2. Medir de tiro unico mente — a dispersao e grande (43-66 ms para o mesmo lote).
//     Uma primeira medicao aqui deu "1,87x"; alternando as duas versoes ao longo de
//     7 repeticoes o ganho real caiu para 1,2-1,35x. Alternar, e usar mediana.
//
// Ou seja: ganho real, modesto, e NAO e onde mora o tempo do ingest. O ingest gasta
// 99,5% no banco (ver project_physiome_ingest_arrow_veredito), mas dentro desse 99,5%
// o custo e disco/WAL/indice, nao a forma do statement.
//
//   columns: [{ name, type, get(row) }] — `type` e o tipo do ELEMENTO; o [] entra aqui.
async function txChunkedUnnest(pool, { table, columns, conflict, chunkSize = 5000 }, rows) {
  if (!rows.length) return 0;
  const names = columns.map((c) => c.name).join(", ");
  const arrays = columns.map((c, i) => `$${i + 1}::${c.type}[]`).join(", ");
  const sql = `INSERT INTO ${table} (${names})
      SELECT * FROM unnest(${arrays})
      ${conflict}`;
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (let i = 0; i < rows.length; i += chunkSize) {
      const slice = rows.slice(i, i + chunkSize);
      await client.query(sql, columns.map((c) => slice.map(c.get)));
    }
    await client.query("COMMIT");
    return rows.length;
  } catch (e) {
    try { await client.query("ROLLBACK"); } catch { /* connection may be dead */ }
    throw e;
  } finally {
    client.release();
  }
}

export async function upsertHealthSamples(pool, rows) {
  return txChunkedUnnest(pool, {
    table: "health_samples",
    columns: [
      { name: "uuid",     type: "uuid",             get: (r) => r.uuid },
      { name: "ts",       type: "timestamptz",      get: (r) => r.ts },
      { name: "end_ts",   type: "timestamptz",      get: (r) => r.end_ts ?? null },
      { name: "type",     type: "text",             get: (r) => r.type },
      { name: "value",    type: "double precision", get: (r) => r.value ?? null },
      { name: "unit",     type: "text",             get: (r) => r.unit ?? null },
      { name: "source",   type: "text",             get: (r) => r.source ?? null },
      { name: "device",   type: "text",             get: (r) => r.device ?? null },
      { name: "metadata", type: "jsonb",            get: (r) => JSON.stringify(r.metadata || {}) },
    ],
    conflict: `ON CONFLICT (uuid) DO UPDATE SET
        ts=EXCLUDED.ts, end_ts=EXCLUDED.end_ts, type=EXCLUDED.type, value=EXCLUDED.value,
        unit=EXCLUDED.unit, source=EXCLUDED.source, device=EXCLUDED.device, metadata=EXCLUDED.metadata`,
  }, rows);
}

// Batch-upsert native-cadence space-weather points into space_weather_hires. `rows` is
// [{ ts, metric, value, source }]. Idempotent (ON CONFLICT (metric, ts)), so the poller can
// safely re-ingest an overlapping trailing window every run without creating duplicates.
export async function upsertHiresSeries(pool, rows) {
  const clean = (rows || []).filter((r) => r && r.ts && r.metric && Number.isFinite(r.value));
  return txChunkedUpsert(pool, {
    colsPerRow: 4,
    toParams: (r) => [r.ts, r.metric, r.value, r.source ?? null],
    sql: (n) => `INSERT INTO space_weather_hires (ts, metric, value, source)
      VALUES ${placeholders(n, 4)}
      ON CONFLICT (metric, ts) DO UPDATE SET value=EXCLUDED.value, source=EXCLUDED.source`,
  }, clean);
}

export async function upsertWeather(pool, rows) {
  return txChunkedUpsert(pool, {
    colsPerRow: 15,
    toParams: (r) => [r.ts, r.lat, r.lon, r.temp_c, r.pressure_hpa, r.humidity, r.uv_index, r.precip, r.aqi, r.condition, JSON.stringify(r.metadata || {}), r.ambient_pressure_hpa ?? null, r.altitude_m ?? null, r.city ?? null, r.place ?? null],
    sql: (n) => `INSERT INTO weather_obs (ts, lat, lon, temp_c, pressure_hpa, humidity, uv_index, precip, aqi, condition, metadata, ambient_pressure_hpa, altitude_m, city, place)
      VALUES ${placeholders(n, 15)}
      ON CONFLICT (ts, lat, lon) DO UPDATE SET
        temp_c=COALESCE(EXCLUDED.temp_c, weather_obs.temp_c), pressure_hpa=COALESCE(EXCLUDED.pressure_hpa, weather_obs.pressure_hpa), humidity=COALESCE(EXCLUDED.humidity, weather_obs.humidity),
        uv_index=COALESCE(EXCLUDED.uv_index, weather_obs.uv_index), precip=COALESCE(EXCLUDED.precip, weather_obs.precip), aqi=COALESCE(EXCLUDED.aqi, weather_obs.aqi),
        condition=COALESCE(EXCLUDED.condition, weather_obs.condition), metadata=EXCLUDED.metadata,
        ambient_pressure_hpa=COALESCE(EXCLUDED.ambient_pressure_hpa, weather_obs.ambient_pressure_hpa),
        altitude_m=COALESCE(EXCLUDED.altitude_m, weather_obs.altitude_m),
        city=COALESCE(EXCLUDED.city, weather_obs.city), place=COALESCE(EXCLUDED.place, weather_obs.place)`,
  }, rows);
}

export async function upsertSpaceWeather(pool, row) {
  if (!row || !row.ts) return 0;
  await pool.query(
    `INSERT INTO space_weather
       (ts, kp, dst, f107, solar_wind_speed, bz, hp30, ap30, hp60, cosmic_ray_oulu,
        xray_flux, proton_flux, aurora_power, sym_h, ae_index, source)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
     ON CONFLICT (ts) DO UPDATE SET
       kp=EXCLUDED.kp, dst=EXCLUDED.dst, f107=EXCLUDED.f107, solar_wind_speed=EXCLUDED.solar_wind_speed,
       bz=EXCLUDED.bz, hp30=EXCLUDED.hp30, ap30=EXCLUDED.ap30, hp60=EXCLUDED.hp60,
       cosmic_ray_oulu=EXCLUDED.cosmic_ray_oulu, xray_flux=EXCLUDED.xray_flux,
       proton_flux=EXCLUDED.proton_flux, aurora_power=EXCLUDED.aurora_power,
       sym_h=EXCLUDED.sym_h, ae_index=EXCLUDED.ae_index, source=EXCLUDED.source`,
    [row.ts, row.kp, row.dst, row.f107, row.solar_wind_speed, row.bz,
     row.hp30 ?? null, row.ap30 ?? null, row.hp60 ?? null, row.cosmic_ray_oulu ?? null,
     row.xray_flux ?? null, row.proton_flux ?? null, row.aurora_power ?? null,
     row.sym_h ?? null, row.ae_index ?? null,
     row.source || "noaa-swpc"]
  );
  return 1;
}

// --- History series for the "Agora" detail screen (weather-app style trends) ---
// All read-only, time-bounded, ASC by ts (chart order), with a row cap for safety.

export async function getSpaceWeatherHistory(pool, hours = 48) {
  const { rows } = await pool.query(
    `SELECT ts, kp, dst, solar_wind_speed, bz, hp30, cosmic_ray_oulu, schumann_f1,
            xray_flux, proton_flux, aurora_power, sym_h, ae_index
       FROM space_weather
     WHERE ts > now() - make_interval(hours => $1) ORDER BY ts ASC LIMIT 1000`,
    [hours]
  );
  return rows;
}

export async function getWeatherHistory(pool, hours = 48) {
  const { rows } = await pool.query(
    `SELECT ts, temp_c, pressure_hpa, humidity, uv_index, aqi,
            ambient_pressure_hpa, altitude_m, city, place
       FROM weather_obs
     WHERE ts > now() - make_interval(hours => $1) ORDER BY ts ASC LIMIT 2000`,
    [hours]
  );
  return rows;
}

export async function getHealthHistory(pool, type, hours = 48) {
  const { rows } = await pool.query(
    `SELECT ts, value FROM health_samples
     WHERE type = $1 AND ts > now() - make_interval(hours => $2) ORDER BY ts ASC LIMIT 2000`,
    [type, hours]
  );
  return rows;
}
