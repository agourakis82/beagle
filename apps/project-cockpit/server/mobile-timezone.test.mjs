// The companion must know it's HIS morning — the ## Agora TEMPO must never fall back
// to UTC. Guards the 2026-07-07 finding: a UTC fallback named "madrugada" at breakfast.
import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveTimezone, HOME_TIMEZONE, buildTemporalContext } from "./temporal-context.mjs";

test("home timezone is São Paulo (never UTC)", () => {
  assert.equal(HOME_TIMEZONE, "America/Sao_Paulo");
});

test("missing/blank timezone resolves to home, not UTC", () => {
  assert.equal(resolveTimezone(undefined), "America/Sao_Paulo");
  assert.equal(resolveTimezone(""), "America/Sao_Paulo");
  assert.equal(resolveTimezone("   "), "America/Sao_Paulo");
  assert.equal(resolveTimezone(null), "America/Sao_Paulo");
});

test("a valid client timezone still wins (he might travel)", () => {
  assert.equal(resolveTimezone("America/New_York"), "America/New_York");
  assert.equal(resolveTimezone("Europe/Lisbon"), "Europe/Lisbon");
  assert.equal(resolveTimezone("  America/Sao_Paulo  "), "America/Sao_Paulo");
  assert.equal(resolveTimezone("UTC"), "UTC"); // explicit UTC is honored; only the *default* changed
});

test("a garbled timezone falls back to home, not UTC", () => {
  assert.equal(resolveTimezone("Not/AZone"), "America/Sao_Paulo");
  assert.equal(resolveTimezone("America/Sorocaba"), "America/Sao_Paulo");
});

test("part-of-day is his local one, not UTC's — the actual bug", () => {
  // 2026-07-07T02:00:00Z: UTC says 02h → "madrugada"; São Paulo (UTC-3) says 23h prev
  // day → "noite". With no client tz we must resolve to home and say NOITE.
  const instant = new Date("2026-07-07T02:00:00Z");
  const tz = resolveTimezone(undefined);
  const ctx = buildTemporalContext({ now: instant, timezone: tz });
  assert.equal(ctx.parteDoDia, "noite", "must reflect his local night, not UTC madrugada");
});

test("his real morning reads as manhã", () => {
  // 2026-07-07T11:20:00Z = 08:20 in São Paulo → manhã.
  const ctx = buildTemporalContext({ now: new Date("2026-07-07T11:20:00Z"), timezone: resolveTimezone("") });
  assert.equal(ctx.parteDoDia, "manhã");
});
