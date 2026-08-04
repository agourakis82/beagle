// apps/project-cockpit/server/temporal-context.mjs
// Pure temporal context for the Personal-space companion. No I/O and no implicit
// "now" — the caller passes Date objects — so every function is deterministic and
// unit-testable. All phrasing is pt-BR.

const FMT_OPTS = {
  year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", hour12: false,
};

// Intl.DateTimeFormat throws RangeError on a non-IANA timeZone. The tz comes from
// untrusted client input, so fall back to UTC instead of letting it propagate —
// this makes EVERY function in this module self-defending (no caller can be broken
// by a malformed timezone).
function safeFormatter(tz) {
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone: tz, ...FMT_OPTS });
  } catch {
    return new Intl.DateTimeFormat("en-CA", { timeZone: "UTC", ...FMT_OPTS });
  }
}

// The intimate companion is single-user. When the client omits or garbles the
// timezone, the fallback must be HIS home zone — never UTC. UTC is +3h from his
// local time, which routinely crosses the madrugada/manhã/tarde/noite boundaries,
// so a UTC fallback makes the "## Agora" TEMPO line name the wrong part of the day
// (e.g. "de madrugada" while he's having breakfast). Overridable per deployment.
export const HOME_TIMEZONE = process.env.PROJECT_COCKPIT_HOME_TZ || "America/Sao_Paulo";

export function isValidTimeZone(tz) {
  if (typeof tz !== "string" || !tz.trim()) return false;
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: tz.trim() });
    return true;
  } catch {
    return false;
  }
}

/** Prefer a valid client-sent IANA zone; otherwise the user's home zone (never UTC). */
export function resolveTimezone(clientTz) {
  return isValidTimeZone(clientTz) ? clientTz.trim() : HOME_TIMEZONE;
}

function localParts(date, tz) {
  const p = Object.fromEntries(safeFormatter(tz).formatToParts(date).map((x) => [x.type, x.value]));
  return { y: +p.year, m: +p.month, d: +p.day, hour: +p.hour, minute: +p.minute };
}

function localDayNumber(date, tz) {
  const { y, m, d } = localParts(date, tz);
  return Math.floor(Date.UTC(y, m - 1, d) / 86400000);
}

const HOJE_PREP = { madrugada: "de madrugada", manhã: "de manhã", tarde: "à tarde", noite: "à noite" };

/** Bare part-of-day word from a local hour. */
export function parteDoDia(hour) {
  if (hour < 5) return "madrugada";
  if (hour < 12) return "manhã";
  if (hour < 18) return "tarde";
  return "noite";
}

/** pt-BR relative phrasing of `from` seen from `to`, in IANA `tz`. Coarsens with
 *  distance; clamps future/skew to "agora há pouco". */
export function relativeTime(from, to, tz = "UTC") {
  const deltaMs = to.getTime() - from.getTime();
  if (deltaMs < 45 * 60 * 1000) return "agora há pouco";
  const days = localDayNumber(to, tz) - localDayNumber(from, tz);
  if (days <= 0) return "hoje " + HOJE_PREP[parteDoDia(localParts(from, tz).hour)];
  // A short gap that merely crossed local midnight isn't really "ontem" (e.g. 23h44
  // seen from 00h30). Only call it "ontem" once the gap is genuinely a day-ish.
  if (days === 1 && deltaMs < 6 * 60 * 60 * 1000) return "há poucas horas";
  if (days === 1) return "ontem";
  if (days < 7) return `há ${days} dias`;
  if (days < 14) return "semana passada";
  if (days < 30) return "há algumas semanas";
  return "faz meses";
}

const DIAS = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"];
const MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

/** Build the temporal context object from a real `now` (Date), IANA tz, and the
 *  client-supplied last-contact timestamp (Date|null). */
export function buildTemporalContext({ now, timezone = "UTC", lastContactAt = null }) {
  const lp = localParts(now, timezone);
  const dow = new Date(Date.UTC(lp.y, lp.m - 1, lp.d)).getUTCDay();
  const hh = String(lp.hour).padStart(2, "0");
  const mm = String(lp.minute).padStart(2, "0");
  return {
    nowLabel: `${DIAS[dow]}, ${lp.d}/${MESES[lp.m - 1]}, ${hh}h${mm}`,
    diaDaSemana: DIAS[dow],
    parteDoDia: parteDoDia(lp.hour),
    desdeUltimo: lastContactAt ? relativeTime(lastContactAt, now, timezone) : null,
  };
}

/** Render the injected TEMPO AGORA block, or "" when there is no context. */
export function formatTempoAgora(ctx) {
  if (!ctx || !ctx.nowLabel) return "";
  const lines = [`TEMPO AGORA: ${ctx.nowLabel} (${ctx.parteDoDia}, fuso dele).`];
  lines.push(ctx.desdeUltimo
    ? `Última vez que se falaram: ${ctx.desdeUltimo}.`
    : "Primeira vez que vocês se falam.");
  return lines.join("\n");
}

