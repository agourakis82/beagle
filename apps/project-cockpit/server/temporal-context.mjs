// apps/project-cockpit/server/temporal-context.mjs
// Pure temporal context for the Personal-space companion. No I/O and no implicit
// "now" — the caller passes Date objects — so every function is deterministic and
// unit-testable. All phrasing is pt-BR.

function localParts(date, tz) {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
  });
  const p = Object.fromEntries(fmt.formatToParts(date).map((x) => [x.type, x.value]));
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

/** Prefix each memory snippet with its relative date; drop empties; leave
 *  date-less snippets unstamped. `results` = memory-pg /query `.results`. */
export function stampMemories(results, now, tz = "UTC") {
  if (!Array.isArray(results)) return [];
  return results
    .map((r) => {
      const text = typeof r?.text === "string" ? r.text.trim() : "";
      if (!text) return null;
      const when = r?.occurred_at ? new Date(r.occurred_at) : null;
      const valid = when && !Number.isNaN(when.getTime());
      return valid ? `[${relativeTime(when, now, tz)}] ${text}` : text;
    })
    .filter(Boolean);
}
