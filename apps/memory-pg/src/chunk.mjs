import crypto from "node:crypto";

// Approximate tokens as chars/4.
const CHARS_PER_TOKEN = 4;

function sha256hex(s) {
  return crypto.createHash("sha256").update(s).digest("hex");
}

/**
 * Hard-split a single oversized string into <= maxChars pieces, breaking on a
 * WORD boundary (the last whitespace in the window) so a chunk never ends
 * mid-word. A single token longer than the window has no boundary to break on,
 * so it falls back to a hard cut (best effort — better than losing content).
 */
function hardSplit(s, maxChars) {
  const out = [];
  let i = 0;
  while (i < s.length) {
    let end = i + maxChars;
    if (end >= s.length) {
      out.push(s.slice(i));
      break;
    }
    // snap back to the last whitespace inside the window to keep words whole.
    let cut = -1;
    for (let j = end; j > i; j--) {
      if (/\s/.test(s[j])) {
        cut = j;
        break;
      }
    }
    if (cut > i) end = cut;
    out.push(s.slice(i, end));
    i = end;
  }
  return out.map((p) => p.trim()).filter((p) => p.length > 0);
}

/**
 * Segment-aware chunking with per-chunk sha256.
 *
 * @param {string} text
 * @param {{target?:number, overlap?:number, minChars?:number}} [opts]
 *   target   - approximate chunk size in TOKENS (chars ≈ target*4)
 *   overlap  - fraction (0..1) of the previous chunk's tail carried into the next
 *   minChars - drop/merge fragments shorter than this (unless sole content)
 * @returns {Array<{chunk_index:number, text:string, sha256:string}>}
 */
export function chunkText(text, opts = {}) {
  const { target = 384, overlap = 0.1, minChars = 40 } = opts;

  if (text == null) return [];
  if (typeof text !== "string") return [];
  if (text.trim().length === 0) return [];

  const targetChars = target * CHARS_PER_TOKEN;
  const overlapChars = Math.floor(target * overlap) * CHARS_PER_TOKEN;

  // 1. Split on natural boundaries (blank lines / turn boundaries).
  let segments = text
    .split(/\n\s*\n/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  // 2. Hard-split any segment larger than the target.
  const units = [];
  for (const seg of segments) {
    if (seg.length > targetChars) {
      for (const piece of hardSplit(seg, targetChars)) units.push(piece);
    } else {
      units.push(seg);
    }
  }

  if (units.length === 0) return [];

  // 3. Pack consecutive units into chunks of ~targetChars.
  const packed = [];
  let cur = "";
  for (const u of units) {
    if (cur.length === 0) {
      cur = u;
    } else if (cur.length + 1 + u.length <= targetChars) {
      cur = cur + "\n\n" + u;
    } else {
      packed.push(cur);
      cur = u;
    }
  }
  if (cur.length > 0) packed.push(cur);

  // 4. Merge trailing fragments shorter than minChars into the previous chunk
  //    (don't emit a sub-minChars chunk unless it's the only content).
  for (let i = packed.length - 1; i > 0; i--) {
    if (packed[i].length < minChars) {
      packed[i - 1] = packed[i - 1] + "\n\n" + packed[i];
      packed.splice(i, 1);
    }
  }

  // 5. Apply overlap: carry the previous chunk's tail into the next chunk's head.
  //    Computed on the pre-overlap packed text so each chunk's overlap depends
  //    only on the (unchanged) tail of its predecessor.
  const finalTexts = [];
  for (let i = 0; i < packed.length; i++) {
    if (i === 0 || overlapChars === 0) {
      finalTexts.push(packed[i]);
    } else {
      const prev = packed[i - 1];
      const start = Math.max(0, prev.length - overlapChars);
      let tail = prev.slice(start);
      // Don't begin the overlap mid-word: if the raw slice cut into a token
      // (the char before it AND the tail's first char are both non-space),
      // advance past the partial token to the next word boundary. A tail with no
      // internal whitespace is a single partial token → drop it rather than
      // inject a fragment like "icação de leigo".
      if (start > 0 && /\S/.test(prev[start - 1]) && /\S/.test(tail[0] || "")) {
        const sp = tail.search(/\s/);
        tail = sp >= 0 ? tail.slice(sp + 1) : "";
      }
      tail = tail.trimStart();
      // Separator so the tail's last word and the chunk's first word don't glue.
      finalTexts.push(tail ? tail + "\n\n" + packed[i] : packed[i]);
    }
  }

  // 6. Emit with 0-based contiguous index + post-chunking sha256.
  return finalTexts.map((t, idx) => ({
    chunk_index: idx,
    text: t,
    sha256: sha256hex(t),
  }));
}

export default chunkText;
