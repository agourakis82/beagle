// backfill-jsonl.test.mjs — Phase 3 full backfill via streaming the canonical JSONL.
//
// The export endpoint has no pagination and a full export is ~330MB+, which would
// spike the live beagle-core. So the full backfill streams the canonical per-kind
// JSONL files line-by-line instead — zero load on beagle-core, restartable,
// idempotent. This tests the pure streaming/routing logic with a stub capture
// (no DB): parse each line, route by kind through extractFromRecord, tolerate
// malformed lines, and respect the restricted filter.

import { test } from "node:test";
import assert from "node:assert/strict";
import { Readable } from "node:stream";
import { backfillJsonlStream } from "../src/backfill-jsonl.mjs";

function streamOf(lines) {
  return Readable.from(lines.map((l) => (typeof l === "string" ? l : JSON.stringify(l)) + "\n"));
}

test("streams atoms, routes through extractFromRecord, captures each", async () => {
  const captured = [];
  const capture = async (rec) => {
    captured.push(rec);
    return { id: `id-${captured.length}`, created: true };
  };
  const lines = [
    { id: "at1", text: "first atom long enough to be text-bearing", privacy_class: "sensitive" },
    { id: "at2", normalized_text: "second atom normalized text here", privacy_class: "sensitive" },
  ];
  const stats = await backfillJsonlStream(streamOf(lines), "MemoryAtom", { capture, concurrency: 2 });
  assert.equal(stats.lines, 2);
  assert.equal(stats.candidates, 2);
  assert.equal(stats.created, 2);
  assert.equal(captured[0].source_type, "MemoryAtom");
  assert.equal(captured[0].metadata.canonical_id, "at1");
});

test("malformed JSON lines are skipped and counted, not fatal", async () => {
  const capture = async () => ({ id: "x", created: true });
  const src = Readable.from(
    [
      JSON.stringify({ id: "ok1", text: "a valid atom that is plenty long for text" }) + "\n",
      "{not valid json\n",
      "\n", // blank line ignored
      JSON.stringify({ id: "ok2", text: "another valid atom long enough to count" }) + "\n",
    ].join(""),
  );
  const stats = await backfillJsonlStream(src, "MemoryAtom", { capture });
  assert.equal(stats.badLines, 1, "one malformed line counted");
  assert.equal(stats.candidates, 2, "two valid atoms");
  assert.equal(stats.created, 2);
});

test("restricted records yield no captures (privacy filter via extractFromRecord)", async () => {
  const captured = [];
  const capture = async (r) => {
    captured.push(r);
    return { id: "x", created: true };
  };
  const lines = [
    { id: "ok", text: "a normal sensitive atom that is long enough", privacy_class: "sensitive" },
    { id: "secret", text: "restricted content never leaves", privacy_class: "restricted" },
  ];
  const stats = await backfillJsonlStream(streamOf(lines), "MemoryAtom", { capture });
  assert.equal(stats.candidates, 1);
  assert.equal(captured.length, 1);
  assert.equal(captured[0].metadata.canonical_id, "ok");
});

test("passages expand to one capture per non-empty turn", async () => {
  const captured = [];
  const capture = async (r) => {
    captured.push(r);
    return { id: "x", created: true };
  };
  const lines = [
    {
      id: "pa1", privacy_class: "sensitive", occurred_at: "2026-02-02",
      turns: [{ content: "turn zero content long enough to keep" }, { content: "" }, { content: "turn two also long enough here" }],
    },
  ];
  const stats = await backfillJsonlStream(streamOf(lines), "ConversationPassage", { capture });
  assert.equal(stats.candidates, 2, "two non-empty turns");
  assert.deepEqual(captured.map((c) => c.metadata.canonical_id), ["passage:pa1:0", "passage:pa1:2"]);
});

test("tracks created vs duplicate from capture result", async () => {
  let n = 0;
  const capture = async () => {
    n += 1;
    return { id: `id-${n}`, created: n === 1 }; // first new, rest duplicates
  };
  const lines = [
    { id: "a", text: "atom one with sufficient length to be kept here" },
    { id: "b", text: "atom two with sufficient length to be kept here" },
    { id: "c", text: "atom three with sufficient length to be kept here" },
  ];
  const stats = await backfillJsonlStream(streamOf(lines), "MemoryAtom", { capture, concurrency: 1 });
  assert.equal(stats.created, 1);
  assert.equal(stats.duplicate, 2);
});
