// episode.mjs — expand recall shards back into scenes.
//
// WHY THIS EXISTS
// Retrieval is chunk-granular, so what reaches the companion's prompt is whatever
// slice of a conversation happened to match the query. Measured in production, the
// median atom was 53 characters: "minha casa", "meu bem-estar pessoal", "Estou me
// sentindo angustiado". Every one of those is TRUE and every one is useless — it is
// the label of a memory with the memory removed. The model receives an index card
// and is asked to sound like someone who was there.
//
// expandEpisodes() takes the hits that survived rerank + trust filtering and widens
// each back to its neighbourhood: the chunks immediately before and after it in the
// same record, stitched in reading order. The shard "angustiado, com vontade de
// chorar," becomes the passage it was cut from.
//
// Two properties matter as much as the widening itself:
//   * Overlapping windows MERGE. Two hits three chunks apart would otherwise repeat
//     the chunk between them, spending scarce prompt budget echoing itself.
//   * Nothing is ever dropped. A graph fact, a hit whose record vanished, a chunk we
//     cannot locate — all pass through unexpanded. Trading warmth for amnesia would
//     defeat the entire point.

const DEFAULT_RADIUS = 1;
const DEFAULT_MAX_CHARS = 1200;

/**
 * Widen each hit into the scene it came from.
 *
 * @param {import("pg").Pool} pool
 * @param {Array<{chunk_id?: string, record_id?: string|null, text: string}>} hits
 *        Rank-ordered hits (best first).
 * @param {{radius?: number, maxChars?: number}} [opts]
 *        radius   — chunks to include on each side (default 1)
 *        maxChars — hard cap per episode; the matched shard always survives
 * @returns {Promise<Array<object>>} hits in rank order, `text` widened, carrying
 *        `hit_text` (the shard that actually matched) and `expanded`.
 */