// --- `## Agora` — the instant the app opened: tempo + corpo + céu, consolidated ---
// One block so the prompt == what the screen shows (HRV strip, mascote aura). All
// pt-BR; narrative-first (named state, raw number only as a parenthetical aside).

function num(v) {
  // Number(null) === 0 and Number("") === 0 — guard those so absent fields read as null.
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/** pt-BR readiness label from the iOS PhysioReadiness raw value. */
export function readinessPtBR(raw) {
  switch (String(raw || "").toLowerCase()) {
    case "restored": return "recuperado";
    case "steady": return "estável";
    case "strained": return "tenso";
    default: return "";
  }
}

/** Kp geomagnetic band (planetary K-index, 0–9). */
export function kpBand(kp) {
  const v = num(kp);
  if (v === null) return "";
  if (v < 4) return "calmo";
  if (v < 5) return "agitado";
  return "tempestade";
}

// Rank a band label by severity so the CÉU line can lead with the worst of Kp/Dst.
function skySeverity(label) {
  switch (label) {
    case "calmo": return 0;
    case "agitado": case "perturbado": return 1;
    case "tempestade": case "tempestade moderada": return 2;
    case "tempestade intensa": return 3;
    case "tempestade severa": return 4;
    default: return -1;
  }
}

/** Dst storm band (disturbance storm-time index, nT; more negative = deeper storm). */
export function dstBand(dst) {
  const v = num(dst);
  if (v === null) return "";
  if (v > -20) return "calmo";
  if (v > -50) return "perturbado";
  if (v > -100) return "tempestade moderada";
  if (v > -200) return "tempestade intensa";
  return "tempestade severa";
}

// Decimal comma for pt-BR; trims a trailing ",0".
function ptNum(v, digits = 1) {
  const n = num(v);
  if (n === null) return "";
  return n.toFixed(digits).replace(/\.0$/, "").replace(".", ",");
}

/**
 * Consolidated `## Agora` block — the live instant the user opened the chat.
 *   ctx  = buildTemporalContext(...) output (TEMPO)
 *   body = { hrvMs, readiness, sleepHours, flowState } (CORPO; client physio)
 *   sky  = { kp, dst, solarWind, bz } (CÉU; client values, server fetch as fallback)
 * Missing sections drop out (fail-open). Returns "" if nothing at all is known.
 */
export function formatAgora({ ctx, body = {}, sky = {}, episodeMinutes = null } = {}) {
  const lines = [];

  const tempo = formatTempoAgora(ctx);
  if (tempo) {
    // TEMPO awareness: how long they've been in this exchange. A sustained conversation
    // (a distress spell that runs an hour) should be felt as duration, not a single instant.
    const dur = num(episodeMinutes);
    const durTxt = dur !== null && dur >= 12 ? ` Estão nisto há ~${humanMin(dur)}.` : "";
    lines.push(tempo + durTxt);
  }

  // CORPO: lead with the NAMED state (recuperado/estável/tenso); the numbers ride in a
  // parenthetical the model can drop. Narrative-first so it speaks the state, not the readout.
  const hr = num(body.heartRate);
  const hrv = num(body.hrvMs);
  const sleep = num(body.sleepHours);
  const readiness = readinessPtBR(body.readiness);
  const detail = [];
  // Heart first: it is the live interoceptive anchor — the thing to name back in a hard moment.
  if (hr !== null) detail.push(`coração ${Math.round(hr)} bpm`);
  if (hrv !== null) detail.push(`HRV ${Math.round(hrv)}ms`);
  if (sleep !== null) detail.push(`sono ${ptNum(sleep)}h`);
  const paren = detail.length ? ` (${detail.join(" · ")})` : "";
  const lead = readiness || cleanFlow(body.flowState);
  if (lead) {
    lines.push(`CORPO: ${lead}${paren}.`);
  } else if (detail.length) {
    lines.push(`CORPO: ${detail.join(" · ")}.`);
  }

  // VOZ: como ESTA fala saiu, quando ele falou em vez de digitar.
  //
  // Derivado no aparelho (VoiceAcousticAnalyzer) e enviado como número — o áudio
  // é descartado e nunca sai do iPhone. Viaja com o turno, não pelo digest: o
  // digest é média do dia, e tom é sobre a frase que ele acabou de dizer.
  //
  // Só ritmo e pausa. Volume em dBFS depende de distância do microfone e de estar
  // de fone; variação de F0 idem. Usar seria fingir precisão que o dado não tem.
  //
  // FRONTEIRA: isto descreve a FALA, nunca o falante. "Falou com pausas longas" é
  // observação; "está cansado" seria diagnóstico — e diagnosticar pelo tom é
  // exatamente o que o invariante da presença proíbe. Se importar, ele pergunta.
  const wpm = num(body.voiceSpeechRateWpm);
  const pausa = num(body.voicePauseRatio);
  const voz = [];
  if (wpm !== null) {
    if (wpm < 100) voz.push("devagar");
    else if (wpm > 180) voz.push("apressado");
  }
  if (pausa !== null && pausa > 0.35) voz.push("com pausas longas");
  if (voz.length) {
    lines.push(
      `VOZ: ele falou ${voz.join(", ")} neste turno — é como a fala saiu, ` +
      `não um diagnóstico dele. Não devolva isso como rótulo; se importar, pergunte.`
    );
  }

  // AFETO: his OWN logged State of Mind (Apple Health, iOS 18+). His testimony about how he
  // feels — honor it, never re-ask what he already recorded. Felt, not recited (block header).
  const affect = stateOfMindPtBR(body.stateOfMind, body.stateOfMindLabel);
  if (affect) lines.push(`AFETO: você mesmo registrou-se ${affect} — é seu, parta disso, não repergunte.`);

  // CÉU: lead with the worst-of-Kp/Dst band as the felt descriptor; the raw values ride in
  // the parenthetical. Omit the whole line only when neither Kp nor Dst is known.
  const kb = kpBand(sky.kp), db = dstBand(sky.dst);
  if (kb || db) {
    const skyLead = skySeverity(db) >= skySeverity(kb) ? (db || kb) : (kb || db);
    const detailSky = [];
    if (kb) detailSky.push(`Kp ${ptNum(sky.kp)}`);
    if (db) detailSky.push(`Dst ${Math.round(num(sky.dst))} nT`);
    if (num(sky.solarWind) !== null) detailSky.push(`vento solar ${Math.round(num(sky.solarWind))} km/s`);
    lines.push(`CÉU: ${skyLead} (${detailSky.join(" · ")}).`);
  }

  if (lines.length <= 0) return "";
  // Header doubles as the instruction: this is private sensing, not a script to recite.
  return ["## Agora — o instante dele (sinta e fale como vivido; nunca recite número nem rótulo)", ...lines].join("\n");
}

function cleanFlow(flowState) {
  const f = String(flowState || "").toUpperCase();
  if (f === "FLOW") return "fluxo";
  if (f === "STRESS") return "tensão";
  if (f === "NORMAL") return "equilíbrio";
  return "";
}

// Minutes → human pt-BR ("40 min", "1 h 20").
function humanMin(m) {
  m = Math.round(m);
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60), r = m % 60;
  return r ? `${h} h ${String(r).padStart(2, "0")}` : `${h} h`;
}

