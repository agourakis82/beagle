// affect.mjs — Phase B: the v1 affect-uncertainty proxy (text → uncertainty[8]).
//
// DECLARED MODELING CHOICE + the program's weakest v1 link (the design doc flags
// this: weak labels limit pillar (iii) — zero-divisor↔dissociation — until a real
// affect head replaces it). This is a cheap, DETERMINISTIC token-level proxy: 8
// surface features that plausibly track affective instability / uncertainty. It
// makes NO claim of psychological validity; it exists so F has a sedenion-half
// (uncertainty) input and the pipeline runs end-to-end. Each channel is a density
// in [0,~1] (count normalized by token/sentence count).
//
// The 8 channels (the sedenion-half coordinates):
//   hedging        epistemic uncertainty (maybe, perhaps, might, i think)
//   negation       affective negativity / conflict (no, not, never, n't)
//   interrogative  unresolved questioning (? per sentence)
//   arousal        intensity (! , very, really, so, intense)
//   self_focus     self-referential rumination (i, me, my, myself)
//   rigidity       absolutist cognition — a known clinical marker (always, never,
//                  completely, everything, nothing)
//   repetition     lexical perseveration (1 - type/token ratio)
//   fragmentation  disfluency / broken structure (ellipses, dashes, short fragments)

export const AFFECT_CHANNELS = [
  "hedging", "negation", "interrogative", "arousal",
  "self_focus", "rigidity", "repetition", "fragmentation",
];

const HEDGES = new Set(["maybe", "perhaps", "might", "possibly", "probably", "guess",
  "seems", "kinda", "sorta", "somewhat", "unsure", "suppose"]);
const NEGATIONS = new Set(["no", "not", "never", "none", "nothing", "cannot", "cant",
  "dont", "doesnt", "wont", "wouldnt", "nobody"]);
const INTENSIFIERS = new Set(["very", "really", "so", "extremely", "totally", "intense",
  "absolutely", "deeply", "incredibly"]);
const SELF = new Set(["i", "me", "my", "myself", "mine", "im", "ive"]);
const ABSOLUTIST = new Set(["always", "never", "completely", "totally", "everything",
  "nothing", "everyone", "nobody", "all", "none", "forever", "ruined"]);

function tokenize(text) {
  return String(text).toLowerCase().replace(/'/g, "").split(/[^a-z]+/).filter(Boolean);
}

/**
 * @param {string} text
 * @returns {number[]} uncertainty[8] aligned to AFFECT_CHANNELS
 */
export function affectUncertainty(text) {
  const raw = String(text || "");
  const toks = tokenize(raw);
  const n = toks.length;
  if (n === 0) return new Array(8).fill(0);
  const sentences = Math.max(1, (raw.match(/[.!?]+/g) || []).length);

  let hedge = 0, neg = 0, intens = 0, self = 0, abs = 0;
  const seen = new Set();
  for (const t of toks) {
    if (HEDGES.has(t)) hedge++;
    if (NEGATIONS.has(t)) neg++;
    if (INTENSIFIERS.has(t)) intens++;
    if (SELF.has(t)) self++;
    if (ABSOLUTIST.has(t)) abs++;
    seen.add(t);
  }
  const questions = (raw.match(/\?/g) || []).length;
  const bangs = (raw.match(/!/g) || []).length;
  const ellipses = (raw.match(/\.\.\.|…/g) || []).length;
  const dashes = (raw.match(/[—–-]/g) || []).length;

  const clamp = (x) => (x > 1 ? 1 : x < 0 ? 0 : x);
  return [
    clamp(hedge / n),
    clamp(neg / n),
    clamp(questions / sentences),
    clamp((intens + bangs) / n),
    clamp(self / n),
    clamp(abs / n),
    clamp(1 - seen.size / n), // repetition: low type/token ratio
    clamp((ellipses + dashes) / sentences),
  ];
}

export default affectUncertainty;
