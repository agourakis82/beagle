# Eval #2 — NL→formal extraction faithfulness on clinical prose

Reproducible experiment for the CPP2026 line of work. It answers the deep-research
synthesis's load-bearing open question (Q2): **how faithfully does the production
extraction model translate a clinical NL claim into the solver-checkable artifact,
and where does it break?** Autoformalization is the weak link the literature says
can *harm* correctness on factual claims (−44.5% in "Grammars of Formal Uncertainty");
this measures it on *our* verbs and clinical prose.

## Method (end-to-end, both production services)

Per case:
1. **Extract** — run the EXACT production extraction prompt (parsed verbatim from
   `crates/beagle-triad/src/lib.rs` at eval time) on the claim via the LiteLLM
   router (`deepseek-chat`, temp 0).
2. **Solve** — feed the extracted artifact to the live Sounio verb (`sounio-inference`).
3. **Score** — compare the solver **verdict** to the **solver-derived gold verdict**.

Verdict-match is the faithfulness signal: every trap case is constructed so a
mistranslation (sign flip, variable split, missing unit conversion, wrong op,
invented edge) flips the verdict. `no_valid_extraction` cases are faithful iff the
extractor correctly abstains.

**Gold is solver-derived, not hand-labeled.** Each gold verdict is computed by
running the curated gold artifact through the live verb (with the production
`claimed < 0.8·u_c` GUM threshold). The first pass exposed 3 hand-labeled GUM golds
that were wrong on borderline cases (labeled "understated" using `claimed < u_c`
instead of the production `< 0.8·u_c`); re-deriving from the verb fixed them. This
is why the harness re-curates gold before scoring.

## Corpus

`corpus.jsonl` — 30 clinical / computational-psychiatry claims (3 domains × trap
types, ~50/50 PT/EN), each with a curated gold artifact and a solver-derived gold
verdict. Trap types: `clean`, `sign`, `role_qualifier`, `unit`, `distractor_number`,
`implicit_premise`, `no_valid_extraction`.

## Run

```bash
# needs the router and sounio-inference reachable:
kubectl -n llm-router port-forward svc/router 14000:4000 &
TRIALS=5 ROUTER=http://127.0.0.1:14000 SOUNIO=http://<sounio-inference-ip>:8799 \
  python3 run_eval.py
```

Writes `results.json` (per-domain/per-trap mean±std, per-case stability) and
`results.md`. Multi-trial because LLM extraction is nondeterministic in principle.

## Result (5 trials, deepseek-chat)

**Overall faithfulness 0.900 ± 0.000** — deterministic across 5 trials (0 unstable
cases), so the failures are *systematic*, not sampling noise.

| domain | faithfulness | note |
|---|---|---|
| smt | **1.00** | robust on every trap (sign / role-qualifier / unit / distractor) — logic-shaped extraction is solid |
| gum | 0.80 | failure isolated to **`gum/unit` = 0.00** |
| causal | 0.90 | failure isolated to **`causal/distractor` = 0.50** |

### Two systematic failure modes found

1. **GUM unit normalization (`gum/unit` 0/2).** The extractor does not convert units
   (1 g vs 2100 mg; 250 µg vs ng) before building the GUM inputs, so the propagated
   `u_c` is wrong and the understated/ok verdict flips. This is precisely the
   factual-domain autoformalization harm, localized.
2. **Causal distractor edges (`causal/distractor` 1/2).** The extractor sometimes
   adds an edge for a variable that is *mentioned* but not causally *linked* in the
   text, turning a d-separated structure into d-connected.

SMT is faithful even on its traps — including the sign and role-qualifier traps that
the original production SMT bug (variable-splitting) once failed, confirming the
two-step canonicalization prompt holds up.

## Actionable (recommended, not yet applied)

- **GUM extraction prompt**: add an explicit unit-normalization step (normalize all
  inputs to a common unit before emitting values). Expected to lift `gum/unit` toward
  1.0. Production prompt change → re-measure here, then redeploy.
- **Causal extraction prompt**: strengthen the "only edges asserted LITERALLY"
  instruction against distractor variables.

## Caveats

- Faithfulness is measured via the **verdict** (what the pipeline acts on), not a
  structural artifact diff; traps are built so mistranslation flips the verdict, but
  a coincidental verdict match would score faithful.
- Single extraction model (`deepseek-chat`) and a 30-case corpus; widen both for a
  publication-strength estimate.
- P2 (SymbCoT round-trip) catch-rate on the unfaithful cases is the next increment
  (layer-2): does the round-trip check abstain on the `gum/unit` and `causal/distractor`
  mistranslations it should?