/**
 * Apple State of Mind → felt pt-BR descriptor. `valence` is HKStateOfMind valence (−1..1);
 * `label` is the optional emotion word he tagged ("ansioso"). The label carries the meaning —
 * prefer it, with the valence band as texture. Returns "" when neither is present.
 */
export function stateOfMindPtBR(valence, label) {
  const lab = typeof label === "string" ? label.trim() : "";
  const v = num(valence);
  let band = "";
  if (v !== null) {
    if (v <= -0.6) band = "muito desagradável";
    else if (v <= -0.2) band = "desagradável";
    else if (v < 0.2) band = "neutro";
    else if (v < 0.6) band = "agradável";
    else band = "muito agradável";
  }
  if (lab && band) return `${lab} (${band})`;
  return lab || band || "";
}

// Cap each recalled snippet so a few large memory-pg rows can't bloat the system
// prompt (token-cost / context overflow). k bounds the count; this bounds the size.
const MAX_SNIPPET = 600;

/**
 * Trust gate for biography grounding (provenance design §4): drop `unverified`
 * memories (orphaned/model-generated content) so they are never injected as
 * "what I know about him". A hit with no tier is kept (fail-open: non-personal
 * recall and pre-P2 rows are not penalized).
 * @param {Array<{trust_tier?: string}>} results
 */
export function filterTrustedMemories(results) {
  if (!Array.isArray(results)) return [];
  // Drop unverified (the companion's own past replies + old generic-assistant echoes come back
  // as 'memories') AND empty-text chunks (a data-quality artifact that wastes recall slots).
  return results.filter((r) => {
    if (r?.trust_tier === "unverified") return false;
    const txt = r?.text ?? r?.content ?? r?.snippet ?? "";
    return typeof txt === "string" && txt.trim().length > 0;
  });
}

/** Prefix each memory snippet with its relative date; drop empties; leave
 *  date-less snippets unstamped; cap each snippet's length. `results` =
 *  memory-pg /query `.results`. */
export function stampMemories(results, now, tz = "UTC") {
  if (!Array.isArray(results)) return [];
  return results
    .map((r) => {
      let text = typeof r?.text === "string" ? r.text.trim() : "";
      if (!text) return null;
      if (text.length > MAX_SNIPPET) text = text.slice(0, MAX_SNIPPET) + "…";
      const when = r?.occurred_at ? new Date(r.occurred_at) : null;
      const valid = when && !Number.isNaN(when.getTime());
      return valid ? `[${relativeTime(when, now, tz)}] ${text}` : text;
    })
    .filter(Boolean);
}
