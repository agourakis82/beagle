# Eval #2 — NL→formal extraction faithfulness (clinical prose)

model: `deepseek-chat` · 30 cases · **5 trials** (temp 0; LLM still nondeterministic)

**Overall faithfulness: 0.933 ± 0.000**

## By domain (mean ± std over trials)

| domain | mean | std |
|---|---|---|
| causal | 0.900 | 0.000 |
| gum | 0.900 | 0.000 |
| smt | 1.000 | 0.000 |

## By trap type

| domain / trap | mean | std |
|---|---|---|
| causal/clean | 1.000 | 0.000 |
| causal/distractor_number | 0.500 | 0.000 |
| causal/implicit_premise | 1.000 | 0.000 |
| causal/no_valid_extraction | 1.000 | 0.000 |
| gum/clean | 1.000 | 0.000 |
| gum/distractor_number | 1.000 | 0.000 |
| gum/no_valid_extraction | 1.000 | 0.000 |
| gum/role_qualifier | 1.000 | 0.000 |
| gum/unit | 0.500 | 0.000 |
| smt/clean | 1.000 | 0.000 |
| smt/distractor_number | 1.000 | 0.000 |
| smt/role_qualifier | 1.000 | 0.000 |
| smt/sign | 1.000 | 0.000 |
| smt/unit | 1.000 | 0.000 |

## Unstable cases (verdict flips across trials)

None — all cases stable across trials.

_Faithful = live Sounio verdict on the extracted artifact matches the solver-derived gold verdict. Trap cases are built so a mistranslation flips the verdict; `no_valid_extraction` is faithful iff the extractor abstains._