export async function expandEpisodes(pool, hits, opts = {}) {
  const radius = Number.isFinite(opts.radius) ? Math.max(0, Math.trunc(opts.radius)) : DEFAULT_RADIUS;
  const maxChars = Number.isFinite(opts.maxChars) && opts.maxChars > 0 ? opts.maxChars : DEFAULT_MAX_CHARS;

  if (!Array.isArray(hits) || hits.length === 0) return [];

  // A hit is expandable only if it is a real chunk of a real record. Graph facts
  // ("fact:<uuid>") and record-less hits skip the DB entirely.
  const expandable = new Map(); // chunk_id -> rank index
  hits.forEach((h, i) => {
    const cid = h?.chunk_id;
    if (typeof cid === "string" && cid && !cid.startsWith("fact:") && h?.record_id) {
      expandable.set(cid, i);
    }
  });

  const passthrough = (h) => ({ ...h, hit_text: h.text, expanded: false });
  if (expandable.size === 0) return hits.map(passthrough);

  // 1. Locate each hit chunk within its record.
  let located;
  try {
    const res = await pool.query(
      `SELECT id, record_id, chunk_index FROM chunks WHERE id = ANY($1::uuid[])`,
      [[...expandable.keys()]],
    );
    located = res.rows;
  } catch {
    // Never let expansion break recall: an unexpandable pool is still a pool.
    return hits.map(passthrough);
  }
  if (!located.length) return hits.map(passthrough);

  const posOf = new Map(located.map((r) => [String(r.id), r]));

  // 2. Build one window per hit, then merge windows that touch or overlap within
  //    the same record. Merged windows inherit the best (lowest) rank index.
  const byRecord = new Map();
  for (const [cid, rank] of expandable) {
    const loc = posOf.get(String(cid));
    if (!loc) continue;
    const rec = String(loc.record_id);
    const idx = Number(loc.chunk_index);
    if (!byRecord.has(rec)) byRecord.set(rec, []);
    byRecord.get(rec).push({ lo: idx - radius, hi: idx + radius, hitIndex: idx, rank, chunk_id: cid });
  }

  const windows = [];
  for (const [rec, list] of byRecord) {
    list.sort((a, b) => a.lo - b.lo);
    let cur = null;
    for (const w of list) {
      // `<=` (not `<`) so adjacent windows merge: [0..1] and [1..2] share chunk 1,
      // and emitting both would print that chunk twice.
      if (cur && w.lo <= cur.hi) {
        cur.hi = Math.max(cur.hi, w.hi);
        cur.hitIndexes.push(w.hitIndex);
        if (w.rank < cur.rank) cur.rank = w.rank;
      } else {
        if (cur) windows.push(cur);
        cur = { record_id: rec, lo: w.lo, hi: w.hi, hitIndexes: [w.hitIndex], rank: w.rank };
      }
    }
    if (cur) windows.push(cur);
  }

  // 3. Fetch the text of every chunk inside every window, in one round trip.
  const clauses = [];
  const params = [];
  for (const w of windows) {
    params.push(w.record_id, w.lo, w.hi);
    const n = params.length;
    clauses.push(`(record_id = $${n - 2}::uuid AND chunk_index BETWEEN $${n - 1} AND $${n})`);
  }
  let rows;
  try {
    const res = await pool.query(
      `SELECT record_id, chunk_index, text FROM chunks WHERE ${clauses.join(" OR ")}
       ORDER BY record_id, chunk_index`,
      params,
    );
    rows = res.rows;
  } catch {
    return hits.map(passthrough);
  }

  const textsOf = new Map(); // record_id -> Map(chunk_index -> text)
  for (const r of rows) {
    const rec = String(r.record_id);
    if (!textsOf.has(rec)) textsOf.set(rec, new Map());
    textsOf.get(rec).set(Number(r.chunk_index), String(r.text ?? ""));
  }

  // 4. Assemble each window's scene, honouring the char cap.
  const sceneByRank = new Map();
  for (const w of windows) {
    const byIndex = textsOf.get(w.record_id);
    if (!byIndex) continue;
    const anchor = Math.min(...w.hitIndexes);
    const pieces = [];
    for (let i = w.lo; i <= w.hi; i++) {
      const t = byIndex.get(i);
      if (typeof t === "string" && t.length) pieces.push({ i, t });
    }
    if (!pieces.length) continue;
    sceneByRank.set(w.rank, assemble(pieces, anchor, maxChars));
  }

  // 5. Emit in the original rank order. A hit whose window merged into an
  //    earlier-ranked episode is dropped (its content is already in that scene).
  const consumed = new Set();
  for (const w of windows) for (const idx of w.hitIndexes) consumed.add(`${w.record_id}:${idx}`);

  const out = [];
  const emitted = new Set();
  hits.forEach((h, i) => {
    const loc = posOf.get(String(h?.chunk_id));
    if (!loc) {
      out.push(passthrough(h));
      return;
    }
    const scene = sceneByRank.get(i);
    if (scene == null) {
      // This hit merged into a better-ranked window; its text is already shown.
      const owner = windows.find(
        (w) => w.record_id === String(loc.record_id) && Number(loc.chunk_index) >= w.lo && Number(loc.chunk_index) <= w.hi,
      );
      if (owner && emitted.has(owner.rank)) return;
      out.push(passthrough(h));
      return;
    }
    emitted.add(i);
    out.push({ ...h, text: scene, hit_text: h.text, expanded: scene !== h.text });
  });

  return out;
}

/**
 * Join a window's chunks in reading order, keeping the anchor (the chunk that
 * actually matched) whole and growing outward until the budget runs out.
 */
function assemble(pieces, anchor, maxChars) {
  const full = pieces.map((p) => p.t).join(" ");
  if (full.length <= maxChars) return full;

  const anchorPiece = pieces.find((p) => p.i === anchor) ?? pieces[0];
  const selected = new Map([[anchorPiece.i, anchorPiece.t.slice(0, maxChars)]]);
  let used = selected.get(anchorPiece.i).length;

  // Grow outward, alternating forward/backward so the scene stays centred on the
  // match instead of drifting to one side.
  let after = pieces.filter((p) => p.i > anchorPiece.i).sort((a, b) => a.i - b.i);
  let before = pieces.filter((p) => p.i < anchorPiece.i).sort((a, b) => b.i - a.i);
  let takeAfter = true;
  while ((after.length || before.length) && used < maxChars) {
    const src = takeAfter && after.length ? after : before.length ? before : after;
    const piece = src.shift();
    takeAfter = !takeAfter;
    if (!piece) continue;
    const budget = maxChars - used - 1; // -1 for the joining space
    if (budget <= 0) break;
    const text = piece.t.length <= budget ? piece.t : piece.t.slice(0, budget);
    if (!text) break;
    selected.set(piece.i, text);
    used += text.length + 1;
  }

  return [...selected.entries()].sort((a, b) => a[0] - b[0]).map(([, t]) => t).join(" ");
}

export default expandEpisodes;
