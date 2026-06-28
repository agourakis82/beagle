# Eval #3 — P3 self-consistency abstention operating point

Reproducible experiment for CPP2026. Answers the deep-research open question Q4:
**what abstention operating point trades coverage against the factual-domain
autoformalization harm?** P3 runs the extraction k times and trusts the artifact only
if ≥ `agree` of the k runs agree on it (majority for smt/theorem, unanimous for
causal/gum), else abstains.

## Method

Collect `K_MAX=5` extractions per case once (cached), then evaluate every
`(k, mode)` config offline against the cache using P3's per-domain canonical key.
Reuses `../extraction_faithfulness/run_eval.py` (same prompts parsed from `lib.rs`,
same live Sounio verbs for scoring, same corpus and solver-derived gold).

- **coverage** = fraction of cases trusted (not abstained)
- **precision (trusted)** = faithful among trusted (live verdict == gold)
- **abstained-unfaithful / total-unfaithful** = of the cases whose single-shot verdict
  is unfaithful, how many P3 abstained on (i.e., did self-consistency *catch* the error)

## Result (deepseek-chat, K=5)

| config | coverage | precision(trusted) | caught-unfaithful |
|---|---|---|---|
| k=1 / majority | 0.867 | 0.923 | 0/2 |
| k=3 / majority | 0.800 | 0.917 | 0/2 |
| k=5 / majority | 0.767 | 0.913 | 0/2 |
| k=3 / unanimous | 0.700 | 0.905 | 0/2 |
| k=5 / unanimous | 0.700 | 0.905 | 0/2 |
| **production-policy** | 0.800 | 0.917 | 0/2 |

Extraction key disagreement across K=5: **5/30 cases**.

## Finding (a clean negative result)

**Self-consistency abstention is the wrong tool for systematic NL→formal
mistranslation.**

1. **It catches 0/2 of the actual errors, in every config.** The two residual
   failures (`gum/unit`, `causal/distractor` from eval #2) are *deterministic* — all
   k extractions agree on the same wrong artifact — so self-consistency, which can only
   abstain on *disagreement*, never sees them. Only 5/30 cases disagree at all, and
   none of those are the unfaithful ones.
2. **Tightening abstention is pure cost.** Going from k=1 to k=5/unanimous drops
   coverage 0.867 → 0.700 while precision does **not** improve (0.923 → 0.905, in fact
   slightly worse — unanimity discards faithful cases that had minor disagreement).
   There is **no beneficial operating point** on this corpus.

## Implication for the architecture

The mitigation must match the failure's *nature*:

- **Deterministic mistranslation** (confidently wrong) → fix the **prompt** (eval #2
  showed unit-normalization lifted `gum/unit` 0.0 → 0.5) or use the **P2 semantic
  round-trip** check (verify the artifact against the source) — NOT self-consistency.
- **Noisy disagreement** (the 5/30 unstable cases) → self-consistency is appropriate.

So P3 should be kept *narrow* (or off by default for the factual/structural verbs where
failures are deterministic), and the trust budget spent on P2 instead. This is the
direct, measured answer to open Q4.

## Caveats

- Verdict-match faithfulness proxy and a 30-case, single-model corpus (see eval #2).
- "Deterministic" here means deterministic across K=5 at temp 0 for `deepseek-chat`;
  a different/hotter model could disagree more, widening self-consistency's reach.
- Precision is measured among trusted cases only; abstained cases are excluded by
  construction (that is what abstention means).
