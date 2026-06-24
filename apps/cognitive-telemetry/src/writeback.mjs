// writeback.mjs — Phase B: the sovereign cognitive-telemetry stream.
//
// F's per-turn telemetry is written back to the exocortex (memory-pg) as a
// first-class structured stream — privacy 'sensitive', NEVER leaves the cluster.
// Idempotent per (session_id, turn_idx): re-running a session updates in place.
// Phase C reads this for the companion digest + Physiome correlation. (Phase C
// inference MUST be cluster-robust — the telemetry is strongly autocorrelated.)

const SCHEMA = `
CREATE TABLE IF NOT EXISTS cognitive_telemetry (
  id bigserial PRIMARY KEY,
  session_id text NOT NULL,
  turn_idx int NOT NULL,
  speaker int NOT NULL,
  coherence double precision NOT NULL,
  lr double precision NOT NULL,
  fano int NOT NULL,
  zd double precision NOT NULL,
  rupture boolean NOT NULL,
  occurred_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  privacy_class text NOT NULL DEFAULT 'sensitive',
  UNIQUE (session_id, turn_idx)
);
CREATE INDEX IF NOT EXISTS cogtel_session ON cognitive_telemetry (session_id);
CREATE INDEX IF NOT EXISTS cogtel_rupture ON cognitive_telemetry (occurred_at) WHERE rupture;
`;

export async function ensureTelemetrySchema(pool) {
  await pool.query(SCHEMA);
}

/**
 * Write one session's telemetry (idempotent on session_id+turn_idx).
 * @param {import("pg").Pool} pool
 * @param {{session_id:string, occurred_at?:(string|null)}} session
 * @param {Array<{idx:number,speaker:number,coherence:number,lr:number,fano:number,zd:number,rupture:boolean}>} telemetry
 * @returns {Promise<number>} rows written
 */
export async function writeTelemetry(pool, session, telemetry) {
  let n = 0;
  for (const t of telemetry) {
    await pool.query(
      `INSERT INTO cognitive_telemetry
         (session_id, turn_idx, speaker, coherence, lr, fano, zd, rupture, occurred_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       ON CONFLICT (session_id, turn_idx) DO UPDATE SET
         speaker=EXCLUDED.speaker, coherence=EXCLUDED.coherence, lr=EXCLUDED.lr,
         fano=EXCLUDED.fano, zd=EXCLUDED.zd, rupture=EXCLUDED.rupture,
         occurred_at=EXCLUDED.occurred_at, created_at=now()`,
      [session.session_id, t.idx, t.speaker, t.coherence, t.lr, t.fano, t.zd, t.rupture,
       session.occurred_at || null],
    );
    n++;
  }
  return n;
}

export default writeTelemetry;
