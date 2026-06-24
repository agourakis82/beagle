// actuator/learn.mjs — conversation-as-fine-tuning, DIRECTIONAL (not scalar).
//
// The whole point (from the design conversation): learning from a scalar approval
// signal collapses toward caution (the model's RLHF prior makes "be careful" the
// safe attractor). So a correction here is a DIRECTION in register/license space,
// never a reward. "Should have been the friend" raises the friend's score for *this
// context*. "Be warmer" raises LICENSE for this context. Neither can drift toward the
// institutional gray, because caution is not an axis these moves travel along.
//
// This is the cheap analogue of updating emotion-VECTORS (not weights) — same
// geometry, at the decision layer. The activation-level version (v2) updates the
// steering vectors; this updates the register/license weights identically in spirit.

function clone(w) {
  return JSON.parse(JSON.stringify(w));
}

/**
 * Apply one correction to the weights, in the direction of the active signals.
 * @param {object} weights  from defaultWeights() (or a learned set)
 * @param {object} signals  from extractSignals() — the context the correction is about
 * @param {{register?:string, licenseDelta?:number}} correction
 * @param {{lr?:number}} [opts]
 * @returns {object} updated weights
 */
export function applyCorrection(weights, signals, correction, opts = {}) {
  const lr = opts.lr ?? 0.1;
  const w = clone(weights);

  // Register correction: raise the target register's score for THIS context by
  // bumping the weights on the signals that were active. Moves the boundary toward
  // the target for similar contexts; leaves other contexts ~unchanged.
  if (correction.register && w[correction.register]) {
    const reg = w[correction.register];
    for (const key of Object.keys(reg)) {
      if (key === "base") continue;
      reg[key] += lr * (signals[key] ?? 0); // key is a signal name (technical/personal/…)
    }
    reg.base += lr * 0.5;
  }

  // License correction: directional. +delta = "be warmer/more intimate" → raise the
  // license weights on the active vulnerability/personal signals. -delta = "be more
  // guarded". The work-suppressor is NEVER touched by warmth corrections, so warmth
  // can never accidentally increase guardedness.
  if (correction.licenseDelta) {
    const dir = Math.sign(correction.licenseDelta);
    for (const key of Object.keys(w.license)) {
      if (key === "work") continue;
      if (key === "base") { w.license.base += lr * dir * 0.5; continue; }
      w.license[key] += lr * dir * (signals[key] ?? 0);
    }
  }
  return w;
}

export default applyCorrection;
