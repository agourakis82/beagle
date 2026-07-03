// apps/physiome/src/places.mjs — server-side mirror of the device's LabeledPlace store
// (Sources/BeagleCore/AgoraHistory.swift on iOS). The phone is the source of truth for
// naming; this table is a sync target so the server can label weather_obs rows with the
// user's own place names ("Minha casa") instead of the Apple-Maps-geocoded street address.
//
// Schema is created lazily here (NOT wired into apps/physiome/sql/001_schema.sql, which is
// a shared file) — call ensurePlacesSchema(pool) once at boot, same pattern as ensureSchema.

const CREATE_SQL = `
CREATE TABLE IF NOT EXISTS labeled_places (
  id         UUID PRIMARY KEY,
  name       TEXT NOT NULL,
  category   TEXT,
  lat        DOUBLE PRECISION NOT NULL,
  lon        DOUBLE PRECISION NOT NULL,
  radius_m   DOUBLE PRECISION NOT NULL DEFAULT 150,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
`;

export async function ensurePlacesSchema(pool) {
  await pool.query(CREATE_SQL);
}

// Upsert the device's full place list. `rows`: [{id, name, category, lat, lon, radiusM}].
// Sync model is last-writer-wins full-list replace from the device (device is authoritative
// for naming), keyed by id (client-generated UUID) so renames/moves overwrite in place.
export async function upsertPlaces(pool, rows) {
  if (!Array.isArray(rows) || rows.length === 0) return 0;
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (const r of rows) {
      if (!r || !r.id || !r.name || typeof r.lat !== "number" || typeof r.lon !== "number") continue;
      await client.query(
        `INSERT INTO labeled_places (id, name, category, lat, lon, radius_m, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6, now())
         ON CONFLICT (id) DO UPDATE SET
           name=EXCLUDED.name, category=EXCLUDED.category, lat=EXCLUDED.lat, lon=EXCLUDED.lon,
           radius_m=EXCLUDED.radius_m, updated_at=now()`,
        [r.id, r.name, r.category ?? null, r.lat, r.lon, r.radiusM ?? r.radius_m ?? 150]
      );
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

export async function getPlaces(pool) {
  const { rows } = await pool.query(
    `SELECT id, name, category, lat, lon, radius_m AS "radiusM", updated_at AS "updatedAt"
       FROM labeled_places ORDER BY updated_at DESC`
  );
  return rows;
}

const EARTH_RADIUS_M = 6371000;

function haversineMeters(lat1, lon1, lat2, lon2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_M * c;
}

// Nearest labeled place within its own radius, or null. O(n) over places — fine at
// personal-cockpit scale (tens of places), called per weather_obs row.
export function matchPlace(places, lat, lon) {
  let best = null;
  let bestDist = Infinity;
  for (const p of places || []) {
    const d = haversineMeters(lat, lon, p.lat, p.lon);
    const radius = p.radiusM ?? p.radius_m ?? 150;
    if (d <= radius && d < bestDist) {
      best = p;
      bestDist = d;
    }
  }
  return best ? { ...best, distanceM: bestDist } : null;
}
