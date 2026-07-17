import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { chunkText } from "../src/chunk.mjs";

const HEX64 = /^[0-9a-f]{64}$/;

function sha256hex(s) {
  return crypto.createHash("sha256").update(s).digest("hex");
}

test("never cuts a word in half (hardSplit + overlap word-boundary)", () => {
  // one long space-separated run of distinct tokens, no blank lines, so it is a
  // single oversized segment forced through hardSplit; a small target also makes
  // the overlap tail land mid-token. Every emitted token must be a WHOLE word.
  const words = [];
  for (let i = 0; i < 400; i++) words.push("palavra" + i);
  const text = words.join(" ");
  const chunks = chunkText(text, { target: 20, overlap: 0.1 }); // 80-char window
  assert.ok(chunks.length > 1, `expected multiple chunks, got ${chunks.length}`);
  for (const c of chunks) {
    for (const tok of c.text.trim().split(/\s+/)) {
      assert.match(tok, /^palavra\d+$/, `mid-word fragment "${tok}" in chunk "${c.text.slice(0, 60)}"`);
    }
  }
});

test("a single token longer than the window still splits and terminates", () => {
  const chunks = chunkText("x".repeat(500), { target: 20 }); // no whitespace to break on
  assert.ok(chunks.length > 1, "the long token is split into multiple chunks");
  // content preserved exactly: overlap on a whitespace-free token is dropped, so
  // the x's are neither lost nor runaway-duplicated.
  const xCount = chunks.map((c) => c.text).join("").replace(/[^x]/g, "").length;
  assert.equal(xCount, 500);
});

test("short text (< target) → exactly 1 chunk, index 0, 64-hex sha", () => {
  const text = "This is a short note that is comfortably under the target size.";
  const chunks = chunkText(text);
  assert.equal(chunks.length, 1);
  assert.equal(chunks[0].chunk_index, 0);
  assert.match(chunks[0].sha256, HEX64);
  // sha is the sha of the final chunk text
  assert.equal(chunks[0].sha256, sha256hex(chunks[0].text));
});

test("long text → multiple chunks, contiguous indices, bounded length", () => {
  const target = 384;
  const overlap = 0.1;
  // 20 paragraphs of ~300 chars each
  const paras = [];
  for (let i = 0; i < 20; i++) {
    paras.push(`Paragraph ${i}. ` + "lorem ipsum dolor sit amet ".repeat(11));
  }
  const text = paras.join("\n\n");
  const chunks = chunkText(text, { target, overlap });

  assert.ok(chunks.length > 1, `expected multiple chunks, got ${chunks.length}`);

  // contiguous 0..n-1
  chunks.forEach((c, i) => assert.equal(c.chunk_index, i));

  // each chunk roughly bounded: target*4 chars + overlap slack + one segment slack
  const maxChars = target * 4 * (1 + overlap) + 400;
  for (const c of chunks) {
    assert.ok(
      c.text.length <= maxChars,
      `chunk ${c.chunk_index} length ${c.text.length} exceeds bound ${maxChars}`
    );
    // sha matches final text
    assert.equal(c.sha256, sha256hex(c.text));
  }
});

test("overlap invariant: chunk[i+1] begins with a WORD-ALIGNED tail of chunk[i]", () => {
  // distinct tokens so overlap carry-over is decisively checkable (and any
  // mid-word fragment would fail the /^tok\d{4}$/ shape).
  const words = [];
  for (let i = 0; i < 300; i++) words.push("tok" + String(i).padStart(4, "0"));
  const text = words.join(" ");
  const chunks = chunkText(text, { target: 30, overlap: 0.2 });
  assert.ok(chunks.length > 1);

  for (let i = 0; i < chunks.length - 1; i++) {
    const prevToks = chunks[i].text.trim().split(/\s+/);
    const nextToks = chunks[i + 1].text.trim().split(/\s+/);
    // every token whole (no mid-word fragment introduced by hardSplit OR overlap).
    for (const t of nextToks) assert.match(t, /^tok\d{4}$/, `fragment "${t}"`);
    // real overlap: chunk i+1 begins with a token carried from the tail of chunk i.
    assert.ok(prevToks.includes(nextToks[0]), `overlap head ${nextToks[0]} not carried from prev`);
  }
});

test("determinism: same input → identical sha list across two calls", () => {
  const paras = [];
  for (let i = 0; i < 20; i++) {
    paras.push(`Paragraph ${i}. ` + "lorem ipsum dolor sit amet ".repeat(11));
  }
  const text = paras.join("\n\n");
  const a = chunkText(text).map((c) => c.sha256);
  const b = chunkText(text).map((c) => c.sha256);
  assert.deepEqual(a, b);
  assert.ok(a.length > 1);
});

test("sha sensitivity: changing one chunk's source text changes only that chunk's sha", () => {
  const target = 384;
  const paras = [];
  for (let i = 0; i < 20; i++) {
    paras.push(`Paragraph ${i}. ` + "lorem ipsum dolor sit amet ".repeat(11));
  }
  const base = chunkText(paras.join("\n\n"), { target });

  // Mutate the LAST paragraph's content (tail of the doc → affects only the
  // final chunk(s), leaving earlier chunks identical).
  const paras2 = paras.slice();
  paras2[paras2.length - 1] =
    paras2[paras2.length - 1] + " ZZZUNIQUEMARKERZZZ extra trailing content here";
  const mutated = chunkText(paras2.join("\n\n"), { target });

  // The earliest chunks should be byte-identical (same sha).
  let firstDiff = -1;
  const n = Math.min(base.length, mutated.length);
  for (let i = 0; i < n; i++) {
    if (base[i].sha256 !== mutated[i].sha256) {
      firstDiff = i;
      break;
    }
  }
  assert.ok(firstDiff > 0, `expected leading chunks unchanged; firstDiff=${firstDiff}`);
  // All chunks before firstDiff are identical
  for (let i = 0; i < firstDiff; i++) {
    assert.equal(base[i].sha256, mutated[i].sha256);
  }
  // The differing chunk's text actually differs (sanity)
  assert.notEqual(base[firstDiff].sha256, mutated[firstDiff].sha256);
});

test("empty/whitespace input → [] (no chunks)", () => {
  assert.deepEqual(chunkText(""), []);
  assert.deepEqual(chunkText("   \n\n   \t  \n"), []);
  assert.deepEqual(chunkText(undefined), []);
  assert.deepEqual(chunkText(null), []);
});

test("tiny content under minChars is still emitted as the only chunk", () => {
  const text = "hi";
  const chunks = chunkText(text, { minChars: 40 });
  assert.equal(chunks.length, 1);
  assert.equal(chunks[0].text, "hi");
  assert.match(chunks[0].sha256, HEX64);
});

test("single oversized segment is hard-split into multiple chunks", () => {
  const target = 100; // small target → 400 chars
  // one segment (no blank lines), much larger than target*4
  const big = "x".repeat(4000);
  const chunks = chunkText(big, { target, overlap: 0.1 });
  assert.ok(chunks.length > 1, `expected hard-split, got ${chunks.length}`);
  chunks.forEach((c, i) => assert.equal(c.chunk_index, i));
});
