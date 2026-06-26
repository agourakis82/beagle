import { test } from "node:test";
import assert from "node:assert/strict";
import { buildDistillPrompt } from "../src/digest.mjs";

test("distill prompt includes recent git + caps length", () => {
  const p = buildDistillPrompt({
    gitLines: ["2026-06-20 feat: x", "2026-06-19 fix: y"],
    profileFacts: ["psiquiatra", "plataforma desde dez"],
  });
  assert.ok(p.includes("feat: x"));
  assert.ok(p.includes("psiquiatra"));
  assert.ok(p.length < 8000);
});
