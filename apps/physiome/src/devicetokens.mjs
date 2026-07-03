// APNs device-token registry (lazy-schema convention, like places.mjs — not 001_schema.sql).
// The iOS app POSTs its APNs token to /api/physiome/device-token; the server pushes to the
// most-recently-registered token via apps/physiome/src/apns.mjs.
const CREATE_SQL = `
CREATE TABLE IF NOT EXISTS device_tokens (
  token      TEXT PRIMARY KEY,
  apns_env   TEXT,
  bundle     TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
`;

export async function ensureDeviceTokensSchema(pool) {
  await pool.query(CREATE_SQL);
}

export async function upsertDeviceToken(pool, { token, apnsEnv, bundle }) {
  await pool.query(
    `INSERT INTO device_tokens (token, apns_env, bundle, updated_at)
     VALUES ($1,$2,$3, now())
     ON CONFLICT (token) DO UPDATE SET
       apns_env=EXCLUDED.apns_env, bundle=EXCLUDED.bundle, updated_at=now()`,
    [token, apnsEnv, bundle]
  );
}

export async function getLatestDeviceToken(pool) {
  const { rows } = await pool.query(
    `SELECT token, apns_env, bundle FROM device_tokens ORDER BY updated_at DESC LIMIT 1`
  );
  return rows[0] || null;
}
