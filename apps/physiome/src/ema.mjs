// EMA (Ecological Momentary Assessment) place-change trigger — the exposure-sampling core of
// the N-of-1 heliobiology experiment. When the user's current place changes, this MAY push a
// prompt to log State-of-Mind. GATED OFF by default (EMA_TRIGGER_ENABLED) so the mechanism can
// ship without starting un-pre-registered data collection. Every prompt/response carries a
// protocol_version so a pre-registration is stamped on the data it produces.
//
// Config (all env, re-read per call so `kubectl set env` takes effect with no rebuild):
//   EMA_TRIGGER_ENABLED   "true"|"false"   default false  — master gate
//   EMA_COOLDOWN_MIN      minutes          default 90     — min gap between prompts (anti-spam on commutes)
//   EMA_ACTIVE_HOURS      "8-22"           default 8-22   — local-hour window (don't ping at night)
//   EMA_TZ               IANA tz           default America/Sao_Paulo
//   EMA_LABELED_ONLY     "true"|"false"    default false  — only fire when arriving at a LABELED place
//   EMA_PROTOCOL_VERSION  string           default v0-draft — bump to lock a pre-registration
import { randomUUID } from "node:crypto";
import { sendPush } from "./apns.mjs";
import { getLatestDeviceToken } from "./devicetokens.mjs";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS ema_state (
  id             INT PRIMARY KEY DEFAULT 1,
  last_place     TEXT,
  last_place_ts  TIMESTAMPTZ,
  last_prompt_ts TIMESTAMPTZ,
  CHECK (id = 1)
);
INSERT INTO ema_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
CREATE TABLE IF NOT EXISTS ema_prompts (
  id               UUID PRIMARY KEY,
  ts               TIMESTAMPTZ NOT NULL DEFAULT now(),
  place            TEXT,
  from_place       TEXT,
  trigger          TEXT,
  protocol_version TEXT,
  delivered        BOOLEAN,
  push_status      INT,
  push_reason      TEXT
);
CREATE TABLE IF NOT EXISTS ema_responses (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prompt_id        UUID,
  ts               TIMESTAMPTZ NOT NULL DEFAULT now(),
  valence          DOUBLE PRECISION,
  kind             TEXT,
  labels           JSONB,
  associations     JSONB,
  note             TEXT,
  place            TEXT,
  protocol_version TEXT
);
-- Sampling scheme of this response, stamped directly on the row so exploratory triggers stay
-- separable from the pre-registered place-change protocol WITHOUT a prompt round-trip. Null =
-- the legacy place-change path. HR-event samples carry hr_variation so HELIO-N1 can filter it
-- out (trigger IS DISTINCT FROM hr_variation) and keep the pre-registration clean.
ALTER TABLE ema_responses ADD COLUMN IF NOT EXISTS trigger TEXT;
`;

export async function ensureEmaSchema(pool) {
  await pool.query(SCHEMA);
}

function cfg() {
  const bool = (v) => /^(1|true|yes|on)$/i.test(v || "");
  const [h0, h1] = String(process.env.EMA_ACTIVE_HOURS || "8-22").split("-").map((x) => Number(x));
  return {
    enabled: bool(process.env.EMA_TRIGGER_ENABLED),
    cooldownMin: Number(process.env.EMA_COOLDOWN_MIN || 90),
    startHour: Number.isFinite(h0) ? h0 : 8,
    endHour: Number.isFinite(h1) ? h1 : 22,
    tz: process.env.EMA_TZ || "America/Sao_Paulo",
    labeledOnly: bool(process.env.EMA_LABELED_ONLY),
    protocol: process.env.EMA_PROTOCOL_VERSION || "v0-draft",
    apnsEnv: process.env.APNS_ENV || "sandbox",
  };
}

function localHour(ts, tz) {
  try {
    return Number(new Intl.DateTimeFormat("en-US", { timeZone: tz, hour: "2-digit", hourCycle: "h23" }).format(new Date(ts)));
  } catch { return new Date(ts).getUTCHours(); }
}

// Decide + (maybe) fire an EMA prompt for the user's current place. Always updates last_place so
// the "changed?" test is meaningful next time — even when gated off. Fail-soft: returns a reason.
export async function maybePromptEMA(pool, { place, ts, labeled = false } = {}) {
  if (!place) return { fired: false, reason: "no-place" };
  const c = cfg();
  const { rows } = await pool.query("SELECT last_place, last_prompt_ts FROM ema_state WHERE id = 1");
  const st = rows[0] || {};
  const changed = st.last_place == null ? false : place !== st.last_place;
  const fromPlace = st.last_place ?? null;

  // Track current position regardless of whether we prompt.
  await pool.query("UPDATE ema_state SET last_place = $1, last_place_ts = $2 WHERE id = 1", [place, ts || new Date().toISOString()]);

  if (!c.enabled) return { fired: false, reason: "disabled", changed };
  if (!changed) return { fired: false, reason: "no-change" };
  if (c.labeledOnly && !labeled) return { fired: false, reason: "unlabeled" };

  const hr = localHour(ts || Date.now(), c.tz);
  const inHours = c.startHour <= c.endHour ? hr >= c.startHour && hr < c.endHour : hr >= c.startHour || hr < c.endHour;
  if (!inHours) return { fired: false, reason: "quiet-hours", hr };

  if (st.last_prompt_ts) {
    const ageMin = (Date.now() - new Date(st.last_prompt_ts).getTime()) / 60000;
    if (ageMin < c.cooldownMin) return { fired: false, reason: "cooldown", ageMin: Math.round(ageMin) };
  }

  return fire(pool, { place, fromPlace, trigger: "place_change", protocol: c.protocol, apnsEnv: c.apnsEnv });
}

// Send the push, record the prompt, arm the cooldown. Shared by the trigger + the test endpoint.
export async function fire(pool, { place, fromPlace = null, trigger = "place_change", protocol = "v0-draft", apnsEnv = "sandbox", force = false } = {}) {
  const promptId = randomUUID();
  const tok = await getLatestDeviceToken(pool);
  let push = { ok: false, status: 0, reason: "no-device-token" };
  if (tok) {
    push = await sendPush({
      deviceToken: tok.token,
      title: "Como você está agora?",
      body: fromPlace && place !== fromPlace ? `Você chegou em ${place}. Um instante pra registrar seu estado?`
                                              : `Um instante pra registrar como você está em ${place}?`,
      payload: {
        ema: { prompt_id: promptId, trigger, place, from_place: fromPlace, protocol_version: protocol, ts: new Date().toISOString() },
        aps: { category: "EMA_PLACE_CHANGE", "mutable-content": 1 },
      },
      env: tok.apns_env || apnsEnv,
    });
  }
  await pool.query(
    `INSERT INTO ema_prompts (id, place, from_place, trigger, protocol_version, delivered, push_status, push_reason)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
    [promptId, place, fromPlace, trigger, protocol, !!push.ok, push.status || null, push.reason || null]
  );
  await pool.query("UPDATE ema_state SET last_prompt_ts = now() WHERE id = 1");
  return { fired: true, promptId, pushStatus: push.status, pushOk: !!push.ok, reason: push.ok ? "sent" : push.reason };
}

export async function saveEmaResponse(pool, r) {
  const id = randomUUID();
  await pool.query(
    `INSERT INTO ema_responses (id, prompt_id, ts, valence, kind, labels, associations, note, place, protocol_version, trigger)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
    [id, r.prompt_id || null, r.ts || new Date().toISOString(), num(r.valence), r.kind || "momentaryEmotion",
     JSON.stringify(Array.isArray(r.labels) ? r.labels : []), JSON.stringify(Array.isArray(r.associations) ? r.associations : []),
     typeof r.note === "string" ? r.note : null, r.place || null, r.protocol_version || process.env.EMA_PROTOCOL_VERSION || "v0-draft",
     typeof r.trigger === "string" ? r.trigger : null]
  );
  return id;
}

function num(v) { const n = Number(v); return Number.isFinite(n) ? n : null; }
