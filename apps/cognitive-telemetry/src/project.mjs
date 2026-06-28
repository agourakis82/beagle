// project.mjs — Phase B: the seeded embedding→octonion-coord projection.
//
// DECLARED MODELING CHOICE (the paper must report results relative to this — it is
// the encoder, not the theory). F operates on an 8-coord content vector; we map the
// 1024-d bge-m3 embedding into it with a FIXED-SEED Johnson–Lindenstrauss random
// projection with SIGN (±1) entries (Achlioptas 2003):
//
//     content = (1/√8) · R · v ,   R ∈ {±1}^{8×D} ,   R fixed by PROJECTION_SEED
//
// Why this and not learned/PCA: the doc mandates a *fixed seeded* projection. Sign
// entries make R fully deterministic (no float transcendentals → bit-reproducible),
// E[‖content‖²]=‖v‖² (norm-preserving in expectation), and JL is citable. d=8 (the
// octonion dimension) is an aggressive sketch — accepted, and telemetry is reported
// relative to it. bge-m3 is L2-normalized, so content lands ~on the unit sphere; F's
// content_to_octonion re-normalizes the imaginary part regardless. content[0] is the
// scalar channel (drops out of the associator/commutator, but feeds zd_proximity).
//
// v2 stretch (documented, not v1): a corpus-fit PCA basis instead of random R.

export const PROJECTION_SEED = 0x7a9e3f11; // fixed; changing it changes the encoder

const OUT_DIM = 8;

// mulberry32 — small, fully-specified deterministic PRNG (reproducible across hosts).
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Cache the ±1 matrix per input dimension D (row-major, 8×D), generated from the
// single seeded stream so it is identical everywhere the seed is.
const _matrixCache = new Map();
function signMatrix(D) {
  let m = _matrixCache.get(D);
  if (m) return m;
  const rng = mulberry32(PROJECTION_SEED);
  m = new Int8Array(OUT_DIM * D);
  for (let i = 0; i < m.length; i++) m[i] = rng() < 0.5 ? -1 : 1;
  _matrixCache.set(D, m);
  return m;
}

/** The 8 sign entries for input coordinate j (one per output coord) — for tests/audit. */
export function signColumn(j, D) {
  const m = signMatrix(D);
  const col = new Array(OUT_DIM);
  for (let k = 0; k < OUT_DIM; k++) col[k] = m[k * D + j];
  return col;
}

/**
 * Project an embedding to the 8-coord content vector.
 * @param {number[]} embedding  (e.g. 1024-d bge-m3)
 * @returns {number[]} content[8]
 */
export function project(embedding) {
  const D = embedding.length;
  const m = signMatrix(D);
  const scale = 1 / Math.sqrt(OUT_DIM);
  const out = new Array(OUT_DIM).fill(0);
  for (let k = 0; k < OUT_DIM; k++) {
    let acc = 0;
    const base = k * D;
    for (let j = 0; j < D; j++) acc += m[base + j] * embedding[j];
    out[k] = scale * acc;
  }
  return out;
}

export default project;
