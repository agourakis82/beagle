import { test } from "node:test";
import assert from "node:assert/strict";
import { filterTrustedMemories } from "./temporal-context.mjs";

test("drops unverified hits, keeps claimed/corroborated/known", async () => {
  const hits = [
    { text: "fabricated orphan atom", trust_tier: "unverified" },
    { text: "you said you run marathons", trust_tier: "claimed" },
    { text: "confirmed across sessions", trust_tier: "corroborated" },
    { text: "a known fact", trust_tier: "known" },
  ];
  const kept = filterTrustedMemories(hits);
  const texts = kept.map((h) => h.text);
  assert.deepEqual(texts, [
    "you said you run marathons",
    "confirmed across sessions",
    "a known fact",
  ]);
});

test("a hit with no trust_tier is kept (fail-open for non-personal recall)", async () => {
  const kept = filterTrustedMemories([{ text: "untiered", trust_tier: undefined }]);
  assert.equal(kept.length, 1);
});

test("non-array input yields an empty array", async () => {
  assert.deepEqual(filterTrustedMemories(null), []);
});
