#!/usr/bin/env node
// bin/backfill-places-names.mjs — one-shot: overwrite weather_obs.place with the user's
// own labeled_places names wherever a row falls inside a place's radius. Run AFTER the
// device has synced its places via POST /api/physiome/places (labeled_places is populated).
//
// Keeps weather_obs.city untouched (city stays the Apple-Maps geocode; only `place`,
// which is the finer "street/POI" label, gets overwritten with e.g. "Minha casa").
//
// Idempotent: safe to re-run — it always recomputes place from the current labeled_places
// set, so a later rename/re-run just re-labels the same rows again.
//
// Run:
//   PHYSIOME_PG_DSN=postgresql://... node apps/physiome/bin/backfill-places-names.mjs
//   PHYSIOME_PG_DSN=... node apps/physiome/bin/backfill-places-names.mjs --dry-run

import { makePool } from "../src/db.mjs";
import { ensurePlacesSchema, getPlaces, matchPlace } from "../src/places.mjs";

const DRY_RUN = process.argv.includes("--dry-run");

async function main() {
  const pool = makePool();
  try {
    await ensurePlacesSchema(pool);
    const places = await getPlaces(pool);
    if (places.length === 0) {
      console.log("[backfill-places] no labeled_places rows yet — sync from device first. Nothing to do.");
      return;
    }
    console.log(`[backfill-places] ${places.length} labeled place(s) loaded.`);

    // Pull distinct (lat, lon) pairs from weather_obs — matching is done in JS (haversine),
    // not SQL, so we only need the coordinate set once, then batch-update by coordinate.
    const { rows: coords } = await pool.query(
      `SELECT DISTINCT lat, lon FROM weather_obs`
    );

    let wouldChange = 0;
    const updates = []; // { lat, lon, place }
    for (const { lat, lon } of coords) {
      const m = matchPlace(places, lat, lon);
      if (m) updates.push({ lat, lon, place: m.name });
    }

    if (updates.length === 0) {
      console.log("[backfill-places] no weather_obs coordinates fall inside any labeled place radius.");
      return;
    }

    // Count how many ROWS (not just coordinates) would actually change value (guards
    // against re-labeling rows that already carry the correct name — cheap idempotency check).
    for (const u of updates) {
      const { rows } = await pool.query(
        `SELECT count(*)::int AS n FROM weather_obs WHERE lat = $1 AND lon = $2 AND (place IS DISTINCT FROM $3)`,
        [u.lat, u.lon, u.place]
      );
      wouldChange += rows[0].n;
    }

    console.log(`[backfill-places] ${updates.length} distinct coordinate(s) matched; ${wouldChange} row(s) would change.`);

    if (DRY_RUN) {
      console.log("[backfill-places] --dry-run: no writes performed.");
      return;
    }

    const client = await pool.connect();
    let touched = 0;
    try {
      await client.query("BEGIN");
      for (const u of updates) {
        const res = await client.query(
          `UPDATE weather_obs SET place = $3 WHERE lat = $1 AND lon = $2 AND (place IS DISTINCT FROM $3)`,
          [u.lat, u.lon, u.place]
        );
        touched += res.rowCount;
      }
      await client.query("COMMIT");
    } catch (e) {
      try { await client.query("ROLLBACK"); } catch { /* connection may be dead */ }
      throw e;
    } finally {
      client.release();
    }
    console.log(`[backfill-places] DONE — ${touched} row(s) updated.`);
  } finally {
    await pool.end();
  }
}

main().catch((e) => {
  console.error("[backfill-places] FAILED:", e);
  process.exit(1);
});
