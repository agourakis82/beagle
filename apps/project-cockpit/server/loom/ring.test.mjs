import { test } from "node:test";
import assert from "node:assert/strict";
import { Ring } from "./ring.mjs";

test("ring keeps only the last capBytes of appended text", () => {
  const r = new Ring(5);
  r.push("abc"); r.push("de"); r.push("fg");   // "abcdefg" -> keep last 5
  assert.equal(r.snapshot(), "cdefg");
  assert.ok(r.size <= 5);
});
test("ring snapshot of a short stream is the whole stream", () => {
  const r = new Ring(100);
  r.push("hello"); assert.equal(r.snapshot(), "hello");
});
