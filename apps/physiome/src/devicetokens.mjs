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
-- AUTORIZACAO (13-ago-2026). Ter token e ter permissao de alerta sao coisas
-- DIFERENTES: registerForRemoteNotifications devolve token mesmo sem o usuario
-- ter autorizado nada. Sem esta coluna o servidor manda, a Apple responde 200, e
-- 'entregue' e 'silenciado' ficam indistinguiveis daqui — que foi exatamente o
-- que aconteceu no primeiro teste.
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS autorizacao TEXT;
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS autorizacao_em TIMESTAMPTZ;
`;

export async function ensureDeviceTokensSchema(pool) {
  await pool.query(CREATE_SQL);
}

export async function upsertDeviceToken(pool, { token, apnsEnv, bundle, autorizacao }) {
  await pool.query(
    `INSERT INTO device_tokens (token, apns_env, bundle, autorizacao, autorizacao_em, updated_at)
     VALUES ($1,$2,$3,$4::text, CASE WHEN $4::text IS NULL THEN NULL ELSE now() END, now())
     ON CONFLICT (token) DO UPDATE SET
       apns_env=EXCLUDED.apns_env, bundle=EXCLUDED.bundle,
       -- so sobrescreve quando o cliente REALMENTE informou; um cliente velho
       -- (sem o campo) nao pode apagar o que um cliente novo ja contou.
       autorizacao=COALESCE(EXCLUDED.autorizacao, device_tokens.autorizacao),
       autorizacao_em=COALESCE(EXCLUDED.autorizacao_em, device_tokens.autorizacao_em),
       updated_at=now()`,
    [token, apnsEnv, bundle, autorizacao || null]
  );
}

export async function getLatestDeviceToken(pool) {
  const { rows } = await pool.query(
    `SELECT token, apns_env, bundle, autorizacao, autorizacao_em
       FROM device_tokens ORDER BY updated_at DESC LIMIT 1`
  );
  return rows[0] || null;
}
