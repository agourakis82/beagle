# Eval — P2 (SymbCoT round-trip) catch rate (layer-2, CPP2026)

Eval #3 showed self-consistency cannot catch *deterministic* mistranslation; the deep-
research synthesis says the **semantic round-trip check (P2)** is the right lever. This
measures whether it actually is, and whether it can be enabled in production.

## Method

Controlled labeled set (by construction, like eval #1), through the EXACT production
P2 prompt (parsed verbatim from `lib.rs`) on the router:

- **FAITHFUL pair** = (claim, GOLD artifact) → P2 should PASS
- **UNFAITHFUL pair** = (claim, CORRUPTED gold artifact) → P2 should ABSTAIN.
  Corruptions: `sign_flip` (negate a constraint → invert the inequality), `op_swap`
  (wrong GUM operator), `unit_desync` (scale one GUM input ×1000, label unchanged),
  `spurious_edge` (add a direct causal edge x→y).

The harness builds (B) the NL back-translation and (C) the solver-JSON **exactly as
`lib.rs` does** (this matters — see below) and votes over `TRIALS` runs (P2 is
nondeterministic). `recall` = abstain rate on UNFAITHFUL; `false-abstain` = abstain
rate on FAITHFUL gold.

## The measurement confound (and why it mattered)

A first pass used a *richer* hand-written (B) than production and a single trial:
recall 0.765, false-abstain 0.385. Mirroring the EXACT production (B)/(C) and voting
over 3 trials changed the picture completely — because the production
`formal_nl_description` is **terse** (SMT listed only constraint *labels*; causal listed
only an *edge count*). The lesson: never tune against a confounded harness.

## Results (3 trials, deepseek-chat)

| (B) description | recall | false-abstain |
|---|---|---|
| original terse production (B) | **0.912** | **0.538** |
| richer (B): SMT inequalities + causal edge list | 0.824 | 0.423 |

By corruption (richer-(B) run): sign_flip 1.00, op_swap 1.00, unit_desync 0.875,
spurious_edge 0.375.

## Findings

1. **P2 has strong recall (0.82–0.91).** With the exact solver-JSON in (C) it catches
   *every* sign-flip and operator-swap, and 0.875 of unit-desyncs (so it complements
   the eval-#2 extraction unit fix). It is genuinely the right lever for mistranslation.
2. **But false-abstain is far too high to enable (0.42–0.54).** P2 abstains on roughly
   *half* of FAITHFUL gold artifacts — in production that would suppress more real
   findings than the confabulation it guards against. **`BEAGLE_TRIAD_SYMB_VERIFY` must
   stay OFF.**
3. **Root cause is precision, not strictness.** Two levers were tried and measured:
   - *Prompt-tune toward leniency* (judge mainly on (C), default true): made it WORSE —
     recall 0.765 → 0.676 while false-abstain barely moved. Reverted.
   - *Richer (B) back-translation* (SMT inequalities, causal edge list): cut false-
     abstain 0.538 → 0.423 (a real gain) but cost recall 0.91 → 0.82. Kept (the
     completer description is objectively better and P2 is gated OFF, so zero prod risk).
   Neither tweak gets false-abstain into a usable range. P2-as-a-single-LLM-judge is
   high-recall / low-precision by nature.

## Recommendation

Do NOT enable P2 as a hard gate. The path to a usable P2 is a **precision** approach,
not more prompt tweaks:
- **Verifier ensemble**: require ≥2 independent P2 judges to agree before abstaining
  (trades a little recall for a large false-abstain cut).
- **Stronger judge model**: route P2 to a reasoning model, not the cheap extraction
  model — equivalence judgment is harder than extraction.
- **Soft signal, not a gate**: feed P2's verdict into a confidence label (P5-style)
  rather than dropping the finding outright.

## Where this lands the suite

- **P3 self-consistency**: 0/2 on deterministic mistranslation (eval #3) — wrong lever.
- **P2 round-trip**: 0.82–0.91 recall (right lever) but 0.42–0.54 false-abstain ⇒ needs
  a precision design (ensemble / stronger judge), not a flag flip.
- **Extraction prompt fix** (eval #2): deterministic, zero false-abstain cost ⇒ the
  cheapest and first line of defense (done + deployed).

Order of mitigation, measured: **prompt fix first → P2 only once its precision is fixed
→ keep P3 narrow/off for the factual verbs.**

## Run

```bash
TRIALS=3 ROUTER=http://127.0.0.1:14000 python3 run_eval_p2.py
```
