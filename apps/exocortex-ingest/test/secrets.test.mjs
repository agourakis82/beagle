import { test } from "node:test";
import assert from "node:assert/strict";
import { isSensitivePath, scanContent } from "../src/secrets.mjs";

test("excludes sensitive paths by name", () => {
  for (const p of ["a/.ssh/id_ed25519", "x/.env", "y/.credentials.json", "z/key.pem", "t/secrets.yaml"])
    assert.equal(isSensitivePath(p), true, p);
  assert.equal(isSensitivePath("notes/diary.md"), false);
});
test("scanContent flags high-entropy keys, tokens, and PII", () => {
  assert.equal(scanContent("AKIA" + "ABCDEFGHIJKLMNOP").flagged, true); // aws key
  assert.equal(scanContent("sk-" + "a".repeat(40)).flagged, true);       // api key
  assert.equal(scanContent("-----BEGIN PRIVATE KEY-----").flagged, true);
  assert.equal(scanContent("Bearer eyJhbGciOi" + "x".repeat(30)).flagged, true); // jwt-ish
  assert.equal(scanContent("Hoje me senti sobrecarregado e sozinho.").flagged, false);
});
