# Eval — P2 (SymbCoT round-trip) catch rate (layer-2, CPP2026)

Eval #3 showed self-consistency cannot catch *deterministic* mistranslation. The
deep-research synthesis says the **semantic round-trip check (P2)** is the right lever.
This measures whether it actually is: does `verify_translation_faithfulness` abstain on
a mistranslated artifact and pass a faithful one?

## Method

Controlled labeled set (by construction, like eval #1), through the EXACT production
P2 prompt (parsed verbatim from `lib.rs`) on the router:

- **FAITHFUL pair** = (claim, GOLD artifact) → P2 should PASS
- **UNFAITHFUL pair** = (claim, CORRUPTED gold artifact) → P2 should ABSTAIN.
  Corruptions: `sign_flip` (negate a constraint → invert the inequality), `op_swap`
  (wrong GUM operator), `unit_desync` (scale one GUM input ×1000, label unchanged),
  `spurious_edge` (add a direct causal edge x→y).

`recall` = abstain rate on UNFAITHFUL pairs (catch rate). `false-abstain` = abstain
rate on FAITHFUL gold (over-caution).

## Result (deepseek-chat)

| metric | value |
|---|---|
| recall (catch rate on mistranslations) | **0.765** |
| false-abstain rate (on faithful gold) | **0.385** |

| corruption | n | catch rate |
|---|---|---|
| sign_flip | 10 | **1.000** |
| op_swap | 8 | 0.750 |
| unit_desync | 8 | 0.750 |
| spurious_edge | 8 | 0.500 |

## Findings

1. **P2 is a real lever for mistranslation (recall 0.77).** It catches **every**
   inequality `sign_flip` (1.00) — exactly the original SMT variable-split / sign bug —
   and 0.75 of `op_swap` and `unit_desync`. Notably `unit_desync` catch is 0.75, *not*
   ~0: although the prompt says to ignore unit *normalization*, a value scaled ×1000 is
   so inconsistent with the claim text that P2 flags it anyway. So P2 complements the
   extraction-prompt unit fix on the `gum/unit` failure. Weakest on `spurious_edge`
   (0.50) — an extra causal edge is subtler than a flipped sign.
2. **But the false-abstain rate is too high to enable as-is (0.385).** P2 wrongly
   rejected ~38% of *faithful* gold artifacts. In production that would suppress more
   than a third of real findings — a worse failure than the confabulation it guards
   against. **P2 must be precision-tuned before `BEAGLE_TRIAD_SYMB_VERIFY=1` in prod.**

## Important caveat (the false-abstain number is pessimistic)

The harness builds the (B) "FORMAL NL DESCRIPTION" with a *simplified* renderer, not the
exact domain-specific `formal_nl_description` the Rust code constructs. A cruder back-
translation makes faithful artifacts look more divergent from the claim, inflating
false-abstain. So **0.385 is an upper bound**; the production false-abstain is likely
lower. Re-measure with the exact Rust renderer before acting on the precision number.
The recall figures (on unambiguous corruptions) are robust to this.

## Where this lands the eval suite

- **P3 self-consistency**: 0/2 on deterministic mistranslation (eval #3) — wrong lever.
- **P2 round-trip**: 0.77 recall, 1.00 on sign-flips — right lever, but 0.385 false-
  abstain ⇒ needs precision tuning, not a flip-the-flag deploy.
- **Extraction prompt fix** (eval #2): deterministic, no false-abstain cost, lifted
  `gum/unit` directly — cheapest first line of defense.

Recommended order of mitigation: prompt fixes first (free), then P2 once its false-
abstain is tuned down, and keep P3 narrow/off for the factual verbs.

## Run

```bash
ROUTER=http://127.0.0.1:14000 python3 run_eval_p2.py
```
