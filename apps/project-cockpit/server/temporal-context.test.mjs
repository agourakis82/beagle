import { test } from "node:test";
import assert from "node:assert/strict";
import { parteDoDia, relativeTime } from "./temporal-context.mjs";

const TZ = "America/Sao_Paulo"; // UTC-03
const at = (iso) => new Date(iso);

test("parteDoDia by local hour", () => {
  assert.equal(parteDoDia(2), "madrugada");
  assert.equal(parteDoDia(9), "manhã");
  assert.equal(parteDoDia(15), "tarde");
  assert.equal(parteDoDia(21), "noite");
});

test("relativeTime coarsens with distance (tz-correct)", () => {
  const now = at("2026-06-26T23:00:00-03:00");
  assert.equal(relativeTime(at("2026-06-26T22:40:00-03:00"), now, TZ), "agora há pouco"); // <45min
  assert.equal(relativeTime(at("2026-06-26T09:00:00-03:00"), now, TZ), "hoje de manhã");
  assert.equal(relativeTime(at("2026-06-25T15:00:00-03:00"), now, TZ), "ontem");
  assert.equal(relativeTime(at("2026-06-23T10:00:00-03:00"), now, TZ), "há 3 dias");
  assert.equal(relativeTime(at("2026-06-18T10:00:00-03:00"), now, TZ), "semana passada");
  assert.equal(relativeTime(at("2026-06-09T10:00:00-03:00"), now, TZ), "há algumas semanas");
  assert.equal(relativeTime(at("2026-03-09T10:00:00-03:00"), now, TZ), "faz meses");
});

test("relativeTime clamps future/skew to agora há pouco", () => {
  const now = at("2026-06-26T12:00:00-03:00");
  assert.equal(relativeTime(at("2026-06-26T12:30:00-03:00"), now, TZ), "agora há pouco");
});

import { buildTemporalContext, formatTempoAgora, stampMemories } from "./temporal-context.mjs";

test("buildTemporalContext: now label + since-last", () => {
  const ctx = buildTemporalContext({
    now: at("2026-06-26T23:47:00-03:00"),
    timezone: TZ,
    lastContactAt: at("2026-06-23T10:00:00-03:00"),
  });
  assert.equal(ctx.diaDaSemana, "sexta");
  assert.equal(ctx.parteDoDia, "noite");
  assert.match(ctx.nowLabel, /sexta, 26\/jun, 23h47/);
  assert.equal(ctx.desdeUltimo, "há 3 dias");
});

test("buildTemporalContext: first contact has no since-last", () => {
  const ctx = buildTemporalContext({ now: at("2026-06-26T08:00:00-03:00"), timezone: TZ, lastContactAt: null });
  assert.equal(ctx.desdeUltimo, null);
});

test("formatTempoAgora renders the block", () => {
  const block = formatTempoAgora({ nowLabel: "sexta, 26/jun, 23h47", parteDoDia: "noite", desdeUltimo: "há 3 dias" });
  assert.match(block, /^TEMPO AGORA: sexta, 26\/jun, 23h47 \(noite, fuso dele\)\./);
  assert.match(block, /Última vez que se falaram: há 3 dias\./);
  assert.equal(formatTempoAgora(null), "");
});

test("formatTempoAgora first contact line", () => {
  const block = formatTempoAgora({ nowLabel: "sexta, 26/jun, 08h00", parteDoDia: "manhã", desdeUltimo: null });
  assert.match(block, /Primeira vez que vocês se falam\./);
});

test("stampMemories prefixes occurred_at, skips missing, drops empties", () => {
  const now = at("2026-06-26T23:00:00-03:00");
  const out = stampMemories([
    { text: "ele falou da apresentação", occurred_at: "2026-06-25T15:00:00-03:00" },
    { text: "sem data", occurred_at: null },
    { text: "   ", occurred_at: "2026-06-25T15:00:00-03:00" },
  ], now, TZ);
  assert.deepEqual(out, ["[ontem] ele falou da apresentação", "sem data"]);
});
