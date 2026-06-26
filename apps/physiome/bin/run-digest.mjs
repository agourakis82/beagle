// Build the daily Physiome digest and store it (sovereign) into the exocortex.
import { makePool } from "../src/db.mjs";
import { generateDigest } from "../src/digest.mjs";
import { assistedImport } from "../../exocortex-ingest/src/contracts.mjs";

const date = process.argv[2] || new Date().toISOString().slice(0, 10); // UTC day, YYYY-MM-DD
const pool = makePool();
try {
  const { summary } = await generateDigest(pool, date, { assistedImport });
  console.log("[physiome-digest]\n" + summary);
} finally {
  await pool.end();
}
