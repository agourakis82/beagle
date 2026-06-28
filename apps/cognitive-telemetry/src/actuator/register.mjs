// actuator/register.mjs — the actuator's decision brain: infer the conversational
// REGISTER (researcher | friend | operator) and a LICENSE level (0=guarded/
// institutional … 1=intimate/opinionated) from F's telemetry + light context.
//
// This is "inference is the magic": the system reads HOW you're asking (the F
// signals + space/time/lexicon), not an explicit mode switch. It consumes F
// directly — zero-divisor proximity (pillar iii) is the vulnerability signal; the
// Fano mode / coherence are the conversational-state signals.
//
// STRUCTURAL ANTI-DRIFT (the load-bearing design): LICENSE is *raised* by
// vulnerability signals (dissociation, late, personal) and only lowered by an
// explicit work/operational context. There is NO "uncertainty → be cautious" term.
// So a system that is unsure cannot drift toward the institutional gray — caution is
// not an axis the inference moves along. (The conversation-as-fine-tuning in learn.mjs
// preserves this: corrections move license DIRECTIONALLY, never as scalar approval.)

export const REGISTERS = ["researcher", "friend", "operator"];

// Default weights — the documented starting point; learn.mjs adapts these per-context.
export function defaultWeights() {
  return {
    researcher: { base: 0.15, technical: 1.0 },
    operator: { base: 0.15, operational: 1.0 },
    friend: { base: 0.2, personal: 0.9, dissociation: 1.1, late: 0.5, instability: 0.7 },
    license: { base: 0.3, dissociation: 0.9, personal: 0.5, late: 0.4, instability: 0.6, work: 0.5 },
  };
}

const TECH = /\b(theorem|proof|octonion|sedenion|associator|compiler|souc|sounio|algebra|lemma|functor|manifold|curvature|eigen|tensor|gradient|topolog|category|homolog)\w*/gi;
const OPS = /\b(cluster|deploy|gpu|pod|slurm|kubectl|node|backfill|rollout|registry|image|port-forward|ceph|nccl|reranker|embed|memory-pg|physiome)\w*/gi;
const PERSONAL = /\b(i|me|my|feel|felt|tired|alone|scared|anxious|sad|happy|love|afraid|hope|worried|lost|hurt|empty|miss)\b/gi;

function density(text, re) {
  const toks = String(text || "").toLowerCase().split(/\s+/).filter(Boolean);
  if (!toks.length) return 0;
  const hits = (String(text || "").match(re) || []).length;
  return Math.min(1, hits / Math.max(4, toks.length));
}
const clamp01 = (x) => (x > 1 ? 1 : x < 0 ? 0 : x);

/**
 * Extract the normalized signal vector the inference scores over.
 * @param {{telemetry?:{coherence?:number, zd?:number, rupture?:boolean},
 *          query?:string, space?:string, hour?:number}} ctx
 */
export function extractSignals(ctx = {}) {
  const t = ctx.telemetry || {};
  const zd = Number.isFinite(t.zd) ? t.zd : 1.4142;
  // near the zero-divisor variety (zd → 0) = vulnerability / dissociation proximity
  const dissociation = clamp01((0.4 - zd) / 0.4);
  const instability = t.rupture ? 1 : 0;
  const technical = density(ctx.query, TECH);
  const operational = density(ctx.query, OPS);
  const personal = clamp01(density(ctx.query, PERSONAL) + (ctx.space === "personal" ? 0.5 : 0));
  const hour = Number.isFinite(ctx.hour) ? ctx.hour : 12;
  const late = hour < 6 || hour >= 23 ? 1 : 0;
  const work = ctx.space === "work" || ctx.space === "cockpit" ? 1 : 0;
  return { dissociation, instability, technical, operational, personal, late, work };
}

/**
 * Infer {register, license} from context.
 * @returns {{register:string, license:number, scores:object, signals:object, rationale:string}}
 */
export function inferRegister(ctx = {}, weights = defaultWeights()) {
  const s = extractSignals(ctx);
  const scores = {
    researcher: weights.researcher.base + weights.researcher.technical * s.technical,
    operator: weights.operator.base + weights.operator.operational * s.operational,
    friend:
      weights.friend.base +
      weights.friend.personal * s.personal +
      weights.friend.dissociation * s.dissociation +
      weights.friend.late * s.late +
      weights.friend.instability * s.instability,
  };
  let register = "friend";
  for (const r of REGISTERS) if (scores[r] > scores[register]) register = r;

  const L = weights.license;
  const license = clamp01(
    L.base + L.dissociation * s.dissociation + L.personal * s.personal +
      L.late * s.late + L.instability * s.instability - L.work * s.work,
  );

  const why = [];
  if (s.dissociation > 0.3) why.push(`dissociação ${s.dissociation.toFixed(2)} (zd baixo) → licença alta`);
  if (s.technical > 0.05) why.push("léxico técnico");
  if (s.operational > 0.05) why.push("léxico operacional");
  if (s.personal > 0.3) why.push("pessoal/primeira-pessoa");
  if (s.late) why.push("tarde da noite");
  return { register, license: Math.round(license * 1000) / 1000, scores, signals: s, rationale: why.join("; ") };
}

export default inferRegister;
